#!/bin/sh -e

CHROOT=${CHROOT:-$(pwd)/rootfs}
RELEASE=${RELEASE:-stable}
HOST_NAME=${HOST_NAME:-openstick-debian}
ARCH=$(uname -m)

if [ -d "${CHROOT}" ]; then
    echo "Cleaning up old rootfs mount points and directory..."
    umount -l -R "${CHROOT}" 2>/dev/null || true
    rm -rf "${CHROOT}"
fi

# 加入 boot 的安全卸载
cleanup_mounts() {
    for a in proc sys dev/pts dev run boot; do
        umount -l "${CHROOT}/${a}" 2>/dev/null || true
    done
}
trap cleanup_mounts EXIT INT TERM

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo "Running native ARM64 debootstrap..."
    debootstrap --arch arm64 --keyring /usr/share/keyrings/debian-archive-keyring.gpg "${RELEASE}" "${CHROOT}"
    CHROOT_PREFIX=""
else
    echo "Running cross-architecture debootstrap with QEMU..."
    debootstrap --foreign --arch arm64 --keyring /usr/share/keyrings/debian-archive-keyring.gpg "${RELEASE}" "${CHROOT}"
    
    QEMU_BIN=$(which qemu-aarch64-static 2>/dev/null || which qemu-arm-static 2>/dev/null || echo "/usr/bin/qemu-aarch64-static")
    cp "$QEMU_BIN" "${CHROOT}/usr/bin/"
    chroot "${CHROOT}" qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage
    CHROOT_PREFIX="qemu-aarch64-static"
fi

cat << EOF > "${CHROOT}/etc/apt/sources.list"
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

# 关键改动：提前创建并挂载真实的 boot 分区
echo "Creating and mounting raw boot image..."
mkdir -p "${CHROOT}/boot"
truncate -s 134217728 boot.raw
mkfs.ext4 -F -L boot boot.raw
mount -o loop boot.raw "${CHROOT}/boot"

# 挂载其他虚拟文件系统
mount -t proc proc "${CHROOT}/proc/"
mount -t sysfs sys "${CHROOT}/sys/"
mount -o bind /dev/ "${CHROOT}/dev/"
mount -o bind /dev/pts/ "${CHROOT}/dev/pts/"
mount -o bind /run "${CHROOT}/run/"

cp scripts/setup.sh "${CHROOT}"
chroot "${CHROOT}" ${CHROOT_PREFIX} /bin/sh -c /setup.sh

# 卸载所有挂载点（此时 boot.raw 已经写入完毕并被安全弹出）
cleanup_mounts
trap - EXIT INT TERM

rm -f "${CHROOT}/setup.sh"
echo -n > "${CHROOT}/root/.bash_history"

echo "${HOST_NAME}" > "${CHROOT}/etc/hostname"
sed -i "/localhost/ s/$/ ${HOST_NAME}/" "${CHROOT}/etc/hosts"

cp -a configs/system/* "${CHROOT}/etc/systemd/system"
cp -a scripts/msm-firmware-loader.sh "${CHROOT}/usr/sbin"

cp configs/*.nmconnection "${CHROOT}/etc/NetworkManager/system-connections"
chmod 0600 "${CHROOT}/etc/NetworkManager/system-connections"/*
sed -i '/\[main\]/a dns=dnsmasq' "${CHROOT}/etc/NetworkManager/NetworkManager.conf"

cat << EOF > "${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules"
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

mkdir -p "${CHROOT}/lib/firmware/msm-firmware-loader"
cat << EOF > "${CHROOT}/etc/fstab"
PARTLABEL=rootfs  /      ext4  defaults,noatime  0  1
PARTLABEL=boot    /boot  ext4  defaults,noatime  0  2
EOF

rm -f "${CHROOT}/usr/bin/qemu-aarch64-static"

# 由于 boot.raw 已被卸载，这里打包出的 rootfs.tgz 将拥有一个完美的空 /boot 挂载点
tar cpzf rootfs.tgz -C rootfs .