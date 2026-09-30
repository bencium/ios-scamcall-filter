# Alternatives checked — 28 September 2026

## Requirement

Reject every incoming call whose presented UK number begins 0845 before the iPhone rings. Keep the existing O2 service and call routing. The user authorizes a private app to inspect calls and call history, but the available iOS permissions still determine what can be implemented. Do not replace the rule with general unknown-caller screening or a narrower prefix.

The user has chosen to keep v0.3's six parts while alternatives are investigated. Do not remove, replace, disable, or reroute that setup merely to explore alternatives.

## Findings

1. **Call Directory lists:** public on-device mechanism. Each entry is a full international-format number. No public prefix or range operation was found in Apple's documentation or installed iOS 27 SDK headers. Current v0.3 uses six parts strictly below the observed failed boundary. Activation/load evidence and live incoming-call proof are separate.
2. **Default dialler:** checked current Apple documentation and installed `LiveCommunicationKit` Swift interface. `TelephonyConversationManager` lists cellular services and starts cellular conversations; it exposes no incoming cellular rejection method. The general `ConversationManager` controls the app's VoIP calls. Default dialler documentation describes recent cellular history since becoming default, with EU account/device conditions for testing. History access does not provide a pre-ring rejection callback.
3. **Live Caller ID Lookup:** system-managed per-call lookup backed by a server, with Apple endpoint validation and private information retrieval. This does not expose the incoming number to an arbitrary local predicate. It avoids a local directory but adds a server and Apple validation; it is not an entirely on-device alternative.
4. **Shortcuts:** Apple's documented communication triggers are email and messages, not a cellular call interception trigger. No documented pre-ring prefix-rejection action was found.
5. **Existing wildcard blockers:** primary developer descriptions for Begone and Simple Call Blocker describe generating or supplying number lists to iOS. They are not evidence that third-party apps can apply native prefix rules directly. Their claims do not prove how they exceed loading limits on this user's phone.
6. **Incremental updates in one extension:** Apple documents additions/removals relative to a prior load, but no primary capacity guarantee was found showing that the observed two-million boundary is per request rather than total stored entries. This could be a future isolated diagnostic; it remains enumerated-number blocking, not a fundamentally different mechanism. Do not replace the currently enabled six parts on this hypothesis.
7. **Carrier or external telephone routing:** explicitly excluded by the user. Nothing was purchased, ported, or forwarded.
8. **Private system access:** personal signing does not grant arbitrary system entitlements. No usable supported bypass was established for the connected iPhone 14 on iOS 26.6.2. No jailbreak or OS modification was attempted.

## Sources

- [Apple: Call Directory](https://developer.apple.com/documentation/callkit/identifying-and-blocking-calls)
- [Apple: default dialler](https://developer.apple.com/documentation/LiveCommunicationKit/preparing-your-app-to-be-the-default-dialer-app)
- [Apple: TelephonyConversationManager](https://developer.apple.com/documentation/LiveCommunicationKit/TelephonyConversationManager)
- [Apple: VoIP conversations](https://developer.apple.com/documentation/livecommunicationkit/initiating-voip-conversations-with-livecommunicationkit)
- [Apple: Live Caller ID Lookup](https://developer.apple.com/documentation/identitylookup/getting-up-to-date-calling-and-blocking-information-for-your-app)
- [Apple: communication triggers](https://support.apple.com/en-ie/guide/shortcuts/apdd711f9dff/ios)
- [Apple: incremental loading](https://developer.apple.com/documentation/callkit/cxcalldirectoryextensioncontext/isincremental)
- [Begone developer description and responses](https://apps.apple.com/us/app/begone-spam-call-blocker/id1596818195)
- [Simple Call Blocker developer explanation (historical)](https://micro.mjdescy.me/2018/07/25/introducing-simple-call.html)
- [Apple: iOS code signing](https://support.apple.com/en-ca/guide/security/sec7c917bf14/web)
