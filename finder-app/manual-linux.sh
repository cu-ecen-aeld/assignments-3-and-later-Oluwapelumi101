#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo. 
# Other: Oluwapelumi

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))

# ARCH=arm64
# CROSS_COMPILE=aarch64-none-linux-gnu-


ARCH=${ARCH:-arm64}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}


ARCH=${ARCH:-arm64}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}

# Test passing frustrations  
if ! command -v ${CROSS_COMPILE}gcc >/dev/null 2>&1; then
  for P in aarch64-none-linux-gnu- aarch64-linux-gnu-; do
    if command -v ${P}gcc >/dev/null 2>&1; then
      CROSS_COMPILE="$P"
      echo "Using cross-compiler: ${CROSS_COMPILE}gcc"
      break
    fi
  done
fi
if ! command -v ${CROSS_COMPILE}gcc >/dev/null 2>&1; then
  echo "ERROR: No aarch64 cross-compiler found on PATH"; exit 1
fi

# sudo wrapper (CI may be root without sudo)
if command -v sudo >/dev/null 2>&1; then SUDO=sudo; else SUDO=; fi




if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs

fi

echo "Adding the Image in outdir"

# review line
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    # sudo rm  -rf ${OUTDIR}/rootfs
    ${SUDO} rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir -p ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
mkdir -p bin sbin lib lib64 proc sys usr/bin usr/sbin etc dev home tmp
chmod 1777 tmp


cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
else
    cd busybox
fi

# Always reset to a minimal, known-good config
make distclean
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
sed -i 's/^CONFIG_TC=.*/# CONFIG_TC is not set/' .config
grep -q '^CONFIG_TC' .config || echo '# CONFIG_TC is not set' >> .config
yes "" | make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} oldconfig

# TODO: Make and install busybox
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX=${OUTDIR}/rootfs install



echo "Library dependencies"
# ${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
# ${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"


${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"


# TODO: Add library dependencies to rootfs
# SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
# cd ${OUTDIR}/rootfs
# mkdir -p lib lib64
# cp ${SYSROOT}/lib/ld-linux-aarch64.so.1 lib/
# cp ${SYSROOT}/lib64/libm.so.6 lib64/
# cp ${SYSROOT}/lib64/libresolv.so.2 lib64/
# cp ${SYSROOT}/lib64/libc.so.6 lib64/

# Discover files; fall back to Ubuntu multiarch path
LOADER="$(${CROSS_COMPILE}gcc -print-file-name=ld-linux-aarch64.so.1)"
LIBC="$(${CROSS_COMPILE}gcc -print-file-name=libc.so.6)"
LIBM="$(${CROSS_COMPILE}gcc -print-file-name=libm.so.6)"
LIBRESOLV="$(${CROSS_COMPILE}gcc -print-file-name=libresolv.so.2)"

# If any are empty, use multiarch defaults
[ -z "$LOADER" ]    && LOADER=/usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1
[ -z "$LIBC" ]      && LIBC=/usr/aarch64-linux-gnu/lib/libc.so.6
[ -z "$LIBM" ]      && LIBM=/usr/aarch64-linux-gnu/lib/libm.so.6
[ -z "$LIBRESOLV" ] && LIBRESOLV=/usr/aarch64-linux-gnu/lib/libresolv.so.2

cd ${OUTDIR}/rootfs
mkdir -p lib
cp -L "$LOADER"    lib/
cp -L "$LIBC"      lib/
cp -L "$LIBM"      lib/
cp -L "$LIBRESOLV" lib/

# TODO: Make device nodes
${SUDO} mknod -m 666 dev/null c 1 3 || true
${SUDO} mknod -m 600 dev/console c 5 1 || true

# TODO: Clean and build the writer utility
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp writer ${OUTDIR}/rootfs/home/
cp finder.sh ${OUTDIR}/rootfs/home/
cp finder-test.sh ${OUTDIR}/rootfs/home/
cp conf/username.txt ${OUTDIR}/rootfs/home/
cp conf/assignment.txt ${OUTDIR}/rootfs/home/
cp autorun-qemu.sh ${OUTDIR}/rootfs/home/


# Fix to pass the gaddam test
mkdir -p ${OUTDIR}/rootfs/home/conf
cp conf/username.txt   ${OUTDIR}/rootfs/home/conf/
cp conf/assignment.txt ${OUTDIR}/rootfs/home/conf/
sed -i '1 s|^#!.*|#!/bin/sh|' ${OUTDIR}/rootfs/home/finder.sh ${OUTDIR}/rootfs/home/finder-test.sh
chmod +x ${OUTDIR}/rootfs/home/finder.sh ${OUTDIR}/rootfs/home/finder-test.sh


# Fix finder-test.sh pathing to conf
sed -i 's|\.\./conf/assignment.txt|assignment.txt|g' ${OUTDIR}/rootfs/home/finder-test.sh
sed -i 's|\.\./conf/username.txt|username.txt|g' ${OUTDIR}/rootfs/home/finder-test.sh

# TODO: Chown the root directory
cd ${OUTDIR}/rootfs
${SUDO} chown -R root:root *

# TODO: Create initramfs.cpio.gz
cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root | gzip -9 > ${OUTDIR}/initramfs.cpio.gz