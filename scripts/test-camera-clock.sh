#!/bin/sh
# Copy the test to the MIRROR over SSH. Does not reboot.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
host=mirror@10.0.76.64
candidate="$root/build/camera-clko1-test.dtb"
installer="$root/scripts/install-camera-clock-remote.sh"
recovery="$HOME/Downloads/mirror-backup/lemonademirror-original.dtb"
testhash=f1cd30738b28929c7385c9d72d3069201cccb1d97f10b73bb4787dafd02b27ef
orighash=1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run test-camera-clock [--check]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
for entry in "$candidate:$testhash" "$recovery:$orighash"; do
  file=${entry%:*}; expected=${entry##*:}
  [ -f "$file" ] || { echo "Missing $file" >&2; exit 1; }
  actual=$(sha256sum "$file"); actual=${actual%% *}
  [ "$actual" = "$expected" ] || { echo "Hash mismatch: $file" >&2; exit 1; }
done
[ -f "$installer" ] || { echo 'Missing remote installer.' >&2; exit 1; }
echo 'Verified local candidate and recovery DTB. Experimental candidate is untested.'
echo 'This changes the Linux boot DTB on the MIRROR, not the eMMC bootloader.'
echo 'If Linux cannot boot, use the documented USB/PROG1 recovery route.'
echo "Command: ssh $host mktemp -d /tmp/mirror-camera.XXXXXXXX"
echo "Command: scp $candidate $installer $host:<new-staging-directory>/"
echo "Command: ssh -t $host sudo /bin/sh <staging-directory>/install-camera-clock-remote.sh <staging-directory>"
if [ "${1:-}" = --check ]; then echo 'Check only: no connection or device changes.'; exit 0; fi
[ -t 0 ] || { echo 'Run interactively in your terminal.' >&2; exit 1; }
printf 'Type INSTALL CAMERA TEST to continue: '
IFS= read -r confirmation
[ "$confirmation" = 'INSTALL CAMERA TEST' ] || { echo 'Stopped: not confirmed.' >&2; exit 1; }
remote=$(ssh "$host" 'mktemp -d /tmp/mirror-camera.XXXXXXXX')
case "$remote" in /tmp/mirror-camera.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
printf 'Command: scp "%s" "%s" "%s:%s/"\n' "$candidate" "$installer" "$host" "$remote"
scp "$candidate" "$installer" "$host:$remote/"
printf 'Command: ssh -t "%s" sudo /bin/sh "%s/install-camera-clock-remote.sh" "%s"\n' "$host" "$remote" "$remote"
ssh -t "$host" sudo /bin/sh "$remote/install-camera-clock-remote.sh" "$remote"
