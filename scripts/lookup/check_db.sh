#!/bin/sh
# Check a built lookup database the way the phone would use it, and print a table of which
# number forms are blocked for each prefix.
#
#   scripts/lookup/check_db.sh DBDIR PREFIX [PREFIX ...]
#
# Starts the patched PIRService on DBDIR (port 8095), then asks it, by real encrypted queries:
#   - about listed numbers (the first and last, plus RANDOM_PER_PREFIX random ones) in
#     five forms. "+44..." and "0..." must be blocked; the database holds only those two, so
#     "44...", "0044..." and the bare number without 0 must stay allowed.
#   - about numbers that must stay allowed: numbers next to the listed ranges that Ofcom doesn't list,
#     0845 (blocked on the phone instead), a mobile and 0800.
# Listed numbers (issued or open for issuing) come from DBDIR/../s8.csv, the Ofcom list the build used (or set S8).
# Exits non-zero on any wrong answer.
#
# Against a deployed server:  SERVER_URL=https://... TOKEN=... S8=/tmp/lookup-db/s8.csv check_db.sh - PREFIX ...
# PIRSERVICE: patched server binary (default: server/upstream/.build/release/PIRService, see server/dev.sh).
set -eu
DB=$1; shift; PREFIXES=$*
HERE=$(cd "$(dirname "$0")" && pwd)
PIRSERVICE=${PIRSERVICE:-$HERE/../../server/upstream/.build/release/PIRService}
CHECK="$HERE/checker/.build/release/CheckLookup"
USECASE=uk.co.bencium.ScamBlocker.Lookup.block
S8=${S8:-$(dirname "$DB")/s8.csv}
[ -f "$S8" ] || { echo "No Ofcom list at $S8. Set S8 to the s8.csv the database was built from."; exit 1; }
WORK=$(mktemp -d)

SERVER=""
trap 'rm -rf "$WORK"; [ -z "$SERVER" ] || kill $SERVER 2>/dev/null' EXIT
if [ -z "${SERVER_URL:-}" ]; then
  TOKEN=${TOKEN:-$(grep -o '"tokens": \["[^"]*"' "$DB/service-config.json" | sed 's/.*\["//; s/"$//')}
  (cd "$DB" && exec "$PIRSERVICE" --port 8095 service-config.json) > /tmp/check_db_server.log 2>&1 &
  SERVER=$!
  until grep -q listening /tmp/check_db_server.log; do
    kill -0 $SERVER 2>/dev/null || { cat /tmp/check_db_server.log; exit 1; }
    sleep 0.5
  done
  SERVER_URL=http://127.0.0.1:8095
fi
: "${TOKEN:?set TOKEN for a remote server}"

# One line per question: prefix, form, number as asked, expected answer.
python3 - "$HERE" "$S8" "${RANDOM_PER_PREFIX:-25}" $PREFIXES > "$WORK/cases" <<'CASES'
import random, sys
sys.path.insert(0, sys.argv[1])
from generate_block_db import listed_ranges, span
s8, count, prefixes = sys.argv[2], int(sys.argv[3]), sys.argv[4:]
FORMS = {"+44...": "+44{}", "0...": "0{}", "44...": "44{}", "0044...": "0044{}", "no 0": "{}"}
BUILT = {"+44...", "0..."}

def ask(label, number, forms, blocked):
    for form in forms:
        print(f"{label}\t{form}\t{FORMS[form].format(number)}\t{'block' if blocked and form in BUILT else 'allow'}")

unlisted = []
for prefix in prefixes:
    ranges = listed_ranges(s8, prefix)
    lowest, highest = span(prefix[1:])
    if not ranges:
        ask(prefix, random.randrange(lowest, highest), BUILT, False)
        continue
    sizes = [end - start for start, end in ranges]
    picks = [random.randrange(total := sum(sizes)) for _ in range(count)]
    listed = [ranges[0][0], ranges[-1][1] - 1]
    for pick in picks:
        for (start, end), size in zip(ranges, sizes):
            if pick < size:
                listed.append(start + pick); break
            pick -= size
    for number in listed:
        ask(prefix, number, FORMS, True)
    edges = [ranges[0][0] - 1, ranges[-1][1]] + [end for (_, end), (start, _) in zip(ranges, ranges[1:]) if end < start]
    unlisted += [number for number in edges[:6] if lowest <= number < highest]
for number in unlisted:
    ask("not in Ofcom list", number, BUILT, False)
ask("0845 (phone)", 8450000123, BUILT, False)
ask("mobile", 7700900123, BUILT, False)
ask("0800", 8000000000, BUILT, False)
CASES

"$CHECK" "$SERVER_URL" "$TOKEN" "$USECASE" $(cut -f3 "$WORK/cases") 2>&1 | grep -v Hummingbird > "$WORK/answers"
grep -v "	" "$WORK/answers" || true
[ -z "$SERVER" ] || echo "server memory: $(( $(ps -o rss= -p $SERVER) / 1024 )) MB resident"

python3 - "$WORK/cases" "$WORK/answers" <<'JUDGE'
import sys
from collections import Counter
cases = [line.rstrip("\n").split("\t") for line in open(sys.argv[1])]
answers = dict(line.rstrip("\n").split("\t", 1) for line in open(sys.argv[2]) if "\t" in line)
asked, blocked, wrong = Counter(), Counter(), []
for label, form, number, expect in cases:
    got = "block" if answers.get(number, "").startswith("BLOCK") else "allow"
    asked[label, form] += 1
    blocked[label, form] += got == "block"
    if got != expect:
        wrong.append(f"WRONG: {number} ({label}, {form}) should be {'blocked' if expect == 'block' else 'allowed'}")
labels = list(dict.fromkeys(label for label, *_ in cases))
forms = list(dict.fromkeys(form for _, form, *_ in cases))
print("blocked / asked   " + "".join(f"{form:>11}" for form in forms))
for label in labels:
    print(f"{label:17} " + "".join(f"{f'{blocked[label, f]}/{asked[label, f]}' if asked[label, f] else '':>11}" for f in forms))
print("\n".join(wrong))
print(f"asked {len(cases)} questions, {len(wrong)} wrong")
sys.exit("CHECK FAILED" if wrong else 0)
JUDGE
echo "ALL CORRECT"
