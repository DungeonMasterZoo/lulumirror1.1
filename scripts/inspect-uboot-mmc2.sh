#!/bin/sh
# Identify MMC 2 using the temporary U-Boot, not the host's disk numbering.
# Source: https://github.com/nxp-imx/uboot-imx/blob/d26632454196662187c2562e404655fa88eea4cb/cmd/mmc.c
# mmc dev 2 selects hardware partition 0 (user area). If a switch is needed,
# NXP's driver updates the partition-access bits of EXT_CSD PARTITION_CONFIG,
# preserving the other bits. This is not a purely passive query. No block write,
# erase, UMS exposure or saveenv is intentionally issued by this script.
set -eu
cd "$(dirname "$0")/.."
libdir="$PWD/.pixi/envs/default/lib"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run mmc-inspect [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
if [ "${1:-}" != --check ] && [ ! -t 0 ]; then
  echo 'Run this task in your terminal to enter your sudo password.' >&2
  exit 1
fi
echo 'MMC 2 selection can change the hardware partition-access setting to the user area.'
echo 'No block write, erase, USB disk exposure, or saveenv command is issued.'
for operation in 'mmc dev 2' 'mmc info' 'mmc part'; do
  printf '\nCommand: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 FB: ucmd %s\n' "$libdir" "$uuu" "$operation"
  if [ "${1:-}" != --check ]; then
    # Fixed command list above; word splitting passes UUU each command token.
    # shellcheck disable=SC2086
    sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -v -t 20 FB: ucmd $operation
  fi
done
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; fi
