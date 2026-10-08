# Offline session — manual phone test (local server)

A checklist for testing the seven-day offline session on a real phone against
a backend running on the development computer, over Wi-Fi. Each step says
what to do and what must happen. Mark a step failed if anything else happens.

The real server (5.189.132.216) is not used here; see "Later: the real
server" at the end.

## 0. Prerequisites

### Local server

The phone and the computer must be on the same Wi-Fi. The computer's LAN IP
was `192.168.0.147` (DHCP; check it with `ip -4 addr show wlan0`). If it
changes, rebuild the APK with the new IP.

| Part | Where |
|---|---|
| MongoDB 7 | Docker, `Leader_backend/docker-compose.yml` (service `mongo`, `127.0.0.1:27017`, volume `leader_backend_leader-mongo`) |
| API | `node server.js` in `Leader_backend`, port `22721` on all interfaces, `NODE_ENV=development` |
| Config | `Leader_backend/config.env` (git-ignored, mode 600) |
| Log | `~/Leader_deploy/local/logs/api-22721.log` |

```bash
B=~/Documents/Python-Files/flutter/apps/Leader_backend

# Start (Mongo first, then the API)
docker compose -f $B/docker-compose.yml up -d mongo
cd $B && setsid nohup node server.js > ~/Leader_deploy/local/logs/api-22721.log 2>&1 < /dev/null &

# Check
curl -s http://192.168.0.147:22721/health      # {"status":"ok","database":"connected",...}

# Stop the API only (by port; the older :4000 server is left alone)
kill $(ss -ltnpH 'sport = :22721' | grep -oP 'pid=\K\d+')

# Stop / start Mongo only
docker compose -f $B/docker-compose.yml stop mongo
docker compose -f $B/docker-compose.yml start mongo
```

Development mode means: every seeded account's password is `Leader@12345`,
every email code is `246810`, and sent emails are readable at
`http://192.168.0.147:22721/api/v1/dev/mailbox?to=<email>`. No SMTP and no
domain are needed.

Test accounts (seeded mock data):

| Use | Email |
|---|---|
| First account (Main Admin, team alwalla) | `pbea4007@mtu.edu.iq` |
| Second account (Simple Admin) | `hamodekaherhm@gmail.com` |

Password sign-in opens a session directly. "Sign in with a code" also works
(`246810`). Customer Demo start works too and needs no account.

### APK

```bash
cd ~/Documents/Python-Files/flutter/apps/MTM-Front-Back/flutter_app
flutter build apk --debug \
  --dart-define=LEADER_API_BASE_URL=http://192.168.0.147:22721 \
  --dart-define-from-file=env/google.json
cp build/app/outputs/flutter-apk/app-debug.apk ~/Leader_deploy/apk/leader-debug-lan-192.168.0.147-22721.apk
```

Debug only: cleartext HTTP is allowed in the debug manifest, never in release.

### Install over USB

1. Phone: Settings → About phone → tap **Build number** seven times
   (Developer options appear).
2. Settings → System → Developer options → turn on **USB debugging**.
3. Plug the phone in. Accept the "Allow USB debugging?" prompt (tick
   "Always allow from this computer").
4. On the computer:

```bash
adb devices                       # the phone must show as "device", not "unauthorized"
adb install -r ~/Leader_deploy/apk/leader-debug-lan-192.168.0.147-22721.apk
```

Do **not** use `adb reverse`: the APK talks to the LAN IP, and the cable can be
unplugged after installing.

### How each failure is made

| Failure | How |
|---|---|
| Phone offline | Airplane mode, and check that Wi-Fi is off too (some phones keep Wi-Fi on in airplane mode). |
| Server unreachable | Stop the API (command above). The phone stays online. |
| Server error | Stop Mongo while the API runs. Verified locally: `/health` answers 503 at once, but `/auth/me` and `/auth/refresh` answer **500 only after about 30 s**. The app gives up after **20 s**, so on the phone this tests "the server hangs, the request times out", not a quick 5xx. The expected screen is the same. The quick-5xx path is covered by the automated test `test/features/auth/offline_session_restore_test.dart`. |

### Database access

```bash
docker compose -f ~/Documents/Python-Files/flutter/apps/Leader_backend/docker-compose.yml exec mongo mongosh leader
```

Find the phone's session inside `mongosh`:

