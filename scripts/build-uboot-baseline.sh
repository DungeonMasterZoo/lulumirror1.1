#!/bin/sh
# Experimental NXP EVK baseline, NOT the guide author's custom U-Boot.
# Source: https://github.com/nxp-imx/uboot-imx/tree/android-10.0.0_2.5.0
# Its fastboot flashing and MMC environment are enabled: never run on a device.
# Host tools need a Mach-O section fix on Apple Silicon; see the adjacent patch.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
src="$root/vendor/uboot-imx-android-10"
patch="$root/patches/uboot-macos-image-tool-data-section.patch"
bootpatch="$root/patches/uboot-evk-bootcommand-guard.patch"
revision=d26632454196662187c2562e404655fa88eea4cb

if [ ! -e "$src" ]; then
  mkdir -p "$root/vendor"
  git clone --depth 1 --branch android-10.0.0_2.5.0 https://github.com/nxp-imx/uboot-imx.git "$src"
fi
if [ "$(git -C "$src" rev-parse HEAD)" != "$revision" ]; then
  echo 'Unexpected U-Boot source revision; refusing to modify it.' >&2
  exit 1
fi
# Do not apply a patch to a checkout containing unrelated work, even if its
# affected file happens to apply cleanly. Do not disturb staged changes.
if ! git -C "$src" diff --cached --quiet || [ -n "$(git -C "$src" ls-files --others --exclude-standard)" ]; then
  echo 'U-Boot checkout has staged or untracked changes; refusing to modify it.' >&2
  exit 1
fi
diff_file=$(mktemp "${TMPDIR:-/tmp}/mirror-uboot-diff.XXXXXX")
expected_file=$(mktemp "${TMPDIR:-/tmp}/mirror-uboot-expected.XXXXXX")
trap 'rm -f "$diff_file" "$expected_file"' EXIT HUP INT TERM
cat "$bootpatch" "$patch" > "$expected_file"
git -C "$src" diff --binary > "$diff_file"
if [ ! -s "$diff_file" ]; then
  git -C "$src" apply --check "$patch"
  git -C "$src" apply "$patch"
  git -C "$src" apply --check "$bootpatch"
  git -C "$src" apply "$bootpatch"
elif cmp -s "$diff_file" "$patch"; then
  git -C "$src" apply --check "$bootpatch"
  git -C "$src" apply "$bootpatch"
elif ! cmp -s "$diff_file" "$expected_file"; then
  echo 'U-Boot checkout has unexpected modifications; refusing to modify it.' >&2
  exit 1
else
  echo 'Host-tool and EVK boot-command patches are already applied.'
fi

# NXP overrides bootcmd with its USB manufacturing path in autoboot.c.
# Build a separate archive so this target-only experimental patch never
# changes the shared vendor checkout.
mkdir -p "$root/build"
isolated=$(mktemp -d "$root/build/uboot-direct-source.XXXXXX")
git -C "$src" archive "$revision" > "$isolated/source.tar"
mkdir "$isolated/source"
tar -xf "$isolated/source.tar" -C "$isolated/source"
src="$isolated/source"
for direct_patch in "$patch" "$bootpatch" "$root/patches/uboot-direct-ums-usb-boot.patch"; do
  patch -d "$src" -p1 --dry-run < "$direct_patch"
  patch -d "$src" -p1 < "$direct_patch"
done

export SOURCE_DATE_EPOCH=1606473267
mkdir -p "$root/build"
rm -rf "$root/build/uboot*"
out="$root/build/uboot-nxp"
mkdir -p $out
echo "Build directory: $out"
make -C "$src" O="$out" CROSS_COMPILE=aarch64-none-elf- imx8mm_evk_defconfig
# These settings reduce accidental persistent changes and select fastboot at
# startup. They do NOT make UCmd, fastboot flash, or arbitrary commands safe.
python3 "$root/scripts/configure-uboot-research.py" "$out/.config"
make -C "$src" O="$out" CROSS_COMPILE=aarch64-none-elf- olddefconfig
bootcmd='ums 0 mmc 2'
for expected in 'CONFIG_ENV_IS_NOWHERE=y' '# CONFIG_ENV_IS_IN_MMC is not set' '# CONFIG_CMD_SAVEENV is not set' 'CONFIG_USE_BOOTCOMMAND=y' "CONFIG_BOOTCOMMAND=\"$bootcmd\"" 'CONFIG_BOOTDELAY=0' 'CONFIG_FASTBOOT_UUU_SUPPORT=y' 'CONFIG_FASTBOOT_BUF_ADDR=0x42800000' 'CONFIG_FASTBOOT_BUF_SIZE=0x800000'; do
  if ! grep -Fqx "$expected" "$out/.config"; then
    echo "Required research setting not retained: $expected" >&2
    exit 1
  fi
done
make -C "$src" O="$out" CROSS_COMPILE=aarch64-none-elf- -j4 u-boot.bin
# The legacy board header can override the Kconfig value. Inspect the actual
# linked default environment, not merely the requested .config setting.
if ! strings -a "$out/u-boot.bin" | grep -Fxq "bootcmd=$bootcmd"; then
  echo "Compiled default boot command is not $bootcmd; refusing to report success." >&2
  exit 1
fi
if ! aarch64-none-elf-nm "$out/u-boot" | grep -q ' do_usb_mass_storage$'; then
  echo 'UMS command missing from linked image.' >&2
  exit 1
fi
if strings -a "$out/u-boot.bin" | grep -Eq 'Boot from USB for (uuu|mfgtools)|Run bootcmd_mfg:'; then
  echo 'USB boot override strings remain in the direct UMS image.' >&2
  exit 1
fi
sha256sum "$out/u-boot.bin"
