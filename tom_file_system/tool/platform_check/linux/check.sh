#!/bin/sh
# Inside the container. /src is the workspace container root (read-only);
# the packages are copied out of it so this run's build state never reaches
# the host's checkout.
set -e
mkdir -p /work
cd /src
# Only the packages tom_file_system reaches (closure.py, run on the host).
tar -cf - --exclude=build --exclude=.dart_tool --exclude=testlog \
  --exclude=node_modules --exclude=.git \
  $(cat /check/closure.txt) | tar -xf - -C /work

echo "== kernel check (tool/platform_check/check.dart)"
dart /check/check.dill /tmp/kernel-check
echo "trash after the kernel check:"
find "$HOME/.local/share/Trash" -maxdepth 2 | sort

echo "== tom_file_system: dart test"
cd /work/tom_ai/basics/tom_file_system
dart pub get >/dev/null
dart test --reporter compact 2>&1 | tail -15
