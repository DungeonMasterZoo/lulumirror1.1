#!/bin/sh
# Download only the pinned ready-made release; never contact the MIRROR.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
dir="$root/build/lemonademirror-v1.0-kernel-6.18.60"
base=https://github.com/ikiiftekhar2/lemonademirror/releases/download/v1.0-kernel-6.18.60
mkdir -p "$dir"
fetch() {
  name=$1
  expected=$2
  dest="$dir/$name"
  if [ ! -f "$dest" ]; then
    tmp=$(mktemp "$dir/.download.XXXXXXXX")
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    printf 'Command: curl -fL %s/%s -o %s\n' "$base" "$name" "$tmp"
    curl -fL "$base/$name" -o "$tmp"
    actual=$(shasum -a 256 "$tmp"); actual=${actual%% *}
    if [ "$actual" != "$expected" ]; then echo "SHA-256 mismatch: $name" >&2; exit 1; fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then echo "Destination appeared; refusing overwrite: $dest" >&2; exit 1; fi
    mv -n "$tmp" "$dest"
    trap - EXIT HUP INT TERM
  fi
  actual=$(shasum -a 256 "$dest"); actual=${actual%% *}
  if [ "$actual" != "$expected" ]; then echo "SHA-256 mismatch; refusing to overwrite: $dest" >&2; exit 1; fi
  printf 'Verified %s  %s\n' "$actual" "$dest"
}
fetch flash-mirror.sh c332eaf3ee2aec9b79ce0165eba80384b8d431eaf0e37ca074a642b00d9a0220
fetch flash-mirror.py 4723625e66e830296633e33409bac86b3b4ac9604404eecede728a1eb5a60502
fetch mirror-boot.img cfcb3476851c87da4ac895c9e3a72f1e6f3f95fa7bb28900be80c56fe3a7a1d2
fetch mirror-rootfs.img.xz c81fe11fbf5753c017fc1502b6a950e37212f8b16d49bf551f8fc83031c020c4
fetch SHA256SUMS d2af475465b546db289b3c4145e014c681c4969f5236610db8f7796d308eff4d
echo 'Release files verified against expected reference SHA sums'
