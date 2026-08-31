#!/bin/sh -e
# =============================================================================
# rootfs 子模块: 卸载镜像 (幂等, 可安全重复执行)
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Unmounting images..."
sync
umount -l "${CHROOT}/proc" 2>/dev/null || true
umount -l "${CHROOT}/sys" 2>/dev/null || true
umount -l "${CHROOT}/dev" 2>/dev/null || true
umount -l "${CHROOT}/var/lib" 2>/dev/null || true
umount -l "${CHROOT}/boot" 2>/dev/null || true
umount -l "${CHROOT}" 2>/dev/null || true
