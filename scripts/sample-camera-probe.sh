#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
host=mirror@10.0.76.64
script="$root/scripts/sample-camera-probe-remote.py"
case "${1:-}" in '') ;; --check) ;; *) echo 'Usage: mise run sample-camera-probe [--check]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
[ -f "$script" ] || { echo 'Missing diagnostic script.' >&2; exit 1; }
python -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' "$script"
echo 'This samples debugfs and retries the unbound camera probe once.'
echo 'The probe temporarily controls the camera clock, power, and reset; no boot files or voltage settings are written.'
echo "Command: ssh $host mktemp -d /tmp/mirror-camera-probe.XXXXXXXX"
echo "Command: scp $script $host:<new-staging-directory>/"
echo "Command: ssh -t $host sudo python3 <staging-directory>/sample-camera-probe-remote.py"
if [ "${1:-}" = --check ]; then echo 'Check only: no connection or device changes.'; exit 0; fi
[ -t 0 ] || { echo 'Run interactively.' >&2; exit 1; }
remote=$(ssh "$host" 'mktemp -d /tmp/mirror-camera-probe.XXXXXXXX')
case "$remote" in /tmp/mirror-camera-probe.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory.' >&2; exit 1 ;; esac
printf 'Command: scp "%s" "%s:%s/"\n' "$script" "$host" "$remote"
scp "$script" "$host:$remote/"
printf 'Command: ssh -t "%s" sudo python3 "%s/sample-camera-probe-remote.py"\n' "$host" "$remote"
ssh -t "$host" sudo python3 "$remote/sample-camera-probe-remote.py"
