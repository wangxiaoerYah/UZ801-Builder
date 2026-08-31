#!/bin/sh
# =============================================================================
# 共享配置与工具函数
# 被 scripts/ 下各子模块 source, 提供统一参数/映射/日志
# =============================================================================

set -eu

# ---- 工具函数 ---------------------------------------------------------------
log() { printf '[%s] %s\n' "$(basename "$0")" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# ---- 可配置参数 (可被环境变量覆盖) -----------------------------------------
INPUT_RELEASE="${RELEASE_INPUT:-v26.06}"        # postmarketOS 版本 (默认 v26.06, 可选 v25.12)
BOARD="${BOARD:-yiming-uz801v3}"                # 目标板子
CHROOT="${CHROOT:-$(pwd)/rootfs}"               # rootfs 挂载点
HOST_NAME="${HOST_NAME:-openstick}"
BOOT_SIZE="${BOOT_SIZE:-134217728}"              # boot 分区 128MB (ext2)
ROOTFS_SIZE="${ROOTFS_SIZE:-1610612736}"        # rootfs 分区 1.5GB (btrfs)
MIRROR="${MIRROR:-http://dl-cdn.alpinelinux.org/alpine}"
PMOS_MIRROR="${PMOS_MIRROR:-http://mirror.postmarketos.org/postmarketos}"

# 固定文件系统 UUID (mkfs 时用 -U 指定, 每次构建一致, fstab 可写死)
# 注意: 这是文件系统 UUID (超级块), 不是 GPT 分区 UUID (PARTUUID)
# pmOS initramfs 用 `blkid --uuid` 匹配, 实测只认文件系统 UUID
ROOTFS_FS_UUID="${ROOTFS_FS_UUID:-dabec847-f9bf-4b4c-881c-4bcb50bb8564}"
BOOT_FS_UUID="${BOOT_FS_UUID:-e089097f-bee7-4339-839b-1d4af1a6f756}"

# ---- 派生变量 ---------------------------------------------------------------
BOOT_IMG="boot.raw"
ROOT_IMG="rootfs.raw"

# ---- 版本映射: pmOS release -> Alpine release -> apk-tools-static -> 设备包名 ----
# 注意: v26.06 起 pmOS 将设备包重命名为 device-zhihe-generic (v25.12 为 device-generic-zhihe)
case "$INPUT_RELEASE" in
  v26.06) ALPINE_RELEASE="v3.24"; APK_TOOLS_STATIC="3.0.7-r0"; DEVICE_PKG="device-zhihe-generic" ;;
  v25.12) ALPINE_RELEASE="v3.23"; APK_TOOLS_STATIC="3.0.7-r0"; DEVICE_PKG="device-generic-zhihe" ;;
  *) fail "Unsupported RELEASE_INPUT: $INPUT_RELEASE (支持 v25.12 / v26.06)" ;;
esac

# ---- 板子映射: 板子 -> deviceinfo dtb + lk2nd compatible ----
case "$BOARD" in
  yiming-uz801v3) DTB="qcom/msm8916-yiming-uz801v3"; LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE:-yiming,uz801-v3}" ;;
  thwc-uf896)     DTB="qcom/msm8916-thwc-uf896";     LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE:-thwc,uf896}" ;;
  thwc-ufi001c)   DTB="qcom/msm8916-thwc-ufi001c";   LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE:-thwc,ufi001c}" ;;
  jz01-45-v33)    DTB="qcom/msm8916-jz01-45-v33";    LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE:-}" ;;
  fy-mf800)       DTB="qcom/msm8916-fy-mf800";       LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE:-}" ;;
  *) fail "Unsupported BOARD: $BOARD (支持 yiming-uz801v3 / thwc-uf896 / thwc-ufi001c / jz01-45-v33 / fy-mf800)" ;;
esac