```js
const a = db.accounts.findOne({ email: '<your test email>' });
db.sessions.find({ accountId: String(a._id), revokedAt: { $exists: false } })
  .sort({ authenticatedAt: -1 }).limit(1);
```

The phone should have a screen lock (fingerprint or PIN) for the lock steps.

## 1. Online sign-in

1. Network on. Sign in with the first account.
2. Expect: the app opens on Home. The fingerprint/PIN prompt does **not**
   appear right after a fresh sign-in.

## 2. Network off + cold launch

1. Swipe the app away. Turn on airplane mode (Wi-Fi off).
2. Open the app.
3. Expect: the lock prompt, then Home with the same account and the last
   data. No login screen. No empty Home.

## 3. Server unreachable at launch

1. Phone online. Stop the API.
2. Swipe the app away and open it.
3. Expect: same as step 2 (opens on the stored account). Not signed out.
4. Start the API again.

## 4. Server error at launch

1. Phone online, API running. Stop Mongo.
2. Swipe the app away and open it.
3. Expect: about 20 s of waiting (up to about 40 s), then the same as step 2.
   Not signed out.
4. Start Mongo. `/health` is `connected` again within a few seconds; no API
   restart is needed.

## 5. Seven-day cutoff

**Offline cutoff (phone clock):**

1. Airplane mode on. Settings → Date & time → automatic off → move the date
   forward 7 days.
2. Open the app (cold launch, and once with the app already running).
3. Expect: «انتهت صلاحية الدخول دون اتصال», buttons «إعادة المحاولة» and
   «تسجيل الخروج». No lock prompt on this screen.
4. Tap «إعادة المحاولة» while still offline. Expect: spinner, then
   «ما زلت دون اتصال…». The screen stays.
5. Restore the date (automatic on), network on, tap «إعادة المحاولة».
   Expect: back into the app with the same account.

**Clock moved back:** set the date **before** the sign-in, airplane mode,
cold launch. Expect: the same expired screen.

**Server cutoff:** in `mongosh`:

```js
db.sessions.updateOne({ _id: '<session id>' }, { $set: { refreshExpiresAt: new Date(Date.now() - 1000) } });
```

Network on, cold launch. Expect: «انتهت الجلسة» (`/session-expired`).
Airplane mode + cold launch afterwards: the login screen, not the old
account.

## 6. Second session / other account

1. Sign out. Sign in as the **second** account. Open Home once.
2. Airplane mode, cold launch.
3. Expect: the second account only. The first account's data never appears.

## 7. Sign-out

1. Online: More → sign out → confirm.
2. Airplane mode, cold launch.
3. Expect: the login screen. Nothing opens offline.
4. Repeat the sign-out **while offline**. Expect: the phone is signed out.
   Known limit: the server session stays alive until its lifetime ends.

## 8. Revoked session

1. Sign in on the phone and on a second device (or a second install).
2. From the second device: More → Security → devices → revoke the phone.
   (Or in `mongosh`: `db.sessions.updateOne({ _id: '<id>' }, { $set: { revokedAt: new Date(), revokeReason: 'test' } })`.)
3. Phone, network on, cold launch. Expect: «انتهت الجلسة».
4. Then airplane mode + cold launch. Expect: the login screen.

## 9. Fingerprint lock

1. Cold launch offline with a valid copy: the lock prompt appears first.
2. Background the app for 5+ minutes, return: the lock prompt again.
3. Background under 5 minutes: no prompt.
4. On the offline-expired screen (step 5): no prompt.

## Report back

For each step: pass/fail, the screen you saw (a screenshot if it failed),
and the time.

## Later: the real server

Deferred until the owner deploys (see `Leader_backend/docs/DEPLOYMENT.md`):
the server must run commit `6ec4a08` or later (it returns `sessionId`), pass
the pre-deploy checks (`JWT_SECRET` 32+ characters, `NODE_ENV=production`,
`REFRESH_TOKEN_TTL_DAYS` value), and have SMTP configured. Then rebuild the
APK with `LEADER_API_BASE_URL=http://5.189.132.216:22721` and repeat this
checklist. On the server, "server error" is `systemctl stop mongod` and the
database shell is
`ssh -t -p 22720 root@5.189.132.216 'mongosh --port 22722 -u mongo_admin --authenticationDatabase admin leader'`.
