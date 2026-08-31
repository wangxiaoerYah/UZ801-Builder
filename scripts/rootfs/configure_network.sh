#!/bin/sh -e
# =============================================================================
# rootfs 子模块: 网络配置
#   - NM 强制 iwd 后端
#   - lte / usb 连接 (immutable, 不可删除)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Configuring network..."

# 网络栈: postmarketOS 官方 (postmarketos-base-ui-networkmanager)
#   - 自带 pmOS 调优: dns=dnsmasq, MAC 随机化, hostname-mode=none
#   - WiFi 后端选 iwd (STA 客户端模式, 更省电稳定); 无需 AP 热点
#   - iwd 通过 D-Bus 由 NM 驱动, 服务顺序: dbus -> iwd (before net) -> NM (provide net)

# 强制 NM 使用 iwd 作为 WiFi 后端 (NM 默认 wpa_supplicant)
mkdir -p "${CHROOT}/etc/NetworkManager/conf.d"
cat > "${CHROOT}/etc/NetworkManager/conf.d/50-use-iwd.conf" <<'EOF'
[device]
wifi.backend=iwd
EOF

# lte/usb 连接配置
mkdir -p "${CHROOT}/etc/NetworkManager/system-connections"
cp configs/*.nmconnection "${CHROOT}/etc/NetworkManager/system-connections/"
chmod 0600 "${CHROOT}/etc/NetworkManager/system-connections/"*
# lte/usb 连接设为 immutable (不可变), 防止被删除/修改; 需要改动时先 chattr -i
chattr +i "${CHROOT}/etc/NetworkManager/system-connections/lte.nmconnection" \
         "${CHROOT}/etc/NetworkManager/system-connections/usb.nmconnection"
