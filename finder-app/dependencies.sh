#!/bin/bash
# Dependency installation script for kernel build.
# Author: Siddhant Jajoo.
sudo apt-get update
sudo apt-get install -y libssl-dev
sudo apt-get install -y u-boot-tools
sudo apt-get install -y qemu-system-arm
sudo apt-get install -y gcc-aarch64-linux-gnu
sudo apt-get install -y binutils-aarch64-linux-gnu
sudo apt-get install -y bc
sudo apt-get install -y bison
sudo apt-get install -y flex
sudo apt-get install -y libelf-dev
sudo apt-get install -y cpio
