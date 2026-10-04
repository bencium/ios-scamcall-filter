"""Write the server's blocking database: every number under the given UK prefixes.

Usage: generate_block_db.py OUTDIR PREFIX [PREFIX ...] [--limit N]

Each PREFIX is either a UK dialling prefix such as 0843, or an international pattern in
which every x stands for any digit, such as +1900xxxxxxx (any country). A UK prefix is
shorthand for the pattern of its ten-digit numbers: 0843 means +44843xxxxxxx. Every number
the pattern covers becomes a key with the one-byte value 0x01, which Live Caller ID Lookup
reads as "block". Numbers that are absent from the database are not blocked, so only blocked
numbers are written. Output is one binary protobuf KeywordDatabase per prefix
(apple.swift_homomorphic_encryption.pir.v1), written in the wire format directly so
no generated protobuf code is needed. --limit N writes only the first N numbers of
each prefix, for pipeline tests.
"""
import argparse
from pathlib import Path

BLOCK = b"\x01"
NUMBER_DIGITS = 10          # UK numbers have ten digits after the leading 0.

def varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)

def row(keyword):
    # KeywordDatabaseRow { bytes keyword = 1; bytes value = 2; } wrapped as KeywordDatabase.rows = 1.
    body = b"\x0a" + varint(len(keyword)) + keyword + b"\x12" + varint(len(BLOCK)) + BLOCK
    return b"\x0a" + varint(len(body)) + body

def pattern(prefix):
    """The international pattern a prefix stands for, e.g. 0843 -> +44843xxxxxxx."""
    if prefix.startswith("0") and prefix.isdigit() and len(prefix) <= NUMBER_DIGITS:
        return "+44" + prefix[1:] + "x" * (NUMBER_DIGITS + 1 - len(prefix))
    fixed = prefix.rstrip("x")
    if prefix.startswith("+") and fixed[1:].isdigit() and len(prefix) > len(fixed) and len(prefix) <= 16:
        return prefix
    raise SystemExit(f"{prefix}: expected a UK prefix such as 0843 or a pattern such as +1900xxxxxxx")


def write_prefix(outdir, prefix, limit):
    full = pattern(prefix)
    international = full.rstrip("x")
    remaining = len(full) - len(international)
    count = 10 ** remaining if limit is None else min(limit, 10 ** remaining)
    path = outdir / f"{prefix}.binpb"
    with path.open("wb") as out:
        for n in range(count):
            out.write(row(f"{international}{n:0{remaining}d}".encode()))
    print(f"{path}: {count} numbers")

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("outdir", type=Path)
    parser.add_argument("prefixes", nargs="+")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    for prefix in args.prefixes:
        write_prefix(args.outdir, prefix, args.limit)

if __name__ == "__main__":
    main()
