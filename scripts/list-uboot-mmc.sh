#!/bin/sh
# Inventory MMC controllers through the temporary U-Boot over USB.
# U-Boot command source: https://github.com/nxp-imx/uboot-imx/blob/d26632454196662187c2562e404655fa88eea4cb/cmd/mmc.c
# "mmc list" lists devices; it does not issue mmc write/erase or saveenv.
set -eu
cd "$(dirname "$0")/.."
libdir="$PWD/.pixi/envs/default/lib"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run mmc-list [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 FB: ucmd mmc list\n' "$libdir" "$uuu"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'Lists MMC devices; does not issue a storage write, erase, or saveenv command.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -v -t 20 FB: ucmd mmc list
