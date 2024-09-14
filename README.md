# OpenStick Builder (postmarketOS)

基于 **postmarketOS** (aarch64) 的 MSM8916 4G 随身 WiFi 棒子 (UZ801 及同系列) 镜像构建器。

把廉价的安卓 LTE 棒子改装成一台 **headless 的 Linux 小主机**:

- 🧠 **postmarketOS aarch64** — 无 GUI, 纯串口/SSH 控制台 (设备无屏幕)
- ⚡ **内核** `linux-postmarketos-qcom-msm8916` (主线内核, apk 包)
- 🔄 **设备端自升级** — `apk update && apk upgrade` 即可升级内核与全部软件, 无需重新编译镜像
- 🗜️ **btrfs rootfs** (@ subvolume + zstd 压缩) — 对 4GB eMMC 容量友好; boot 分区固定 ext2 (lk2nd 限制)
- 🧠 **zram swap** — 512MB RAM 自动扩展 ~768MB 压缩内存, 不磨损 eMMC
- 🔌 **USB gadget** — 插上电脑即插即用 (rndis 网卡 192.168.5.1)
- 📶 **WiFi 客户端** (iwd 后端, 省电稳定) + **4G LTE 上网** (ModemManager/QMI)

## 构建

### 本地构建 (Ubuntu 22.04+ / x86_64 或 ARM64)

```shell
git clone --recurse-submodules <repo-url>
cd UZ801-Builder

# 一键构建 (默认 yiming-uz801v3)
sudo ./build.sh

# 指定板子 / 版本 (参数需经 sudo env 传递; 默认 RELEASE_INPUT=v26.06)
sudo env BOARD=thwc-uf896 ./build.sh
sudo env BOARD=yiming-uz801v3 RELEASE_INPUT=v25.12 ./build.sh
```

产物位于 `files/`:

| 文件 | 说明 |
| ---- | ---- |
| `gpt_both0.bin` | GPT 分区表 (固定布局: p13=boot ext2 128MB, p14=rootfs; fastboot 按实际数据刷入 sparse 镜像) |
| `aboot.mbn` / `hyp.mbn` | lk2nd + qhypstub (签名引导加载器) |
| `rpm.mbn` / `sbl1.mbn` / `tz.mbn` | 高通官方引导固件 |
| `boot.bin` | 内核 + initramfs + dtb + extlinux.conf (sparse) |
| `rootfs.bin` | postmarketOS 根文件系统 (sparse) |
| `fsc.bin` ... `sec.bin` | 设备专有分区备份 (来自 `firmware/<board>/`) |

### GitHub Actions 云构建

1. Fork 本仓库
2. Actions → **Build postmarketOS image** → Run workflow (可选 board / release)
3. 完成后下载 artifact, 或从自动发布的 GitHub Release 获取

## 刷机

> ⚠️ **有变砖风险, 请谨慎操作!**
> 刷机前务必用 `edl rf orig_fw.bin` 备份原固件。

### 前置

- [EDL](https://github.com/bkerler/edl) 工具
- Android fastboot (`sudo apt install fastboot`)

### 步骤

1. 按 [pmOS wiki 指南](https://wiki.postmarketos.org/wiki/Zhihe_series_LTE_dongles_(generic-zhihe)#How_to_enter_flash_mode) 进入高通 EDL 模式

2. 备份专有分区 (若 `firmware/` 下已有则跳过):
   ```shell
   for n in fsc fsg modem modemst1 modemst2 persist sec; do
       edl r ${n} ${n}.bin
   done
   ```

3. 刷入 lk2nd, 重启到 fastboot:
   ```shell
   edl w aboot aboot.mbn
   edl e boot
   edl reset
   ```

4. 刷入 GPT + 引导链 + 系统:
   ```shell
   fastboot flash partition gpt_both0.bin
   fastboot flash aboot aboot.mbn
   fastboot flash hyp hyp.mbn
   fastboot flash rpm rpm.mbn
   fastboot flash sbl1 sbl1.mbn
   fastboot flash tz tz.mbn
   fastboot flash boot boot.bin
   fastboot flash rootfs rootfs.bin
   ```

5. 还原专有分区 (modem 固件、WiFi 校准等):
   ```shell
   for n in fsc fsg modem modemst1 modemst2 persist sec; do
       fastboot flash ${n} ${n}.bin
   done
   fastboot reboot
   ```

> `firmware/yiming-uz801v3/` 下还提供了一键刷机脚本 `flash.sh` / `flash.bat`。

## 使用

| | |
| ---- | ---- |
| 串口 | ttyMSM0 @ 115200, 自动登录 root |
| SSH | ssh user@<ip> (密码 `1`) |
| WiFi | iwd 客户端, `nmcli device wifi connect <SSID> password <pwd>` 或 `nmtui` |
| USB 网卡 | usb0 @ 192.168.5.1 |
| 4G | ModemManager 管理, APN `internet` |
| 默认用户 | `user` / `1` (sudo NOPASSWD) |

> 网络由 NetworkManager 管理 (pmOS 官方栈)。`lte` / `usb` 连接文件为 immutable (不可删除); 需要修改时:
> `sudo chattr -i /etc/NetworkManager/system-connections/{lte,usb}.nmconnection`

## 系统自升级 (核心特性)

镜像内的内核是 **postmarketOS 官方仓库的 apk 包**, 设备端直接:

```shell
apk update
apk upgrade        # 升级内核 + 全部软件
```

升级内核时 `postmarketos-mkinitfs` 触发器会自动:

1. 用 `mkinitfs` 重建 initramfs
2. 用 `boot-deploy` 把新 vmlinuz / initramfs / dtb / extlinux.conf 写入 `/boot`
3. 下次重启 lk2nd 自动加载新内核

**前提**: `/boot` 分区 (ext2) 通过 fstab 正常挂载 (脚本已配置)。

## 支持的板子

| 板子 | BOARD 参数 | DTB |
| ---- | ---------- | --- |
| UZ801 V3.0 | `yiming-uz801v3` | msm8916-yiming-uz801v3 |
| UF896 | `thwc-uf896` | msm8916-thwc-uf896 |
| UFIxxx | `thwc-ufi001c` | msm8916-thwc-ufi001c |
| JZxxx | `jz01-45-v33` | msm8916-jz01-45-v33 |
| MF800 | `fy-mf800` | msm8916-fy-mf800 |

> 内核包内置 uz801/uf896/ufi001c 的 dtb; jz01/mf800 使用仓库 `dtbs/` 下的自定义 dtb。
> lk2nd 的 compatible 字符串在 `scripts/build_hyp_aboot.sh` 中按板子映射。

## 目录结构

```
scripts/
  install_deps.sh      # 宿主依赖 (qemu + 交叉编译工具链)
  build_hyp_aboot.sh   # qhypstub + lk2nd + 签名
  extract_fw.sh        # GPT 分区表 + 高通 rpm/sbl1/tz
  pmos_rootfs.sh       # ★ postmarketOS aarch64 rootfs (核心)
  build_images.sh      # raw → Android sparse
  copy_custom_fw.sh    # 复制设备专有固件分区
configs/
  *.nmconnection       # NetworkManager: 热点 / USB / LTE
  templates/           # USB gadget 方案 (gt)
  deviceinfo           # 生成 /usr/share/deviceinfo/deviceinfo
dtbs/                  # 自定义 dtb (jz01 / mf800 等)
firmware/              # 从设备备份的专有分区
src/                   # lk2nd / qhypstub / qtestsign (子模块)
```

## 许可

参见 [LICENSE](LICENSE)。固件刷入设备存在风险, 请自行承担。
