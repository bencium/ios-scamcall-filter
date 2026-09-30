# How iOS call blocking and filtering interact

Researched 29 September 2026 against Apple documentation, Apple Developer Forums, EE/O2 community discussions, and an indexed ISPreview telecom discussion. The target device is an iPhone 14 on iOS 26.6.2. No settings, lists, application code, or carrier services were changed for this research.

## Finding

iOS makes the final decision about incoming cellular calls. An ordinary Call Directory app supplies full-number records; it does not receive each cellular call and decide whether to hang up. Apple documents several separate controls, and its engineers acknowledge that some sources take priority over app blocking. The complete priority rules are not public.

This does not excuse the unwanted interruption. Our configured number range includes the reported number, but we have not demonstrated the required result: no incoming interruption from the full 0845 range.

## The separate controls

| Control | What it does | Consequence for this app |
| --- | --- | --- |
| Phone's built-in Block Caller | Adds a particular number to the user's system block list. A caller may still leave voicemail without notifying the user. | Distinct from the lists supplied by our six extensions; the app does not own this list. |
| Call Directory extension | Submits individual full phone numbers for blocking or identification. iOS consults stored data. | This is the mechanism used by 0845 Blocker. The documented API has no prefix or wildcard entry. |
| Live Caller ID Lookup | iOS obtains blocking/identity data from a server through Apple's privacy-preserving infrastructure. | Separate technology, requiring server operation and Apple endpoint validation. It is not a local callback for each number. |
| Screen Unknown Callers: Ask Reason | Answers an unknown caller, asks for information, then can ring with that information. | Does not satisfy a blanket rejection rule. |
| Screen Unknown Callers: Silence | Silences unsaved callers and sends them to voicemail. | Applies beyond 0845 and can lead to a visible Live Voicemail screen. |
| Call Filtering: Unknown Callers | Moves unknown calls out of the main Recents list. | Organizing history is not evidence that a call was blocked. |
| Call Filtering: Spam | Uses carrier spam/fraud identification to silence and route calls to voicemail and a Spam list. | Different evidence and scope from our complete 0845 number list. |
| Business/caller identification | Provides caller information from Apple Business Connect, carriers, or apps. | A displayed name or spam label does not establish that the block rule ran. |
| Live Voicemail | The iPhone handles a voicemail live and can display a transcript and an answer option. | Explains how a silenced call can still appear on screen. Its presence does not prove a successful directory block. |

