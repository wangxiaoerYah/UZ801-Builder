#!/bin/sh -e

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# 1. 预设时区与语言环境
echo 'tzdata tzdata/Areas select Etc' | debconf-set-selections
echo 'tzdata tzdata/Zones/Etc select UTC' | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

# 2. 优化 initramfs 生成配置（使用 MODULES=most 兼容 chroot 构建环境）
mkdir -p /etc/initramfs-tools/conf.d
cat << 'EOF' > /etc/initramfs-tools/conf.d/openstick.conf
MODULES=most
COMPRESS=gzip
EOF

mkdir -p /etc/kernel/postrm.d
cat << 'EOF' > /etc/kernel/postrm.d/10-dtb-clean
#!/bin/sh
set -e
KVER="$1"
if [ -n "${KVER}" ] && [ -d "/boot/dtbs/${KVER}" ]; then
    rm -rf "/boot/dtbs/${KVER}"
    echo "Cleaned up all DTBs for kernel ${KVER}"
fi
EOF
chmod +x /etc/kernel/postrm.d/10-dtb-clean

mkdir -p /etc/kernel/postinst.d
cat << 'EOF' > /etc/kernel/postinst.d/10-dtb-sync
#!/bin/sh
set -e
KVER="$1"
DTB_SRC="/usr/lib/linux-image-${KVER}/qcom"

# 将整个 qcom 目录完整拷贝到特定版本号的目录下
if [ -d "${DTB_SRC}" ]; then
    mkdir -p "/boot/dtbs/${KVER}/qcom"
    cp -a "${DTB_SRC}/." "/boot/dtbs/${KVER}/qcom/"
    echo "Synced all qcom DTBs for kernel ${KVER}"
fi
EOF
chmod +x /etc/kernel/postinst.d/10-dtb-sync

# 3. 安装 Debian 官方内核、引导组件及系统服务
apt-get update -qqy
apt-get upgrade -qqy
apt-get install -qqy --no-install-recommends \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
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

# 4. 写入 u-boot-menu 配置并更新 extlinux.conf
mkdir -p /etc/default
cat << 'EOF' > /etc/default/u-boot
U_BOOT_ROOT="root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e"
U_BOOT_PARAMETERS="console=ttyMSM0,115200 earlycon no_framebuffer=true rw rootwait audit=0"
U_BOOT_FDT="qcom/msm8916-yiming-uz801v3.dtb"
EOF


KERNEL_VER=$(ls /lib/modules | head -n 1)
/etc/kernel/postinst.d/10-dtb-sync "${KERNEL_VER}"
# 显式触发更新引导配置
u-boot-update

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