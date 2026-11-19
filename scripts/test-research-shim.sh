#!/bin/sh
# RAM-only shim transfer: https://failedattempts.neocities.org/part3a
# The generated image is unsigned and unverified on the MIRROR.
# This stage does not flash, jump, or execute any loaded component.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
image="$root/build/shim-package.dvxmz4/shim.imx"
libdir="$root/.pixi/envs/default/lib"
expected=4e29cfa5230758619fbc82a730e940dc11d85d21ebc0dcdd0f4249a1d29e2281
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run shim-test [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
if [ ! -f "$image" ]; then echo "Missing experimental shim package: $image" >&2; exit 1; fi
actual=$(sha256sum "$image")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then echo 'Shim SHA-256 mismatch; refusing to transfer.' >&2; exit 1; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Experimental shim SHA-256: %s\n' "$actual"
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f "%s" -addr 0x40000000\n' "$libdir" "$uuu" "$image"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This writes the experimental shim to RAM only; it does not flash or jump.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: write -f "$image" -addr 0x40000000
