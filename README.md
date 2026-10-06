# iPhone scam call blocker: block whole number ranges, in any country

A private iPhone app that blocks whole ranges of phone numbers, not one number at a time. **It's a global tool.** Its server takes any country's number ranges as patterns, so the same setup works wherever scam calls come from. There is no tracking, and no access to your contacts or call history.

This repository ships configured for UK scam ranges:

- **On the phone:** every 0845 number, all 10 million of them. This part works with no internet connection.
- **On your own small server:** every number Ofcom has issued or opened for issuing in 0840 to 0849 (except 0845) and 0870 to 0879, about 31 million, each stored as both `+44…` and `0…`. The server can't see which number is calling. See [Server lookup](#server-lookup-for-0843-0844-and-08700873).

**About 40 million numbers in total.** To block other countries' ranges, or to run the server somewhere other than Fly.io, see [Other countries and other hosts](#other-countries-and-other-hosts). So far, real-call testing covers the UK 0845 list on the phone.

Your carrier may already label these calls "Suspected Spam" and still put them through. iOS can only block numbers one at a time, not a whole prefix. This app works around that by handing iOS the complete range.

## Quick start with Claude Code or Codex

You need:
- a Mac with Xcode installed
- a free Apple account signed in to Xcode (Xcode > Settings > Accounts)
- your iPhone and a USB cable

Then:

1. Clone this repo and open a terminal in it.
2. Start Claude Code (`claude`) or Codex in that folder.
3. Plug your iPhone into the Mac, unlock it, and tap **Trust** if asked.
4. Tell the agent: **"Follow README.md to build and install this on my connected iPhone."**
5. Follow what it tells you on screen. The steps below are what it will do.

## Setup steps (what the agent does, or what you do by hand)

1. **Use your own identifiers.** Bundle identifiers are unique across all Apple accounts, and every account has its own team ID. Replace:
   - `uk.co.bencium.ScamBlocker` with your own prefix (for example `com.yourname.ScamBlocker`) in `scripts/create_project.py`, `Shared/BlockerPlan.swift`, `App/BlockerStatus.swift` and `Blocker/CallDirectoryHandler.swift`.
   - Find your team ID in Xcode > Settings > Accounts, or in the signing error Xcode gives you.
2. **Generate the Xcode project:** `python3 scripts/create_project.py`. Pass your team ID at build time (step 5), or keep it in a local `.env` file, which git ignores. Never commit it.
3. **Check the number ranges:**
   ```sh
   xcrun swiftc -module-cache-path /tmp/scamblocker-swift-cache \
     Shared/BlockerPlan.swift Shared/FallbackBlocks.swift scripts/verify_plan.swift -o /tmp/scamblocker-verify-plan
   /tmp/scamblocker-verify-plan
   ```
4. **Turn on Developer Mode on the iPhone:** Settings > Privacy & Security > Developer Mode, then restart the phone.
5. **Build and install:**
   ```sh
   xcrun devicectl list devices          # find your iPhone's identifier
   xcodebuild -project ScamBlocker.xcodeproj -scheme ScamBlocker \
     -configuration Release -destination 'id=YOUR_DEVICE_ID' \
     -derivedDataPath build -allowProvisioningUpdates \
     DEVELOPMENT_TEAM=YOURTEAMID build
   xcrun devicectl device install app --device YOUR_DEVICE_ID \
     build/Build/Products/Release-iphoneos/ScamBlocker.app
   ```
   On a free account, the first launch may say the developer is untrusted. Trust it in Settings > General > VPN & Device Management.
6. **Switch the blocking on.** On the iPhone, go to Settings > Apps > Phone > Call Blocking & Identification. Turn on the six **084x Blocker — 0845 part** switches **one at a time**, letting each finish loading before the next.
7. **Confirm it loaded.** Open **084x Blocker** and tap **Check enabled parts**. All six should show "On · checked".
8. **Turn off Live Voicemail:** Settings > Apps > Phone > Live Voicemail. See the next section for why.
9. **Delete old outgoing calls to 0845 numbers from Recents.** On iOS 26 a number you have called before overrides the block.

