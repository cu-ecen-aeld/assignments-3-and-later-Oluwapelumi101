### Failing Code

#!/bin/sh
# Manual kernel + rootfs build for AESD Assignment 3 Part 2
# Non-interactive, CI-safe version.
set -euo pipefail

# -------- CONFIG --------
OUTDIR="${1:-/tmp/aeld}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_VERSION="${KERNEL_VERSION:-v5.15.163}"
BUSYBOX_REPO="git://busybox.net/busybox.git"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1_33_1}"
# ------------------------

# Resolve OUTDIR to absolute path
OUTDIR="$(realpath -m "${OUTDIR}")"
echo "[i] Using OUTDIR=${OUTDIR}"

mkdir -p "${OUTDIR}" || { echo "[!] Failed to create ${OUTDIR}"; exit 1; }

# Paths
LINUX_DIR="${OUTDIR}/linux-stable"
BUSYBOX_DIR="${OUTDIR}/busybox"
ROOTFS="${OUTDIR}/rootfs"

# Summary helper
say_ok() { printf '\n[OK] %s\n' "$*"; }




# ---------- 1) Build the kernel Image -----------
export ARCH CROSS_COMPILE

if [ ! -d "${LINUX_DIR}" ]; then
  echo "[i] Cloning kernel ${KERNEL_VERSION}..."
  git clone --depth 1 --branch "${KERNEL_VERSION}" "${KERNEL_REPO}" "${LINUX_DIR}"
else
  echo "[i] Kernel tree exists. Ensuring correct tag ${KERNEL_VERSION}..."
  ( cd "${LINUX_DIR}" && git fetch --tags --depth 1 "${KERNEL_REPO}" "+refs/tags/${KERNEL_VERSION}:refs/tags/${KERNEL_VERSION}" || true
    git checkout -f "${KERNEL_VERSION}" )
fi

echo "[i] Building kernel (defconfig + Image)..."
(
  cd "${LINUX_DIR}"
  make mrproper
  make defconfig
  make -j"$(nproc)" all
)

cp -v "${LINUX_DIR}/arch/arm64/boot/Image" "${OUTDIR}/"
say_ok "Kernel built and copied to ${OUTDIR}/Image"


##########where the failure seems to start #####
# ---------- 2) Create rootfs staging tree ----------
echo "[i] Creating rootfs at ${ROOTFS} ..."
rm -rf "${ROOTFS}"
mkdir -p "${ROOTFS}"
mkdir -p "${ROOTFS}"/{bin,dev,etc,home,lib,lib64,proc,sys,usr/bin,usr/sbin,sbin,tmp,var}
chmod 755 "${ROOTFS}"
say_ok "Rootfs skeleton ready"

# ---------- 3) BusyBox (install into rootfs) ----------
if [ ! -d "${BUSYBOX_DIR}" ]; then
  echo "[i] Cloning BusyBox ${BUSYBOX_VERSION} ..."
  git clone "${BUSYBOX_REPO}" "${BUSYBOX_DIR}"
fi
(
  cd "${BUSYBOX_DIR}"
  git fetch --all --tags || true
  git checkout -f "${BUSYBOX_VERSION}"
  make distclean
  make defconfig
  make -j"$(nproc)"
  make CONFIG_PREFIX="${ROOTFS}" install
)
say_ok "BusyBox installed into rootfs"

# ---------- 4) Runtime libs for dynamic BusyBox ----------
SYSROOT="$(${CROSS_COMPILE}gcc -print-sysroot)"
echo "[i] Using SYSROOT=${SYSROOT}"

# Copy minimal libs (ok if some already present)
cp -v "${SYSROOT}/lib/ld-linux-aarch64.so.1"    "${ROOTFS}/lib/"    || true
cp -v "${SYSROOT}/lib64/libm.so.6"              "${ROOTFS}/lib64/"  || true
cp -v "${SYSROOT}/lib64/libresolv.so.2"         "${ROOTFS}/lib64/"  || true
cp -v "${SYSROOT}/lib64/libc.so.6"              "${ROOTFS}/lib64/"  || true
say_ok "Runtime libs staged"

