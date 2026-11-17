#!/bin/sh
# RAM-only first-stage test described at https://failedattempts.neocities.org/part3a
# Reference SPL is not a backup from this device; compatibility is unverified.
# No U-Boot or shim is sent and no UUU flash command is issued.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
image="$root/reference-images/spl_0-60k.img"
libdir="$root/.pixi/envs/default/lib"
expected=2b46eb4059d59bfd60df1d8f159a27de84fbe6ca91c140b26ffe6dad7368daad
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run spl-test [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
if [ ! -f "$image" ]; then echo "Missing reference SPL: $image" >&2; exit 1; fi
actual=$(shasum -a 256 "$image")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then echo 'Reference SPL SHA-256 mismatch; refusing to execute.' >&2; exit 1; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Reference SPL SHA-256: %s\n' "$actual"
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDP: boot -f "%s"\n' "$libdir" "$uuu" "$image"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This executes the reference SPL in device RAM. It does not issue a flash command.'
echo 'Compatibility is unverified. Afterward use mise run usb to check for SDPV.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDP: boot -f "$image"
