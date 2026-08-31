#!/bin/sh -e
# =============================================================================
# rootfs 子模块: 安装 postmarketOS 基础包 + 自定义 dtb
# =============================================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../lib/common.sh"

log "Installing postmarketOS base packages (${INPUT_RELEASE})..."
chroot "${CHROOT}" /bin/sh -c "
  # merge-usr 必须先于 apk add: pmOS initramfs 文件列表要求 /usr/sbin/xxx 路径,
  # 而内核包安装时 mkinitfs trigger 立即运行, 晚了会因缺 /usr/sbin/losetup 失败
  # (apk.static 引导阶段无法执行 aarch64 post-install, 所以手动执行)
  /usr/bin/merge-usr
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
