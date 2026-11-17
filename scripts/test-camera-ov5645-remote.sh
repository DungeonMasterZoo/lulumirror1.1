#!/bin/sh
# Probe only, using a temporary module. Installed modules and DT remain unchanged.
set -eu
[ "$#" = 2 ] || exit 2
case "$1" in /tmp/mirror-ov5645.*) ;; *) echo 'Unexpected staging directory.' >&2; exit 2 ;; esac
case "$2" in probe|capture) mode=$2 ;; *) echo 'Unexpected test mode.' >&2; exit 2 ;; esac
testfile="$1/ov5645.ko"
testhash=6426a32546bef00dea6acb27dbd56ddb7654930b4f76d109d5598abda1493973
original=/lib/modules/6.18.60-dirty/kernel/drivers/media/i2c/ov5640.ko
orighash=e759349fd739e2d0f3151a5836ccdef03ce93ca0e1763f493424fdd11b3a8091
hash() { sha256sum "$1" | cut -d ' ' -f 1; }
loaded() { grep -q "^$1 " /proc/modules; }
[ "$(id -u)" = 0 ] || { echo 'Must run with sudo.' >&2; exit 1; }
[ "$(uname -r)" = 6.18.60-dirty ] || { echo 'Unexpected kernel.' >&2; exit 1; }
[ "$(hash "$testfile")" = "$testhash" ] || { echo 'Test module hash mismatch.' >&2; exit 1; }
[ "$(hash "$original")" = "$orighash" ] || { echo 'Original OV5640 module hash mismatch.' >&2; exit 1; }
[ "$(cat /proc/sys/kernel/modules_disabled)" = 0 ] || { echo 'Module loading disabled.' >&2; exit 1; }
loaded ov5640 || { echo 'Original OV5640 module not loaded.' >&2; exit 1; }
! loaded ov5645 || { echo 'OV5645 module already loaded; refusing to disturb it.' >&2; exit 1; }
[ ! -L /sys/bus/i2c/devices/2-003c/driver ] || { echo 'Camera already bound; refusing test.' >&2; exit 1; }
for module in v4l2_fwnode v4l2_async videodev mc; do
  loaded "$module" || { echo "Required module $module is not loaded." >&2; exit 1; }
done
service_was_active=0
if systemctl is-active --quiet camhub; then service_was_active=1; fi
inserting=0
cleanup() {
  trap - EXIT HUP INT TERM
  set +e
  status=0
  if [ "$inserting" = 1 ] && loaded ov5645; then
    if [ -L /sys/bus/i2c/devices/2-003c/driver ]; then
      driver=$(readlink /sys/bus/i2c/devices/2-003c/driver)
      case "$driver" in
        */ov5645)
          echo 'Command: write 2-003c to /sys/bus/i2c/drivers/ov5645/unbind'
          printf 2-003c > /sys/bus/i2c/drivers/ov5645/unbind || status=1 ;;
        *) echo "WARNING: unexpected camera driver $driver; refusing unbind." >&2; status=1 ;;
      esac
    fi
    if [ "$status" = 0 ]; then
      echo 'Command: /sbin/rmmod ov5645'
      /sbin/rmmod ov5645 || status=1
    fi
  fi
  if loaded ov5645; then echo 'WARNING: test module remains loaded.' >&2; status=1; fi
  if ! loaded ov5640 || [ "$(hash "$original")" != "$orighash" ]; then
    echo 'WARNING: original OV5640 module state or file hash is unexpected.' >&2; status=1
  fi
  if [ "$service_was_active" = 1 ] && ! loaded ov5645 && loaded ov5640; then
    echo 'Command: systemctl start camhub'
    systemctl start camhub && systemctl is-active --quiet camhub || status=1
  fi
  if [ "$status" = 0 ]; then
    echo 'Cleanup checks passed: test module absent, original module loaded and unchanged, prior service state restored.'
  else
    echo 'WARNING: cleanup incomplete. Share output before further changes; reboot should reload the unchanged original driver.' >&2
  fi
  return "$status"
}
finish() { result=$?; cleanup || result=1; exit "$result"; }
trap 'finish' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
echo 'Command: systemctl stop camhub'
systemctl stop camhub
echo "Command: /sbin/insmod $testfile"
inserting=1
/sbin/insmod "$testfile"
echo 'Command: readlink /sys/bus/i2c/devices/2-003c/driver'
if [ -L /sys/bus/i2c/devices/2-003c/driver ]; then
  driver=$(readlink /sys/bus/i2c/devices/2-003c/driver)
  echo "Camera driver: $driver"
  case "$driver" in */ov5645) ;; *) echo 'Unexpected driver; stopping.' >&2; exit 1 ;; esac
else
  echo 'Camera sensor did not bind.'
  [ "$mode" != capture ] || exit 1
fi
echo 'Command: media-ctl -d /dev/media0 -p'
media-ctl -d /dev/media0 -p || echo 'Media topology unavailable.'
if [ "$mode" = capture ]; then
  echo 'Command: media-ctl -d /dev/media0 -l '\''"ov5645 2-003c":0 -> "csis-32e30000.mipi-csi":0 [1]'\'''
  media-ctl -d /dev/media0 -l '"ov5645 2-003c":0 -> "csis-32e30000.mipi-csi":0 [1]'
  echo 'Command: media-ctl -d /dev/media0 -V '\''"ov5645 2-003c":0 [fmt:UYVY8_1X16/1920x1080]'\'''
  media-ctl -d /dev/media0 -V '"ov5645 2-003c":0 [fmt:UYVY8_1X16/1920x1080]'
  for pad in '"csis-32e30000.mipi-csi":0' '"csis-32e30000.mipi-csi":1' '"csi":0' '"csi":1'; do
    echo "Command: media-ctl -d /dev/media0 -V '$pad [fmt:UYVY8_1X16/1920x1080]'"
    media-ctl -d /dev/media0 -V "$pad [fmt:UYVY8_1X16/1920x1080]"
  done
  echo 'Command: v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=UYVY'
  v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=UYVY
  echo 'Command: timeout 15 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=15 --stream-to=/dev/null'
  if output=$(timeout 15 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=15 --stream-to=/dev/null 2>&1); then capture_status=0; else capture_status=$?; fi
  printf '%s\n' "$output"
  frames=$(printf '%s' "$output" | tr -cd '<' | wc -c | tr -d ' ')
  echo "Capture exit status: $capture_status; frame markers: $frames (frames discarded)."
  if [ "$capture_status" != 0 ] || [ "$frames" -lt 15 ]; then
    echo 'Capture did not confirm 15 frames.' >&2
    capture_failed=1
  else
    echo 'Captured 15 frame markers; image content was not inspected.'
    capture_failed=0
  fi
fi
echo 'Command: journalctl -k -b --no-pager -n 60'
journalctl -k -b --no-pager -n 60 || echo 'Kernel log unavailable.'
echo 'Probe check complete; restoring prior state.'
[ "$mode" != capture ] || [ "$capture_failed" = 0 ]
