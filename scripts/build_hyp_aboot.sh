#!/bin/sh -e
# =============================================================================
# 编译引导加载器: qhypstub + lk2nd + 签名
# 产出: files/hyp.mbn, files/aboot.mbn
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Building qhypstub"
"${HERE}/bootloader/build_qhypstub.sh"

echo "==> Building lk2nd"
"${HERE}/bootloader/build_lk2nd.sh"

echo "==> Signing binaries"
"${HERE}/bootloader/sign_bootloader.sh"

echo "Hyp and aboot built successfully."
