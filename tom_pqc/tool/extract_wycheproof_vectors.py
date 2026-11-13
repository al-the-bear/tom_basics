#!/usr/bin/env python3
# Copyright (c) 2026 Peter Nicolai Alexis Kyaw
# SPDX-License-Identifier: BSD-3-Clause
"""Copies the Wycheproof ML-KEM-768 and ML-DSA-65 vectors into
test/vectors/wycheproof/.

    git clone https://github.com/C2SP/wycheproof <dir>
    git -C <dir> checkout <commit>
    tool/extract_wycheproof_vectors.py <dir>

The files are copied unchanged, with Wycheproof's LICENSE (Apache-2.0), and
SOURCE.json records the commit and each file's SHA-256, which
test/wycheproof_ml_kem_768_test.dart and test/wycheproof_ml_dsa_65_test.dart
check. Run by hand when the vectors are
to be refreshed.
"""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

FILES = [
    'mlkem_768_keygen_seed_test.json',
    'mlkem_768_encaps_test.json',
    'mlkem_768_test.json',
    'mlkem_768_semi_expanded_decaps_test.json',
    'mldsa_65_sign_seed_test.json',
    'mldsa_65_sign_noseed_test.json',
    'mldsa_65_verify_test.json',
]


def main(clone: str) -> None:
    root = pathlib.Path(clone)
    commit = subprocess.run(['git', '-C', clone, 'rev-parse', 'HEAD'],
                            check=True, capture_output=True, text=True).stdout.strip()
    target = pathlib.Path(__file__).resolve().parent.parent / 'test' / 'vectors' / 'wycheproof'
    target.mkdir(parents=True, exist_ok=True)
    digests = {}
    for name in FILES:
        source = root / 'testvectors_v1' / name
        shutil.copyfile(source, target / name)
        digests[name] = hashlib.sha256(source.read_bytes()).hexdigest()
    shutil.copyfile(root / 'LICENSE', target / 'LICENSE')
    (target / 'SOURCE.json').write_text(json.dumps({
        'source': 'https://github.com/C2SP/wycheproof',
        'commit': commit,
        'directory': 'testvectors_v1',
        'licence': 'Apache-2.0 (LICENSE in this folder)',
        'sha256': digests,
    }, indent=1) + '\n')
    print(f'{target}: {", ".join(FILES)} at {commit}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
