# Copy the content directly
#!/bin/bash
# Script to install and build kernel.
# Author: Azeez Oluwapelumi.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]; then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR} || { echo "ERROR: Could not create ${OUTDIR}"; exit 1; }

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION} linux-stable
fi

if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j"$(nproc)" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]; then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf ${OUTDIR}/rootfs
fi

ROOTFS=${OUTDIR}/rootfs
mkdir -p ${ROOTFS}
cd "$ROOTFS"
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin usr/lib64
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]; then
    git clone https://git.busybox.net/busybox
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    make distclean
    make defconfig
else
    cd busybox
fi
sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config

make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX=${ROOTFS} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

cd "$ROOTFS"
echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

SYSROOT=$(${CROSS_COMPILE}gcc --print-sysroot)

find ${SYSROOT} -name "ld-linux-aarch64.so.1" | xargs -I{} cp {} ${ROOTFS}/lib/
for lib in libm.so.6 libresolv.so.2 libc.so.6; do
    LIBFILE=$(find ${SYSROOT} -name "${lib}" | head -1)
    cp ${LIBFILE} ${ROOTFS}/lib/
    cp ${LIBFILE} ${ROOTFS}/lib64/
done

sudo mknod -m 666 ${ROOTFS}/dev/null    c 1 3
sudo mknod -m 666 ${ROOTFS}/dev/console c 5 1

cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

cp ./writer          ${ROOTFS}/home/
cp ./finder.sh       ${ROOTFS}/home/
cp ./finder-test.sh  ${ROOTFS}/home/
cp ./autorun-qemu.sh ${ROOTFS}/home/
mkdir -p             ${ROOTFS}/home/conf
cp ./conf/username.txt   ${ROOTFS}/home/conf/
cp ./conf/assignment.txt ${ROOTFS}/home/conf/

sed -i 's|/conf/assignment.txt|conf/assignment.txt|g' ${ROOTFS}/home/finder-test.sh
sed -i 's|#!/bin/bash|#!/bin/sh|' ${ROOTFS}/home/finder.sh

echo "Creating initramfs..."
cd "$ROOTFS"
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio

cd "$OUTDIR"
gzip -f initramfs.cpio

echo "Done! Kernel: ${OUTDIR}/Image  Initramfs: ${OUTDIR}/initramfs.cpio.gz"
echo "Boot with: ./finder-app/start-qemu-terminal.sh ${OUTDIR}"
