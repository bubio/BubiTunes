#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Linux ]] || { echo 'Run this script on Linux.' >&2; exit 1; }
arch="$(uname -m)"
case "$arch" in
  x86_64) arch=x64 ;;
  aarch64) arch=arm64 ;;
esac

swift --version
swift test -c release
# Keep the release archive runnable on a Linux host which does not have the
# Swift toolchain installed. Without this, the executable depends on
# libswiftCore.so (and the rest of the Swift runtime) from the CI toolchain.
# Build after the tests: swift test also rebuilds bubitunes with dynamic linking.
swift build -c release --product bubitunes -Xswiftc -static-stdlib
binary_dir="$(swift build -c release --show-bin-path -Xswiftc -static-stdlib)"

mkdir -p dist
stage="$(mktemp -d "$PWD/dist/.stage-linux-XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
cp "$binary_dir/bubitunes" "$stage/"
mkdir "$stage/BubiTunesRhythm"
cp BubiTunesRhythm/*.wav "$stage/BubiTunesRhythm/"
cp README.md LICENSE FMGEN-NOTICE.txt "$stage/"
"$stage/bubitunes" --help
if ldd "$stage/bubitunes" | grep -q 'libswift[^[:space:]]*\.so'; then
  echo 'The packaged binary still depends on the Swift shared runtime.' >&2
  exit 1
fi
tar -czf "$stage/package.tar.gz" -C "$stage" bubitunes BubiTunesRhythm README.md LICENSE FMGEN-NOTICE.txt
archive="$PWD/dist/BubiTunes-linux-$arch.tar.gz"
mv -f "$stage/package.tar.gz" "$archive"
echo "Package: $archive"
