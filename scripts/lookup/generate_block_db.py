"""Write the server's blocking database: the numbers to block under the given prefixes.

Usage: generate_block_db.py OUTDIR PREFIX [PREFIX ...] [--issued S8_CSV] [--limit N]

Each PREFIX is either a UK prefix such as 0843 or 087, or an international pattern in which
every x stands for any digit, such as +1900xxxxxxx (any country).

A UK prefix covers every number Ofcom has issued under it, read from Ofcom's s8.csv (--issued,
downloaded to that path if it doesn't exist yet):
the blocks listed as Allocated, Allocated(Closed Range) or Quarantined. Numbers Ofcom never
issued are left out, because UK networks must block calls that show them. Each UK number is
written in both forms, +448431234567 and 08431234567: the lookup matches exact text, UK
networks deliver numbers in both forms, and Apple doesn't document which form iOS sends.
An international pattern covers every number it matches, in that one form.

Every number becomes a key with the one-byte value 0x01, which Live Caller ID Lookup reads as
"block". Numbers absent from the database are not blocked. Output is one binary protobuf
KeywordDatabase per prefix (apple.swift_homomorphic_encryption.pir.v1), written in the wire
format directly so no generated protobuf code is needed. A prefix with nothing to block
writes no file. --limit N writes only the first N numbers of each prefix, for pipeline tests.
"""
import argparse
import csv
import urllib.request
from itertools import islice
from pathlib import Path

BLOCK = b"\x01"
NATIONAL_DIGITS = 10        # UK numbers have ten digits after the leading 0.
ISSUED = {"Allocated", "Allocated(Closed Range)", "Quarantined"}
S8_URL = ("https://www.ofcom.org.uk/siteassets/resources/documents/phones-telecoms-and-internet/"
          "information-for-industry/numbering/regular-updates/telephone-numbers/s8.csv")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("outdir", type=Path)
    parser.add_argument("prefixes", nargs="+")
    parser.add_argument("--issued", type=Path, help=f"Ofcom's s8.csv, from {S8_URL}")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    for prefix in args.prefixes:
        if is_uk(prefix):
            if args.issued is None:
                raise SystemExit("UK prefixes need --issued with Ofcom's s8.csv")
            if not args.issued.exists():
                download(S8_URL, args.issued)
            numbers = (n for start, end in issued_ranges(args.issued, prefix) for n in range(start, end))
            keywords = (form for n in islice(numbers, args.limit) for form in (f"+44{n}", f"0{n}"))
        else:
            keywords = islice(pattern_numbers(prefix), args.limit)
        write(args.outdir / f"{prefix}.binpb", keywords)


def download(url, path):
    # Ofcom's site refuses Python's default client name with 403 Forbidden.
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        path.write_bytes(response.read())


def is_uk(prefix):
    return prefix.startswith("0") and prefix.isdigit() and len(prefix) <= NATIONAL_DIGITS


def issued_ranges(s8_csv, prefix):
    """The national numbers Ofcom issued under a UK prefix, as merged [start, end) ranges.

    A number is its ten digits after the leading 0 as an integer, e.g. 8431234567.
    """
    if not prefix.startswith("08"):
        raise SystemExit(f"{prefix}: Ofcom's s8.csv lists only numbers starting 08")
    wanted = span(prefix[1:])
    ranges = []
    with open(s8_csv, encoding="utf-8-sig", newline="") as f:
        # Columns: number block, status, provider, number length, allocation date. The first
        # header cell reads "NMS Number Block: Number Block", so columns are read by position.
        for cells in list(csv.reader(f))[1:]:
            if len(cells) < 4 or cells[1] not in ISSUED or cells[3] != f"{NATIONAL_DIGITS} digit numbers":
                continue
            block = span(cells[0].replace(" ", ""))
            start, end = max(block[0], wanted[0]), min(block[1], wanted[1])
            if start < end:
                ranges.append((start, end))
    merged = []
    for start, end in sorted(ranges):       # Ofcom lists some 1,000-number blocks inside larger ones
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def span(digits):
    """The [start, end) range of national numbers that begin with these digits."""
    start = int(digits.ljust(NATIONAL_DIGITS, "0"))
    return start, start + 10 ** (NATIONAL_DIGITS - len(digits))


def pattern_numbers(prefix):
    """Every number an international pattern covers, e.g. +1900xxxxxxx."""
    fixed = prefix.rstrip("x")
    if not (prefix.startswith("+") and fixed[1:].isdigit() and len(prefix) > len(fixed) and len(prefix) <= 16):
        raise SystemExit(f"{prefix}: expected a UK prefix such as 0843 or a pattern such as +1900xxxxxxx")
    free = len(prefix) - len(fixed)
    return (f"{fixed}{n:0{free}d}" for n in range(10 ** free))


def write(path, keywords):
    count = 0
    with path.open("wb") as out:
        for keyword in keywords:
            out.write(row(keyword.encode()))
            count += 1
    if count:
        print(f"{path}: {count} keys")
    else:
        path.unlink()
        print(f"{path.stem}: nothing to block (Ofcom has issued no numbers there), skipped")


def row(keyword):
    # KeywordDatabaseRow { bytes keyword = 1; bytes value = 2; } wrapped as KeywordDatabase.rows = 1.
    body = b"\x0a" + varint(len(keyword)) + keyword + b"\x12" + varint(len(BLOCK)) + BLOCK
    return b"\x0a" + varint(len(body)) + body


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


if __name__ == "__main__":
    main()
