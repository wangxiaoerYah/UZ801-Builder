#!/bin/sh -e
# =============================================================================
# bootloader 子模块: 编译 qhypstub (移除高通 Hypervisor 的桩)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

# 交叉编译器前缀 (x86_64 宿主需要, aarch64 原生用空)
if [ "$(uname -m)" = "x86_64" ]; then
    CROSS_COMPILE="aarch64-linux-gnu-"
else
    CROSS_COMPILE=""
fi

log "Building qhypstub..."
make -C src/qhypstub CROSS_COMPILE="${CROSS_COMPILE}"
