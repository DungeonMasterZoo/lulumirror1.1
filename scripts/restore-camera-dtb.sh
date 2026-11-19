#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
host=mirror@10.0.76.64
recovery="$HOME/Downloads/mirror-backup/lemonademirror-original.dtb"
expected=1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run restore-camera-dtb [--check]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
[ -f "$recovery" ] || { echo 'Local recovery DTB missing.' >&2; exit 1; }
actual=$(sha256sum "$recovery"); actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo 'Local recovery hash mismatch.' >&2; exit 1; }
echo 'This restores the original DTB from the verified backup on the MIRROR.'
echo "Command: ssh $host mktemp -d /tmp/mirror-restore.XXXXXXXX"
echo "Command: scp $root/scripts/restore-camera-dtb-remote.sh $host:<new-staging-directory>/"
echo "Command: ssh -t $host sudo /bin/sh <staging-directory>/restore-camera-dtb-remote.sh"
if [ "${1:-}" = --check ]; then echo 'Check only: no connection or device changes.'; exit 0; fi
[ -t 0 ] || { echo 'Run interactively.' >&2; exit 1; }
printf 'Type RESTORE ORIGINAL DTB to continue: '
IFS= read -r confirmation
[ "$confirmation" = 'RESTORE ORIGINAL DTB' ] || { echo 'Stopped: not confirmed.' >&2; exit 1; }
remote=$(ssh "$host" 'mktemp -d /tmp/mirror-restore.XXXXXXXX')
case "$remote" in /tmp/mirror-restore.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
printf 'Command: scp "%s" "%s:%s/"\n' "$root/scripts/restore-camera-dtb-remote.sh" "$host" "$remote"
scp "$root/scripts/restore-camera-dtb-remote.sh" "$host:$remote/"
printf 'Command: ssh -t "%s" sudo /bin/sh "%s/restore-camera-dtb-remote.sh"\n' "$host" "$remote"
ssh -t "$host" sudo /bin/sh "$remote/restore-camera-dtb-remote.sh"