Sources: [Apple Call Directory documentation](https://developer.apple.com/documentation/callkit/identifying-and-blocking-calls), [Apple's iOS 26 screening/filtering guide](https://support.apple.com/en-gb/guide/iphone/iphe4b3f7823/26/ios/26), [built-in blocking](https://support.apple.com/en-gb/111104), [Live Voicemail](https://support.apple.com/en-gb/guide/iphone/iph3c99490e/26/ios/26), [Live Caller ID Lookup](https://developer.apple.com/documentation/identitylookup/getting-up-to-date-calling-and-blocking-information-for-your-app).

## Apple engineers' forum explanations

1. **Contacts override app blocking by design.** In August 2025, Apple DTS explained that an app cannot block a number already in the user's contact database. The reply distinguishes the user-controlled system block list. The user says the reported caller was not saved, so this does not explain our incident. [Thread 795580](https://developer.apple.com/forums/thread/795580)

2. **Outgoing Recents can override app blocking in iOS 26.** Apple DTS acknowledged that changes around Live Caller ID gave prior outgoing calls higher priority. The user says they never called the number, so this exception is also not our established cause. [Thread 800415](https://developer.apple.com/forums/thread/800415)

3. **Blocked calls may intentionally remain in Missed Calls.** Apple DTS says the history should identify which app blocked a number. This concerns a history entry, not an incoming live screen. Checking the actual call detail is therefore useful independent evidence. The same reply describes the roughly two-million-entry capacity as informal, not a guaranteed public limit. [Thread 796430, August 2025](https://developer.apple.com/forums/thread/796430)

4. **There is no published complete hierarchy.** Apple DTS describes conflicts between multiple information sources and says the detailed priority rules are not fully defined. This thread also contains an Apple-confirmed iOS 26 beta implementation defect; a developer later reports it fixed in beta 7. That older defect cannot establish a cause on 26.6.2. [Thread 794740](https://developer.apple.com/forums/thread/794740)

5. **Later failures are reported but not fully diagnosed publicly.** A June 2026 developer reports blocking failure on iOS 26.5 and explicitly excludes prior outgoing calls. Apple requests a small reproducer rather than confirming a cause. [Thread 828538](https://developer.apple.com/forums/thread/828538)

6. **A multiple-extension failure has been reported, not confirmed.** In November 2025 a developer reported that one of two extensions blocked while the second did not. The only reply suggests checking outgoing Recents; there is no Apple staff diagnosis or posted test result. A separate October 2025 thread also ends with Apple requesting a reproducer and feedback report. These reports do not prove that our six-part layout is the cause. [Thread 808320](https://developer.apple.com/forums/thread/808320), [thread 804176](https://developer.apple.com/forums/thread/804176)

No inspected Apple reply confirms that ordinary Call Directory blocking is deliberately converted into the exact `shouldBlock: NO shouldSilence YES` plus Live Voicemail sequence found on this phone.

## Telecom forum evidence

- **EE staff, 25 July 2023:** an iPhone-blocked caller can still be diverted to voicemail. This older explanation concerns network voicemail and does not establish current Call Directory matching. [EE discussion](https://community.ee.co.uk/t5/Mobile-Services/Blocking-numbers-and-diversion-to-voicemail/m-p/1277602/highlight/true)
- **EE staff, 8 October 2024:** the iPhone's Live Voicemail and EE's mailbox can answer calls separately and use different greetings. [EE voicemail greeting](https://community.ee.co.uk/t5/Mobile-Services/EE-Voicemail-greeting/td-p/1452973)
- **O2 customer, 28 April 2025:** reports that disabling Live Voicemail restored expected network-diversion behaviour. This is a firsthand customer report, not an O2-confirmed repair to call blocking. The original poster in the same thread reports a different resolution involving a SIM swap, so the thread does not establish one universal cause. [O2 discussion](https://community.o2.co.uk/t5/Tech-Support/eSIM-call-divert-issue-concern/td-p/1753715)
- **ISPreview, July 2023 test:** a participant's iOS 17 beta test describes the phone answering and showing live transcription with call controls. It is historical firsthand evidence consistent with Apple's current Live Voicemail documentation. The full page returned 403 during this research; only indexed content was accessible. No advice about changing region from this old beta test applies to the current phone. [Telecom forum discussion](https://www.ispreview.co.uk/talk/threads/apple-live-voicemail-ios-17.39886/)

No inspected telecom discussion establishes a different, reliable local iOS prefix-blocking mechanism or proves why this specific 0845 call was not rejected.

## What the phone itself proves

See `INCIDENT-2026-09-29.md` for the preserved diagnostic details. At the reported time, iOS ran a directory lookup, chose silencing rather than rejection, started Live Voicemail, and issued ringtone-suppression instructions. The lookup result and trust score are privacy-redacted. The later log explicitly says the directory allowed the call before trying the separate live-lookup mechanism.

It is not established whether the result was caused by an unmatched entry, another policy taking priority, a platform defect, or another interaction. No arithmetic gap was found, and all six switches were enabled at the later read-only check. This is insufficient to declare the app successful or to blame a specific iOS bug.

## Next evidence to collect

First inspect the 12:38 call's detail in Phone and check whether it attributes a block to 0845 Blocker. This is read-only and does not disturb existing evidence. Also record the present screening and Live Voicemail settings before any experiment.

If attribution does not resolve the issue, use a real, user-authorized test caller to compare our directory with the built-in Block Caller function, capturing call-time diagnostics. Keep the 0845 partitions intact. This requires an available real test number and a planned incoming call; neither has been supplied yet. No test caller should be contacted without authorization.

Disabling Live Voicemail could isolate the visible-screen path, but it is not evidence that prefix blocking has been repaired. A broad unknown-caller setting, another list reload, caller-ID labels, and successful compilation are likewise not acceptance tests. The success condition remains no unwanted incoming interruption, with unrelated permitted calls still working.
