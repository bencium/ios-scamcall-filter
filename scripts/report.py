"""Call report: what happened to every incoming call, matched against the lookup server's log.

Usage:
  python3 scripts/report.py [--history PATH] [--days 30] [--upload]

Reads a private copy of the iPhone call history synced to this Mac (the live file is never
opened), fetches the server's metrics, and gives every incoming call one verdict:

  blocked_server   blocked by an app on a server prefix (0843, 0844, 087x). It counts as proven
                   only when the server logged a lookup within 30 seconds of the call.
  blocked_phone    blocked by an app on any other prefix (the on-device 0845 list)
  rang_unknown     rang, from a number that isn't a contact or a number you've called
  known            rang, from a contact or a number you've called before

Prints a 7-day summary. With --upload it sends the dashboard a summary: counts per day and per
prefix, and the numbers of blocked calls only (never contacts, answered calls or names).
History: --history, else private/backup-copy (a fresh copy from scripts/call_history.sh), else
private/CallHistory.storedata, else the synced location (days behind, and needs Full Disk Access
for the terminal). The report names the file it used. Settings come from .env: DASHBOARD_PASSWORD, LOOKUP_URL.
"""
import argparse
import base64
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYNCED = Path.home() / "Library/Application Support/CallHistoryDB/CallHistory.storedata"
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
BLOCKED_BY_APP = 2            # trust score calibrated against this phone's history on 29 September 2026
KNOWN_SCORES = {5, 8}         # 5: a number you've called, 8: a contact
MATCH_WINDOW = timedelta(seconds=30)
VERDICTS = ["blocked_server", "blocked_phone", "rang_unknown", "known"]
SERVER_PREFIXES = ["0843", "0844", "0870", "0871", "0872", "0873"]


def main():
    args = parse_args()
    env = read_env()
    history = find_history(args.history)
    calls = read_calls(history, args.days)
    lookups = fetch_lookups(env)
    rows = [classify(call, lookups) for call in calls]
    summary = summarise(rows, calls, args.days)
    print_report(summary, lookups is not None, history)
    if args.upload:
        upload(summary, env)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--history", type=Path)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--upload", action="store_true")
    return parser.parse_args()


def read_env():
    """Settings from .env; environment variables of the same name win (useful for testing)."""
    import os
    env = {}
    for line in (ROOT / ".env").read_text().splitlines():
        key, sep, value = line.partition("=")
        if sep and not key.startswith("#"):
            env[key.strip()] = value.strip()
    env.update({k: os.environ[k] for k in ["DASHBOARD_PASSWORD", "LOOKUP_URL"] if k in os.environ})
    return env


def find_history(given):
    private = ROOT / "private"
    for candidate in [given, private / "backup-copy", private / "CallHistory.storedata", SYNCED]:
        if candidate is None:
            continue
        path = candidate / "CallHistory.storedata" if candidate.is_dir() else candidate
        try:
            with open(path, "rb"):
                return path
        except FileNotFoundError:
            continue
        except PermissionError:
            continue        # the synced location needs Full Disk Access for the terminal
    if any(private.glob("CallHistory.storedata-*")):
        sys.exit(f"{private} has the -wal and -shm files but not CallHistory.storedata itself. Copy that file too.")
    sys.exit("No call history found. Run scripts/call_history.sh for a fresh copy from the phone, or copy\n"
             f"CallHistory.storedata and its -wal and -shm files from {SYNCED.parent} into {private}.")


