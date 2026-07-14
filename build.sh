#!/bin/sh
set -eu

: "${PACKAGES:?PACKAGES is required}"

profile="${PROFILE:-generic}"
bin_dir="${BIN_DIR:-/out}"
packages="$(printf '%s\n' "$PACKAGES" | xargs)"
[ -n "$packages" ] || { echo "Package list is empty" >&2; exit 1; }

ib_root=/home/build/immortalwrt
[ -f "$ib_root/Makefile" ] || { echo "ImageBuilder not found: $ib_root" >&2; exit 1; }
cd "$ib_root"

sed -i 's/256/1024/g' target/linux/x86/image/Makefile

if [ -d /work/files ]; then
  mkdir -p files
  cp -a /work/files/. files/
fi

for package in /work/packages/*.ipk; do
  [ -f "$package" ] || continue
  cp -f "$package" packages/
done

mkdir -p "$bin_dir"
make -j"$(nproc)" image PROFILE="$profile" PACKAGES="$packages" FILES=files/ BIN_DIR="$bin_dir"

find bin/targets -type f \( -name '*squashfs*' -o -name '*ext4*' \) -exec cp -f {} "$bin_dir"/ \;
