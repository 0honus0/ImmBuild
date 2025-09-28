#!/bin/sh
set -eu

# 必填
: "${PACKAGES:?FATAL: 必须通过环境变量 PACKAGES 传入包列表}"

PROFILE="${PROFILE:-generic}"                  # generic 或 64
BIN_DIR="${BIN_DIR:-/out}"                     # 输出目录
CUSTOM_REPOSITORIES="${CUSTOM_REPOSITORIES:-}" # 追加仓库（可多行）

# 规范化包列表
PKGS="$(printf "%s\n" "$PACKAGES" | tr -d '\r' | awk 'NF' | xargs || true)"
[ -z "$PKGS" ] && { echo "FATAL: 解析后包列表为空"; exit 1; }

echo "==> Packages:"; printf "%s\n" "$PKGS" | tr ' ' '\n' | sed 's/^/  - /'

# 定位 IB
IB_ROOT=""
for d in "$HOME/immortalwrt" /root/immortalwrt /home/build /builder /imagebuilder /openwrt /; do
  if [ -f "$d/Makefile" ] && [ -f "$d/repositories.conf" ]; then IB_ROOT="$d"; break; fi
done
[ -z "$IB_ROOT" ] && { echo "FATAL: 找不到 ImageBuilder 根目录（含 Makefile 与 repositories.conf）" >&2; exit 1; }

cd "$IB_ROOT"; echo "==> ImageBuilder root: $PWD"

# ✅ fix bios boot partition is under 1 MiB
sed -i 's/256/1024/g' target/linux/x86/image/Makefile || true

# 自定义源
if [ -n "$CUSTOM_REPOSITORIES" ]; then
  echo "==> 追加自定义源到 repositories.conf:"; printf "%s\n" "$CUSTOM_REPOSITORIES" | sed 's/^/  + /'
  printf "\n# --- custom repositories (appended by CI) ---\n%s\n" "$CUSTOM_REPOSITORIES" >> repositories.conf
fi

# 关键修复：确保 rootfs 内一定有 /boot 目录（避免 cp .../boot/. 报错）
# 无 files 时创建最小 files，并启用 FILES=files/
EXTRA=""
[ -d ./files ] && { echo "==> 将 ./files/ 打入固件"; EXTRA="FILES=files/"; }

mkdir -p "$BIN_DIR"

# 并行度
CORES="$( (nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null) || echo 1 )"
[ -z "$CORES" ] && CORES=1

echo "==> Building (PROFILE=$PROFILE, CORES=$CORES)"
if ! make -j"$CORES" image PROFILE="$PROFILE" PACKAGES="$PKGS" $EXTRA; then
  echo "==> 并行失败，回退到串行 V=s"
  if ! make -j1 V=s image PROFILE="$PROFILE" PACKAGES="$PKGS" $EXTRA; then
    echo "==> 构建失败，打印可用 profiles 及关键 info："
    echo "---- make info ----"; make info || true; echo "-------------------"
    exit 1
  fi
fi

echo "==> Collecting EFI images to $BIN_DIR"
mkdir -p "$BIN_DIR"

have_any=false

# 先尝试 squashfs
if find bin/targets -type f -name "*squashfs*" | grep -q .; then
  echo "==> Found squashfs images"
  find bin/targets -type f -name "*squashfs*" -print0 \
  | xargs -0 -I{} sh -c 'cp -f "$1" "$2"/; echo "  + ${1##*/}"' _ "{}" "$BIN_DIR"
  have_any=true
fi

# 若没有，再尝试 ext4
if [ "$have_any" != true ] && find bin/targets -type f -name "*ext4*" | grep -q .; then
  echo "WARNING: 未生成 squashfs 回退收集 ext4"
  find bin/targets -type f -name "*ext4*" -print0 \
  | xargs -0 -I{} sh -c 'cp -f "$1" "$2"/; echo "  + ${1##*/}"' _ "{}" "$BIN_DIR"
  have_any=true
fi

if [ "$have_any" != true ]; then
  echo "FATAL: 未找到 *squashfs* 或 *ext4* 产物"
  echo "---- ls bin/targets (for debug) ----"
  ls -R bin/targets || true
  echo "------------------------------------"
  exit 1
fi

FOUND="$(find "$BIN_DIR" -maxdepth 1 -type f -name "*combined-efi*" | wc -l | tr -d ' ')"
echo "==> Done. ($FOUND file(s))"
