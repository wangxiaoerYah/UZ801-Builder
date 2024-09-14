#!/bin/sh -e
# =============================================================================
# 提取 MSM8916 固件: GPT 分区表 + 高通官方引导固件
# 产出: files/gpt_both0.bin, rpm.mbn, sbl1.mbn, tz.mbn
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Generating GPT partition table"
"${HERE}/fw/generate_gpt.sh"

echo "==> Downloading Qualcomm bootloader firmware"
"${HERE}/fw/download_bootloader.sh"

echo "Firmware extracted successfully."
