# Draft Feedback Assistant report — for review, not submitted

Submit only if you are happy with it: use the Feedback Assistant app on the iPhone or feedbackassistant.apple.com. Choose the area "iOS & iPadOS" > "Phone" (or "CallKit" if offered).

Feedback Assistant will offer to attach a sysdiagnose. A sysdiagnose contains personal device data; attaching one is your choice. The 29 September logs below are enough to describe the problem. Apple engineers usually ask for a sysdiagnose captured straight after the next occurrence.

---

**Title**

Call Directory blocking entry matches (trust score BlockedByThirdParty) but the call is silenced and answered by Live Voicemail instead of being rejected; blockedByExtension is not recorded

**Device and software**

iPhone 14, iOS 26.6.2 (23G90), O2 UK, VoLTE.

**Setup**

- A development-signed app with six Call Directory extensions supplies blocking entries only, with no identification entries.
- Together the six cover the contiguous range 448450000000–448459999999 (+44 845 000 0000 to +44 845 999 9999). That is 10,000,000 entries, each extension below 2,000,000, submitted in ascending order.
- All six extensions are enabled. All six reloads completed successfully on 28 September 2026.
- Phone settings: Screen Unknown Callers = Never. Call Filtering > Unknown Callers = On. Live Voicemail = On. Focus off.
- The caller is not in Contacts and has never been called from this iPhone.

**Steps**

1. An incoming VoLTE call arrived on 29 September 2026 at 11:38:48 UTC from 0845xxxxxxx, which is +44 845 xxx xxxx. O2 delivered the number in national format in the SIP `From:` header, with display name "Suspected Spam".

**Expected**

The call is rejected, as documented for Call Directory blocking entries. The Recents entry is attributed to the blocking app.

**Actual**

1. `communicationtrustd` looked up call-directory blocked entries for the handle, and the trust chain ended immediately afterwards. The identification lookup and "mark as unknown" steps did not run:
   ```
   11:38:48.877 communicationtrustd [DataSource] <private>: Looking up call directory blocked entries for handles <private>
   11:38:48.878 communicationtrustd [DataSource] <private> Phone number variants <private>
   11:38:48.881 communicationtrustd [DataSource] <private>: Call directory blocked entries found <private>
   11:38:48.882 communicationtrustd [DataSource] <private>: No remaining handles, returning trustScores <private>
   ```
2. The stored CallHistory record for this call has `ZCOMMUNICATIONTRUSTSCORE = 2`. That is the only record with this value in the device's call history. Earlier calls from the same 0845 range, before the extensions were installed, and every call with the same carrier "Suspected Spam" name, all scored 4.
3. `callservicesd` then silenced the call instead of blocking it, and routed it to Live Voicemail, which answered:
   ```
   11:38:48.897 callservicesd shouldBlock: NO shouldSilence YES
   11:38:48.905 callservicesd simFocus: resolutionReason: =disabled, shouldAllowCall=1
   11:38:48.911 callservicesd Should we send to AnsweringMachine? shouldSendToLVM=YES shouldSendToReceptionist=NO ... hasSpamIdentifierInCarrierName=NO
   11:38:49.309 CommCenter Session confirmed with "Suspected Spam" <sip:0845xxxxxxx@uk.pri.o2.com;user=phone>
   ```
4. About two seconds later, `callservicesd`'s own directory check disagreed with step 1, and recorded no blocking extension:
   ```
   11:38:51.031 callservicesd phoneNumberVariants: <private>
   11:38:51.034 callservicesd callDirectory allowed call, checking live blocking info
   11:38:51.041 callservicesd firstEnabledLiveBlockingExtensionIdentifierForPhoneNumber handle=<private> blockedByExtension=(null)
   11:38:51.041 callservicesd Updated filtered out reason to 4
   ```
5. The Recents entry shows only the carrier name, with no attribution to the blocking app. `ZBLOCKEDBYEXTENSION` is empty.

(Times are UTC. The device logged them as 12:38 BST.)

**Questions**

1. Is "silence and send to voicemail" the intended iOS 26 behaviour for numbers matched by a Call Directory blocking entry, rather than rejection? If it is, blocked calls should not be answered by Live Voicemail and shown on screen.
2. Why does `callservicesd`'s directory check ("callDirectory allowed call", `blockedByExtension=(null)`) disagree with `communicationtrustd` for the same call? Could the national-format number in the SIP `From:` header produce different phone-number variants in the two checks?
