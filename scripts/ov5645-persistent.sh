#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
host=mirror@10.0.76.64
mode=${OV5645_ACTION:-install}
case "$mode" in install|restore) ;; *) exit 2 ;; esac
case "${1:-}" in ''|--check) ;; *) echo 'Only --check is supported.' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
dir="$root/build/ov5645-persistent"
remote_script="$root/scripts/ov5645-persistent-remote.sh"
recovery="$HOME/Downloads/mirror-backup/lemonademirror-original.dtb"
if [ "$mode" = install ]; then
for entry in "$dir/imx8mm-mirror-ov5645.dtb:ac1bb195a5b86b39f238c4ee3e6a87ade4247378b46fcf7b9e65a98d3aaf5ae8" "$dir/camhub.sh:3cdaa4534e206d79d13507a5d07f764b02ba3c881c9d92c41db97ebb124edb72" "$dir/camset.sh:b72ec805fdd6b945e7a0be725ec798bc087417a3c23bbced04b1b319527e3d2b" "$recovery:1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41"; do
  file=${entry%:*}; expected=${entry##*:}; [ -f "$file" ] || { echo "Missing: $file" >&2; exit 1; }
  actual=$(shasum -a 256 "$file"); actual=${actual%% *}; [ "$actual" = "$expected" ] || { echo "Hash mismatch: $file" >&2; exit 1; }
done
fi
[ -f "$remote_script" ] || exit 1
echo "Action: $mode persistent OV5645 configuration. Changes Linux boot DTB and camera scripts, not bootloader or regulators."
echo 'No reboot is performed. If anything fails, do not reboot; share output.'
echo 'The USB/PROG1 boot-partition recovery path has not been tested end-to-end.'
echo "Command: ssh $host mktemp -d /tmp/mirror-ov5645-persist.XXXXXXXX"
if [ "$mode" = install ]; then
  echo "Command: scp $remote_script $dir/imx8mm-mirror-ov5645.dtb $dir/camhub.sh $dir/camset.sh $host:<staging>/"
else
  echo "Command: scp $remote_script $host:<staging>/"
fi
echo "Command: ssh -t $host sudo /bin/sh <staging>/ov5645-persistent-remote.sh $mode <staging>"
[ "${1:-}" != --check ] || { echo 'Check only: no connection or device changes.'; exit 0; }
[ -t 0 ] || { echo 'Run interactively.' >&2; exit 1; }
printf 'Type %s OV5645 to continue: ' "$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')"
IFS= read -r confirmation
[ "$confirmation" = "$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]') OV5645" ] || { echo 'Stopped: not confirmed.' >&2; exit 1; }
remote=$(ssh "$host" 'mktemp -d /tmp/mirror-ov5645-persist.XXXXXXXX')
case "$remote" in /tmp/mirror-ov5645-persist.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
if [ "$mode" = install ]; then
  printf 'Command: scp "%s" "%s" "%s" "%s" "%s:%s/"\n' "$remote_script" "$dir/imx8mm-mirror-ov5645.dtb" "$dir/camhub.sh" "$dir/camset.sh" "$host" "$remote"
  scp "$remote_script" "$dir/imx8mm-mirror-ov5645.dtb" "$dir/camhub.sh" "$dir/camset.sh" "$host:$remote/"
else
  printf 'Command: scp "%s" "%s:%s/"\n' "$remote_script" "$host" "$remote"
  scp "$remote_script" "$host:$remote/"
fi
printf 'Command: ssh -t %s sudo /bin/sh %s/ov5645-persistent-remote.sh %s %s\n' "$host" "$remote" "$mode" "$remote"
ssh -t "$host" sudo /bin/sh "$remote/ov5645-persistent-remote.sh" "$mode" "$remote"
