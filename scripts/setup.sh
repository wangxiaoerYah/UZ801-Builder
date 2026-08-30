#!/bin/sh -e

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# 1. 预设时区与语言环境
echo 'tzdata tzdata/Areas select Etc' | debconf-set-selections
echo 'tzdata tzdata/Zones/Etc select UTC' | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

# 2. 预设 u-boot-menu 引导配置（apt upgrade 内核时自动更新 /boot/extlinux/extlinux.conf）
mkdir -p /etc/default
cat << 'EOF' > /etc/default/u-boot
# 1. 显式锁定 root 分区 PARTUUID（与 GPT 分区表 rootfs uuid 完全一致）
U_BOOT_ROOT="root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e"

# 2. 完整还原硬件启动参数
U_BOOT_PARAMETERS="console=ttyMSM0,115200 earlycon no_framebuffer=true rw rootwait audit=0"

# 3. 指定设备树相对路径
U_BOOT_FDT="qcom/msm8916-yiming-uz801v3.dtb"
U_BOOT_FDT_DIR="/dtbs/"

# 4. 当 /boot 为独立分区时，自动将 DTB 同步拷贝至 /boot/dtbs/
U_BOOT_SYNC_DTBS="true"
EOF

# 3. 优化 initramfs 生成配置
mkdir -p /etc/initramfs-tools/conf.d
cat << 'EOF' > /etc/initramfs-tools/conf.d/openstick.conf
MODULES=dep
COMPRESS=gzip
EOF

# 4. 安装 Debian 官方内核、引导组件及系统服务
apt-get update -qqy
apt-get upgrade -qqy
apt-get install -qqy --no-install-recommends \
    linux-image-arm64 \
    u-boot-menu \
    initramfs-tools \
    bridge-utils \
    dnsmasq \
    hostapd \
    iptables \
    libconfig11 \
    locales \
    modemmanager \
    netcat-traditional \
    net-tools \
    network-manager \
    openssh-server \
    qrtr-tools \
    rmtfs \
    sudo \
    systemd-timesyncd \
    tzdata \
    wireguard-tools \
    wpasupplicant

apt-get autoremove -qqy
apt-get clean
rm -rf /var/lib/apt/lists/*

# 5. 清理 root 密码并配置默认用户
passwd -d root

if ! id "user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash user
fi
echo "user:1" | chpasswd

echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/user
chmod 0440 /etc/sudoers.d/user