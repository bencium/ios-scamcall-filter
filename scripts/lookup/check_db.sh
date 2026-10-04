#!/bin/sh
# Check a built lookup database the way the phone would use it.
#
#   scripts/lookup/check_db.sh DBDIR PREFIX [PREFIX ...]
#
# Starts the patched PIRService on DBDIR (port 8095), then asks it, by real encrypted
# queries, about the first and last number of every prefix plus RANDOM_PER_PREFIX random
# ones (all must be BLOCK), and about numbers that must stay allowed: the numbers just
# outside each prefix's edges, 0845, a mobile and 0800. Prints lookup times and the
# server's memory use. Exits non-zero on any wrong answer.
#
# Against a deployed server instead:  SERVER_URL=https://... TOKEN=... check_db.sh - PREFIX ...
# PIRSERVICE: patched server binary (default: ~/src/live-caller-id-lookup-example/.build/release/PIRService).
set -eu
DB=$1; shift; PREFIXES=$*
HERE=$(cd "$(dirname "$0")" && pwd)
PIRSERVICE=${PIRSERVICE:-$HOME/src/live-caller-id-lookup-example/.build/release/PIRService}
CHECK="$HERE/checker/.build/release/CheckLookup"
USECASE=uk.co.bencium.ScamBlocker.Lookup.block

SERVER=""
if [ -z "${SERVER_URL:-}" ]; then
  TOKEN=${TOKEN:-$(grep -o '"tokens": \["[^"]*"' "$DB/service-config.json" | sed 's/.*\["//; s/"$//')}
  cd "$DB"
  "$PIRSERVICE" --port 8095 service-config.json > /tmp/check_db_server.log 2>&1 &
  SERVER=$!
  trap 'kill $SERVER 2>/dev/null' EXIT
  until grep -q listening /tmp/check_db_server.log; do
    kill -0 $SERVER 2>/dev/null || { cat /tmp/check_db_server.log; exit 1; }
    sleep 0.5
  done
  SERVER_URL=http://127.0.0.1:8095
fi
: "${TOKEN:?set TOKEN for a remote server}"

numbers=$(python3 - "${RANDOM_PER_PREFIX:-25}" $PREFIXES <<'GEN'
import random, sys
count, prefixes = int(sys.argv[1]), sys.argv[2:]
codes = {int(p[1:]) for p in prefixes}
blocked, allowed = [], ["+448450000123", "+447700900123", "+448000000000"]
for code in sorted(codes):
    blocked += [f"+44{code}0000000", f"+44{code}9999999"]
    blocked += [f"+44{code}{random.randrange(10_000_000):07d}" for _ in range(count)]
    if code - 1 not in codes: allowed.append(f"+44{code - 1}9999999")
    if code + 1 not in codes: allowed.append(f"+44{code + 1}0000000")
print(" ".join(blocked))
print(" ".join(allowed))
GEN
)
blocked=$(echo "$numbers" | sed -n 1p)
allowed=$(echo "$numbers" | sed -n 2p)

result=$("$CHECK" "$SERVER_URL" "$TOKEN" "$USECASE" $blocked $allowed | grep -v Hummingbird)
echo "$result" | grep -v -E '^\+44' || true
fail=0
for number in $blocked; do echo "$result" | grep -q "^$number	BLOCK" || { echo "WRONG: $number should be blocked"; fail=1; }; done
for number in $allowed; do echo "$result" | grep -q "^$number	not in database" || { echo "WRONG: $number should be allowed"; fail=1; }; done
echo "checked $(echo $blocked | wc -w | tr -d ' ') numbers that must be blocked and $(echo $allowed | wc -w | tr -d ' ') that must be allowed"
[ -n "$SERVER" ] && echo "server memory: $(( $(ps -o rss= -p $SERVER) / 1024 )) MB resident"
[ $fail -eq 0 ] && echo "ALL CORRECT" || { echo "CHECK FAILED"; exit 1; }
