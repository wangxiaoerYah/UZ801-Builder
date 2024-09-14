#!/bin/sh -e

# 构建依赖安装 (Ubuntu/Debian 宿主)
# 需要能够运行 aarch64 目标: 交叉编译 qhypstub/lk2nd + qemu 模拟 apk 安装

ARCH=$(uname -m)

COMMON_PKGS="
    android-sdk-libsparse-utils
    binfmt-support
    btrfs-progs
    device-tree-compiler
    fdisk
    gcc-arm-none-eabi
    make
    python3-cryptography
    python3-pyasn1-modules
    python3-pycryptodome
    qemu-user-static
    unzip
    wget
"

apt update

if [ "$ARCH" = "x86_64" ]; then
    echo "Detected x86_64, installing cross toolchain + QEMU..."
    apt install -y \
        $COMMON_PKGS \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu
else
    echo "Detected native ARM64 ($ARCH), installing native tools..."
    apt install -y \
        $COMMON_PKGS \
        build-essential \
        gcc \
        g++
fi

# qemu-aarch64-static 必须可用 (pmos_rootfs.sh 会复制进 chroot)
if ! which qemu-aarch64-static >/dev/null 2>&1; then
    # 兼容旧版本 Ubuntu 的包名差异
    apt install -y qemu-user-static binfmt-support || true
fi
command -v qemu-aarch64-static >/dev/null 2>&1 || {
    echo "ERROR: qemu-aarch64-static not found after install" >&2
    exit 1
}

# 确保 binfmt_misc 已注册 aarch64 处理器 (某些环境安装后未自动激活)
if command -v update-binfmts >/dev/null 2>&1; then
    update-binfmts --enable qemu-aarch64 2>/dev/null || true
fi
if [ -d /proc/sys/fs/binfmt_misc ]; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
fi
