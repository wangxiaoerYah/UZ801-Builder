#!/bin/sh -e
# =============================================================================
# rootfs 子模块: 安装 postmarketOS 基础包 + 自定义 dtb
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Installing postmarketOS base packages (${INPUT_RELEASE})..."
chroot "${CHROOT}" /bin/sh -c "
  apk add --no-cache --allow-untrusted postmarketos-keys
  apk add --no-cache \
      postmarketos-base \
      postmarketos-mkinitfs \
      postmarketos-installkernel \
      boot-deploy \
      ${DEVICE_PKG} \
      linux-postmarketos-qcom-msm8916 \
      soc-qcom-msm8916-gpu \
      gadget-tool \
      postmarketos-base-ui-networkmanager \
      postmarketos-base-ui-wifi-iwd \
      iwd-openrc \
      networkmanager-openrc \
      dbus-openrc \
      modemmanager \
      rmtfs \
      rmtfs-openrc \
      msm-firmware-loader \
      qrtr \
      qmi-utils \
      libqmi \
      iptables \
      nftables \
      shadow \
      bash \
      chrony \
      curl \
      wget \
      nano \
      htop \
      vnstat \
      util-linux \
      e2fsprogs-extra \
      btrfs-progs \
      tzdata

  # 清除缓存, 减小镜像体积
  rm -rf /var/cache/apk/*
"

# merge-usr: 合并 /bin /sbin /lib -> /usr/*
# apk.static 引导阶段 (宿主侧) 无法执行 aarch64 post-install, 需手动执行
# pmOS initramfs 文件列表要求 /usr/sbin/losetup 等, 不合并则 mkinitfs 失败
chroot "${CHROOT}" /bin/sh -c '/usr/bin/merge-usr'

# 内核包 dtbs 缺少的板子 (jz01-45-v33 / fy-mf800), 从仓库复制自定义 dtb
case "$BOARD" in
  jz01-45-v33)
    log "Copying custom dtb for ${BOARD}..."
    mkdir -p "${CHROOT}/boot/dtbs/qcom"
    cp "dtbs/msm8916-jz01-45-v33.dtb" "${CHROOT}/boot/dtbs/qcom/" ;;
  fy-mf800)
    log "Copying custom dtb for ${BOARD}..."
    mkdir -p "${CHROOT}/boot/dtbs/qcom"
    cp "dtbs/msm8916-fy-mf800.dtb" "${CHROOT}/boot/dtbs/qcom/" ;;
esac
