#!/bin/sh
# RAM-only U-Boot transfer from https://failedattempts.neocities.org/part3a
# This is our experimental EVK reconstruction, not the guide author's build.
# This stage does not flash, jump, or execute the loaded U-Boot.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
image="$root/build/uboot-nxp-task.qsrMm7/u-boot.bin"
libdir="$root/.pixi/envs/default/lib"
expected=51f3c4c7be541e728accafe52d0f9dfa4af36adea742ab7ab29fdd7daf8d77a7
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run uboot-test [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
if [ ! -f "$image" ]; then echo "Missing experimental U-Boot: $image" >&2; exit 1; fi
actual=$(sha256sum "$image")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then echo 'Experimental U-Boot SHA-256 mismatch; refusing to transfer.' >&2; exit 1; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Experimental U-Boot SHA-256: %s\n' "$actual"
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f "%s" -addr 0x40200000\n' "$libdir" "$uuu" "$image"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This writes experimental U-Boot to RAM only; it does not flash, jump, or execute it.'
echo 'The image is unverified and includes commands capable of writing storage.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: write -f "$image" -addr 0x40200000
