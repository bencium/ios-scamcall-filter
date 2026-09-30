# iOS scam call filter — block every 0845 number on your iPhone

A small private iPhone app that blocks **every** UK number starting with 0845: all 10 million of them. Everything runs on your phone. There is no server, no tracking, and no access to your contacts or call history.

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
     Shared/BlockerPlan.swift scripts/verify_plan.swift -o /tmp/scamblocker-verify-plan
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

**Re-sign every 7 days.** On a free Apple account the app stops working 7 days after installing. Plug the phone in and repeat step 5.

## What we found on the way (iOS 26.6.2, iPhone 14, O2 UK)

1. **One list can't hold all 10 million numbers.** iOS rejected a single list with "maximum allowed entries (2000000)". A list of exactly 2 million also failed. The app therefore splits the range into six parts: five of 1.8 million and one of 1 million.
2. **All six parts loaded,** but a scam 0845 call still reached the screen.
3. **Where the "Suspected Spam" label comes from.** The phone's logs showed that O2's network writes "Suspected Spam" into the caller name itself. The carrier flags these calls but still connects them.
4. **The block did work.** The phone's stored call history gave that call a trust score that appears exactly once in the whole history: on the first 0845 call after the app was installed. Every earlier 0845 call, and every other call O2 labelled as spam, got the ordinary "unknown" score.
5. **iOS silences blocked calls instead of rejecting them.** With unknown-caller screening set to Never, the only thing that silenced the call was the app's block. With Live Voicemail on, the phone then answered the call itself and showed it on screen. That is why step 8 turns Live Voicemail off. The inconsistency has been reported to Apple.

The full engineering record is in [BUILD-HISTORY-AND-HANDOVER.md](BUILD-HISTORY-AND-HANDOVER.md), with the call investigation in [INCIDENT-2026-09-29.md](INCIDENT-2026-09-29.md) and background research in [IOS-CALL-BLOCKING-RESEARCH.md](IOS-CALL-BLOCKING-RESEARCH.md).

## Limits

- It blocks **every** 0845 caller, including legitimate ones. It does not cover hidden numbers or other prefixes.
- **More prefixes (0843, 0844, 087x…) need a paid Apple Developer account.** A free account allows only 10 app identifiers, and this app already uses 7: the app plus six parts. Each extra 10-million range needs six more parts.
- iOS decides what happens to a blocked call. Apple can change that behaviour in any update.
- A number saved in your contacts, or one you have called, overrides the block.
- To stop blocking, turn off the six parts in Settings > Apps > Phone > Call Blocking & Identification.

## Privacy

- The app asks for no permissions and makes no network requests.
- It never sees your calls. iOS does the matching internally.
- Its own logs record only which part loaded and any errors.
