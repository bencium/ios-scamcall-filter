"""Prove the server database holds exactly the intended numbers: every number of every
prefix once, no duplicates, nothing else, every value "block".

Usage: verify_coverage.py MERGED_DIR PREFIX [PREFIX ...]
       (MERGED_DIR is OUTDIR/merged from build_db.sh: the exact input to PIR processing)

Every row written by generate_block_db.py is 20 bytes: protobuf framing, the 13-character
key "+44" plus ten digits, and the one-byte value 0x01. Any other shape fails the check.
"""
import sys
from pathlib import Path
import numpy as np

ROW = 20
HEAD = np.frombuffer(b"\x0a\x12\x0a\x0d+44", dtype=np.uint8)
TAIL = np.frombuffer(b"\x12\x01\x01", dtype=np.uint8)
PER_PREFIX = 10_000_000

def main():
    merged, prefixes = Path(sys.argv[1]), sys.argv[2:]
    wanted = {int(p[1:4]): p for p in prefixes}        # "0843" -> 843
    if any(len(p) != 4 or not p.startswith("0") for p in prefixes):
        sys.exit("expects four-digit prefixes such as 0843")
    seen = {code: np.zeros(PER_PREFIX, dtype=np.uint8) for code in wanted}
    rows = 0
    for path in sorted(merged.glob("block-shard-*.binpb")):
        data = np.fromfile(path, dtype=np.uint8)
        if data.size % ROW:
            sys.exit(f"{path.name}: size is not a whole number of rows")
        table = data.reshape(-1, ROW)
        if not ((table[:, :7] == HEAD).all() and (table[:, 17:] == TAIL).all()):
            sys.exit(f"{path.name}: a row has unexpected framing, key format or value")
        digits = table[:, 7:17].astype(np.int64) - 48
        if ((digits < 0) | (digits > 9)).any():
            sys.exit(f"{path.name}: a key contains a non-digit")
        code = digits[:, 0] * 100 + digits[:, 1] * 10 + digits[:, 2]
        suffix = digits[:, 3:] @ (10 ** np.arange(6, -1, -1, dtype=np.int64))
        outside = ~np.isin(code, list(wanted))
        if outside.any():
            sys.exit(f"{path.name}: number outside the prefixes, e.g. 0{code[outside][0]}{suffix[outside][0]:07d}")
        for c in wanted:
            np.add.at(seen[c], suffix[code == c], 1)
        rows += len(table)
    ok = True
    for c, prefix in wanted.items():
        missing = int((seen[c] == 0).sum())
        duplicated = int((seen[c] > 1).sum())
        print(f"{prefix}: {int((seen[c] == 1).sum()):,} present once, {missing:,} missing, {duplicated:,} duplicated")
        ok = ok and missing == 0 and duplicated == 0
    print(f"rows: {rows:,} (expected {PER_PREFIX * len(wanted):,})")
    if not ok or rows != PER_PREFIX * len(wanted):
        sys.exit("COVERAGE FAILED")
    print("COVERAGE EXACT: every number of every prefix once, nothing else, all values = block")

if __name__ == "__main__":
    main()
