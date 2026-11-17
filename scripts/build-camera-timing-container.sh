#!/bin/sh
set -eu
[ "$#" = 2 ] || exit 2
out=$1
variant=$2
case "$variant:$out" in timing:build/camera-timing.*|polarity:build/camera-polarity.*|ov5645:build/camera-ov5645.*) ;; *) echo 'Unexpected build variant or output directory.' >&2; exit 2 ;; esac
echo 'Extracting pinned Linux source into the container Linux filesystem.'
# A macOS host volume may be case-insensitive and cannot represent all Linux
# source-tree names correctly. Keep the source and build inside the container.
work=$(mktemp -d /tmp/mirror-kernel.XXXXXXXX)
tar -xf build/linux-6.18.60.tar.xz -C "$work"
src="$work/linux-6.18.60"
for patch in vendor/lemonademirror/kernel/patches/*.patch; do
  echo "Applying $patch"
  git -C "$src" apply "/workspace/$patch"
done
cp vendor/lemonademirror/kernel/kernel.config "$src/.config"
case "$variant" in
  timing) patch=ov5640-vendor-reset-delay.patch; module=ov5640 ;;
  polarity) patch=ov5640-invert-powerdown.patch; module=ov5640 ;;
  ov5645) patch=ov5645-mirror-probe.patch; module=ov5645 ;;
esac
echo "Applying camera experiment: $patch"
git -C "$src" apply "/workspace/patches/$patch"
export ARCH=arm64 LOCALVERSION=
make -C "$src" olddefconfig
make -C "$src" -j4 modules_prepare
make -C "$src" -j4 KBUILD_MODPOST_WARN=1 "drivers/media/i2c/$module.ko"
echo 'Kernel release:'
make -s -C "$src" kernelrelease
echo 'Experimental module SHA-256:'
sha256sum "$src/drivers/media/i2c/$module.ko"
cp "$src/drivers/media/i2c/$module.ko" "$out/$module.ko"
echo 'WARNING: modules_prepare lacks a complete Module.symvers; ABI compatibility and loading are not established.'
