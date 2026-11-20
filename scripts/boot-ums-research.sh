#!/bin/sh
# Reproduce the guide's RAM-only boot sequence using our unverified UMS variant.
# https://failedattempts.neocities.org/part3a
# Every stage prints its command. No flash, erase or saveenv is issued.
# The resulting U-Boot can expose writable UMS after fastboot exits.
set -eu
cd "$(dirname "$0")/.."
echo 'Starting RAM-only sequence; stop on any stage failure.'
ls -1 /dev/disk/by-uuid/ > /tmp/dev1
uuu SDP: boot -f "/code/reference-images/spl_0-60k.img"
uuu SDPV: write -f "/code/build/extracted-boot-components/atf.bin" -addr 0x00920000
uuu SDPV: write -f "/code/build/extracted-boot-components/tee.bin" -addr 0xbe000000
uuu SDPV: write -f "/code/build/uboot-nxp/u-boot.bin" -addr 0x40200000
uuu SDPV: write -f "/code/build/extracted-boot-components/fdt.dtb" -addr 0x43000000
uuu SDPV: write -f "/code/build/shim-package/shim.imx"   -addr 0x40000000
wait 5s
ls -1 /dev/disk/by-uuid/ > /tmp/dev2
mirrordiskuuid=$(diff -u /tmp/dev1 /tmp/dev2)
echo "Your disk path is /dev/disk/by-uuid/"$mirrordiskuuid
echo $mirrordiskuuid > /code/build/mirrordiskuuid
