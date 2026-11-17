#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
host=mirror@10.0.76.64
variant=${CAMERA_TEST_VARIANT:-timing}
case "$variant" in
  timing)
    testfile="$root/build/camera-timing.Y8bzANnH/ov5640.ko"
    testhash=2f1fa8d0775cdf8da2b4600e4af4034ce1a3b5eb56e6baa62d9b71e93351f3d1 ;;
  polarity)
    testfile="$root/build/camera-polarity.9LYH08NX/ov5640.ko"
    testhash=b1a7dda8f981be8bec43e524bb4714106ed294a5f9789087fe1a34cb17619cb4 ;;
  *) echo 'Unknown test variant.' >&2; exit 2 ;;
esac
original="$root/build/camera-timing.Y8bzANnH/ov5640-original.ko"
remote_script="$root/scripts/test-camera-timing-remote.sh"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run test-camera-timing [--check]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
for item in "$testfile:$testhash" "$original:e759349fd739e2d0f3151a5836ccdef03ce93ca0e1763f493424fdd11b3a8091"; do
  file=${item%:*}; expected=${item##*:}
  [ -f "$file" ] || { echo "Missing file: $file" >&2; exit 1; }
  actual=$(shasum -a 256 "$file"); actual=${actual%% *}
  [ "$actual" = "$expected" ] || { echo "Hash mismatch: $file" >&2; exit 1; }
done
[ -f "$remote_script" ] || { echo 'Missing remote script.' >&2; exit 1; }
echo "This temporarily unloads the original camera driver, loads the unverified $variant module, and attempts to restore the original."
[ "$variant" != polarity ] || echo 'This reverses the camera power-down GPIO levels; it does not change regulator settings.'
echo 'A faulty module could hang Linux; reboot should reload the unchanged on-disk original.'
echo 'The camera service will be temporarily stopped. The task does not replace installed module files.'
echo "Command: ssh $host mktemp -d /tmp/mirror-timing.XXXXXXXX"
echo "Command: scp $testfile $remote_script $host:<new-staging-directory>/"
echo "Command: ssh -t $host sudo /bin/sh <staging-directory>/test-camera-timing-remote.sh <staging-directory> $variant"
if [ "${1:-}" = --check ]; then echo 'Check only: no connection or device changes.'; exit 0; fi
[ -t 0 ] || { echo 'Run interactively.' >&2; exit 1; }
printf 'Type TEST CAMERA MODULE to continue: '
IFS= read -r confirmation
[ "$confirmation" = 'TEST CAMERA MODULE' ] || { echo 'Stopped: not confirmed.' >&2; exit 1; }
remote=$(ssh "$host" 'mktemp -d /tmp/mirror-timing.XXXXXXXX')
case "$remote" in /tmp/mirror-timing.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
printf 'Command: scp "%s" "%s" "%s:%s/"\n' "$testfile" "$remote_script" "$host" "$remote"
scp "$testfile" "$remote_script" "$host:$remote/"
printf 'Command: ssh -t "%s" sudo /bin/sh "%s/test-camera-timing-remote.sh" "%s" "%s"\n' "$host" "$remote" "$remote" "$variant"
ssh -t "$host" sudo /bin/sh "$remote/test-camera-timing-remote.sh" "$remote" "$variant"
