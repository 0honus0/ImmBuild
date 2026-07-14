#!/usr/bin/env bash
# Based on OpenWrt scripts/ipkg-make-index.sh (GPL-2.0-only).
# Generates an opkg Packages index from a directory of .ipk files.
set -euo pipefail

pkg_dir=${1:-}
if [ -z "$pkg_dir" ] || [ ! -d "$pkg_dir" ]; then
  echo "Usage: $0 <package_directory>" >&2
  exit 1
fi

for pkg in "$pkg_dir"/*.ipk; do
  [ -f "$pkg" ] || continue
  name=${pkg##*/}
  package_name=${name%%_*}
  [ "$package_name" = kernel ] && continue
  [ "$package_name" = libc ] && continue

  echo "Generating index for package $name" >&2
  file_size=$(stat -L -c%s "$pkg")
  sha256=$(sha256sum "$pkg" | cut -d' ' -f1)
  tar -xzOf "$pkg" ./control.tar.gz \
    | tar -xzOf - ./control \
    | sed "s/^Description:/Filename: $name\\
Size: $file_size\\
SHA256sum: $sha256\\
Description:/"
  echo
done
