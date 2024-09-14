#!/bin/sh -e
# =============================================================================
# bootloader 子模块: 用 qtestsign 签名 hyp / aboot
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Signing binaries..."
mkdir -p files
python3 src/qtestsign/qtestsign.py hyp src/qhypstub/qhypstub.elf \
    -o files/hyp.mbn
python3 src/qtestsign/qtestsign.py aboot src/lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn \
    -o files/aboot.mbn
