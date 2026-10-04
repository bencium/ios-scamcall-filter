# iOS scam call filter — block every 0845 number on your iPhone

A small private iPhone app that blocks **every** UK number starting with 0845: all 10 million of them. The 0845 list runs entirely on your phone. There is no tracking, and no access to your contacts or call history.

Version 0.4 adds an optional **server lookup** for 0843, 0844, 0870, 0871, 0872 and 0873 (another 60 million numbers). Those prefixes don't fit on a free Apple account, so a small private server answers for them. The server cannot see which number is calling. See [Server lookup](#server-lookup-for-0843-0844-and-08700873).

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
6. **Switch the blocking on.** On the iPhone, go to Settings > Apps > Phone > Call Blocking & Identification. Turn on the six **0845 Blocker** parts **one at a time**, letting each finish loading before the next.
7. **Confirm it loaded.** Open 0845 Blocker and tap **Check enabled parts**. All six should show "On · checked".
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
- To stop blocking, turn off the six parts in Settings > Apps > Phone > Call Blocking & Identification.

## Privacy

- The app asks for no permissions. The app and the six 0845 parts make no network requests.
- It never sees your calls. iOS does the matching internally.
- With the server lookup switched on, iOS itself sends an encrypted query to your server when an unknown caller rings. The server answers without learning the number, using Apple's private information retrieval. Callers in your contacts never trigger a query.
- Its own logs record only which part loaded, whether the lookup switch is on, and any errors.

## Server lookup for 0843, 0844 and 0870–0873

**Status, 4 October 2026.** The server runs on Fly.io in London at `https://scamblocker-lookup.fly.dev` and passes the full number check. The list is generated straight from the prefixes: every number, allocated or not, with no reputation or allocation data. iOS accepted the lookup part on a free Apple account: the phone completed its setup with the trial server. **Not yet confirmed:** that a real call from these prefixes is silenced. Do not rely on it until that is checked.

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
| Numbers | 60,000,000 (6 prefixes × 10 million) |
| Pieces (shards) | 8,192 |
| Database on disk | 10 GB |
| Server memory with everything loaded | 91 MB |
| Build time on an M2 Pro | about 6 minutes |
| Coverage check | every number of every prefix present once, none missing, none duplicated, nothing else |
| One lookup, Mac as server and client | about 157 ms |

