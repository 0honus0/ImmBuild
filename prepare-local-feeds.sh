#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/.ci/local-feed-packages.conf}"
FEED_ROOT="${FEED_ROOT:-$ROOT_DIR/feed}"
REPO_LINES_FILE="$FEED_ROOT/custom-repositories.conf"

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl 未安装" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 未安装" >&2; exit 1; }

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
  # opkg-utils is no longer available in the Ubuntu runner repositories.
  # An opkg feed index is a concatenation of control.tar.* members from .ipk files.
  python3 - "$feed_dir" > "$feed_dir/Packages" <<'PY'
import hashlib
import io
import sys
import tarfile
from pathlib import Path

feed_dir = Path(sys.argv[1])
for package in sorted(feed_dir.glob("*.ipk")):
    try:
        package_data = package.read_bytes()
        with tarfile.open(fileobj=io.BytesIO(package_data), mode="r:*") as ipk:
            control_member = next(
                (member for member in ipk.getmembers()
                 if member.name.rsplit("/", 1)[-1].startswith("control.tar")),
                None,
            )
            if control_member is None:
                raise ValueError("missing control.tar.*")
            control_stream = ipk.extractfile(control_member)
            if control_stream is None:
                raise ValueError("cannot read control archive")
            with tarfile.open(fileobj=io.BytesIO(control_stream.read()), mode="r:*") as control_tar:
                control = next(
                    (member for member in control_tar.getmembers()
                     if member.name.rsplit("/", 1)[-1] == "control"),
                    None,
                )
                if control is None:
                    raise ValueError("missing control metadata")
                control_data = control_tar.extractfile(control)
                if control_data is None:
                    raise ValueError("cannot read control metadata")
                sys.stdout.buffer.write(control_data.read().rstrip(b"\\n") + b"\\n")
        sys.stdout.write(f"Filename: {package.name}\\n")
        sys.stdout.write(f"Size: {len(package_data)}\\n")
        sys.stdout.write(f"MD5Sum: {hashlib.md5(package_data).hexdigest()}\\n")
        sys.stdout.write(f"SHA256sum: {hashlib.sha256(package_data).hexdigest()}\\n\\n")
    except (tarfile.TarError, OSError, ValueError) as exc:
        raise SystemExit(f"FATAL: invalid IPK {package.name}: {exc}")
PY
  gzip -kf "$feed_dir/Packages"
done

echo "==> 已生成自定义源定义: $REPO_LINES_FILE"
cat "$REPO_LINES_FILE"
