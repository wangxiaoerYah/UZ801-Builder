# OpenStick Builder — 构建说明

MSM8916 4G 棒子 (UZ801 系列) 的 postmarketOS 镜像构建器。

## 架构决策 (2025)

- **放弃 Debian** (无法启动), **放弃 armv7 Alpine**
- 改为 **postmarketOS aarch64**:
  - postmarketOS 本身就是 Alpine 之上的发行版, 直接使用其官方 `postmarketos-base` / 设备包 / `mkinitfs` / `boot-deploy`
  - 内核 `linux-postmarketos-qcom-msm8916` 是 apk 包 → **设备端可自升级**, 无需重编译镜像
  - headless (无 GUI), 串口 + SSH 管理
- 引导链: lk2nd (extlinux) + qhypstub, 内核/initramfs/dtb/extlinux.conf 全部由 boot-deploy 自动部署

## 构建流水线

| 步骤 | 入口脚本 | 产出 |
| ---- | --------- | ---- |
| 1. 依赖 | `scripts/install_deps.sh` | 宿主环境 |
| 2. 引导加载器 | `scripts/build_hyp_aboot.sh` | `files/hyp.mbn`, `files/aboot.mbn` |
| 3. GPT + 引导固件 | `scripts/extract_fw.sh` | `files/gpt_both0.bin`, `rpm/sbl1/tz.mbn` |
| 4. ★ rootfs | `scripts/pmos_rootfs.sh` | `boot.raw` (ext2), `rootfs.raw` (btrfs, zstd) |
| 5. 镜像 | `scripts/build_images.sh` | `files/boot.bin`, `files/rootfs.bin` (sparse) |
| 6. 专有固件 | `scripts/copy_custom_fw.sh` | `files/*.bin` (fsc/fsg/modem/...) |

## 脚本结构 (小脚本, 一个文件一件事)

```
scripts/
  顶层入口 (仅 6 个可执行脚本, 对应流水线)
  lib/common.sh                  # 共享: 参数/版本映射/板子映射/log/fail
  bootloader/
    build_qhypstub.sh            # 编译 qhypstub
    build_lk2nd.sh               # 编译 lk2nd (+ MMC 降速补丁)
    sign_bootloader.sh           # qtestsign 签名
  fw/
    generate_gpt.sh              # GPT 分区表 + gpt_both0.bin
    download_bootloader.sh       # 下载 rpm/sbl1/tz
  rootfs/
    create_images.sh             # boot.raw/rootfs.raw + subvolume + 挂载
    bootstrap.sh                 # apk.static 引导
    deviceinfo.sh                # 写入 deviceinfo
    install_packages.sh          # apk 安装 + 自定义 dtb
    configure_network.sh         # NM/iwd/连接 immutable
    configure_runtime.sh         # udev/fstab/用户/服务/时区
    finalize.sh                  # 卸载 (幂等)
```

- 子模块通过 `lib/common.sh` 共享参数 (环境变量可覆盖), 可独立调试
- 顶层入口负责编排 + 失败清理 (trap → finalize)

## merge-usr (重要坑)

- pmOS 基于 **usrmerge**: `/bin` `/sbin` `/lib` 合并到 `/usr/*` (符号链接)
- initramfs 文件列表要求 `/usr/sbin/losetup` 等路径, 不合并则 **mkinitfs 失败** (boot 分区无 initramfs/extlinux.conf)
- apk.static 引导阶段 (宿主侧) 无法执行 aarch64 post-install → merge-usr 需在 `install_packages.sh` 里手动执行
- 已在 `apk add` 之后执行 `/usr/bin/merge-usr` (实测修复)

## 版本支持

| RELEASE_INPUT | Alpine 基础 | 设备包名 | 说明 |
| ------------- | ----------- | -------- | ---- |
| **v26.06** (仅支持) | v3.24 | `device-zhihe-generic` | 内核 6.12.1-r5; rmtfs 由 Alpine v3.24 提供 |

