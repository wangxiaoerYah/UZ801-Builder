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

  # fstab 必须先于内核安装: mkinitfs trigger 在 apk add 结束时运行,
  # boot-deploy 从 fstab 读取 UUID/options 生成 pmos_root_uuid/pmos_rootfsopts
  # 若 fstab 后写, extlinux.conf 缺 root 定位参数 -> 无法引导
  # (固定文件系统 UUID, mkfs -U 指定; /var/lib 独立 @var_lib subvolume + nodatacow)
  cat > /etc/fstab <<EOF
UUID=${ROOTFS_FS_UUID} /         btrfs subvol=@,compress=zstd,noatime,discard=async,ssd 0 1
UUID=${ROOTFS_FS_UUID} /var/lib  btrfs subvol=@var_lib,compress=zstd,noatime,discard=async,ssd,nodatacow 0 0
UUID=${BOOT_FS_UUID}   /boot     ext2  noatime 0 2
EOF

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
      qmi-ping \
      qmic \
      libqmi \
      libqmi-bash-completion \
      iperf3 \
      # Alpine 的 iptables 即 iptables-nft (nftables 后端兼容层),
      # 保留以支持传统 iptables 命令语法, 实际规则走 nft
      iptables \
      nftables \
      # podman 容器 (服务器场景; 无根需 slirp4netns/fuse-overlayfs/shadow-uidmap)
      podman \
      podman-docker \
      slirp4netns \
      fuse-overlayfs \
      shadow-uidmap \
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

  # 生成 SSH host keys (bootstrap 阶段 apk.static 无法执行 aarch64 post-install)
  # 缺失时 sshd 报 'no hostkeys available' 拒绝启动
  # pmOS 默认 SSH = openssh-server-pam (postmarketos-base-ssh 依赖), sshd.pam 同样需要 keys
  [ -e /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A

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
