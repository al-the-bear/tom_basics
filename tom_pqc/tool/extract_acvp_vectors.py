#!/usr/bin/env python3
# Copyright (c) 2026 Peter Nicolai Alexis Kyaw
# SPDX-License-Identifier: BSD-3-Clause
"""Writes test/vectors/acvp_ml_kem_768.json from a clone of NIST's ACVP-Server.

    git clone https://github.com/usnistgov/ACVP-Server <dir>
    git -C <dir> checkout <commit>
    tool/extract_acvp_vectors.py <dir>

Takes the ML-KEM-768 groups of the keyGen and encapDecap internal projections
(inputs and expected outputs together), every test case unchanged, and records
the commit they came from. Run by hand when the vectors are to be refreshed.
"""
import json
import pathlib
import subprocess
import sys

KEYGEN = 'gen-val/json-files/ML-KEM-keyGen-FIPS203/internalProjection.json'
ENCAP_DECAP = 'gen-val/json-files/ML-KEM-encapDecap-FIPS203/internalProjection.json'
FIELDS = {
    'encapsulation': ['tcId', 'ek', 'dk', 'm', 'c', 'k'],
    'decapsulation': ['tcId', 'ek', 'dk', 'c', 'k', 'reason'],
    'encapsulationKeyCheck': ['tcId', 'ek', 'testPassed', 'reason'],
    'decapsulationKeyCheck': ['tcId', 'dk', 'testPassed', 'reason'],
}


def pick(group, keys):
    return [{k: t[k] for k in keys if k in t} for t in group['tests']]


def main(clone: str) -> None:
    root = pathlib.Path(clone)
    commit = subprocess.run(['git', '-C', clone, 'rev-parse', 'HEAD'],
                            check=True, capture_output=True, text=True).stdout.strip()
    out = {
        'source': 'https://github.com/usnistgov/ACVP-Server',
        'commit': commit,
        'files': [KEYGEN, ENCAP_DECAP],
        'parameterSet': 'ML-KEM-768',
        'note': 'The ML-KEM-768 test groups of the two files, every test case '
                'unchanged; fields the tests do not read (deferred) left out. '
                'Regenerate with tool/extract_acvp_vectors.py.',
    }
    for group in json.loads((root / KEYGEN).read_text())['testGroups']:
        if group['parameterSet'] == 'ML-KEM-768':
            out['keyGen'] = pick(group, ['tcId', 'd', 'z', 'ek', 'dk'])
    for group in json.loads((root / ENCAP_DECAP).read_text())['testGroups']:
        if group['parameterSet'] == 'ML-KEM-768':
            out[group['function']] = pick(group, FIELDS[group['function']])
    target = pathlib.Path(__file__).resolve().parent.parent / 'test' / 'vectors' / 'acvp_ml_kem_768.json'
    target.write_text(json.dumps(out, indent=1))
    print(f'{target}: ' + ', '.join(f'{k} {len(out[k])}' for k in ['keyGen', *FIELDS]))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