> 默认构建已全面切到 v26.06 (已验证全部依赖闭环: pmOS 仓库 + Alpine v3.24 main/community)。

## pmos_rootfs.sh 详解 (核心)

1. 创建 `boot.raw` (ext2, 128MB) 与 `rootfs.raw` (btrfs, zstd 压缩), 直接挂载为 chroot 的 `/` 与 `/boot`
2. 用 `apk.static --arch aarch64` + qemu-aarch64-static 引导
3. 仓库: Alpine `main`/`community` + postmarketOS 官方 mirror
4. 写入 `/usr/share/deviceinfo/deviceinfo` (boot-deploy/mkinitfs 的依据)
5. `apk add postmarketos-base ...` — **安装内核时 mkinitfs 触发器自动运行**, boot-deploy 把 vmlinuz/initramfs/dtb/extlinux.conf 写进挂载中的 boot.raw
6. 配置 fstab (动态文件系统 UUID)、NetworkManager、udev、OpenRC 服务、串口登录、用户

### 关键依赖链 (自升级机制)

```
apk upgrade
  └─ linux-postmarketos-qcom-msm8916 更新
       └─ apk trigger (postmarketos-mkinitfs)
            └─ /usr/sbin/mkinitfs   → 重建 initramfs
            └─ boot-deploy          → 更新 /boot/vmlinuz + extlinux.conf
                 └─ 下次重启 lk2nd 加载新内核
```

### 分区表 (extract_fw.sh, boot 已扩至 128MB)

```
p1  fsc      p8  hyp     p13 boot   (ext2, 128MB)
p2  fsg      p9  rpm     p14 rootfs (btrfs, 名义 2015 扇区)
p3  modem    p10 sbl1
p4  modemst1 p11 tz
p5  modemst2 p12 aboot
p6  persist
p7  sec
```

- boot 已由 64MB 扩至 128MB (分区表与 boot.raw 同步调整); rootfs 声明保持 2015 扇区不变
- ⚠️ fastboot 刷 sparse 镜像时按实际数据写入, GPT 里 rootfs 声明的 2015 扇区不影响 1.5GB 的 rootfs.bin 完整写入
- 分区名保持 **boot / rootfs** (兼容 lk2nd 对 <16MB 小分区的 label 豁免, 以及 fastboot 传统命令)
- fstab 用**固定文件系统 UUID** (`mkfs -U` 指定, 每次构建一致): 实测 `blkid --uuid` 只认超级块 UUID, 不认 GPT 分区 UUID (PARTUUID), 所以不能用 extract_fw.sh 里的值
- fastboot 刷写: `fastboot flash boot boot.bin` / `fastboot flash rootfs rootfs.bin`

### 网络栈 (pmOS 官方)

- `postmarketos-base-ui-networkmanager` + `postmarketos-base-ui-wifi-wpa_supplicant` + `networkmanager-openrc` + `dbus-openrc`
- 自带 pmOS 调优: `dns=dnsmasq`、MAC 随机化、`hostname-mode=none`
- WiFi 后端用 **iwd** (STA 客户端模式, 更省电稳定; 不需要 AP 热点)
- 服务顺序: `dbus` → `iwd` (before net) → `networkmanager` (provide net)
- 连接: `lte` (wwan0qmi0 4G) / `usb` (usb0 gadget 网卡)
- **lte / usb 连接文件为 immutable** (`chattr +i`): 不可删除/修改, 需要改动时先 `chattr -i`
- 连接 WiFi: `nmcli device wifi connect <SSID> password <pwd>` 或 `nmtui`

### 文件系统选择

| 分区 | 格式 | 原因 |
| ---- | ---- | ---- |
| boot | **ext2** (固定) | lk2nd 硬编码 ext2 驱动, 仅支持经典块映射; ext4 的 extents/64bit 特性会导致挂载失败 |
| rootfs | **btrfs** (@ subvolume + zstd) | pmOS initramfs 白名单 ext4/f2fs/btrfs; 系统装在 `@` subvolume (顶层干净); `subvol=@` 经 fstab → `pmos_rootfsopts` 传给 initramfs 的 mount -o |

