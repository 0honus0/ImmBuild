#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/.ci/local-feed-packages.conf}"
FEED_ROOT="${FEED_ROOT:-$ROOT_DIR/feed}"
REPO_LINES_FILE="$FEED_ROOT/custom-repositories.conf"

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl 未安装" >&2; exit 1; }
command -v opkg-make-index >/dev/null 2>&1 || { echo "FATAL: opkg-make-index 未安装（请安装 opkg-utils）" >&2; exit 1; }

[ -f "$CONFIG_FILE" ] || { echo "FATAL: 配置文件不存在: $CONFIG_FILE" >&2; exit 1; }

rm -rf "$FEED_ROOT"
mkdir -p "$FEED_ROOT"
: > "$REPO_LINES_FILE"

feeds_seen=""

while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw#${raw%%[![:space:]]*}}"
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
  esac

  set -- $line
  [ "$#" -ge 3 ] || { echo "FATAL: 配置行格式错误: $raw" >&2; exit 1; }

  feed_name="$1"
  output_name="$2"
  shift 2
  url="$*"

  feed_dir="$FEED_ROOT/$feed_name"
  mkdir -p "$feed_dir"

  echo "==> 下载 [$feed_name] $output_name"
  curl -fL --retry 3 --retry-delay 2 -o "$feed_dir/$output_name" "$url"

  case " $feeds_seen " in
    *" $feed_name "*) ;;
    *)
      printf 'src/gz %s file:///work/feed/%s\n' "$feed_name" "$feed_name" >> "$REPO_LINES_FILE"
      feeds_seen="$feeds_seen $feed_name"
      ;;
  esac
done < "$CONFIG_FILE"

for feed_dir in "$FEED_ROOT"/*; do
  [ -d "$feed_dir" ] || continue
  feed_name="$(basename "$feed_dir")"
  echo "==> 生成索引 [$feed_name]"
  opkg-make-index "$feed_dir" > "$feed_dir/Packages"
  gzip -kf "$feed_dir/Packages"
done

echo "==> 已生成自定义源定义: $REPO_LINES_FILE"
cat "$REPO_LINES_FILE"
