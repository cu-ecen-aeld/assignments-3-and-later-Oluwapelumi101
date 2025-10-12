#!/bin/bash

# Script outline to install and build kernel.
# Author: Siddhant Jajoo and Oluwapelumi Azeez

#Shell flags
# set -e # exit on command failure
# set -u # treat unset vars as errors
# set -o pipefail
# set -x #remove this later
set -euo pipefail


## Configuration Variables #####
OUTDIR=/tmp/aeld # default directory for building kennel and app
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
# ARCH=arm64
# CROSS_COMPILE=aarch64-none-linux-gnu-
ARCH=${ARCH:-arm64}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}



if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi


###################################
# Logging Output to file #

LOG_DIR="${OUTDIR:-/tmp}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build_$(date +%F_%H-%M-%S).log"

# Mirror stdout and stderr to console + log
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

# Optional: timestamped xtrace for debugging
PS4='+ $(date "+%F %T") ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}: '
set -x

####################################


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
    #deep clean
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    #defconfig
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    #buiuld vmlinux
    make -j"$(nproc)" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    #build modules
    # make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    #device tree
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs

fi

echo "Adding the Image in outdir"
# cp ${OUTDIR}/linux-stable/arch/arm64/boot/Image ${OUTDIR}
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/"


echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
ROOTFS=${OUTDIR}/rootfs
mkdir -p ${ROOTFS}
cd "$ROOTFS"
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin usr/lib64
mkdir -p var/log
chmod 1777 tmp


cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}

    make distclean
    make defconfig

    # make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} distclean
    # make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    
    # Disable tc applet
    sed -i '/^CONFIG_TC=y/d' .config
    printf '# CONFIG_TC is not set\n' >> .config
    yes "" | make oldconfig

else
    cd busybox
fi



make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX=${ROOTFS} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

cd "$ROOTFS"
CROSS_COMPILER=${CROSS_COMPILE}gcc
TOOLCHAIN_DIR=$(which $CROSS_COMPILER | xargs dirname)/..

# cp ${TOOLCHAIN_DIR}/aarch64-linux-gnu/libc/lib/ld-linux-aarch64.so.1 $ROOTFS/lib/
# cp ${TOOLCHAIN_DIR}/aarch64-linux-gnu/libc/lib64/libm.so.6 $ROOTFS/lib64/
# cp ${TOOLCHAIN_DIR}/aarch64-linux-gnu/libc/lib64/libresolv.so.2 $ROOTFS/lib64/
# cp ${TOOLCHAIN_DIR}/aarch64-linux-gnu/libc/lib64/libc.so.6 $ROOTFS/lib64/

SYSROOT="$(${CROSS_COMPILE}gcc -print-sysroot)"
install -D "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${ROOTFS}/lib/ld-linux-aarch64.so.1" || true
for lib in libc.so.6 libm.so.6 libresolv.so.2; do
  if   [ -f "${SYSROOT}/lib64/${lib}" ]; then install -D "${SYSROOT}/lib64/${lib}" "${ROOTFS}/lib64/${lib}";
  elif [ -f "${SYSROOT}/lib/${lib}"   ]; then install -D "${SYSROOT}/lib/${lib}"   "${ROOTFS}/lib/${lib}";
  fi
done


echo "Library dependencies"

# TODO: Add library dependencies to rootfs
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"


# TODO: Make device nodes
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 666 dev/console c 5 1

# TODO: Clean and build the writer utility
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp -r ./writer ./finder.sh ./conf/ ./finder-test.sh ./autorun-qemu.sh ${ROOTFS}/home/
# Ensure executables
chmod +x ${ROOTFS}/home/finder.sh ${ROOTFS}/home/finder-test.sh ${ROOTFS}/home/autorun-qemu.sh

# TODO: Chown the root directory
sudo chown -R root:root "${ROOTFS}"

# TODO: Create initramfs.cpio.gz
cd "$ROOTFS"
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
cd "$OUTDIR"
gzip -f initramfs.cpio


echo "Build complete!"
echo "Kernel: ${OUTDIR}/Image"
echo "Initramfs: ${OUTDIR}/initramfs.cpio.gz"
