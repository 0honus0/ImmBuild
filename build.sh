#!/bin/sh
set -eu

# 工作流传入的最终安装包列表
: "${PACKAGES:?PACKAGES is required}"

profile="${PROFILE:-generic}"
bin_dir="${BIN_DIR:-/out}"
packages="$(printf '%s\n' "$PACKAGES" | xargs)"
[ -n "$packages" ] || { echo "Package list is empty" >&2; exit 1; }

# 当前固定 ImageBuilder 镜像中的构建根目录
ib_root=/home/build/immortalwrt
[ -f "$ib_root/Makefile" ] || { echo "ImageBuilder not found: $ib_root" >&2; exit 1; }
cd "$ib_root"

# 将 x86 镜像分区对齐从 128 KiB 改为 512 KiB
# 此项只影响磁盘分区布局 不处理 boot 文件
sed -i 's/256/1024/g' target/linux/x86/image/Makefile

if [ -d /work/files ]; then
  # 将仓库中的系统配置覆盖写入固件根目录
  mkdir -p files
  cp -a /work/files/. files/
fi

# 导入下载的第三方 IPK
# ImageBuilder 会为 packages 目录生成匹配的索引和签名
for package in /work/packages/*.ipk; do
  [ -f "$package" ] || continue
  cp -f "$package" packages/
done

# 输出目录来自 GitHub Actions 的挂载卷
mkdir -p "$bin_dir"
make -j"$(nproc)" image PROFILE="$profile" PACKAGES="$packages" FILES=files/ BIN_DIR="$bin_dir"

# ImageBuilder 已直接写入输出目录
# 仅确认产物存在 不再复制不存在的 bin targets 路径
find "$bin_dir" -maxdepth 1 -type f -name 'immortalwrt-*' -print -quit | grep -q . || {
  echo "No firmware artifacts were produced" >&2
  exit 1
}
