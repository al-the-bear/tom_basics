#!/usr/bin/env python3
# Copyright (c) 2026 Peter Nicolai Alexis Kyaw
# SPDX-License-Identifier: BSD-3-Clause
"""Copies the vectors of the hybrids into test/vectors/.

    tool/extract_hybrid_vectors.py --xwing <clone> --composite <clone> --cctv <clone>

- xwing/: test-vectors.json of draft-connolly-cfrg-xwing-kem
  (https://github.com/dconnolly/draft-connolly-cfrg-xwing-kem, spec/), the
  X-Wing = MLKEM768-X25519 known answers.
- rfc10073/: the id-MLDSA65-Ed25519-SHA512 entry of RFC 10073's test vectors
  (https://github.com/lamps-wg/draft-composite-sigs, src/testvectors.json),
  with the message and context they sign.
- age/: every hybrid file of the age testkit
  (https://github.com/C2SP/CCTV, age/testdata/*hybrid*).

Each folder gets a SOURCE.json with the repository, commit and SHA-256 of every
file; the files are copied unchanged, except the RFC 10073 extract, which keeps
the one entry of the composite tom_pqc implements. Run by hand when the vectors
are to be refreshed.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess

VECTORS = pathlib.Path(__file__).resolve().parent.parent / 'test' / 'vectors'


def commit_of(clone: pathlib.Path) -> str:
    return subprocess.run(['git', '-C', str(clone), 'rev-parse', 'HEAD'],
                          check=True, capture_output=True, text=True).stdout.strip()


def write_source(folder: pathlib.Path, source: str, commit: str, licence: str) -> None:
    digests = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted(folder.iterdir()) if p.name != 'SOURCE.json'}
    (folder / 'SOURCE.json').write_text(json.dumps({
        'source': source, 'commit': commit, 'licence': licence, 'sha256': digests,
    }, indent=1) + '\n')
    print(f'{folder}: {len(digests)} files at {commit}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--xwing', required=True, type=pathlib.Path)
    parser.add_argument('--composite', required=True, type=pathlib.Path)
    parser.add_argument('--cctv', required=True, type=pathlib.Path)
    args = parser.parse_args()

    xwing = VECTORS / 'xwing'
    xwing.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.xwing / 'spec' / 'test-vectors.json', xwing / 'test-vectors.json')
    write_source(xwing, 'https://github.com/dconnolly/draft-connolly-cfrg-xwing-kem',
                 commit_of(args.xwing),
                 'IETF Trust; code components of Internet-Drafts under the '
                 'Simplified/Revised BSD License (BCP 78, the TLP)')

    composite = VECTORS / 'rfc10073'
    composite.mkdir(parents=True, exist_ok=True)
    data = json.loads((args.composite / 'src' / 'testvectors.json').read_text())
    entry = [t for t in data['tests'] if t['tcId'] == 'id-MLDSA65-Ed25519-SHA512']
    assert len(entry) == 1, entry
    (composite / 'mldsa65_ed25519.json').write_text(json.dumps({
        'note': 'The id-MLDSA65-Ed25519-SHA512 entry of RFC 10073 Appendix E '
                '(src/testvectors.json), with the message m and context ctx it '
                'signs; base64 as in the source. s signs m with an empty '
                'context, sWithContext signs m with ctx.',
        'm': data['m'], 'ctx': data['ctx'], 'test': entry[0],
    }, indent=1) + '\n')
    write_source(composite, 'https://github.com/lamps-wg/draft-composite-sigs',
                 commit_of(args.composite),
                 'IETF Trust; code components of RFCs under the Revised BSD '
                 'License (BCP 78, the TLP)')

    age = VECTORS / 'age'
    age.mkdir(parents=True, exist_ok=True)
    for path in sorted((args.cctv / 'age' / 'testdata').glob('*hybrid*')):
        shutil.copyfile(path, age / path.name)
    write_source(age, 'https://github.com/C2SP/CCTV (age/testdata)',
                 commit_of(args.cctv), '0BSD OR CC0-1.0 OR Unlicense')


if __name__ == '__main__':
    main()