**Re-sign every 7 days.** On a free Apple account the app stops working 7 days after installing. Plug the phone in and run `scripts/resign.sh` (see [Weekly re-sign](#weekly-re-sign)).

## What we found on the way (iOS 26.6.2, iPhone 14, O2 UK)

1. **One list can't hold all 10 million numbers.** iOS rejected a single list with "maximum allowed entries (2000000)". A list of exactly 2 million also failed. The app therefore splits the range into six parts: five of 1.8 million and one of 1 million.
2. **All six parts loaded,** but a scam 0845 call still reached the screen.
3. **Where the "Suspected Spam" label comes from.** The phone's logs showed that O2's network writes "Suspected Spam" into the caller name itself. The carrier flags these calls but still connects them.
4. **The block did work.** The phone's stored call history gave that call a trust score that appears exactly once in the whole history: on the first 0845 call after the app was installed. Every earlier 0845 call, and every other call O2 labelled as spam, got the ordinary "unknown" score.
5. **iOS silences blocked calls instead of rejecting them.** With unknown-caller screening set to Never, the only thing that silenced the call was the app's block. With Live Voicemail on, the phone then answered the call itself and showed it on screen. That is why step 8 turns Live Voicemail off. The inconsistency has been reported to Apple.

The full engineering record is in [BUILD-HISTORY-AND-HANDOVER.md](BUILD-HISTORY-AND-HANDOVER.md), with the call investigation in [INCIDENT-2026-09-29.md](INCIDENT-2026-09-29.md) and background research in [IOS-CALL-BLOCKING-RESEARCH.md](IOS-CALL-BLOCKING-RESEARCH.md).

## Limits

- It blocks **every** 0845 caller, including legitimate ones. It does not cover hidden numbers or other prefixes.
- **More prefixes can't go on the phone with a free Apple account.** A free account allows 10 app identifiers, and each 10-million range needs six parts. The server lookup below covers 0843, 0844 and 0870 to 0873 instead, using one more identifier (8 of 10).
- iOS decides what happens to a blocked call. Apple can change that behaviour in any update.
- A number saved in your contacts, or one you have called, overrides the block.
- To stop blocking, turn off every **084x Blocker** switch in Settings > Apps > Phone > Call Blocking & Identification.

## Keeping your own settings private

You can run your own deployment from a clone of this public repository without publishing anything personal. Read [IMPORTANT.md](IMPORTANT.md) first.

- **Your values live only in git-ignored files.** `.env` holds your team ID, server address, Fly app name, token and dashboard password. `private/` holds your call-history copies and notes. `server/fly.toml` holds your Fly app; start it from `server/fly.example.toml`. `Lookup/Info.plist` and `Shared/LookupSecrets.swift` are generated from `.env`.
- **The privacy guard installs itself** the first time you run `python3 scripts/create_project.py` in a clone. You can also install it with `scripts/privacy_guard.sh --install`. Every commit and push is then blocked if it adds a value from `.env`, a pattern from `private/guard-patterns.txt`, or a file that must never be committed. Put your own patterns in that file, such as your computer's name or phone numbers, one regular expression per line. It is git-ignored, so the patterns stay private too.

## Privacy

- The app asks for no permissions. The app and the six 0845 parts make no network requests.
- It never sees your calls. iOS does the matching internally.
- With the server lookup switched on, iOS itself sends an encrypted query to your server when an unknown caller rings. The server answers without learning the number, using Apple's private information retrieval. Callers in your contacts never trigger a query.
- Its own logs record only which part loaded, whether the lookup switch is on, and any errors.

## Server lookup for 0843, 0844 and 0870–0873

**Status, 5 October 2026.** On 5 October three real 0843 calls rang through. The phone asked the server each time and got an answer, but the database held each number only as `+44843…`. UK networks often deliver the same number as `0843…`, and the lookup matches exact text. The database is now rebuilt from Ofcom's numbering list, with each number in both forms. It includes every block Ofcom has issued, withdrawn or opened for issuing, because opened blocks can be handed out at any time. Blocks Ofcom doesn't list are left out: they can't be issued until Ofcom opens them, and UK networks must block calls showing numbers that were never issued. This database went live at 16:00 UK time on 5 October. Against the live server, 453 encrypted lookups gave 0 wrong answers, and all three callers now block in both forms. A single lookup takes about 190 ms. Rebuild when Ofcom's list changes (see [Keeping the list current](#setting-it-up)). iOS accepted the lookup part on a free Apple account: the phone completed its setup with the trial server. **Not yet confirmed:** that a real call from these prefixes is silenced. Do not rely on it until that is checked.

How it works:

- The app contains one extra part, a Live Caller ID Lookup extension. When an unknown caller rings, iOS asks your server whether to block the number and waits briefly for the answer before ringing.
- The server is Apple's open-source example server (Apache-2.0), built from a pinned commit with two local changes in `server/patches/`:
  - It loads each piece of the database from disk only when a call needs it. Memory stays around 100 MB instead of about 17 GB, so the smallest Fly.io machine is enough.
  - It keeps its token-signing key and the phone's uploaded key on disk. Apple's version makes a new signing key and forgets phone keys on every restart, which breaks lookups until iOS notices. This change is what makes stopping when idle safe.
- It needs mobile data or Wi-Fi at the moment of the call. Apple doesn't document what iOS does when the server can't be reached, so assume the call rings through.
- The app is installed straight from Xcode, so Apple's relay and approval form don't apply. An App Store or TestFlight build would need Apple's approval.

Measured on the Mac with the full database:

| Item | Value |
|---|---|
| Numbers | 31,350,000 listed numbers × 2 forms = 62,700,000 entries |
| Pieces (shards) | 8,192 |
| Database on disk | 10 GB |
| Server memory after 139 lookups | 110 MB |
| Build time on an M2 Pro | about 9 minutes |
| Coverage check | every listed number present once in each form, none missing, none duplicated, nothing else |
| One lookup, Mac as server and client | about 120 ms |

Cost ([Fly.io pricing](https://docs.fly.io/about/pricing)):

| Item | Monthly cost |
|---|---|
| 13 GB disk, billed all the time | about $1.95 |
| 256 MB machine, always on (London) | about $2.48 (checked 6 October 2026) |

**The machine stays awake all the time, because iOS waits only about 1 second.** On 6 October the phone's own log showed iOS giving up 1.006 seconds after a call arrived ("Timeout occured waiting for LiveLookup Blocking information") and letting it ring. The server's "block" answer arrived 15 ms later: waking from suspend had taken 0.8 s of that second. The limit comes from Apple's settings on the phone; the server can't change it. Measured on the live server:

| Situation | One lookup |
|---|---|
| Machine awake | 171–194 ms |
| Awake, complete first lookup including setup | 404–636 ms |
| Woken from suspend | 945 ms, often too slow |
| Woken from a full stop | 4.7 s, always too slow |

Sleep-when-idle (`auto_stop_machines = "suspend"`) would save about $2.30 a month, but calls that arrive while it sleeps ring through.

### Setting it up

You need the four Apple PIR tools on your Mac: `ConstructDatabase`, `PIRService` (from [apple/live-caller-id-lookup-example](https://github.com/apple/live-caller-id-lookup-example)) and `PIRShardDatabase`, `PIRProcessDatabase` (from [apple/swift-homomorphic-encryption](https://github.com/apple/swift-homomorphic-encryption)). Install each with `swift package experimental-install -c release --product NAME` in its checkout. They land in `~/.swiftpm/bin`.

1. **Build the database** (about 6 minutes, needs about 14 GB free disk):
   ```sh
   export PATH="$HOME/.swiftpm/bin:$PATH"
   scripts/lookup/build_db.sh /tmp/lookup-db 8192 0840 0841 0842 0843 0844 0846 0847 0848 0849 087
   ```
2. **Check exact coverage** of every entry:
   ```sh
   python3 scripts/lookup/verify_coverage.py /tmp/lookup-db 0840 0841 0842 0843 0844 0846 0847 0848 0849 087
   ```
   It must end with `COVERAGE EXACT`: every listed number once in each form, nothing else.
3. **Check it with real lookups.** This needs the patched server binary (`server/dev.sh setup`, then `swift build -c release --product PIRService` in `server/upstream`; or set `PIRSERVICE` to one you built) and the checker (`swift build -c release` in `scripts/lookup/checker`):
   ```sh
   scripts/lookup/check_db.sh /tmp/lookup-db/db 0840 0841 0842 0843 0844 0846 0847 0848 0849 087
   ```
   It must end with `ALL CORRECT`. It asks about the first, last and 25 random listed numbers of each prefix in five forms, and prints a table of what was blocked. `+44…` and `0…` must be blocked. The other forms, numbers next to the listed ones that Ofcom doesn't list, 0845, a mobile and 0800 must stay allowed.
4. **Create the Fly app** from the `server` folder. Pick your own app name; it becomes `https://<your-app>.fly.dev`:
   ```sh
   cd server
   cp fly.example.toml fly.toml        # then set app = "<your-app>" in fly.toml (git-ignored)
   fly apps create <your-app>
   fly volumes create pirdata --region lhr --size 13
   fly secrets set LOOKUP_TOKEN="$(openssl rand -base64 33)"
   ```
   Copy the same token into `.env` as `LOOKUP_TOKEN`, and set `LOOKUP_URL=https://<your-app>.fly.dev` and `FLY_APP=<your-app>`. Then deploy from the top folder of the repository with `scripts/deploy.sh --detach`. The server waits for its database instead of crashing.
5. **Upload the database:** `scripts/lookup/upload_db.sh /tmp/lookup-db/db`. It sends 16 parts and restarts the server. To replace a live database, add `IN_PLACE=1` in front: the volume only has room for one copy, so each part is unpacked over the live files. It first checks that the shard count and settings match, so blocking never stops. Fly's command-line tunnel managed about 2 MB/s, so this takes over an hour. If the connection drops, run it again and it resumes. Avoid other `fly ssh` sessions while it runs. Auto-stop only counts web traffic, so switch it off for the upload and back on afterwards:
   ```sh
   fly machine update <machine id> --autostop=off --skip-health-checks --yes    # before
   fly machine update <machine id> --autostop=suspend --skip-health-checks --yes   # after
   ```
6. **Check the live server:** `SERVER_URL=https://<your-app>.fly.dev TOKEN=<your token> S8=/tmp/lookup-db/s8.csv scripts/lookup/check_db.sh - 0840 0841 0842 0843 0844 0846 0847 0848 0849 087`
7. **Rebuild the app:** `python3 scripts/create_project.py`, then build and install as in the setup steps above.
8. **On the iPhone,** turn on **084x Blocker — Server lookup (0843, 0844, 087x)** in Settings > Apps > Phone > Call Blocking & Identification. If it isn't listed, restart the phone once.

To add or remove a prefix, rerun steps 1, 2, 3 and 5 with the new list. Update `serverPrefixes` in `Shared/BlockerPlan.swift` so the app shows it. Then tap **Refresh server data** in the app.

**Keeping the list current.** Ofcom updates its numbering list regularly, and a block it opens later isn't blocked until the database is rebuilt. Now and then, run:

```sh
python3 scripts/lookup/ofcom_changes.py
```

It compares Ofcom's current list with `scripts/lookup/listed-ranges.txt`, the record of what the live database blocks, and prints any ranges that were added or removed. It also sends the result to the server, where the app shows it. If something changed, rerun steps 1, 2, 3 and 5 (with `IN_PLACE=1`). Then run `python3 scripts/lookup/ofcom_changes.py --save /tmp/lookup-db/s8.csv` and commit the updated record.

To run it on its own on the 1st of every month at 09:00, with a Mac notification when the list changes or the check fails:

```sh
scripts/schedule_ofcom_check.sh --install    # also --run-now and --remove
```

A run missed while the Mac sleeps happens when it wakes. The log is `~/Library/Logs/084x-ofcom-check.log`.

### Changing and deploying the server

The server's code is Apple's example server plus the patch files in `server/patches/`. To change it:

```sh
server/dev.sh setup     # Apple's code at the pinned commit, with the patches applied, in server/upstream (git-ignored)
                        # then edit and commit in server/upstream, on the branch local-patches
server/dev.sh save      # rewrites server/patches from those commits
```

Commit the patch files, then deploy with `scripts/deploy.sh`. It refuses unless you are on `main` with nothing uncommitted, the patches apply to Apple's pinned code and match `server/upstream`, and `server/fly.toml` names the same app as `FLY_APP` in `.env`. A Claude Code hook in `.claude/` stops an agent from running `fly deploy` directly.

### Other countries and other hosts

**Any country's numbers.** The server matches full international numbers, so it isn't tied to the UK. Give the build script an international pattern in which each `x` is any digit. For example, `+1900xxxxxxx` covers 10 million US 900 numbers. A UK prefix like `0843` stands for every number Ofcom has issued or opened for issuing under it, in both forms (Ofcom's list covers numbers starting 08 only). Both kinds can be mixed in one database:

```sh
scripts/lookup/build_db.sh /tmp/lookup-db 8192 0843 0844 +1900xxxxxxx
```

Each 10 million numbers adds about 1.8 GB of disk and no extra server memory. The on-phone 0845 list stays UK-only. Two limits apply. The coverage check and the sample-number check only understand UK prefixes for now. Blocking non-UK numbers hasn't been tested with real calls.

**Any host that runs a container.** This repository deploys to Fly.io, but `server/Dockerfile` is a standard container. It should run on Oracle Cloud (its Always Free tier can be set up in London), Google Cloud, AWS or a home server. It needs:

- HTTPS on its own hostname: no custom port, no path, and a valid certificate
- a persistent disk of about 13 GB for the 63-million-entry database
- about 256 MB of memory
- the `LOOKUP_TOKEN` and `DASHBOARD_PASSWORD` secrets as environment variables, and `SHARD_COUNT` set to the shard count you built

Any host must answer within iOS's 1-second limit, so the server has to run all the time. After moving, set `LOOKUP_URL` in `.env` to the new address and rebuild the app. Only Fly.io has been tested.

### Free trial with the Mac as the server

Before paying for hosting, the Mac can serve the full database on your Wi-Fi. Set `LOOKUP_URL=http://<your Mac's name>.local:8080` and `LOOKUP_TOKEN=BBBB` in `.env`, rebuild the app, and run the patched server from the database folder. `caffeinate -i` keeps the Mac awake while it runs:

```sh
cd /tmp/lookup-db/db && caffeinate -i PIRService --hostname 0.0.0.0 --port 8080 service-config.json
```

Lookups only work while the phone is on the same Wi-Fi and the Mac is awake.

### Acceptance checklist

Generating or installing the list proves nothing about blocking. Check each of these on the phone:

- [ ] A call from each server prefix is blocked: no ring, no vibration, no incoming-call screen. Test 0843 separately from the others.
- [ ] 0845 is tested separately. The on-device 0845 parts answer first, so an 0845 block does not prove the server lookup works.
- [ ] A permitted caller, for example a contact, still rings with no extra delay.
- [ ] The same results with the phone locked, after a restart, and after a few idle hours.
- [ ] With the server stopped, and with the phone offline, record whether calls from server prefixes get through.

A real-call test needs a caller presenting one of these numbers. Scam calls arrive on their own schedule; a test call from a number you own is the only controlled option.

### Privacy of the server lookup

- The server receives only encrypted lookups and cannot tell which number called.
- Because the app is installed from Xcode, Apple's relay is not used. The server therefore sees the phone's internet address and the time of each lookup from an unknown caller.
- The server logs only request type and path. Keep the token out of Git: it lives in `.env` and Fly secrets only.
- Apple describes its example server as "just an example service and should not be run in production". This setup runs it for one person's phone, behind a token, with one reviewed patch.

### Metrics dashboard

Open `https://<your-app>.fly.dev/dashboard`. The browser asks for a password: any user name, and `DASHBOARD_PASSWORD` from `.env` (also stored as a Fly secret). The page wakes the server if it is asleep.

- **Server side, live:** lookups per day, response times, errors and restarts. The server never sees caller numbers, so its log holds none.
- **Phone side, after each report run:** calls per day by outcome, calls per prefix, O2 "Suspected Spam" labels, the re-sign date, and a scrolling list of blocked numbers.
- The status line turns amber when the re-sign is due within two days or no lookup has arrived for three days, and red when the server logged an error in the last 24 hours.
- The blocked-numbers list holds real caller numbers. Scammers often spoof other people's numbers, so keep the dashboard behind its password.

### Call report

```sh
python3 scripts/report.py            # 7-day summary in the terminal
python3 scripts/report.py --upload   # also update the dashboard
```

It reads a private copy of the call history, never the live file, and its last line names the copy it used and its newest call. For a fresh copy, run `scripts/call_history.sh` with the phone plugged in. It backs up the phone and pulls only the call history out of the backup, into `private/backup-copy/` (git-ignored). It needs three things set up once:

1. In Finder, select the iPhone and tick **Encrypt local backup**, with a password. iOS keeps call history only in encrypted backups. The first backup copies everything; later ones copy only what changed.
2. Save that password in the Keychain. This asks for it, so it never shows on screen: `security add-generic-password -a "$USER" -s 084x-blocker-backup -w`
3. In System Settings > Privacy & Security > Full Disk Access, turn on your terminal app, then quit and reopen it. This also lets the terminal read everything else on the Mac, such as Mail and Messages.

Without a backup copy, the report falls back to the history iCloud syncs to the Mac, which can be days behind. It reads it directly with Full Disk Access, or from a copy of `CallHistory.storedata` and its `-wal` and `-shm` files placed in `private/`. Each incoming call gets one verdict:

| Verdict | Meaning |
|---|---|
| Blocked by server | Blocked, on a server prefix; proven when the server logged a lookup within 30 seconds |
| Blocked on phone | Blocked, on any other prefix (the 0845 list) |
| Rang, unknown caller | Not a contact or a number you've called |
| Rang, known caller | A contact or a number you've called |

The upload contains counts, plus the numbers of blocked calls for the dashboard list. It never contains contacts, answered calls or names. Nothing is written into the repository.

### Details screen in the app

The line at the top of the app says whether protection is on: all six 0845 parts and the server lookup. If the Mac's call report is recent, it also shows how many calls were blocked this week. Tap it for the Details screen:

- **Server:** how fast it answered just now (about 1 s means it was asleep, too slow for iOS), when it started, unknown callers checked in the last 24 hours and 7 days, the last one, and errors.
- **Numbers blocked:** on the server, from the Mac's notes, and on the phone, plus the last Ofcom check.
- **Blocked calls:** counts and the last five numbers, from the Mac's call report. Only that report knows which calls were blocked: iOS doesn't tell apps, and the server never sees its own answers. The screen says how old the report is.
- **Phone:** the switches and the re-sign date, read from the app's own signing profile.

The app fetches `/dashboard/status.json` once each time it opens, with `DASHBOARD_PASSWORD` built into the app from `.env`. A call counts as checked only when its lookups include the identity question iOS always asks, so test lookups don't count. Pull down to refresh. Launch with `--details` to open the screen directly.

### Phone status

```sh
scripts/phone_status.sh
```

It opens the app on the phone over the cable and prints what the app saw: each 0845 switch, the server lookup switch, and when **Check enabled parts** and **Refresh server data** last ran, with their results. The phone must be unlocked. Otherwise it prints the last status the app saved, with the time it was saved. It never contains phone numbers.

### Weekly re-sign

```sh
scripts/resign.sh            # re-signs only if a profile expires within 48 hours
FORCE=1 scripts/resign.sh    # re-sign now
```

It moves expiring signing profiles to a backup folder (never deleting them) so Xcode issues fresh 7-day ones, rebuilds in whichever mode the project was last generated (normal or fallback), checks every part got a fresh week, and installs. The phone must be paired and unlocked. If the install fails, the next run retries it. It runs only when you start it.

### On-device fallback: allocated 0843 only

If the server lookup can't run, for example because iOS won't enable it on a free account, there is a phone-only fallback. It drops the server part and adds three Call Directory parts holding the 0843 blocks Ofcom lists as Allocated: 567 blocks, 5.67 million numbers, 1.89 million per part. Unallocated 0843 numbers are not covered in this mode.

It uses exactly 10 App IDs, the free account's limit. The first 0843 part reuses the server part's App ID, `uk.co.bencium.ScamBlocker.Lookup`, so only two new IDs are needed. If any other app on the same Apple account registered an App ID in the last 7 days, Xcode may refuse the two new ones until that ID's 7 days pass.

```sh
python3 scripts/fallback_0843_blocks.py          # optional: refresh the block list from Ofcom
FALLBACK_0843=1 python3 scripts/create_project.py
```

Then build, install and check the plan as in the setup steps. Turn on the six **0845 part** switches and the three **0843 part** switches one at a time. To return to the server lookup, run `python3 scripts/create_project.py` without the variable.

