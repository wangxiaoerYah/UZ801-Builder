#!/bin/sh -e
# =============================================================================
# rootfs 子模块: 创建 boot/rootfs 镜像 + btrfs subvolume + 挂载
# 产出: boot.raw (ext2) / rootfs.raw (btrfs) 并挂载为 CHROOT
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

# 清理旧构建产物与挂载点
umount -l -R "${CHROOT}" 2>/dev/null || true
rm -rf "${CHROOT}" "${BOOT_IMG}" "${ROOT_IMG}"
mkdir -p "${CHROOT}" files

# 挂载失败时清理
trap 'umount -l "${CHROOT}/proc" 2>/dev/null || true; umount -l "${CHROOT}/sys" 2>/dev/null || true; umount -l "${CHROOT}/dev" 2>/dev/null || true; umount -l "${CHROOT}/var/lib" 2>/dev/null || true; umount -l "${CHROOT}/boot" 2>/dev/null || true; umount -l "${CHROOT}" 2>/dev/null || true' EXIT INT TERM

log "Creating image files..."
truncate -s "${BOOT_SIZE}" "${BOOT_IMG}"
mkfs.ext2 -q -L boot -U "${BOOT_FS_UUID}" "${BOOT_IMG}"

truncate -s "${ROOTFS_SIZE}" "${ROOT_IMG}"
# btrfs: pmOS initramfs 原生支持 (白名单 ext4/f2fs/btrfs), zstd 压缩节省 4GB eMMC 空间
mkfs.btrfs -q -L rootfs -U "${ROOTFS_FS_UUID}" "${ROOT_IMG}"

# btrfs subvolume 布局:
#   @        -> /        系统 (顶层保持干净, 不需要 @snapshots)
#   @var_lib -> /var/lib 数据库/状态数据 (独立挂载 + nodatacow, 可单独快照)
log "Creating btrfs subvolumes (@, @var_lib)..."
mount -o loop "${ROOT_IMG}" "${CHROOT}"
btrfs subvolume create "${CHROOT}/@" >/dev/null
btrfs subvolume create "${CHROOT}/@var_lib" >/dev/null
umount "${CHROOT}"
mount -o loop,subvol=@ "${ROOT_IMG}" "${CHROOT}"

# @var_lib 在 apk 安装前挂载, 使 /var/lib 数据直接写入独立 subvolume
mkdir -p "${CHROOT}/boot" "${CHROOT}/var/lib"
mount -o loop "${BOOT_IMG}" "${CHROOT}/boot"
mount -o loop,subvol=@var_lib "${ROOT_IMG}" "${CHROOT}/var/lib"

# 挂载虚拟文件系统: chroot 内 mkinitfs/boot-deploy 的 df 空间检查依赖 /proc /sys
mkdir -p "${CHROOT}/proc" "${CHROOT}/sys" "${CHROOT}/dev"
mount -t proc proc "${CHROOT}/proc" 2>/dev/null || true
mount -t sysfs sys "${CHROOT}/sys" 2>/dev/null || true
mount -o bind /dev "${CHROOT}/dev" 2>/dev/null || true

trap - EXIT INT TERM
log "Mounted: ${CHROOT} (@), ${CHROOT}/boot, ${CHROOT}/var/lib (@var_lib)"
