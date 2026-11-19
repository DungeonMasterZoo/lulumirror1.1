#!/bin/sh
# Experimental, local-only build of the shim source from:
# https://failedattempts.neocities.org/part3a
# This does not produce a bootable shim.imx or contact the MIRROR. The guide
# does not pin tool versions or fully specify the required i.MX header layout.
# Record the installed compiler version with each build; outputs are not claimed
# to be byte-identical to the author's or safe for this hardware.
# The source is reproduced by get-shim-source.py; it pins the original guide's
# text and adds provenance comments. NXP's tooling is documented at:
# https://github.com/nxp-imx/imx-mkimage
set -eu

cd "$(dirname "$0")/.."
mkdir -p build/shim-xpack
if [ -e build/shim-xpack/shim.o ] || [ -e build/shim-xpack/shim.elf ] || [ -e build/shim-xpack/shim.bin ]; then
  echo 'Build outputs already exist; refusing to overwrite them.' >&2
  exit 1
fi

echo 'Compiler version:'
aarch64-none-elf-gcc --version | head -n 1
echo 'Linker version:'
aarch64-none-elf-ld --version | head -n 1
echo 'Source hashes:'
sha256sum shim/shim.c shim/atf_common.h

# Address and entry point follow the guide. The xPack aarch64-none-elf tools
# differ from the guide's aarch64-linux-gnu tools; equivalence is unverified.
aarch64-none-elf-gcc -c -static -nostdinc -nostartfiles -ffreestanding shim/shim.c -o build/shim-xpack/shim.o
aarch64-none-elf-ld build/shim-xpack/shim.o -o build/shim-xpack/shim.elf -Ttext=0x40000040 --entry=_start --build-id=none
aarch64-none-elf-objcopy -O binary build/shim-xpack/shim.elf build/shim-xpack/shim.bin

echo 'Output hashes:'
sha256sum build/shim-xpack/shim.o build/shim-xpack/shim.elf build/shim-xpack/shim.bin
echo 'Experimental raw binary only. Do not send it to the device.'
