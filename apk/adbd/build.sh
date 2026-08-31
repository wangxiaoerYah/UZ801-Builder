#!/bin/sh
# 构建 adbd apk (可复现):
#   1. submodule 更新 (src/adbd-linux = tonyho 原版)
#   2. 更新 APKBUILD sha512sums (patch/initd/confd)
#   3. Alpine 容器 (aarch64) 执行 abuild
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$HERE"

echo "=== 1. submodule 更新 ==="
git -C "$REPO" submodule update --init --recursive 2>/dev/null || true
test -d "$REPO/src/adbd-linux" || { echo "submodule 缺失"; exit 1; }

echo "=== 2. 更新 sha512sums ==="
python3 - << PYEOF
import re, subprocess
files = ['adbd-linux-fixes.patch', 'adbd.initd', 'adbd.confd']
sums = subprocess.run(['sha512sum'] + files, capture_output=True, text=True).stdout.strip().split('\n')
entries = []
for line in sums:
    parts = line.split()
    entries.append(f"{parts[0]}  {parts[1]}")
s = open('APKBUILD').read()
s = re.sub(r'(sha512sums="\n)[^"]*(\n")', lambda m: m.group(1) + '\n'.join(entries) + m.group(2), s)
open('APKBUILD', 'w').write(s)
print("sha512sums 已更新")
PYEOF

echo "=== 3. Alpine 容器构建 (aarch64, 源码=submodule) ==="
sudo podman run --rm --network host --platform linux/arm64 \
	-v "$HERE":/work:Z -v "$REPO/src/adbd-linux":/src/adbd-linux:ro,Z alpine:3.24 sh -c '
apk add --no-cache abuild alpine-sdk openssl-dev libcap-dev linux-headers glib-dev libcap openssl >/dev/null 2>&1
addgroup -S abuild >/dev/null 2>&1
adduser -D builder >/dev/null 2>&1
adduser builder abuild >/dev/null 2>&1
su builder -c "abuild-keygen -a -n" >/dev/null 2>&1
chown -R builder /work 2>/dev/null
# builddir = \$startdir/../../src/adbd-linux = /src/adbd-linux (submodule 挂载)
su builder -c "cd /work && abuild" 2>&1 | tail -5
cp /home/builder/packages/aarch64/adbd-1.0.0-r0.apk /work/ 2>/dev/null
'
echo "=== 完成 ==="
ls -la adbd-1.0.0-r0.apk 2>/dev/null
