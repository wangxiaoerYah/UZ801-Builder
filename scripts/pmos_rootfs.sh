#!/bin/sh -e
# =============================================================================
# postmarketOS rootfs 构建入口 (编排 rootfs/ 子模块)
# 产出: boot.raw (ext2), rootfs.raw (btrfs @ + @var_lib)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"

# 失败时清理挂载 (finalize 幂等)
cleanup() { "${HERE}/rootfs/finalize.sh" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

echo "==> 1/6 Creating images and btrfs subvolumes"
"${HERE}/rootfs/create_images.sh"

echo "==> 2/6 Bootstrapping apk"
"${HERE}/rootfs/bootstrap.sh"

echo "==> 3/6 Writing deviceinfo"
"${HERE}/rootfs/deviceinfo.sh"

echo "==> 4/6 Installing postmarketOS packages"
"${HERE}/rootfs/install_packages.sh"

echo "==> 5/6 Configuring network"
"${HERE}/rootfs/configure_network.sh"

echo "==> 5b/6 Configuring runtime"
"${HERE}/rootfs/configure_runtime.sh"

echo "==> 6/6 Unmounting images"
"${HERE}/rootfs/finalize.sh"

trap - EXIT INT TERM
echo "Done. boot.raw / rootfs.raw 已就绪, 下一步运行 scripts/build_images.sh"
