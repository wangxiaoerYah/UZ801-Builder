#!/bin/sh -e

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

echo 'tzdata tzdata/Areas select Etc' | debconf-set-selections
echo 'tzdata tzdata/Zones/Etc select UTC' | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

mkdir -p /etc/initramfs-tools/conf.d
cat << 'EOF' > /etc/initramfs-tools/conf.d/openstick.conf
MODULES=most
COMPRESS=xz
EOF

mkdir -p /etc/kernel/postrm.d
cat << 'EOF' > /etc/kernel/postrm.d/10-dtb-clean
#!/bin/sh
set -e
KVER="$1"
if [ -n "${KVER}" ] && [ -d "/boot/dtb-${KVER}" ]; then
    rm -rf "/boot/dtb-${KVER}"
fi
EOF
chmod +x /etc/kernel/postrm.d/10-dtb-clean

mkdir -p /etc/kernel/postinst.d
cat << 'EOF' > /etc/kernel/postinst.d/10-dtb-sync
#!/bin/sh
set -e
KVER="$1"
DTB_SRC="/usr/lib/linux-image-${KVER}/qcom"
DTB_DST="/boot/dtb-${KVER}/qcom"

if [ -d "${DTB_SRC}" ]; then
    mkdir -p "${DTB_DST}"
    cp -a "${DTB_SRC}/." "${DTB_DST}/"
fi
EOF
chmod +x /etc/kernel/postinst.d/10-dtb-sync

# 写入纯正的原生配置
mkdir -p /etc/default
cat << 'EOF' > /etc/default/u-boot
U_BOOT_ROOT="root=PARTLABEL=rootfs"
U_BOOT_PARAMETERS="console=ttyMSM0,115200 earlycon no_framebuffer=true rw rootwait audit=0"
U_BOOT_FDT="qcom/msm8916-yiming-uz801v3.dtb"
U_BOOT_FDT_DIR="/dtb-"
EOF

# 安装内核。由于 /boot 是真实挂载，dpkg 安装内核时会自动触发 DTB 同步与 u-boot-update
apt-get update -qqy
apt-get upgrade -qqy
apt-get install -qqy --no-install-recommends \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    linux-image-arm64 u-boot-menu initramfs-tools xz-utils bridge-utils dnsmasq \
    hostapd iptables libconfig11 locales modemmanager netcat-traditional \
    net-tools network-manager openssh-server qrtr-tools rmtfs sudo \
    systemd-timesyncd tzdata wireguard-tools wpasupplicant

u-boot-update

apt-get autoremove -qqy
apt-get clean
rm -rf /var/lib/apt/lists/*

passwd -d root
if ! id "user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash user
fi
echo "user:1" | chpasswd
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/user
chmod 0440 /etc/sudoers.d/user