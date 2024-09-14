#!/bin/sh -e
# =============================================================================
# fw 子模块: 下载并校验高通官方引导固件 (rpm/sbl1/tz)
# DragonBoard 410c 同源包 (linaro 原链接已失效, 用 archive.org 镜像)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

SRC="https://archive.org/download/dragonboard-410c-bootloader-emmc-linux-176/dragonboard-410c-bootloader-emmc-linux-176.zip"
SHA256=a37c4e82a970ae2350fcfc7180559caf1dc3928e7c169316fe4ab899b7d305ad
FNAME=$(basename "${SRC}")

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT INT TERM
mkdir -p files

log "Downloading Qualcomm bootloader firmware..."
wget --tries=3 --timeout=30 -q --show-progress -P "${TMPDIR}" "${SRC}"

echo "${SHA256} ${TMPDIR}/${FNAME}" | sha256sum -c

unzip -o -j -d files/ "${TMPDIR}/${FNAME}" \
    "${FNAME%.*}/rpm.mbn" \
    "${FNAME%.*}/sbl1.mbn" \
    "${FNAME%.*}/tz.mbn"
