#!/bin/sh -e
# =============================================================================
# 将 boot.raw / rootfs.raw 转换为 Android sparse 格式镜像
# (boot.raw / rootfs.raw 由 scripts/pmos_rootfs.sh 直接生成)
# =============================================================================

mkdir -p files

if [ ! -f boot.raw ] || [ ! -f rootfs.raw ]; then
    echo "ERROR: boot.raw / rootfs.raw 不存在, 请先运行 scripts/pmos_rootfs.sh" >&2
    exit 1
fi

echo "Converting raw images to Android sparse format..."
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin

echo "Images built successfully: files/boot.bin, files/rootfs.bin"
