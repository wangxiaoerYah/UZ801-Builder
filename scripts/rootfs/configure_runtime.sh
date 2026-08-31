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

# ---- USB 网络: 完全采用 pmOS 官方 usb-tethering 机制 (无需额外配置) ----
# postmarketos-base-ui-networkmanager-usb-tethering 包自带完整方案:
#   - USB_Networking.nmconnection: usb0 = 172.16.42.1/16 manual (NM 管 IP)
#   - 50-tethering.sh dispatcher: 连接 up 时 killall unudhcpd -> 重启 unudhcpd
#     (DHCP 172.16.42.2) + reactivate gadget (电脑重新 DHCP)
#   - 50-tethering.conf: no-auto-default=usb0, managed=true
# 与 initramfs 的 unudhcpd (172.16.42.1) 网段一致, 开机后无缝交接:
# initramfs unudhcpd 残留持续服务引导早期, NM 激活 USB_Networking 连接后
# dispatcher killall 并重启 unudhcpd (同 IP 网段, 无冲突), 电脑无需干预。
# 不做任何本地覆盖 (不写 local.d / conf.d / rc 服务), 与官方行为一致。

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
  # 禁用磁盘 swapfile: btrfs 不支持普通 swapfile, 该服务从未生效, 白跑
  # (zram swap 564M 已足够; 避免每次启动尝试创建 + eMMC 写入)
  rc-update del swapfile 2>/dev/null || true
'

# ---- podman 容器配置 (服务器场景) ----
# 无根 (rootless) 子 uid/gid 映射
cat > "${CHROOT}/etc/subuid" <<'EOF'
user:100000:65536
EOF
cat > "${CHROOT}/etc/subgid" <<'EOF'
user:100000:65536
EOF
# 容器默认配置: crun 运行时 (默认), 日志限制, cgroupfs (openrc 无 systemd)
mkdir -p "${CHROOT}/etc/containers"
cat > "${CHROOT}/etc/containers/containers.conf" <<'EOF'
[containers]
log_size_max = 10485760
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF
# 内核模块预加载 (overlay 存储 + veth 网络)
printf 'overlay\nveth\n' > "${CHROOT}/etc/modules-load.d/containers.conf"

# ---- WiFi: 关闭省电 (服务器场景, USB 供电, 无功耗顾虑) ----
# wcn36xx + iwd 省电模式下帧级延迟高 (实测局域网 ping 15.6ms -> 4.8ms,
# 下载 1.3 -> 2.3 Mbps)。服务器场景必须关闭。
mkdir -p "${CHROOT}/etc/iwd"
cat > "${CHROOT}/etc/iwd/main.conf" <<'EOF'
[General]
EnablePowerSave=False
EOF

# ---- 网络 sysctl: 服务器场景 (USB 供电, 长期在线) ----
# 增大 TCP 缓冲区 (大文件下载/测速); BBR 内核未编入 (仅 reno/cubic), 保持 cubic
cat > "${CHROOT}/etc/sysctl.d/99-network.conf" <<'EOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 16384 16777216
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 75
EOF

# 服务器场景系统级优化
cat > "${CHROOT}/etc/sysctl.d/99-server.conf" <<'EOF'
kernel.panic = 10
fs.file-max = 65536
EOF

# ---- NTP (阿里云) ----
# 注释 chrony.conf 默认 pool.ntp.org, 追加阿里云 NTP
sed -i '/^pool / s/^/# /' "${CHROOT}/etc/chrony/chrony.conf"
mkdir -p "${CHROOT}/etc/chrony/sources.d"
cat > "${CHROOT}/etc/chrony/sources.d/aliyun.sources" <<'EOF'
server ntp.aliyun.com iburst
EOF

# ---- 时区 (默认上海) ----
ln -sf /usr/share/zoneinfo/Asia/Shanghai "${CHROOT}/etc/localtime"
echo "Asia/Shanghai" > "${CHROOT}/etc/timezone"
