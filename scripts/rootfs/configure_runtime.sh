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

# ---- fstab: 用固定文件系统 UUID (mkfs -U 指定, 每次构建一致, 可写死) ----
# 引导链说明:
#   - boot-deploy 把 fstab 中 UUID= 条目转成 pmos_root_uuid / pmos_boot_uuid cmdline
#   - pmOS initramfs 用 `blkid --uuid` 匹配 (实测: 只认文件系统 UUID, 不认 PARTUUID!)
#     因此必须用 mkfs -U 指定的超级块 UUID, 不能用 extract_fw.sh 里的 GPT 分区 UUID
#   - fstab options 经 boot-deploy 转成 pmos_rootfsopts, 传给 initramfs 的 mount -o
#     subvol=@ 使 initramfs 挂载到 btrfs 的 @ subvolume (而非顶层)
#   - /var/lib 独立 @var_lib subvolume, nodatacow (数据库/状态数据禁 CoW)
cat > "${CHROOT}/etc/fstab" <<EOF
UUID=${ROOTFS_FS_UUID} /         btrfs subvol=@,compress=zstd,noatime,discard=async,ssd 0 1
UUID=${ROOTFS_FS_UUID} /var/lib  btrfs subvol=@var_lib,compress=zstd,noatime,discard=async,ssd,nodatacow 0 0
UUID=${BOOT_FS_UUID}   /boot     ext2  noatime 0 2
EOF

# ---- 主机名 ----
echo "${HOST_NAME}" > "${CHROOT}/etc/hostname"
sed -i "/localhost/ s/$/ ${HOST_NAME}/" "${CHROOT}/etc/hosts"

# ---- 串口控制台自动登录 (headless, 无屏幕) ----
sed -i '/^tty/ s/^/#/' "${CHROOT}/etc/inittab"
echo 'ttyMSM0::respawn:/sbin/getty -L 115200 ttyMSM0 vt100' >> "${CHROOT}/etc/inittab"

# ---- 默认用户 user / 密码 1 ----
chroot "${CHROOT}" /bin/sh -c '
  if ! id user >/dev/null 2>&1; then
      useradd -m -s /bin/bash user
  fi
  echo "user:1" | chpasswd
'
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > "${CHROOT}/etc/sudoers.d/user"
chmod 0440 "${CHROOT}/etc/sudoers.d/user"

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
'

# ---- 时区 (默认上海) ----
ln -sf /usr/share/zoneinfo/Asia/Shanghai "${CHROOT}/etc/localtime"
echo "Asia/Shanghai" > "${CHROOT}/etc/timezone"
