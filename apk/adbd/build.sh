#!/bin/sh
# 在 Alpine 容器内构建本包 (workflow / 本地 docker 均调用)
# 用法: docker run -v <包目录>:/pkg -v <repo>/src:/src alpine:3.24 sh -c 'sh /pkg/build.sh'
# 模块化: 新包 = 目录 + APKBUILD + 本脚本 (workflow 无需修改)
set -e
cd /pkg

echo "=== 安装构建依赖 ==="
apk update >/dev/null 2>&1 || true
apk add --no-cache abuild alpine-sdk sudo >/dev/null 2>&1
# 解析 APKBUILD 的 depends + makedepends 并安装 (按需, 支持任意新包)
# depends = 运行时依赖 (abuild 会校验), makedepends = 构建依赖
for VAR in depends makedepends; do
	PKGS=$(grep "^$VAR=" APKBUILD 2>/dev/null | sed -n 's/'"$VAR"'="\(.*\)"/\1/p' | tr ' ' '\n' | grep -v '^$' | paste -sd' ')
	if [ -n "$PKGS" ]; then
		apk add --no-cache $PKGS >/dev/null 2>&1 || { echo "::warning::$VAR 部分安装失败: $PKGS"; }
	fi
done

echo "=== 配置 builder ==="
addgroup -S abuild 2>/dev/null || true
adduser -D builder 2>/dev/null || true
adduser builder abuild 2>/dev/null || true
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
su builder -c "abuild-keygen -a -n" >/dev/null 2>&1 || true
chown -R builder /pkg /src 2>/dev/null || true

echo "=== abuild 构建 ==="
# 依赖已预装, 用 abuild (不带 -r, 避免 setuid/apk 索引问题)
su builder -c "cd /pkg && abuild" 2>&1 | tail -8 || { echo "::error::abuild 失败"; exit 1; }

echo "=== 导出 apk ==="
find /home/builder/packages -name "*.apk" -exec cp {} /pkg/ \; 2>/dev/null || true
if [ -z "$(ls /pkg/*.apk 2>/dev/null)" ]; then
	echo "::error::未生成 apk"
	exit 1
fi
ls -la /pkg/*.apk
