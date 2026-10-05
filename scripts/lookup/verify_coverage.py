"""Prove the server database holds exactly the intended numbers: every number Ofcom lists
(issued or open for issuing) under the given prefixes, once in each form (+448431234567 and 08431234567), nothing else,
every value "block".

Usage: verify_coverage.py OUTDIR PREFIX [PREFIX ...]
       OUTDIR is build_db.sh's output folder. The check reads OUTDIR/merged, the exact input
       to PIR processing, and OUTDIR/s8.csv, the Ofcom list the build used.

generate_block_db.py writes two row shapes, each with protobuf framing and the one-byte value
0x01: 20 bytes for "+44" plus ten digits, 18 bytes for "0" plus ten digits. A row of any other
shape or value fails the check.
"""
import re
import sys
from pathlib import Path

import numpy as np

from generate_block_db import listed_ranges

FORMS = {
    "+44": (re.compile(rb"\x0a\x12\x0a\x0d\+44([0-9]{10})\x12\x01\x01"), 20),
    "0": (re.compile(rb"\x0a\x10\x0a\x0b0([0-9]{10})\x12\x01\x01"), 18),
}
TEN_DIGITS = 10 ** np.arange(9, -1, -1, dtype=np.int64)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    outdir, prefixes = Path(sys.argv[1]), sys.argv[2:]
    ranges = [r for prefix in prefixes for r in listed_ranges(outdir / "s8.csv", prefix)]
    expected = np.unique(np.concatenate([np.arange(start, end, dtype=np.int64) for start, end in ranges]))
    ok = True
    for form, numbers in read_merged(outdir / "merged").items():
        ok = report(form, numbers, expected) and ok
    if not ok:
        sys.exit("COVERAGE FAILED")
    print(f"COVERAGE EXACT: all {len(expected):,} listed numbers, once in each form, nothing else, all values = block")


def read_merged(merged):
    """Every number in the merged shard files, per form, after checking every byte is part of a valid row."""
    found = {form: [] for form in FORMS}
    paths = sorted(merged.glob("block-shard-*.binpb"))
    if not paths:
        sys.exit(f"No merged shard files in {merged}. Did build_db.sh finish?")
    for path in paths:
        data = path.read_bytes()
        covered = 0
        for form, (row, size) in FORMS.items():
            digits = row.findall(data)
            covered += len(digits) * size
            table = np.frombuffer(b"".join(digits), dtype=np.uint8).reshape(-1, 10).astype(np.int64) - 48
            found[form].append(table @ TEN_DIGITS)
        # Framing bytes never occur inside a row, so matches can't overlap: full byte cover means no stray rows.
        if covered != len(data):
            sys.exit(f"{path.name}: a row has unexpected framing, key format or value")
    return {form: np.sort(np.concatenate(parts)) for form, parts in found.items()}


def report(form, numbers, expected):
    duplicated = len(numbers) - len(np.unique(numbers))
    missing = np.setdiff1d(expected, numbers)
    unlisted = np.setdiff1d(numbers, expected)
    print(f'"{form}..." form: {len(numbers):,} keys, {len(missing):,} missing, {duplicated:,} duplicated, '
          f"{len(unlisted):,} not in Ofcom's list")
    for label, sample in (("missing", missing), ("not in Ofcom's list", unlisted)):
        if len(sample):
            print(f"   e.g. {label}: 0{sample[0]}")
    return not (len(missing) or duplicated or len(unlisted))


if __name__ == "__main__":
    main()
