#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Run this script on macOS.' >&2; exit 1; }
arch="$(uname -m)"
[[ "$arch" != x86_64 ]] || arch=x64

swift --version
swift build -c release --product bubitunes
swift test -c release
binary_dir="$(swift build -c release --show-bin-path)"

mkdir -p dist
stage="$(mktemp -d "$PWD/dist/.stage-macos-XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
cp "$binary_dir/bubitunes" "$stage/"
cp README.md LICENSE FMGEN-NOTICE.txt "$stage/"
codesign --force --sign - "$stage/bubitunes"
codesign --verify --strict "$stage/bubitunes"
"$stage/bubitunes" --help
tar -czf "$stage/package.tar.gz" -C "$stage" bubitunes README.md LICENSE FMGEN-NOTICE.txt
archive="$PWD/dist/BubiTunes-macos-$arch.tar.gz"
mv -f "$stage/package.tar.gz" "$archive"
echo "Package: $archive"
