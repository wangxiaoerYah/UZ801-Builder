#!/bin/sh -e
# =============================================================================
# bootloader 子模块: 编译 lk2nd (主线引导加载器, 支持 extlinux.conf)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

# 安全追加 MMC 降速补丁 (部分板子的 eMMC 高速模式不稳定, 幂等)
MK_FILE="src/lk2nd/project/lk1st-msm8916.mk"
if ! grep -q "USE_TARGET_HS200_CAPS=1" "$MK_FILE"; then
    echo 'DEFINES += USE_TARGET_HS200_CAPS=1' >> "$MK_FILE"
fi

log "Building lk2nd for ${BOARD} (compatible=${LK2ND_COMPATIBLE:-generic})..."
make -C src/lk2nd \
    LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" \
    LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE}" \
    TOOLCHAIN_PREFIX=arm-none-eabi- \
    lk1st-msm8916 -j$(nproc)
