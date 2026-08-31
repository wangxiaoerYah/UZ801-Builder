#!/bin/sh -e
# =============================================================================
# rootfs 子模块: 运行时配置 (udev / fstab / 主机名 / 串口 / 用户 / 服务 / 时区)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Configuring runtime..."

# ---- USB gadget 模板 (gt) ----
mkdir -p "${CHROOT}/etc/gt"
cp -a configs/templates/* "${CHROOT}/etc/gt/"

# ---- udev: UDC 出现时加载 rndis gadget; NetworkManager 接管 gadget 网卡 ----
cat > "${CHROOT}/etc/udev/rules.d/10-udc.rules" <<'EOF'
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/bin/gt load rndis-os-desc.scheme rndis"
EOF
cat > "${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules" <<'EOF'
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# fstab 已由 install_packages.sh 在 apk add 前写入 (boot-deploy 需要)
# 说明: 固定文件系统 UUID (mkfs -U 指定); boot-deploy 据此生成
#   pmos_root_uuid / pmos_boot_uuid / pmos_rootfsopts (含 subvol=@)
# pmOS initramfs 用 blkid --uuid 匹配 (实测只认文件系统 UUID, 不认 PARTUUID)
# ---- 主机名 ----
echo "${HOST_NAME}" > "${CHROOT}/etc/hostname"
sed -i "/localhost/ s/$/ ${HOST_NAME}/" "${CHROOT}/etc/hosts"

# ---- 串口控制台 root 自动登录 (headless, 无屏幕; 与 Alpine 验证版一致) ----
sed -i '/^tty/ s/^/#/' "${CHROOT}/etc/inittab"
echo 'ttyMSM0::respawn:/bin/sh' >> "${CHROOT}/etc/inittab"

# ---- 默认用户 user / 密码 1 ----
chroot "${CHROOT}" /bin/sh -c '
  if ! id user >/dev/null 2>&1; then
      useradd -m -s /bin/bash user
  fi
  echo "user:1" | chpasswd
'
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > "${CHROOT}/etc/sudoers.d/user"
chmod 0440 "${CHROOT}/etc/sudoers.d/user"

# ---- USB 网络: 清理 initramfs 残留的 unudhcpd ----
# initramfs 用 unudhcpd 提供早期 USB 网络 (usb0=172.16.42.1, 电脑=172.16.42.2),
# switch_root 不终止它, 残留进程与 NM shared 的 dnsmasq DHCP 冲突
# (电脑可能拿到 172.16.42.2 但网关 172.16.42.1 已被 NM 覆盖 -> 网络不通)
# local 服务 (字母序在 networkmanager 前) 启动时杀掉, 让 NM 独占 usb0
mkdir -p "${CHROOT}/etc/local.d"
cat > "${CHROOT}/etc/local.d/usb-net.start" <<'EOF'
#!/bin/sh
# NM 接管 usb0 前清理 initramfs 残留的 unudhcpd (DHCP 冲突源)
pkill -x unudhcpd 2>/dev/null || true
EOF
chmod +x "${CHROOT}/etc/local.d/usb-net.start"

# ---- OpenRC 服务 ----
chroot "${CHROOT}" /bin/sh -c '
  rc-update add devfs sysinit
  rc-update add dmesg sysinit
  rc-update add udev sysinit
  rc-update add udev-trigger sysinit
  rc-update add udev-settle sysinit
  rc-update add udev-postmount default
  rc-update add dbus boot
  rc-update add iwd default
  rc-update add networkmanager default
  rc-update add modemmanager default
  rc-update add rmtfs default
  rc-update add chronyd default
  # zram swap (pmOS 内置: RAM 150%, zstd), 替代 eMMC swap 避免闪存磨损
  rc-update add postmarketos-zram-swap boot
  # swclock-offset (msm8916 RTC 时钟偏移修正, soc-qcom-msm8916-gpu 的依赖)
  # post-install 可能因 "swap 虚拟服务冲突" 警告而失败, 这里幂等补上
  rc-update add swclock-offset-boot boot 2>/dev/null || true
  rc-update add swclock-offset-shutdown shutdown 2>/dev/null || true
  # SSH (user 用户密码登录; host keys 由 install_packages.sh 生成)
  rc-update add sshd default
  rc-update add local default
'

# ---- 时区 (默认上海) ----
ln -sf /usr/share/zoneinfo/Asia/Shanghai "${CHROOT}/etc/localtime"
echo "Asia/Shanghai" > "${CHROOT}/etc/timezone"