def read_calls(path, days):
    """Reads incoming calls from a private temporary copy, so the live database is never touched."""
    with tempfile.TemporaryDirectory(prefix="callhistory.") as work:
        for suffix in ["", "-wal", "-shm"]:
            source = Path(str(path) + suffix)
            if source.exists():
                shutil.copy2(source, Path(work) / (path.name + suffix))
        db = sqlite3.connect(Path(work) / path.name)
        columns = {row[1] for row in db.execute("PRAGMA table_info(ZCALLRECORD)")}
        wanted = ["ZDATE", "ZADDRESS", "ZNAME", "ZANSWERED", "ZDURATION", "ZORIGINATED",
                  "ZCOMMUNICATIONTRUSTSCORE", "ZBLOCKEDBYEXTENSION"]
        missing = [c for c in wanted if c not in columns]
        if missing:
            print(f"note: call history has no {', '.join(missing)}; those details are left out", file=sys.stderr)
        select = ", ".join(c if c in columns else "NULL" for c in wanted)
        since = (datetime.now(timezone.utc) - timedelta(days=days) - APPLE_EPOCH).total_seconds()
        records = db.execute(f"SELECT {select} FROM ZCALLRECORD WHERE ZDATE >= ? ORDER BY ZDATE", (since,)).fetchall()
        db.close()
    calls = []
    for date, address, name, answered, duration, originated, trust, blocked_by in records:
        if originated:          # outgoing calls are not part of this report
            continue
        calls.append({
            "time": APPLE_EPOCH + timedelta(seconds=date),
            "number": as_text(address),
            "o2_spam": "suspected spam" in as_text(name).lower() or "suspected scam" in as_text(name).lower(),
            "answered": bool(answered),
            "trust": trust,
            "blocked": trust == BLOCKED_BY_APP or bool(as_text(blocked_by)),
        })
    return calls


def as_text(value):
    if value is None:
        return ""
    return value.decode("utf-8", "ignore") if isinstance(value, bytes) else str(value)


def fetch_lookups(env):
    """Times of the server's block lookups, or None if the server can't be reached."""
    password = env.get("DASHBOARD_PASSWORD")
    base = env.get("LOOKUP_URL", "").rstrip("/")
    local = base.startswith("http://127.0.0.1") or base.startswith("http://localhost")
    if not password or not (base.startswith("https://") or local):
        print("note: no DASHBOARD_PASSWORD or https LOOKUP_URL in .env; server lookups not matched", file=sys.stderr)
        return None
    request = urllib.request.Request(f"{base}/dashboard/server.csv", headers={"Authorization": basic_auth(password)})
    try:
        text = urllib.request.urlopen(request, timeout=60).read().decode()
    except OSError as error:
        print(f"note: server metrics unavailable ({error}); server lookups not matched", file=sys.stderr)
        return None
    times = []
    for line in text.splitlines()[1:]:
        time, event, detail, status, _ = (line.split(",") + [""] * 5)[:5]
        if event == "lookup" and "block" in detail and status == "200":
            times.append(datetime.fromisoformat(time.replace("Z", "+00:00")))
    return times


def basic_auth(password):
    return "Basic " + base64.b64encode(f"report:{password}".encode()).decode()


def classify(call, lookups):
    looked_up = lookups is not None and any(abs(t - call["time"]) <= MATCH_WINDOW for t in lookups)
    if call["blocked"]:
        verdict = "blocked_server" if prefix(call["number"]) in SERVER_PREFIXES else "blocked_phone"
    elif call["trust"] in KNOWN_SCORES:
        verdict = "known"
    else:
        verdict = "rang_unknown"
    return {**call, "verdict": verdict, "looked_up": looked_up, "prefix": prefix(call["number"])}


def prefix(number):
    digits = number.replace(" ", "").replace("-", "")
    if digits.startswith("+44"):
        digits = "0" + digits[3:]
    elif digits.startswith("0044"):
        digits = "0" + digits[4:]
    if not digits:
        return "withheld"
    if digits.startswith("+") or digits.startswith("00"):
        return "international"
    for p in ["0843", "0844", "0845", "0870", "0871", "0872", "0873"]:
        if digits.startswith(p):
            return p
    for p, label in [("084", "084 other"), ("087", "087 other"), ("0800", "0800/0808"), ("0808", "0800/0808"),
                     ("03", "03"), ("07", "07 mobile"), ("01", "01/02 landline"), ("02", "01/02 landline")]:
        if digits.startswith(p):
            return label
    return "other"


def spaced(number):
    digits = number.replace(" ", "")
    if digits.startswith("+44"):
        digits = "0" + digits[3:]
    return f"{digits[:4]} {digits[4:7]} {digits[7:]}".strip() if len(digits) == 11 else digits


