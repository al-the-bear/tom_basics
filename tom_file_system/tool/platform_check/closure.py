#!/usr/bin/env python3
"""Prints the directories, relative to ROOT, that PACKAGES reach through
`path:` dependencies (pubspec.yaml and pubspec_overrides.yaml, dev
dependencies included) — what a container needs to resolve them.

    closure.py ROOT PACKAGE_DIR...
"""
import os
import re
import sys

PATH_LINE = re.compile(r"^\s+path:\s*['\"]?([./][^'\"\s#]*)")


def path_deps(package):
    found = []
    for name in ("pubspec.yaml", "pubspec_overrides.yaml"):
        file = os.path.join(package, name)
        if not os.path.exists(file):
            continue
        with open(file, encoding="utf-8") as f:
            for line in f:
                if line.lstrip().startswith("#"):
                    continue
                m = PATH_LINE.match(line)
                if m:
                    found.append(os.path.normpath(os.path.join(package, m.group(1))))
    return found


def main():
    root = os.path.abspath(sys.argv[1])
    todo = [os.path.abspath(p) for p in sys.argv[2:]]
    seen = set()
    while todo:
        package = todo.pop()
        if package in seen or not os.path.exists(os.path.join(package, "pubspec.yaml")):
            continue
        seen.add(package)
        todo.extend(path_deps(package))
    for package in sorted(seen):
        print(os.path.relpath(package, root))


if __name__ == "__main__":
    main()
