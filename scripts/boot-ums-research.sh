#!/bin/sh
# Reproduce the guide's RAM-only boot sequence using our unverified UMS variant.
# https://failedattempts.neocities.org/part3a
# Every stage prints its command. No flash, erase or saveenv is issued.
# The resulting U-Boot can expose writable UMS after fastboot exits.
set -eu
cd "$(dirname "$0")/.."
echo 'Starting RAM-only sequence; stop on any stage failure.'
uuu SDP: boot -f "/code/reference-images/spl_0-60k.img"
sleep 5s
uuu SDPV: write -f "/code/build/extracted-boot-components/atf.bin" -addr 0x00920000
uuu SDPV: write -f "/code/build/extracted-boot-components/tee.bin" -addr 0xbe000000
uuu SDPV: write -f "/code/build/uboot-nxp/u-boot.bin" -addr 0x40200000
uuu SDPV: write -f "/code/build/extracted-boot-components/fdt.dtb" -addr 0x43000000
uuu SDPV: write -f "/code/build/shim-package/shim.imx"   -addr 0x40000000
uuu -t 20 SDPV: jump -addr 0x40000000
sleep 5s
mirrordiskuuid=$(for i in /sys/block/*; do grep -q UMS ${i}/device/model 2>/dev/null && echo $i | sed -e 's:/sys/block:/dev:'; done)
echo "Your disk path is "$mirrordiskuuid
echo $mirrordiskuuid > /code/build/mirrordiskuuid
