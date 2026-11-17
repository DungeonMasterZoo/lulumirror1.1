#!/bin/sh
# Install or restore verified camera files. Never reboots or changes bootloader.
set -eu
[ "$#" = 2 ] || exit 2
mode=$1; stage=$2
case "$mode" in install|restore) ;; *) exit 2 ;; esac
case "$stage" in /tmp/mirror-ov5645-persist.*) ;; *) exit 2 ;; esac
[ "$(id -u)" = 0 ] || { echo 'Must run with sudo.' >&2; exit 1; }
[ "$(uname -r)" = 6.18.60-dirty ] || { echo 'Unexpected kernel.' >&2; exit 1; }
od=1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41
nd=ac1bb195a5b86b39f238c4ee3e6a87ade4247378b46fcf7b9e65a98d3aaf5ae8
oh=0e5b492ebc670aadd186056ddbbe3c4637cda0471d15d2535b1200f224bd23dd
nh=3cdaa4534e206d79d13507a5d07f764b02ba3c881c9d92c41db97ebb124edb72
os=b346f61c962ea749e20a208ea15b9ca09deb75b8e162251d534622b9388818c3
ns=b72ec805fdd6b945e7a0be725ec798bc087417a3c23bbced04b1b319527e3d2b
ov5645=482f35679958eee7d29be08dba8ee6d53ebb3897d5bf98263cb71fe5c243480d
backup=/home/mirror/mirror-ov5645-recovery.bak
hub=/usr/local/sbin/camhub.sh
camset=/usr/local/sbin/camset.sh
hash() { sha256sum "$1" | cut -d ' ' -f 1; }
check() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(hash "$1")" = "$2" ]; }
known() { check "$1" "$2" || check "$1" "$3"; }
if findmnt -rn -S /dev/mmcblk2p4 | grep -q .; then echo 'Boot partition already mounted; refusing.' >&2; exit 1; fi
dir=$(mktemp -d /run/mirror-ov5645-boot.XXXXXXXX)
mounted=0
cleanup() {
  trap - EXIT HUP INT TERM
  result=$1
  if [ "$mounted" = 1 ]; then
    echo "Command: umount $dir"
    umount "$dir" || { echo 'WARNING: boot unmount failed.' >&2; result=1; }
  fi
  rmdir "$dir" 2>/dev/null || :
  if [ "$result" != 0 ]; then echo 'STOP: operation incomplete; do not reboot. Share the output.' >&2; fi
  exit "$result"
}
trap 'cleanup $?' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
echo "Command: mount /dev/mmcblk2p4 $dir"
mount /dev/mmcblk2p4 "$dir"
mounted=1
dtb="$dir/imx8mm-mirror.dtb"
if [ "$mode" = install ]; then
  check "$dtb" "$od" && check "$hub" "$oh" && check "$camset" "$os" || { echo 'Existing files differ from expected originals.' >&2; exit 1; }
  check "$stage/imx8mm-mirror-ov5645.dtb" "$nd" && check "$stage/camhub.sh" "$nh" && check "$stage/camset.sh" "$ns" || { echo 'Candidate hash mismatch.' >&2; exit 1; }
  check /lib/modules/6.18.60-dirty/kernel/drivers/media/i2c/ov5645.ko "$ov5645" || { echo 'Stock OV5645 module missing or differs.' >&2; exit 1; }
  [ ! -e "$backup" ] && [ ! -L "$backup" ] || { echo 'Recovery directory already exists; refusing overwrite.' >&2; exit 1; }
  echo "Command: mkdir -m 700 $backup"
  mkdir -m 700 "$backup"
  for spec in "$dtb:original.dtb" "$hub:camhub.sh" "$camset:camset.sh"; do
    source=${spec%:*}; name=${spec##*:}
    echo "Command: cp -p $source $backup/$name"
    cp -p "$source" "$backup/$name"
  done
  sync
  check "$backup/original.dtb" "$od" && check "$backup/camhub.sh" "$oh" && check "$backup/camset.sh" "$os" || { echo 'Recovery copy verification failed.' >&2; exit 1; }
  echo 'Recovery copies verified before changes.'
  source_dtb="$stage/imx8mm-mirror-ov5645.dtb"; source_hub="$stage/camhub.sh"; source_set="$stage/camset.sh"
  target_d=$nd; target_h=$nh; target_s=$ns
else
  check "$backup/original.dtb" "$od" && check "$backup/camhub.sh" "$oh" && check "$backup/camset.sh" "$os" || { echo 'Recovery files missing or changed.' >&2; exit 1; }
  known "$dtb" "$od" "$nd" && known "$hub" "$oh" "$nh" && known "$camset" "$os" "$ns" || { echo 'Current files have unexpected changes; refusing restore.' >&2; exit 1; }
  source_dtb="$backup/original.dtb"; source_hub="$backup/camhub.sh"; source_set="$backup/camset.sh"
  target_d=$od; target_h=$oh; target_s=$os
fi
replace() {
  src=$1; dest=$2; expected=$3; perm=$4
  if check "$dest" "$expected"; then echo "Already matches: $dest"; return; fi
  tmp="${dest}.ov5645-new"
  [ ! -e "$tmp" ] && [ ! -L "$tmp" ] || { echo "Staging file exists: $tmp" >&2; return 1; }
  echo "Command: install -m $perm $src $tmp"
  install -m "$perm" "$src" "$tmp"
  sync
  check "$tmp" "$expected" || { echo 'Staging hash mismatch.' >&2; return 1; }
  echo "Command: mv $tmp $dest"
  mv "$tmp" "$dest"
  sync
  check "$dest" "$expected" || { echo 'Installed hash mismatch.' >&2; return 1; }
}
# The scripts support both sensor variants, so update them before switching DT.
replace "$source_hub" "$hub" "$target_h" 755
replace "$source_set" "$camset" "$target_s" 755
replace "$source_dtb" "$dtb" "$target_d" 644
echo 'All three files verified. No reboot or service restart was issued.'
