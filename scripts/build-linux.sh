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
swift build -c release --product bubitunes
swift test -c release
binary_dir="$(swift build -c release --show-bin-path)"

mkdir -p dist
stage="$(mktemp -d "$PWD/dist/.stage-linux-XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
cp "$binary_dir/bubitunes" "$stage/"
cp -R BubiTunesRhythm README.md LICENSE FMGEN-NOTICE.txt "$stage/"
"$stage/bubitunes" --help
tar -czf "$stage/package.tar.gz" -C "$stage" bubitunes BubiTunesRhythm README.md LICENSE FMGEN-NOTICE.txt
archive="$PWD/dist/BubiTunes-linux-$arch.tar.gz"
mv -f "$stage/package.tar.gz" "$archive"
echo "Package: $archive"
