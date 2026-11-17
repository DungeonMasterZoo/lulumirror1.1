#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
host=mirror@10.0.76.64
testfile="$root/build/camera-ov5645.DmSlYCCR/ov5645.ko"
remote_script="$root/scripts/test-camera-ov5645-remote.sh"
expected=6426a32546bef00dea6acb27dbd56ddb7654930b4f76d109d5598abda1493973
mode=${CAMERA_OV5645_MODE:-probe}
case "$mode" in probe|capture) ;; *) echo 'Unexpected test mode.' >&2; exit 2 ;; esac
case "${1:-}" in ''|--check) ;; *) echo 'Usage: mise run test-camera-ov5645 [--check]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
[ -f "$testfile" ] && [ -f "$remote_script" ] || { echo 'Missing test artifact or script.' >&2; exit 1; }
actual=$(shasum -a 256 "$testfile"); actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo 'Test module hash mismatch.' >&2; exit 1; }
echo 'This temporarily stops camhub and loads an unverified OV5645 driver to check sensor binding and topology.'
[ "$mode" != capture ] || echo 'It also enables the media link and captures 15 frames to /dev/null; no images are saved.'
echo 'It initializes the camera registers and uses existing supply mappings; it does not change regulator voltages or installed files.'
echo 'A faulty or ABI-incompatible module could hang Linux; reboot should reload the original unchanged driver.'
echo "Command: ssh $host mktemp -d /tmp/mirror-ov5645.XXXXXXXX"
echo "Command: scp $testfile $remote_script $host:<new-staging-directory>/"
echo "Command: ssh -t $host sudo /bin/sh <staging-directory>/test-camera-ov5645-remote.sh <staging-directory> $mode"
if [ "${1:-}" = --check ]; then echo 'Check only: no connection or device changes.'; exit 0; fi
[ -t 0 ] || { echo 'Run interactively.' >&2; exit 1; }
printf 'Type TEST OV5645 to continue: '
IFS= read -r confirmation
[ "$confirmation" = 'TEST OV5645' ] || { echo 'Stopped: not confirmed.' >&2; exit 1; }
remote=$(ssh "$host" 'mktemp -d /tmp/mirror-ov5645.XXXXXXXX')
case "$remote" in /tmp/mirror-ov5645.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
printf 'Command: scp "%s" "%s" "%s:%s/"\n' "$testfile" "$remote_script" "$host" "$remote"
scp "$testfile" "$remote_script" "$host:$remote/"
printf 'Command: ssh -t "%s" sudo /bin/sh "%s/test-camera-ov5645-remote.sh" "%s" "%s"\n' "$host" "$remote" "$remote" "$mode"
ssh -t "$host" sudo /bin/sh "$remote/test-camera-ov5645-remote.sh" "$remote" "$mode"
