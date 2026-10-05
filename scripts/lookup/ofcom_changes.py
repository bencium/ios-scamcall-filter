"""Tell whether Ofcom's numbering list has changed since the live database was built.

  python3 scripts/lookup/ofcom_changes.py                         compare with Ofcom's current list
  python3 scripts/lookup/ofcom_changes.py --save S8_CSV [PREFIX ...]   record what a build used

listed-ranges.txt (next to this script) holds the number ranges the live database blocks and
the prefixes it was built for. When Ofcom has opened, issued or withdrawn blocks since, this
prints what changed and exits 1. Then rebuild with build_db.sh, upload, and run --save with
that build's s8.csv. Without new prefixes, --save keeps the recorded ones.
"""
import argparse
import sys
import tempfile
from pathlib import Path

from generate_block_db import S8_URL, download, listed_ranges

SNAPSHOT = Path(__file__).with_name("listed-ranges.txt")
THOUSAND = 1000     # every Ofcom block in these ranges is a whole number of 1,000-number groups


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--save", type=Path, metavar="S8_CSV")
    parser.add_argument("prefixes", nargs="*")
    args = parser.parse_args()
    if args.save:
        prefixes = args.prefixes or read_snapshot()[0]
        save_snapshot(prefixes, groups(args.save, prefixes))
        return
    prefixes, recorded = read_snapshot()
    with tempfile.TemporaryDirectory() as work:
        current_list = Path(work) / "s8.csv"
        download(S8_URL, current_list)
        current = groups(current_list, prefixes)
    added, removed = current - recorded, recorded - current
    if not added and not removed:
        print(f"No change: Ofcom's list matches the live database ({len(recorded) * THOUSAND:,} numbers).")
        return
    for label, changed in (("Now listed, not yet blocked", added), ("No longer listed, still blocked", removed)):
        if changed:
            print(f"{label}: {len(changed) * THOUSAND:,} numbers")
            for start, end in as_ranges(changed):
                print(f"   {spell(start)} to {spell(end - 1)}")
    sys.exit("Ofcom's list has changed. Rebuild and upload the database, then run --save.")


def groups(s8_csv, prefixes):
    """The 1,000-number groups listed under the prefixes, as a set of group numbers."""
    found = set()
    for prefix in prefixes:
        for start, end in listed_ranges(s8_csv, prefix):
            if start % THOUSAND or end % THOUSAND:
                sys.exit(f"{prefix}: a block that isn't whole 1,000-number groups; Ofcom's format changed")
            found.update(range(start // THOUSAND, end // THOUSAND))
    return found


def as_ranges(group_set):
    """Consecutive groups merged into [start, end) number ranges."""
    ranges = []
    for group in sorted(group_set):
        if ranges and ranges[-1][1] == group * THOUSAND:
            ranges[-1][1] += THOUSAND
        else:
            ranges.append([group * THOUSAND, (group + 1) * THOUSAND])
    return ranges


def spell(number):
    return f"0{number}"


def read_snapshot():
    lines = SNAPSHOT.read_text().splitlines()
    prefixes = next(line.split(":", 1)[1].split() for line in lines if line.startswith("# prefixes:"))
    found = set()
    for line in lines:
        if line and not line.startswith("#"):
            first, last = (int(part) for part in line.split("-"))
            found.update(range(first // THOUSAND, last // THOUSAND + 1))
    return prefixes, found


def save_snapshot(prefixes, group_set):
    ranges = as_ranges(group_set)
    SNAPSHOT.write_text("\n".join([
        "# Numbers the live lookup database blocks, from Ofcom's s8.csv. Written by ofcom_changes.py --save.",
        f"# prefixes: {' '.join(prefixes)}",
        *(f"{spell(start)}-{spell(end - 1)}" for start, end in ranges),
        ""]))
    print(f"Saved {len(ranges)} ranges, {len(group_set) * THOUSAND:,} numbers, to {SNAPSHOT.name}")


if __name__ == "__main__":
    main()
