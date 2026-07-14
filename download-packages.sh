#!/usr/bin/env bash
set -euo pipefail

# 仓库根目录
root_dir="$(cd "$(dirname "$0")" && pwd)"
# 外部 IPK 下载清单
config_file="${1:-$root_dir/.ci/external-packages.conf}"
# 下载结果仅用于当前构建
output_dir="${LOCAL_PACKAGES_DIR:-$root_dir/packages}"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
[ -f "$config_file" ] || { echo "Missing package config: $config_file" >&2; exit 1; }

# 每次重新下载 避免旧包混入本次固件
rm -rf "$output_dir"
mkdir -p "$output_dir"

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  set -- $line
  [ "$#" -eq 2 ] || { echo "Invalid package entry: $line" >&2; exit 1; }
  # 配置格式为 文件名 URL
  echo "Downloading $1"
  curl -fL --retry 3 --retry-delay 2 -o "$output_dir/$1" "$2"
done < "$config_file"

# 没有 IPK 时终止构建 防止生成缺少第三方功能的固件
find "$output_dir" -maxdepth 1 -type f -name '*.ipk' -print -quit | grep -q . || {
  echo "No IPK packages downloaded" >&2
  exit 1
}
