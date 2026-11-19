#!/bin/sh
# RAM-only transfer of experimental UMS-handoff U-Boot; no flash or jump.
# https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/06-flash-image.md
# The image starts ordinary writable UMS after fastboot exits. It is untested.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
libdir="$root/.pixi/envs/default/lib"
case "${MIRROR_UMS_VARIANT:-handoff}" in
  handoff) image="$root/build/uboot-nxp-task.9GbZRg/u-boot.bin"; expected=c59fe703096ad83d5f654753b58d9f07b4e2d51622bcc6247a44b1fe40825386 ;;
  direct) image="$root/build/uboot-nxp-task.LHWaKn/u-boot.bin"; expected=52b99eb75edeafa04691fba33913e2bbdf419926eeb19c72134f4a2ba9347c9b ;;
  *) echo 'Unknown UMS U-Boot variant.' >&2; exit 2 ;;
esac
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run uboot-ums-test [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
if [ ! -f "$image" ]; then echo "Missing experimental U-Boot: $image" >&2; exit 1; fi
actual=$(sha256sum "$image")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then echo 'UMS-handoff U-Boot SHA-256 mismatch; refusing to transfer.' >&2; exit 1; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'UMS-handoff U-Boot SHA-256: %s\n' "$actual"
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f "%s" -addr 0x40200000\n' "$libdir" "$uuu" "$image"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This writes experimental U-Boot to RAM only; it does not flash or jump.'
if [ "${MIRROR_UMS_VARIANT:-handoff}" = direct ]; then
  echo 'Once executed, this build attempts to expose writable UMS immediately.'
else
  echo 'Once executed, this build is configured to start writable UMS after fastboot exits.'
fi
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: write -f "$image" -addr 0x40200000
