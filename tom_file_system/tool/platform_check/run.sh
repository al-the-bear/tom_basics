#!/bin/bash
# The local file system's platform-specific parts, run on Linux and Windows
# from this machine — no other host involved:
#
#   linux    The Dart VM in a Linux container: the kernel check (atomic
#            writes, the watch one directory at a time, the trash) and this
#            package's suite.
#   windows  The kernel check on the Windows Dart VM under Wine: atomic
#            writes, the Recycle Bin call, and whether the watch reports.
#
#   tool/platform_check/run.sh            # both
#   tool/platform_check/run.sh linux      # one
#
# Started by hand, like every check in this repository. Needs Docker and a
# Dart SDK, which compiles the kernel file both halves run and names the SDK
# the containers install (a kernel file runs only on the Dart version that
# wrote it). The Windows image is amd64 and slow under emulation on an arm64
# host.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(cd "$HERE/../.." && pwd)"
ROOT="$(cd "$PKG/../../.." && pwd)"
OUT="$PKG/testlog/platform_check"
mkdir -p "$OUT"

DART_VERSION="$(dart --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p')"
echo "Dart $DART_VERSION"
(cd "$PKG" && dart compile kernel tool/platform_check/check.dart -o "$OUT/check.dill" >/dev/null)
python3 "$HERE/closure.py" "$ROOT" "$PKG" > "$OUT/closure.txt"

for half in ${@:-linux windows}; do
  case "$half" in
    linux)
      docker build -q --build-arg DART_VERSION="$DART_VERSION" \
        -t tom-file-system-platform-linux "$HERE/linux" >/dev/null
      echo "== linux"
      docker run --rm -v "$ROOT":/src:ro -v "$OUT":/check:ro \
        -v "$HERE/linux":/platform:ro tom-file-system-platform-linux \
        sh /platform/check.sh 2>&1 | tee "$OUT/linux.log"
      ;;
    windows)
      docker build -q --platform linux/amd64 --build-arg DART_VERSION="$DART_VERSION" \
        -t tom-file-system-platform-windows "$HERE/windows" >/dev/null
      echo "== windows (Wine)"
      docker run --rm --platform linux/amd64 -v "$OUT":/check:ro \
        -v "$HERE/windows":/platform:ro tom-file-system-platform-windows \
        sh /platform/check.sh 2>&1 | tee "$OUT/windows.log"
      ;;
    *) echo "unknown half: $half" >&2; exit 2 ;;
  esac
done
