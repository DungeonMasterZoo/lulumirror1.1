#!/bin/sh
# RAM-only SDPV ATF transfer from https://failedattempts.neocities.org/part3a
# This is a reference firmware component, not a backup or a verified match.
# It does not flash, jump, or start the remaining boot stages.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
image="$root/build/extracted-boot-components/atf.bin"
libdir="$root/.pixi/envs/default/lib"
expected=4c881c3e6c8936c883ba0c60a40f1c2bf3136a483e026f414da3eee1f26fc2b4
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run atf-test [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
if [ ! -f "$image" ]; then echo 'Missing reference ATF; run mise run extract.' >&2; exit 1; fi
actual=$(shasum -a 256 "$image")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then echo 'Reference ATF SHA-256 mismatch; refusing to transfer.' >&2; exit 1; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup" >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
printf 'Reference ATF SHA-256: %s\n' "$actual"
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f "%s" -addr 0x00920000\n' "$libdir" "$uuu" "$image"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run this task in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'This writes ATF to device RAM only; it does not flash, jump, or execute ATF.'
exec sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: write -f "$image" -addr 0x00920000
