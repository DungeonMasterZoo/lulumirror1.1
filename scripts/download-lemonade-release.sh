#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
dir="$root/build/lemonademirror-v1.0-kernel-6.18.60"
base=https://github.com/ikiiftekhar2/lemonademirror/releases/download/v1.0-kernel-6.18.60
mkdir -p "$dir"

sums_hash='d2af475465b546db289b3c4145e014c681c4969f5236610db8f7796d308eff4d'
printf 'Command: curl -fL %s/SHA256SUMS -o %s/SHA256SUMS\n' "$base" "$dir"
curl -fL "${base}/SHA256SUMS" -o "${dir}/SHA256SUMS"
[ "$(sha256sum "${dir}/SHA256SUMS" | sed -e 's: \+.*::')" = $sums_hash ] || { echo 'SHA-256 mismatch on sums file'; exit 1; }

for _file in flash-mirror.sh flash-mirror.py mirror-boot.img mirror-rootfs.img.xz; do
	printf 'Command: curl -fL %s/%s -o %s\n' "$base" "$_file" "${dir}/${_file}"
	curl -fL "${base}/${_file}" -o "${dir}/${_file}"
done

cd "$dir"
sha256sum -c "${dir}/SHA256SUMS" --ignore-missing || { echo 'SHA-256 mismatch'; exit 1; }
echo 'Release files verified against expected reference SHA sums'
