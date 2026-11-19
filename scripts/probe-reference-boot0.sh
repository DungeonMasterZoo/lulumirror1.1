#!/bin/sh
# Compare the eMMC boot0 hardware area with the reference, using RAM only.
# Selecting an eMMC hardware area changes PARTITION_CONFIG access bits.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
reference="$root/reference-images/mmcblk2boot0.img"
expected=5d02ce60d2ea095fafb87bcb0b893cc81785bff738ef147220350de0deaae83e
libdir="$root/.pixi/envs/default/lib"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run probe-reference-boot0 [--check]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
[ -f "$reference" ] || { echo 'Missing reference boot0 image.' >&2; exit 1; }
actual=$(sha256sum "$reference"); actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo 'Reference image hash mismatch.' >&2; exit 1; }
uuu=$(command -v uuu)
for stage in test-reference-spl.sh test-reference-atf.sh test-reference-tee.sh test-research-uboot.sh test-reference-fdt.sh test-research-shim.sh jump-research-shim.sh route-uboot-output.sh; do
  sh "scripts/$stage" --check
done
echo 'The first 4 MiB of the reference boot0 image will be transferred to RAM at 0x46000000.'
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f <temporary-reference-4MiB> -addr 0x46000000\n' "$libdir" "$uuu"
for operation in 'mmc dev 2 1' 'mmc read 47000000 0 2000' 'cmp.b 46000000 47000000 400000' 'mmc dev 2 0'; do
  printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 FB: ucmd %s\n' "$libdir" "$uuu" "$operation"
done
if [ "${1:-}" = --check ]; then echo 'Check only: no device commands run.'; exit 0; fi
[ -t 0 ] || { echo 'Run interactively.' >&2; exit 1; }
echo 'Temporarily booting experimental U-Boot; boot0 is read to RAM and compared.'
echo 'Hardware partition-access bits may change. No block write or saveenv is issued.'
temp=$(mktemp "${TMPDIR:-/tmp}/mirror-reference-boot0.XXXXXXXX")
trap 'rm -f "$temp"' EXIT HUP INT TERM
python -c 'import pathlib,sys; data=pathlib.Path(sys.argv[1]).read_bytes(); assert len(data)==4194384; pathlib.Path(sys.argv[2]).write_bytes(data[:4194304])' "$reference" "$temp"
for stage in test-reference-spl.sh test-reference-atf.sh test-reference-tee.sh test-research-uboot.sh test-reference-fdt.sh test-research-shim.sh; do
  echo "Running $stage"
  sh "scripts/$stage"
done
printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -t 20 SDPV: write -f "%s" -addr 0x46000000\n' "$libdir" "$uuu" "$temp"
sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -t 20 SDPV: write -f "$temp" -addr 0x46000000
sh scripts/jump-research-shim.sh
sh scripts/route-uboot-output.sh
for operation in 'mmc dev 2 1' 'mmc read 47000000 0 2000' 'cmp.b 46000000 47000000 400000' 'mmc dev 2 0'; do
  printf 'Command: sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 FB: ucmd %s\n' "$libdir" "$uuu" "$operation"
  # Fixed command list above, split into UUU argument tokens.
  # shellcheck disable=SC2086
  sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -v -t 20 FB: ucmd $operation
done
echo 'Share all output; an OKAY response alone does not prove the comparison matched.'
