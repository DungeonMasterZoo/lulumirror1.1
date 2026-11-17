#!/bin/sh
# Restore the verified original Linux DTB from the boot-partition backup.
set -eu
orig=1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41
candidate=f1cd30738b28929c7385c9d72d3069201cccb1d97f10b73bb4787dafd02b27ef
hash() { sha256sum "$1" | cut -d ' ' -f 1; }
[ "$(id -u)" = 0 ] || { echo 'Must run with sudo.' >&2; exit 1; }
dir=$(mktemp -d /run/mirror-camera-restore.XXXXXXXX)
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
next="$dir/imx8mm-mirror.restore.tmp"
[ "$(hash "$current")" = "$candidate" ] || { echo 'Current DTB is not the expected experiment; refusing overwrite.' >&2; exit 1; }
[ "$(hash "$saved")" = "$orig" ] || { echo 'Original backup missing or changed.' >&2; exit 1; }
[ ! -e "$next" ] || { echo 'Restore staging file already exists.' >&2; exit 1; }
echo "Command: cp $saved $next"
cp "$saved" "$next"
sync
[ "$(hash "$next")" = "$orig" ] || { echo 'Restore copy verification failed.' >&2; exit 1; }
echo "Command: mv $next $current"
mv "$next" "$current"
sync
[ "$(hash "$current")" = "$orig" ] || { echo 'Restored DTB verification failed; do not reboot.' >&2; exit 1; }
echo "Command: umount $dir"
umount "$dir"
mounted=0
rmdir "$dir"
trap - EXIT
echo 'Original DTB restored and verified. No reboot was issued.'
