#!/bin/sh
# Offline output only; never transfers or loads a module on the MIRROR.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
repo="$root/vendor/lemonademirror"
source="$root/build/linux-6.18.60.tar.xz"
expected=3c2f44ef6acc021a7ad444d9a2e6ec1ef488ff09368793d0004a6080f69d621e
revision=900b4ca4c0f7152be96108bb7f4a2d15bd10c1bb
variant=${CAMERA_BUILD_VARIANT:-timing}
case "$variant" in timing|polarity|ov5645) ;; *) echo 'Unknown camera build variant.' >&2; exit 2 ;; esac
[ "$(git -C "$repo" rev-parse HEAD)" = "$revision" ] || { echo 'Unexpected LemonadeMirror revision.' >&2; exit 1; }
[ -z "$(git -C "$repo" status --porcelain)" ] || { echo 'LemonadeMirror checkout is modified; refusing to build from changed inputs.' >&2; exit 1; }
mkdir -p "$root/build"
if [ ! -f "$source" ]; then
  temp=$(mktemp "$root/build/linux-download.XXXXXXXX")
  trap 'rm -f "$temp"' EXIT HUP INT TERM
  echo "Command: curl -fL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.60.tar.xz -o $temp"
  curl -fL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.60.tar.xz -o "$temp"
  actual=$(sha256sum "$temp"); actual=${actual%% *}
  [ "$actual" = "$expected" ] || { echo 'Linux source hash mismatch.' >&2; exit 1; }
  [ ! -e "$source" ] && [ ! -L "$source" ] || { echo 'Source appeared; refusing overwrite.' >&2; exit 1; }
  mv -n "$temp" "$source"
  trap - EXIT HUP INT TERM
fi
actual=$(sha256sum "$source"); actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo 'Linux source hash mismatch.' >&2; exit 1; }
out=$(mktemp -d "$root/build/camera-$variant.XXXXXXXX")
image=mirror-camera-build:linux-6.18.60
printf 'Command: docker build -f "%s/scripts/camera-kernel.Dockerfile" -t "%s" "%s/scripts"\n' "$root" "$image" "$root"
docker build -f "$root/scripts/camera-kernel.Dockerfile" -t "$image" "$root/scripts"
printf 'Command: docker run --rm --network none -v "%s:/workspace" -w /workspace "%s" sh scripts/build-camera-timing-container.sh "%s" "%s"\n' "$root" "$image" "${out#"$root"/}" "$variant"
docker run --rm --network none -v "$root:/workspace" -w /workspace "$image" sh scripts/build-camera-timing-container.sh "${out#"$root"/}" "$variant"
echo "Output directory: $out"
echo 'Local build only. The module is untested; no device was contacted.'
