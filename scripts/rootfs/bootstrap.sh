#!/bin/sh -e
# =============================================================================
# rootfs 子模块: apk.static 引导 (宿主侧, 目标架构 aarch64)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Bootstrapping apk (aarch64)..."

# 新建的 @ subvolume 是空的, 先创建基础目录
mkdir -p "${CHROOT}/etc/apk" "${CHROOT}/usr/bin"

# 软件仓库: Alpine main/community + postmarketOS 官方
# 设备端 repositories 用国内镜像 (构建用官方源, 见 common.sh)
cat > "${CHROOT}/etc/apk/repositories" <<EOF
${DEVICE_MIRROR}/${ALPINE_RELEASE}/main
${DEVICE_MIRROR}/${ALPINE_RELEASE}/community
${DEVICE_PMOS_MIRROR}/${INPUT_RELEASE}
EOF
cp /etc/resolv.conf "${CHROOT}/etc/"

# qemu 用户态模拟 (仅 x86_64 宿主需要)
if [ "$(uname -m)" != "aarch64" ]; then
  cp "$(which qemu-aarch64-static)" "${CHROOT}/usr/bin/"
fi

# apk-tools-static 从 Alpine 官方 mirror 获取 (gitlab 上的 apk.static 直链已失效)
case "$(uname -m)" in
  x86_64) APK_STATIC_ARCH="x86_64" ;;
  aarch64|arm64) APK_STATIC_ARCH="aarch64" ;;
  *) fail "Unsupported host arch: $(uname -m)" ;;
esac

wget -q --tries=3 --timeout=30 \
  "${MIRROR}/${ALPINE_RELEASE}/main/${APK_STATIC_ARCH}/apk-tools-static-${APK_TOOLS_STATIC}.apk" \
  -O apk-tools-static.apk
tar xzf apk-tools-static.apk sbin/apk.static
mv sbin/apk.static apk.static
rm -rf sbin apk-tools-static.apk
chmod a+x apk.static
./apk.static add -p "${CHROOT}" --initdb -U --arch aarch64 --allow-untrusted alpine-base
rm -f apk.static
