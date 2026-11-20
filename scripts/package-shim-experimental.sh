#!/bin/sh
# Pinned source: https://github.com/nxp-imx/imx-mkimage/tree/1b577853ae1afe1f26cdef27548da52fb424af48
# Guide: https://failedattempts.neocities.org/part3a
set -eu
cd "$(dirname "$0")/.."
root=$PWD
src="$root/vendor/nxp-imx-mkimage"
raw="$root/build/shim-xpack/shim.bin"
rev=1b577853ae1afe1f26cdef27548da52fb424af48
if [ ! -f "$raw" ]; then
  echo 'Missing raw shim; run sh /code/scripts/build-shim-experimental.sh first.' >&2
  exit 1
fi
if [ ! -d "$src/.git" ] || [ "$(git -C "$src" rev-parse HEAD)" != "$rev" ]; then
  echo "Missing or unexpected imx-mkimage checkout; expected commit $rev at $src" >&2
  exit 1
fi
if ! git -C "$src" diff --quiet HEAD -- iMX8M/mkimage_imx8.c; then
  echo 'Packer source has local modifications; refusing to build it.' >&2
  exit 1
fi
mkdir -p "$root/build"
out="$root/build/shim-package"
mkdir -p $out
echo "Output directory: $out"
rm -rf "$root/build/shim*"
# NXP's standalone i.MX8M packer uses system zlib and the macOS host compiler.
cc -O2 "$src/iMX8M/mkimage_imx8.c" -o "$out/mkimage_imx8" -lz
"$out/mkimage_imx8" -loader "$raw" 0x40000040 -out "$out/shim.imx"
python3 "$root/scripts/verify-shim-imx.py" "$out/shim.imx" "$raw"