Cost ([Fly.io pricing](https://docs.fly.io/about/pricing)):

| Item | Monthly cost |
|---|---|
| 13 GB disk, billed all the time | about $1.95 |
| 256 MB machine, if it ran all the time | about $2.50 |
| 256 MB machine with auto-suspend | only while awake; asleep it costs storage only |

The machine suspends itself after about 5 to 7 minutes without lookups and resumes on the next one. Measured on the live server:

| Situation | One lookup |
|---|---|
| Machine awake | 171 ms |
| Woken from suspend | 945 ms |
| Woken from a full stop | 4.7 s |

Suspend is used rather than stop because of that difference. If Fly ever loses the suspended snapshot, for example during maintenance, the next call gets the slower full start. Apple doesn't document how long iOS waits for the answer before ringing.

### Setting it up

You need the four Apple PIR tools on your Mac: `ConstructDatabase`, `PIRService` (from [apple/live-caller-id-lookup-example](https://github.com/apple/live-caller-id-lookup-example)) and `PIRShardDatabase`, `PIRProcessDatabase` (from [apple/swift-homomorphic-encryption](https://github.com/apple/swift-homomorphic-encryption)). Install each with `swift package experimental-install -c release --product NAME` in its checkout. They land in `~/.swiftpm/bin`.

1. **Build the database** (about 6 minutes, needs about 14 GB free disk):
   ```sh
   export PATH="$HOME/.swiftpm/bin:$PATH"
   scripts/lookup/build_db.sh /tmp/lookup-db 8192 0843 0844 0870 0871 0872 0873
   ```
2. **Check exact coverage** of all 60 million entries (about 20 seconds):
   ```sh
   python3 scripts/lookup/verify_coverage.py /tmp/lookup-db/merged 0843 0844 0870 0871 0872 0873
   ```
   It must end with `COVERAGE EXACT`.
3. **Check it with real lookups.** This needs the patched server binary (apply `server/patches/*.patch` to a checkout of the example server and run `swift build -c release --product PIRService`) and the checker (`swift build -c release` in `scripts/lookup/checker`):
   ```sh
   scripts/lookup/check_db.sh /tmp/lookup-db/db 0843 0844 0870 0871 0872 0873
   ```
   It must end with `ALL CORRECT`. It asks about the first, last and 25 random numbers of each prefix, and about the numbers just outside each prefix, which must stay allowed.
4. **Create the Fly app** from the `server` folder:
   ```sh
   cd server
   fly apps create scamblocker-lookup
   fly volumes create pirdata --region lhr --size 13
   fly secrets set LOOKUP_TOKEN="$(openssl rand -base64 33)"
   fly deploy --detach
   ```
   Copy the same token into `.env` as `LOOKUP_TOKEN`, and set `LOOKUP_URL=https://scamblocker-lookup.fly.dev`. The server waits for its database instead of crashing.
5. **Upload the database:** `scripts/lookup/upload_db.sh /tmp/lookup-db/db`. It sends 16 parts and restarts the server. Fly's command-line tunnel managed about 2 MB/s, so this takes over an hour. If the connection drops, run it again and it resumes. Avoid other `fly ssh` sessions while it runs. Auto-stop only counts web traffic, so switch it off for the upload and back on afterwards:
   ```sh
   fly machine update <machine id> --autostop=off --skip-health-checks --yes    # before
   fly machine update <machine id> --autostop=suspend --skip-health-checks --yes   # after
   ```
6. **Check the live server:** `SERVER_URL=https://scamblocker-lookup.fly.dev TOKEN=<your token> scripts/lookup/check_db.sh - 0843 0844 0870 0871 0872 0873`
7. **Rebuild the app:** `python3 scripts/create_project.py`, then build and install as in the setup steps above.
8. **On the iPhone,** turn on **0845 Blocker — Server lookup (0843, 0844, 087x)** in Settings > Apps > Phone > Call Blocking & Identification. If it isn't listed, restart the phone once.

To add or remove a prefix, rerun steps 1, 2, 3 and 5 with the new list. Update `serverPrefixes` in `Shared/BlockerPlan.swift` so the app shows it. Then tap **Refresh server data** in the app.

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

Open `https://scamblocker-lookup.fly.dev/dashboard`. The browser asks for a password: any user name, and `DASHBOARD_PASSWORD` from `.env` (also stored as a Fly secret). The page wakes the server if it is asleep.

- **Server side, live:** lookups per day, response times, errors and restarts. The server never sees caller numbers, so its log holds none.
- **Phone side, after each report run:** calls per day by outcome, calls per prefix, O2 "Suspected Spam" labels, the re-sign date, and a scrolling list of blocked numbers.
- The status line turns amber when the re-sign is due within two days or no lookup has arrived for three days, and red when the server logged an error in the last 24 hours.
- The blocked-numbers list holds real caller numbers. Scammers often spoof other people's numbers, so keep the dashboard behind its password.

### Call report

```sh
python3 scripts/report.py            # 7-day summary in the terminal
python3 scripts/report.py --upload   # also update the dashboard
```

It reads a private copy of the call history that iCloud syncs to the Mac, never the live file. Copy `CallHistory.storedata` and its `-wal` and `-shm` files from `~/Library/Application Support/CallHistoryDB/` into `private/` (git-ignored; in Finder press Cmd+Shift+G). Alternatively give Terminal Full Disk Access and it reads them directly. Each incoming call gets one verdict:

| Verdict | Meaning |
|---|---|
| Blocked by server | Blocked, on a server prefix; proven when the server logged a lookup within 30 seconds |
| Blocked on phone | Blocked, on any other prefix (the 0845 list) |
| Rang, unknown caller | Not a contact or a number you've called |
| Rang, known caller | A contact or a number you've called |

The upload contains counts, plus the numbers of blocked calls for the dashboard list. It never contains contacts, answered calls or names. Nothing is written into the repository.

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

Then build, install and check the plan as in the setup steps. Turn on the six **0845 Blocker** parts and the three **0843 Blocker** parts one at a time. To return to the server lookup, run `python3 scripts/create_project.py` without the variable.