### btrfs eMMC 优化配置

挂载选项 (fstab): `subvol=@,compress=zstd,noatime,discard=async,ssd`

| 选项 | 作用 |
| ---- | ---- |
| `compress=zstd` | 压缩减少写入量 (eMMC 寿命) |
| `noatime` | 禁止访问时间更新, 减少读改写 |
| `discard=async` | 异步 TRIM (内核 6.2+, 我们的 6.12 支持), 减少写放大且不阻塞 IO |
| `ssd` | 显式启用 SSD 模式 (eMMC 通常自动探测, 显式更稳) |

### subvolume 布局

```
顶层          (干净, 仅含下面两个 subvolume)
@        -> /         系统 (含 /etc /usr /boot 挂载点)
@var_lib -> /var/lib  数据库/状态数据
```

- `@var_lib` 独立挂载: 可单独快照/回滚数据库, 系统升级与数据隔离
- 启动时序: initramfs 挂 `subvol=@` → openrc `localmount` 挂 `/var/lib` (dbus 等服务的 init.d 声明 `need localmount`, 顺序保证)

### CoW 与数据库 (写时复制影响)

- **有影响**: SQLite/vnstat、ModemManager 等自带事务机制 (WAL/journal), btrfs CoW 会导致:
  1. 数据库文件碎片化 (每次修改产生新 extent) → 随机读性能下降
  2. 崩溃时文件可能处于新旧块混合状态, 与数据库自身的 WAL 恢复假设冲突 (低概率但存在)
- **对策**: `/var/lib` 挂载选项含 **nodatacow** (整个挂载内所有文件生效, 比 chattr +C 更彻底)
  - 代价: 这些文件不压缩 (数据库随机数据压缩率本就低, 可接受)
- **日志保留 CoW + zstd** (文本压缩率高, 写放大影响小)

### 内存策略 (512MB RAM)

- **zram swap** (默认启用): postmarketOS 内置 `postmarketos-zram`, RAM 的 150% (≈768MB) + zstd 压缩 + `vm.swappiness=180`
- 不建 eMMC swap: 闪存写入寿命 + 慢速 eMMC 卡顿
- 可在 deviceinfo 加 `deviceinfo_zram_swap_pct="200"` 调大或 `"0"` 禁用
- fstab 用固定文件系统 UUID (`mkfs -U` 指定: rootfs=dabec847-... boot=e089097f-...), boot-deploy 据此生成 `pmos_root_uuid` / `pmos_boot_uuid` 到 cmdline, pmOS initramfs 用 `blkid --uuid` 匹配 (实测验证)

## 自定义

| 想改什么 | 改哪里 |
| -------- | ------ |
| 4G APN | `configs/lte.nmconnection` |
| 默认用户/密码 | `scripts/pmos_rootfs.sh` (user/1) |
| 额外软件包 | `scripts/pmos_rootfs.sh` 的 `apk add` 列表 |
| USB gadget 功能 | `configs/templates/` + `etc/gt` 加载方案 |
| 分区大小 | `scripts/extract_fw.sh` (固定布局) / `scripts/pmos_rootfs.sh` (BOOT_SIZE/ROOTFS_SIZE) |

## 排错

- **内核更新后不生效**: 检查 `/boot` 是否挂载 (`mount | grep boot`), `ls /boot/vmlinuz*`
- **modem 不工作**: `rc-service rmtfs status`, `rc-service modemmanager status`, 检查 `msm-firmware-loader` 日志
- **USB gadget 无网卡**: `gt list`, 检查 `dmesg | grep -i udc`
- **回滚内核**: boot-deploy 会保留 `/boot/vmlinuz.old`? 不, 它备份为 `.old`, 可手动 `cp /boot/vmlinuz.old /boot/vmlinuz`
