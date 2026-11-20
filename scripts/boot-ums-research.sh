#!/bin/sh
# Reproduce the guide's RAM-only boot sequence using our unverified UMS variant.
# https://failedattempts.neocities.org/part3a
# Every stage prints its command. No flash, erase or saveenv is issued.
# The resulting U-Boot can expose writable UMS after fastboot exits.
set -eu
cd "$(dirname "$0")/.."
echo 'Starting RAM-only sequence; stop on any stage failure.'
uuu SDP: boot -f "/code/reference-images/spl_0-60k.img"
uuu SDPV: write -f "/code/build/extracted-boot-components/atf.bin" -addr 0x00920000
uuu SDPV: write -f "/code/build/extracted-boot-components/tee.bin" -addr 0xbe000000
uuu SDPV: write -f "/code/build/uboot-nxp/u-boot.bin" -addr 0x40200000 
uuu SDPV: write -f "/code/build/extracted-boot-components/fdt.dtb" -addr 0x43000000
uuu SDPV: write -f "/code/build/shim-package/shim.imx"   -addr 0x40000000
for stage in test-reference-tee.sh test-ums-uboot.sh test-reference-fdt.sh test-research-shim.sh jump-research-shim.sh; do
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
