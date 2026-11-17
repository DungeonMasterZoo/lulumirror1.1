#!/bin/sh
# Temporary live module test; the installed module file is never replaced.
set -eu
[ "$#" = 2 ] || exit 2
case "$1" in /tmp/mirror-timing.*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
testfile="$1/ov5640.ko"
case "$2" in
  timing) testhash=2f1fa8d0775cdf8da2b4600e4af4034ce1a3b5eb56e6baa62d9b71e93351f3d1 ;;
  polarity) testhash=b1a7dda8f981be8bec43e524bb4714106ed294a5f9789087fe1a34cb17619cb4 ;;
  *) echo 'Unexpected test variant.' >&2; exit 2 ;;
esac
orighash=e759349fd739e2d0f3151a5836ccdef03ce93ca0e1763f493424fdd11b3a8091
original=/lib/modules/6.18.60-dirty/kernel/drivers/media/i2c/ov5640.ko
hash() { sha256sum "$1" | cut -d ' ' -f 1; }
loaded() { grep -q '^ov5640 ' /proc/modules; }
[ "$(id -u)" = 0 ] || { echo 'Must run with sudo.' >&2; exit 1; }
[ "$(uname -r)" = 6.18.60-dirty ] || { echo 'Unexpected kernel release.' >&2; exit 1; }
[ "$(hash "$testfile")" = "$testhash" ] || { echo 'Test module hash mismatch.' >&2; exit 1; }
[ "$(hash "$original")" = "$orighash" ] || { echo 'Original installed module differs.' >&2; exit 1; }
[ "$(/sbin/modinfo -n ov5640)" = "$original" ] || { echo 'modprobe resolves a different module; refusing test.' >&2; exit 1; }
[ "$(cat /proc/sys/kernel/modules_disabled)" = 0 ] || { echo 'Module loading is disabled.' >&2; exit 1; }
loaded || { echo 'Original camera module is not currently loaded.' >&2; exit 1; }
[ ! -L /sys/bus/i2c/devices/2-003c/driver ] || { echo 'Camera is already bound; refusing to disrupt a working device.' >&2; exit 1; }
for module in v4l2_fwnode v4l2_async videodev mc; do
  grep -q "^$module " /proc/modules || { echo "Required module $module is not loaded." >&2; exit 1; }
done
service_was_active=0
if systemctl is-active --quiet camhub; then service_was_active=1; fi
removed=0
test_loaded=0
transition=none
cleanup() {
  trap - EXIT HUP INT TERM
  set +e
  status=0
  # A signal may arrive between a successful command and its bookkeeping.
  if [ "$transition" = removing ] && ! loaded; then removed=1; fi
  if [ "$transition" = inserting ] && loaded; then test_loaded=1; fi
  if [ "$test_loaded" = 1 ]; then
    echo 'Command: systemctl stop camhub'
    systemctl stop camhub || status=1
    echo 'Command: /sbin/rmmod ov5640'
    if /sbin/rmmod ov5640; then test_loaded=0; else status=1; fi
  fi
  if [ "$removed" = 1 ] && [ "$test_loaded" = 0 ]; then
    echo "Command: /sbin/insmod $original"
    if [ "$(hash "$original")" = "$orighash" ] && /sbin/insmod "$original" && loaded; then
      echo 'Original on-disk module reloaded.'
      removed=0
    else
      echo 'WARNING: original module could not be confirmed loaded.' >&2
      status=1
    fi
  fi
  if [ "$service_was_active" = 1 ] && [ "$test_loaded" = 0 ] && [ "$removed" = 0 ]; then
    echo 'Command: systemctl start camhub'
    systemctl start camhub && systemctl is-active --quiet camhub || status=1
  fi
  [ "$(hash "$original")" = "$orighash" ] || { echo 'WARNING: original module file hash changed.' >&2; status=1; }
  if [ "$status" = 0 ]; then echo 'Cleanup checks passed: original module file unchanged; prior service state restored.'; fi
  if [ "$status" != 0 ]; then
    echo 'WARNING: automatic cleanup was incomplete. Share output; a reboot should reload the unchanged original module.' >&2
  fi
  return "$status"
}
finish() {
  result=$?
  cleanup || result=1
  exit "$result"
}
trap 'finish' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
echo 'Command: systemctl stop camhub'
systemctl stop camhub
[ "$(cat /sys/module/ov5640/refcnt)" = 0 ] || { echo 'Camera module is in use; refusing unload.' >&2; exit 1; }
echo 'Command: /sbin/rmmod ov5640'
transition=removing
/sbin/rmmod ov5640
removed=1
transition=none
echo "Command: /sbin/insmod $testfile"
transition=inserting
/sbin/insmod "$testfile"
test_loaded=1
transition=none
echo 'Experimental module loaded; inspecting camera binding.'
if [ -L /sys/bus/i2c/devices/2-003c/driver ]; then
  echo 'Camera sensor is bound to a driver.'
  if [ "$service_was_active" = 1 ]; then
    echo 'Command: systemctl start camhub'
    systemctl start camhub
    echo 'Waiting 10 seconds for the camera service.'
    sleep 10
    echo 'Command: /usr/local/sbin/mirror-hwcheck'
    /usr/local/sbin/mirror-hwcheck || true
  fi
else
  echo 'Camera sensor did not bind.'
fi
echo 'Command: journalctl -k -b --no-pager -n 40'
journalctl -k -b --no-pager -n 40
echo 'Test complete. Restoring original module and service.'
