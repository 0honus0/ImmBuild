#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
config_file="${1:-$root_dir/.ci/external-packages.conf}"
output_dir="${LOCAL_PACKAGES_DIR:-$root_dir/packages}"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
[ -f "$config_file" ] || { echo "Missing package config: $config_file" >&2; exit 1; }

rm -rf "$output_dir"
mkdir -p "$output_dir"

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  set -- $line
  [ "$#" -eq 2 ] || { echo "Invalid package entry: $line" >&2; exit 1; }
  echo "Downloading $1"
  curl -fL --retry 3 --retry-delay 2 -o "$output_dir/$1" "$2"
done < "$config_file"

find "$output_dir" -maxdepth 1 -type f -name '*.ipk' -print -quit | grep -q . || {
  echo "No IPK packages downloaded" >&2
  exit 1
}
