#!/bin/sh
# Run on the MIRROR by test-camera-clock.sh. Alters only its Linux boot FAT.
set -eu
[ "$#" -eq 1 ] || exit 2
case "$1" in /tmp/mirror-camera.*) ;; *) echo 'Unexpected staging path' >&2; exit 1 ;; esac
staged="$1/camera-clko1-test.dtb"
orig=1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41
candidate=f1cd30738b28929c7385c9d72d3069201cccb1d97f10b73bb4787dafd02b27ef
hash() { sha256sum "$1" | cut -d ' ' -f 1; }
[ "$(id -u)" = 0 ] || { echo 'Must run with sudo.' >&2; exit 1; }
[ "$(hash "$staged")" = "$candidate" ] || { echo 'Staged candidate hash mismatch.' >&2; exit 1; }
dir=$(mktemp -d /run/mirror-camera-boot.XXXXXXXX)
mounted=0
cleanup() {
  if [ "$mounted" = 1 ]; then
    if ! umount "$dir"; then echo "WARNING: could not unmount $dir" >&2; return 1; fi
    mounted=0
  fi
  rmdir "$dir"
}
trap cleanup EXIT
echo "Command: mount /dev/mmcblk2p4 $dir"
mount /dev/mmcblk2p4 "$dir"
mounted=1
current="$dir/imx8mm-mirror.dtb"
saved="$dir/imx8mm-mirror.original.dtb"
next="$dir/imx8mm-mirror.camera-test.tmp"
[ "$(hash "$current")" = "$orig" ] || { echo 'Installed DTB does not match expected original.' >&2; exit 1; }
if [ -e "$saved" ]; then
  [ "$(hash "$saved")" = "$orig" ] || { echo 'Existing boot-partition backup differs; refusing overwrite.' >&2; exit 1; }
else
  echo "Command: cp $current $saved"
  cp "$current" "$saved"
  sync
  [ "$(hash "$saved")" = "$orig" ] || { echo 'Original DTB backup verification failed.' >&2; exit 1; }
fi
[ ! -e "$next" ] || { echo 'Temporary DTB already exists; refusing overwrite.' >&2; exit 1; }
echo "Command: cp $staged $next"
cp "$staged" "$next"
sync
[ "$(hash "$next")" = "$candidate" ] || { echo 'Candidate copy verification failed.' >&2; exit 1; }
echo "Command: mv $next $current"
mv "$next" "$current"
sync
[ "$(hash "$current")" = "$candidate" ] || { echo 'Installed DTB verification failed; do not reboot.' >&2; exit 1; }
echo 'Verified installed candidate and boot-partition original backup.'
echo "Command: umount $dir"
umount "$dir"
mounted=0
rmdir "$dir"
trap - EXIT
echo 'Installation complete. No reboot was issued; share this output before rebooting.'
