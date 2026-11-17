#!/bin/sh
# Reproduce the guide's RAM-only boot sequence using our unverified UMS variant.
# https://failedattempts.neocities.org/part3a
# Every stage prints its command. No flash, erase or saveenv is issued.
# The resulting U-Boot can expose writable UMS after fastboot exits.
set -eu
cd "$(dirname "$0")/.."
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run ums-boot [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
echo 'Checking every local stage before sending anything:'
for stage in test-reference-spl.sh test-reference-atf.sh test-reference-tee.sh test-ums-uboot.sh test-reference-fdt.sh test-research-shim.sh jump-research-shim.sh; do
  sh "scripts/$stage" --check
done
if [ "${1:-}" = --check ]; then echo 'All local checks passed; no device commands run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'Starting RAM-only sequence; stop on any stage failure.'
if [ "${MIRROR_UMS_VARIANT:-handoff}" = direct ]; then
  echo 'The untested U-Boot attempts to expose a writable disk immediately after the jump.'
  echo 'If macOS asks to initialize the disk, choose Ignore, never Initialize.'
else
  echo 'The untested U-Boot can expose a writable disk after fastboot exits.'
fi
for stage in test-reference-spl.sh test-reference-atf.sh test-reference-tee.sh test-ums-uboot.sh test-reference-fdt.sh test-research-shim.sh jump-research-shim.sh; do
  echo "Running $stage"
  sh "scripts/$stage"
done
if [ "${MIRROR_UMS_VARIANT:-handoff}" = direct ]; then
  echo 'Jump acknowledged. Checking current disk list; UMS may take time to appear.'
  diskutil list
  echo 'Share this output before selecting or copying a disk.'
else
  echo 'Jump acknowledged. Run mise run usb and share the output before continuing.'
fi
