#!/bin/sh
# Attempt UMS after the specially built RAM U-Boot exits fastboot normally.
# https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/06-flash-image.md
# The host-visible disk is writable. Do not initialize or write to it.
# Handoff and recovery without UART have not been established.
set -eu
cd "$(dirname "$0")/.."
libdir="$PWD/.pixi/envs/default/lib"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run backup-expose [--check]' >&2; exit 2 ;; esac
if [ "$#" -gt 1 ]; then echo 'Too many arguments.' >&2; exit 2; fi
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then echo "Missing $library; run mise run setup." >&2; exit 1; fi
done
uuu=$(command -v uuu)
if [ ! -f "$uuu" ] || [ ! -x "$uuu" ]; then echo 'Missing mise-managed UUU.' >&2; exit 1; fi
fastboot=$(command -v fastboot)
if [ ! -f "$fastboot" ] || [ ! -x "$fastboot" ]; then echo 'Missing mise-managed fastboot.' >&2; exit 1; fi
serial=2f1979aac2a4e006
printf 'Commands (in order):\n'
printf '  sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 -m 2:1 FB: ucmd setenv stdout serial,fastboot\n' "$libdir" "$uuu"
printf '  sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 -m 2:1 FB: ucmd printenv bootcmd\n' "$libdir" "$uuu"
printf '  sudo /usr/bin/env DYLD_LIBRARY_PATH="%s" "%s" -v -t 20 -m 2:1 FB: ucmd setenv stdout serial\n' "$libdir" "$uuu"
printf '  sudo "%s" -s %s continue\n' "$fastboot" "$serial"
if [ "${1:-}" = --check ]; then echo 'Check only: no sudo and no device command run.'; exit 0; fi
if [ ! -t 0 ]; then echo 'Run in your terminal to enter your sudo password.' >&2; exit 1; fi
echo 'Before handoff, existing disks are:'
before=$(mktemp "${TMPDIR:-/tmp}/mirror-disks-before.XXXXXX")
after=$(mktemp "${TMPDIR:-/tmp}/mirror-disks-after.XXXXXX")
proof=$(mktemp "${TMPDIR:-/tmp}/mirror-bootcmd.XXXXXX")
trap 'rm -f "$before" "$after" "$proof"' EXIT HUP INT TERM
diskutil list -plist > "$before"
diskutil list
echo 'The exposed disk is WRITABLE. If macOS asks to initialize it, choose Ignore.'
echo 'This untested handoff may end fastboot access or require a power cycle.'
echo 'Routing stdout temporarily to fastboot so the boot command can be inspected.'
sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -v -t 20 -m 2:1 FB: ucmd setenv stdout serial,fastboot
echo 'Reading the current bootcmd; this cannot prove what command is already executing.'
if ! sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -v -t 20 -m 2:1 FB: ucmd printenv bootcmd > "$proof"; then
  cat "$proof"
  echo 'Could not read bootcmd; refusing to leave fastboot.' >&2
  exit 1
fi
cat "$proof"
if ! grep -Fxq 'bootcmd=fastboot 0; ums 0 mmc 2' "$proof"; then
  echo 'Expected UMS-handoff bootcmd not observed; refusing to leave fastboot.' >&2
  exit 1
fi
echo 'Restoring stdout to serial before the fastboot gadget is unregistered; no saveenv.'
sudo /usr/bin/env DYLD_LIBRARY_PATH="$libdir" "$uuu" -v -t 20 -m 2:1 FB: ucmd setenv stdout serial
echo 'Requesting fastboot continue for the observed MIRROR serial only.'
sudo "$fastboot" -s "$serial" continue
echo 'Fastboot continue does not confirm UMS started. Check for a newly attached disk:'
diskutil list -plist > "$after"
diskutil list
python -c 'import plistlib,sys
with open(sys.argv[1], "rb") as f: before = set(plistlib.load(f).get("WholeDisks", []))
with open(sys.argv[2], "rb") as f: after = set(plistlib.load(f).get("WholeDisks", []))
new = sorted(after - before)
if not new:
 print("No new whole disk is visible immediately after the command; UMS is not confirmed. Check manually before retrying.", file=sys.stderr)
 sys.exit(1)
print("New whole-disk candidates:", ", ".join(new), "(identity not yet verified)")' "$before" "$after"
echo 'Do not initialize the disk. Share the output before choosing a disk to copy.'
