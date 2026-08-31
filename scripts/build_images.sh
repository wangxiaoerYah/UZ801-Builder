#!/bin/sh -e

CHROOT=${CHROOT:-$(pwd)/rootfs}

cleanup() {
    umount -l mnt 2>/dev/null || true
    rm -rf mnt
}
trap cleanup EXIT INT TERM

# boot.raw 已经由 debootstrap.sh 生成，无需再次创建
rm -f rootfs.raw
mkdir -p files mnt

echo "Creating rootfs image..."
truncate -s 1610612736 rootfs.raw
mkfs.ext4 -F -L rootfs rootfs.raw
mount -o loop rootfs.raw mnt

# 提取主文件系统（/boot 将作为空目录被提取）
tar xpf rootfs.tgz -C mnt --exclude='./dev/*'

if [ -d "dist" ]; then
    cp -a dist/* mnt/
fi

umount mnt

echo "Converting raw images to Android sparse format..."
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

# 清理过程文件，保留最终产物
rm -f rootfs.raw boot.raw

echo "Images built successfully: files/boot.bin, files/rootfs.bin"