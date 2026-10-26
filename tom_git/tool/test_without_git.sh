#!/usr/bin/env bash
# Runs this package's suite with no git binary reachable: PATH is replaced by
# one directory holding a link to every executable of the real PATH except
# those named git*. GIT-NOBIN-1 then asserts that git cannot be started, so a
# green run proves the library needed none.
#
# Live suites run too when TOM_LIVE is set (with GITHUB_TEST_TOKEN for GitHub,
# and docker for Gitea).
#
#   tool/test_without_git.sh [dart test arguments]
set -euo pipefail
cd "$(dirname "$0")/.."

dart_bin="$(command -v dart)"
# Flutter's `dart` is a wrapper script that may call git; the SDK's own binary
# does not.
real_dart="$(cd "$(dirname "$(readlink -f "$dart_bin")")" && pwd)/cache/dart-sdk/bin/dart"
[ -x "$real_dart" ] || real_dart="$dart_bin"

shim="$(pwd)/.dart_tool/no_git_path"
rm -rf "$shim"
mkdir -p "$shim"
IFS=: read -r -a dirs <<< "$PATH"
for dir in "${dirs[@]}"; do
  [ -d "$dir" ] || continue
  for exe in "$dir"/*; do
    name="$(basename "$exe")"
    case "$name" in git*) continue ;; esac
    [ -x "$exe" ] && [ ! -e "$shim/$name" ] && ln -s "$exe" "$shim/$name"
  done
done

PATH="$shim" TOM_GIT_NO_BINARY=1 "$real_dart" test "$@"
