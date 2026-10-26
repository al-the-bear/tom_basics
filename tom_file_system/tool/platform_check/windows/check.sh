#!/bin/sh
# Inside the container: the kernel check on the Windows Dart VM under Wine,
# then the Recycle Bin from the Linux side — Wine's shell32 keeps it in the
# Linux user's freedesktop.org trash.
set -e
wineboot -i >/dev/null 2>&1 || true
mkdir -p /tmp/pc
wine /opt/dart-sdk/bin/dart.exe 'Z:\check\check.dill' 'Z:\tmp\pc' 2>&1 \
  | grep -v NativeSymbolResolver || true
echo "Recycle Bin, as Wine keeps it:"
find "$HOME/.local/share/Trash" -maxdepth 2 2>/dev/null | sort