# ---------- 5) Device nodes ----------
echo "[i] Creating device nodes ..."
need_sudo=0
if [ "$(id -u)" -ne 0 ]; then need_sudo=1; fi
if [ "${need_sudo}" -eq 1 ]; then
  sudo mknod -m 666 "${ROOTFS}/dev/null" c 1 3
  sudo mknod -m 622 "${ROOTFS}/dev/console" c 5 1
else
  mknod -m 666 "${ROOTFS}/dev/null" c 1 3
  mknod -m 622 "${ROOTFS}/dev/console" c 5 1
fi
say_ok "/dev nodes created"

# ---------- 6) /init ----------
cat > "${ROOTFS}/init" << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
echo "Boot OK: minimal init running"
exec /bin/sh
EOF
chmod +x "${ROOTFS}/init"
say_ok "/init created"

# ---------- 7) Cross-compile writer + copy course scripts ----------
REPOROOT="$(realpath -m "$(dirname "$0")/..")"

# Build writer (prefer Makefile if exists)
if [ -f "${REPOROOT}/finder-app/Makefile" ]; then
  echo "[i] Building writer via Makefile ..."
  make -C "${REPOROOT}/finder-app" clean >/dev/null 2>&1 || true
  make -C "${REPOROOT}/finder-app" CC="${CROSS_COMPILE}gcc"
  cp -v "${REPOROOT}/finder-app/writer" "${ROOTFS}/home/"
elif [ -f "${REPOROOT}/finder-app/writer.c" ]; then
  echo "[i] Building writer.c directly ..."
  "${CROSS_COMPILE}gcc" -Wall -Werror -o "${ROOTFS}/home/writer" "${REPOROOT}/finder-app/writer.c"
else
  echo "[!] Could not find writer source (finder-app/Makefile or writer.c)."
  exit 1
fi

# Ensure /home/conf exists and copy conf + scripts
mkdir -p "${ROOTFS}/home/conf"
cp -v "${REPOROOT}/conf/username.txt"    "${ROOTFS}/home/conf/"
cp -v "${REPOROOT}/conf/assignment.txt"  "${ROOTFS}/home/conf/"
cp -v "${REPOROOT}/finder-app/finder.sh" "${ROOTFS}/home/"
cp -v "${REPOROOT}/finder-app/finder-test.sh" "${ROOTFS}/home/"
cp -v "${REPOROOT}/finder-app/autorun-qemu.sh" "${ROOTFS}/home/" || true

# Patch finder-test.sh to use conf/assignment.txt (not ../conf/assignment.txt)
# Safe even if already patched.
sed -i 's|\.\./conf/assignment\.txt|conf/assignment.txt|g' "${ROOTFS}/home/finder-test.sh"

# Make scripts executable
chmod +x "${ROOTFS}/home/"*.sh 2>/dev/null || true
say_ok "Writer + scripts staged into /home"

# ---------- 8) Pack initramfs ----------
echo "[i] Creating initramfs ..."
(
  cd "${ROOTFS}"
  find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"
)
gzip -f "${OUTDIR}/initramfs.cpio"
say_ok "initramfs at ${OUTDIR}/initramfs.cpio.gz"

# ---------- Summary ----------
echo
echo "==========================================="
echo " Build complete"
echo "  Image:          ${OUTDIR}/Image"
echo "  Initramfs:      ${OUTDIR}/initramfs.cpio.gz"
echo "  Rootfs (staged): ${ROOTFS}"
echo " Next:"
echo "  ./start-qemu-terminal.sh ${OUTDIR}"
echo "  (Inside QEMU) $ cd /home && ./finder-test.sh"
echo "==========================================="
