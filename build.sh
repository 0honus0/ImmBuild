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

# 25.12 使用 apk，外部仓库仍提供传统 ipk。
# 将 ipk 的 data/control 元数据转换为 apk，再交给 ImageBuilder 建索引。
# 25.12 的 apk 不会读取 packages 目录中的 ipk 文件。
convert_ipk_to_apk() {
  package="$1"
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  tar xzf "$package" -C "$workdir"
  mkdir -p "$workdir/control" "$workdir/data"
  tar xzf "$workdir/control.tar.gz" -C "$workdir/control"
  tar xzf "$workdir/data.tar.gz" -C "$workdir/data"

  control="$workdir/control/control"
  name="$(sed -n 's/^Package: //p' "$control")"
  version="$(sed -n 's/^Version: //p' "$control")"
  arch="$(sed -n 's/^Architecture: //p' "$control")"
  description="$(sed -n 's/^Description: //p' "$control")"
  depends="$(sed -n 's/^Depends: //p' "$control")"

  [ -n "$name" ] && [ -n "$version" ] && [ -n "$arch" ] || {
    echo "Invalid package metadata: $package" >&2
    return 1
  }

  [ "$arch" = all ] && arch=noarch
  args=(
    --output "packages/${name}-${version}.apk"
    --files "$workdir/data"
    --info "name:$name"
    --info "version:$version"
    --info "arch:$arch"
  )
  [ -n "$description" ] && args+=(--info "description:$description")

  IFS=',' read -ra dependency_list <<< "$depends"
  for dependency in "${dependency_list[@]}"; do
    dependency="$(printf '%s' "$dependency" | xargs)"
    [ -n "$dependency" ] && args+=(--info "depends:$dependency")
  done

  # postinst-pkg contains the package-specific action used after installation.
  if [ -s "$workdir/control/postinst-pkg" ]; then
    args+=(--script "post-install:$workdir/control/postinst-pkg")
  fi

  "$ib_root/staging_dir/host/bin/apk" mkpkg "${args[@]}"
}

for package in /work/packages/*.ipk; do
  [ -f "$package" ] || continue
  convert_ipk_to_apk "$package"
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
