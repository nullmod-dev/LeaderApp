# Device trust — two-device test (local server)

A checklist for testing device trust with two Android devices against the
backend on the development computer. Each step says what to do and what must
happen; mark it failed if anything else happens. The real server
(5.189.132.216) is not used.

## 0. Prerequisites

Server, accounts, Wi-Fi and the APK build are as in
[`offline_session_server_test.md`](offline_session_server_test.md) §0.
Development mode: every code is `246810`, and every email (codes, "new device
signed in", the admin alert) is readable at
`http://192.168.0.147:22721/api/v1/dev/mailbox?to=<email>`.

1. **Restart the API** so it runs the device-trust code:

   ```bash
   B=~/Documents/Python-Files/flutter/apps/Leader_backend
   kill $(ss -ltnpH 'sport = :22721' | grep -oP 'pid=\K\d+')
   cd $B && setsid nohup node server.js > ~/Leader_deploy/local/logs/api-22721.log 2>&1 < /dev/null &
   curl -s http://192.168.0.147:22721/health
   ```

2. **Rebuild and install the APK** (same command as the offline test) on
   **Phone A** (the Xiaomi) and on **Device B** (a second phone, or an Android
   emulator on this computer — it reaches `192.168.0.147` the same way).
   Install B **fresh** (uninstall first) so it has a new device id.

3. Accounts: **Main** = `pbea4007@mtu.edu.iq` (Main Admin), **Simple** =
   `hamodekaherhm@gmail.com` (Simple Admin), password `Leader@12345`.
   Seeded accounts have no device record yet.

## 1. First device (no restriction)

| # | Do | Must happen |
|---|---|---|
| 1.1 | A: open the app. Check the sign-in screen. | Google button, no «الدخول برمز يصل إلى بريدك». |
| 1.2 | A: sign in as Main with the password. | Code screen titled «تأكيد هذا الجهاز». |
| 1.3 | A: enter `246810`. | Home opens. **No** banner at the top. |
| 1.4 | A: sign out, sign in again as Main. | No code this time; Home opens. |
| 1.5 | A: More → Security. | Rows «أجهزتي» and «الدخول دون اتصال» (until a date ~7 days ahead). |

## 2. New device (restricted 6 hours)

| # | Do | Must happen |
|---|---|---|
| 2.1 | B: sign in as Main with the password. | «تأكيد هذا الجهاز» code screen. |
| 2.2 | B: enter `246810`. | Home opens with a yellow bar «جهاز جديد: … مقفل حتى {time}», time ≈ now + 6 h. |
| 2.3 | Mailbox for Main. | A «دخول من جهاز جديد» email. |
| 2.4 | B: edit an **existing** detachment (or member) and save. | Refused with «هذا جهاز جديد على حسابك…». Nothing changes. |
| 2.5 | B: create a new member. Then edit and save that new member. | Both succeed. |
| 2.6 | B: on an existing shift, add an assignment, then check that member in. | Both succeed (allowed field work). |
| 2.7 | B: remove that assignment again. | Refused (unassign is blocked on an older shift). |
| 2.8 | B: More → Security → أجهزتي. | Two devices; B marked «هذا الجهاز» and «مقيّد مؤقتاً»; note that removing is not possible; no «إزالة» buttons. |
| 2.9 | B: Security → reset password / Simple Admins → invite. | Refused with the same sentence. |

## 3. Yes from the trusted device

| # | Do | Must happen |
|---|---|---|
| 3.1 | A: leave the app for a minute and come back (or reopen it). | Blue bar «سجّل جهاز جديد الدخول إلى حسابك. هل هو أنت؟» + «مراجعة». |
| 3.2 | A: «مراجعة». | Prompt shows the device label and its sign-in time. |
| 3.3 | A: «نعم، هذا جهازي». | Snackbar «أكّدنا الجهاز…»; the blue bar is gone. |
| 3.4 | B: leave the app for a minute and come back. | The yellow bar is gone. Step 2.4 now succeeds. |

## 4. No from the trusted device

Device records are per account: B stays trusted for Main whatever happens to
Simple here.

| # | Do | Must happen |
|---|---|---|
| 4.1 | A: sign out; sign in as **Simple**, code `246810`. | Home, no bar (Simple's first device). |
| 4.2 | B: sign out; sign in as **Simple**, code `246810`. | Yellow restricted bar on B. |
| 4.3 | A: leave the app and come back (or reopen it). | Blue bar «سجّل جهاز جديد…». |
| 4.4 | A: «مراجعة» → «لا، ليس أنا». | A confirmation dialog first. |
| 4.5 | Confirm «حظر الجهاز وإنهاء الجلسات». | «حمَينا حسابك» with «إعادة تعيين كلمة المرور». |
| 4.6 | B: do anything online. | B lands on «انتهت الجلسة». |
| 4.7 | B: sign in as Simple. | «حُظر هذا الجهاز من الدخول إلى هذا الحساب…». |
| 4.8 | A: sign in as Simple with the old password. | «لأسباب أمنية، أعد تعيين كلمة المرور…». |
| 4.9 | Mailbox for Main. | «تنبيه أمني: جهاز مرفوض» naming Simple. |
| 4.10 | A: «نسيت كلمة المرور؟» → code `246810` → new password → sign in. | Signs in with no device code (A is still trusted). |

## 5. Device limit and My devices

| # | Do | Must happen |
|---|---|---|
| 5.1 | Get Main to 3 trusted devices (A, B, plus a reinstall approved with Yes). | My devices shows «٣ من ٣ أجهزة موثوقة». |
| 5.2 | Reinstall on one device, sign in as Main, code. | Bar: «هذا الجهاز غير موثوق: …» (no time). |
| 5.3 | Sign out and in again on that device. | The code is asked again. |
| 5.4 | Trusted device: «مراجعة» → «نعم». | «لديك العدد الأقصى…» + a link to «أجهزتي». |
| 5.5 | «أجهزتي» → «إزالة» on an old device → confirm. | «أُزيل الجهاز.»; that device is signed out on its next request. |
| 5.6 | Back to the prompt → «نعم». | Accepted; the untrusted device is now trusted and unrestricted. |

## 6. Offline window and lifetime

| # | Do | Must happen |
|---|---|---|
| 6.1 | A online: Security → «الدخول دون اتصال». | Until ≈ now + 7 days. |
| 6.2 | A: airplane mode, sign-out dialog. | Adds «…وتبقى جلستك على الخادم حتى تنتهي خلال ٧ أيام.» Cancel. |
| 6.3 | A: phone date +6 days, airplane mode, open the app. | Opens on the saved account. |
| 6.4 | A: phone date +8 days (from the last online open), airplane mode. | «انتهت صلاحية الدخول دون اتصال». Restore the real date. |

## Known limits seen in this test

Device and email both lost = no way back in; a blocked device comes back as a
new device after a reinstall (code + restriction again); an operation queued
offline on a restricted phone and refused later shows as "failed" in the sync
queue. See [`device_trust_flow.md`](device_trust_flow.md) → Known limits.
