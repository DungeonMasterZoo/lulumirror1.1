#!/bin/sh
# Experimental RAM-only jump from https://failedattempts.neocities.org/part3a
# This executes the loaded shim and attempts to start ATF, TEE and U-Boot.
# Loaded RAM cannot be verified by this script. No flash command is issued,
# but the unverified U-Boot contains commands capable of writing storage.
set -eu
cd "$(dirname "$0")/.."
libdir="$PWD/.pixi/envs/default/lib"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run shim-jump [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: jump -addr 0x40000000\n' "$libdir" "$uuu"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This executes the shim and attempts to start experimental firmware and U-Boot.'
echo 'The script cannot verify loaded RAM. No flash command is issued.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: jump -addr 0x40000000