def summarise(rows, calls, days):
    daily = defaultdict(Counter)
    by_prefix = defaultdict(Counter)
    for row in rows:
        day = row["time"].astimezone().date().isoformat()
        daily[day][row["verdict"]] += 1
        by_prefix[row["prefix"]][row["verdict"]] += 1
        if row["verdict"] == "blocked_server" and row["looked_up"]:
            daily[day]["server_proven"] += 1
        if row["o2_spam"]:
            daily[day]["o2_spam_label"] += 1
            by_prefix[row["prefix"]]["o2_spam_label"] += 1
    today = datetime.now().date()
    keys = VERDICTS + ["o2_spam_label", "server_proven"]
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "days": days,
        "latest_call_in_history": calls[-1]["time"].isoformat(timespec="seconds") if calls else None,
        "resign_due": resign_due(),
        "daily": [{"date": (today - timedelta(days=i)).isoformat(),
                   **{k: daily[(today - timedelta(days=i)).isoformat()][k] for k in keys}}
                  for i in range(days - 1, -1, -1)],
        "by_prefix": sorted(({"prefix": p, **{k: c[k] for k in keys}} for p, c in by_prefix.items()),
                            key=lambda r: -sum(r[k] for k in VERDICTS)),
        # Requested by the user: blocked calls only, newest first. Never contacts, answered calls or names.
        "blocked_calls": [{"time": r["time"].isoformat(timespec="seconds"), "number": spaced(r["number"]),
                           "by": ("server" if r["looked_up"] else "server, lookup not matched")
                                 if r["verdict"] == "blocked_server" else "phone"}
                          for r in sorted(rows, key=lambda r: r["time"], reverse=True) if r["verdict"].startswith("blocked")],
    }


def resign_due():
    """Earliest signing-profile expiry in the last build: when the app and its parts stop working."""
    app = ROOT / "build/Build/Products/Release-iphoneos/ScamBlocker.app"
    expiries = []
    for bundle in [app, *app.glob("PlugIns/*.appex"), *app.glob("Extensions/*.appex")]:
        profile = bundle / "embedded.mobileprovision"
        if not profile.exists():
            continue
        plist = subprocess.run(["security", "cms", "-D", "-i", str(profile)], capture_output=True).stdout
        date = subprocess.run(["plutil", "-extract", "ExpirationDate", "raw", "-o", "-", "-"],
                              input=plist, capture_output=True).stdout.decode().strip()
        if date:
            expiries.append(date)
    return min(expiries) if expiries else None


def print_report(summary, matched, history):
    week = summary["daily"][-7:]
    totals = Counter()
    for day in week:
        totals.update({k: day[k] for k in VERDICTS + ["o2_spam_label", "server_proven"]})
    print(f"Last 7 days ({week[0]['date']} to {week[-1]['date']})")
    print(f"  blocked by server lookup : {totals['blocked_server']} ({totals['server_proven']} proven by a matching lookup)")
    print(f"  blocked on phone (0845)  : {totals['blocked_phone']}")
    print(f"  rang, unknown caller     : {totals['rang_unknown']}")
    print(f"  rang, known caller       : {totals['known']}")
    print(f"  O2 'Suspected Spam' label: {totals['o2_spam_label']}")
    if not matched:
        print("  (server log unavailable: no server block can be proven)")
    source = history.relative_to(ROOT) if history.is_relative_to(ROOT) else history
    print(f"Latest call in {source}: {summary['latest_call_in_history']}")
    print(f"Re-sign due by: {summary['resign_due']}")


def upload(summary, env):
    base = env["LOOKUP_URL"].rstrip("/")
    request = urllib.request.Request(
        f"{base}/dashboard/phone.json", data=json.dumps(summary).encode(), method="POST",
        headers={"Authorization": basic_auth(env["DASHBOARD_PASSWORD"]), "Content-Type": "application/json"})
    urllib.request.urlopen(request, timeout=60)
    print(f"Uploaded the summary to {base}/dashboard")


if __name__ == "__main__":
    main()
