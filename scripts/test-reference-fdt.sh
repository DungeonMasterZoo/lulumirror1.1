#!/bin/sh
# RAM-only reference device-tree transfer: https://failedattempts.neocities.org/part3a
# The reference device tree has not been validated against this MIRROR.
# This stage does not flash, jump, or execute any loaded component.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
image="$root/build/extracted-boot-components/fdt.dtb"
libdir="$root/.pixi/envs/default/lib"
expected=d6f8dc9aac1dcbf8fe7733f8d8b9c5fd8e7cbae56718f862c641ce2609b5e619
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run fdt-test [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
if [ ! -f "$image" ]; then echo 'Missing reference device tree; run mise run extract.' >&2; exit 1; fi
actual=$(sha256sum "$image")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then echo 'Reference device-tree SHA-256 mismatch; refusing to transfer.' >&2; exit 1; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Reference device-tree SHA-256: %s\n' "$actual"
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f "%s" -addr 0x43000000\n' "$libdir" "$uuu" "$image"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This writes the reference device tree to RAM; it does not flash or jump.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: write -f "$image" -addr 0x43000000
