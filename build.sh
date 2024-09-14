#!/bin/sh -e
# =============================================================================
# OpenStick postmarketOS 镜像构建入口
#
# 用法:  sudo ./build.sh                          (默认 yiming-uz801v3)
#        sudo env BOARD=thwc-uf896 ./build.sh
#        sudo env BOARD=yiming-uz801v3 RELEASE_INPUT=v26.06 ./build.sh
# 注: 参数经 `sudo env` 传递 (sudo 默认清除环境变量)
# =============================================================================

echo "==> Install dependencies"
scripts/install_deps.sh

echo "==> Build hyp and aboot firmware"
scripts/build_hyp_aboot.sh

echo "==> Extract MSM8916 firmware (GPT + bootloader)"
scripts/extract_fw.sh

echo "==> Create postmarketOS rootfs"
scripts/pmos_rootfs.sh

echo "==> Create images"
scripts/build_images.sh

echo "==> Copy custom firmware partitions"
scripts/copy_custom_fw.sh

echo
echo "Build complete. 刷机文件位于 files/ 目录:"
ls -lh files/
