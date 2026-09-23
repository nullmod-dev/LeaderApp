# DATA-NEEDS

A requirements log for the backend developer. **This is not an API design.**
There are no endpoints, no verbs, no payloads, no status codes here — only what
each screen shows, what the user can do on it, and when the screen needs fresh
data. How that is served is entirely the backend developer's decision.

Maintained by the frontend developer. Updated at the end of every page in the
per-page loop.

Legend for **State**: `built` = screen exists; `stub` = compiling placeholder
only (Batch 0 item D); `planned` = not yet created.

Entity and field names are the frontend's current domain vocabulary. Where the
new app invented a value set that the legacy program did not have, it is flagged
— see LEGACY-EXTRACTION-REPORT.md §5.

---

## 1. Entities in the domain today

| Entity | Fields the UI reads | Notes |
|---|---|---|
| **AuthUser** | id, name, email, role, saasTenantId, capabilities, orgName, avatarInitials | `role` is `super_admin` / `main_admin` / `admin` and selects the **product surface**; `capabilities` is what authorizes actions inside it (CAPABILITIES.md §5). `saasTenantId` is null for `super_admin` and required for the other two — an account breaking that pairing is refused, never repaired. See API_CONTRACT.md § AuthUser. |
| **Session** | id, device, ipMasked, locationLabel, startedAt, current | Shown on the security screen. IP is masked before it reaches the client. |
| **MfaSetupData** | otpauthUrl, manualSecret, backupCodes | Issued by the server. The client must never generate a TOTP secret. |
| **DetachmentGroup** | id, name, createdAt, notes, status, and three **derived** roll-ups (detachmentCount, memberCount, coveragePercent) | The umbrella several detachments sit under. **Not** the SaaS tenant — see API_CONTRACT.md § Terminology. Called `Tenant` before the Point 1 rename. |
| **Detachment** | id, detachmentGroupId, name, region, mainCenter, memberCount, weeklyShiftCount, coveragePercent, status, notes | `status` values pending your ruling. `detachmentGroupId` names the group it was created inside; there is no unfiled detachment. |
| **DetachmentStats** | attendanceSeries[7], coverageSeries[7], stockSeries[7] | Last 7 days, oldest first. |
| **TeamMember** | id, name, initials, role, detachmentId, attendance, phoneMasked | `detachmentId` is **scalar** — the model currently assumes one detachment per person. See open decision #2. |
| **Shift** | id, detachmentId, centerName, startHour, endHour, assigned, needed, hasCoverageGap, attendees[] | Current model is a single dated shift. The legacy model is a weekly template plus dated occurrences — richer, and the rules are already proven. Reconciling these is part of the scheduling redesign. |
| **InventoryItem** | id, detachmentId, name, unit, currentStock, minimum, expiresOn, level | New module, no legacy source. |
| **InventoryMovement** | id, itemId, direction, quantity, reason, at | |
| **Workshop** | id, name, at, location, capacity, registered, guests, status, organizingTeam[] | Legacy adds a **registration fee** and derives status from the date rather than storing it. |
| **WorkshopParticipant** | id, workshopId, name, initials, kind, attendance | Legacy also carries a section assignment and a tri-state payment status. |
| **HomeSummary** | detachmentName, centerName, activeShift, lockRemaining, attendancePresent, attendanceTotal, decisions[], workshopsThisWeek, attendanceRatePercent, stockLowCount | |
| **HomeDecisionItem** | id, kind, title, subtitle, actionLabel | kind: unfilled shift / expiring stock / join request. |
| **AppNotification** | id, kind, occurredAt, count, recordLabel, target, isRead | The Notifications Center. **Derived, not stored** — no backend emits these yet, so the client joins shift + inventory records and its own outbox. `id` must be stable per condition: read state is keyed by it. |
| **NotificationPrefs** | shiftReminders, stockAlerts, workshopUpdates, joinRequests | Personal, per-user. |
| **Announcement** | id, text, detachmentIds, placements, publishedAt, expiresAt, status, authorName | Internal admin notice, **not** advertising and never seen by volunteers. **Stored, not derived** — unlike `AppNotification`, this is a record a person wrote, so nothing else in the app can produce it. No backend serves it yet; the client ships a repository seam and a mock. Plain text only: no shift/member/item reference, no attachment. `detachmentIds` is never empty and has no wildcard. `expiresAt` is always finite. |
| **OrgInfo** | name, legalName, address, emailPublic, detachmentCount, memberCount | |

### Entities the legacy program has that this domain does not model yet

Raised for your decision, not assumed:

- **Workshop section** — an optional grouping of a workshop's people.
- **Workshop payment status** — paid / unpaid / unspecified, per person.
- **Workshop team member** — distinct from a participant, carries a role.
- **Shift occurrence** — a dated instance of a weekly shift, cancellable as a
  tombstone.
- **Shift roster vs per-date attendance** — two separate lists, deliberately.
- **Attendance correction** — an append-only record a session with
  `shift.attendance.override` adds once the one-hour ordinary edit window has
  closed. Never edits or removes an earlier entry or the original attendance
  row; the current (effective) attendance is a value derived by applying
  every correction in order, not a second copy the two could disagree on. See
  `FRONTEND-BACKEND-INTEGRATION.md` §6 (Task 5).
- **Patient** — a detachment's patient register. See open decision #8.
- **Member specialty and phone** — legacy member fields with no equivalent here.

---

## 2. Screens

### 2.1 Authentication (outside the main shell)

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger |
|---|---|---|---|---|---|
| Login `/login` | built | — | email (email only — no username identity, Point 18B), password; Google as a full-width alternative; forgot password; sign-up; Customer Demo while globally enabled | Sign in, continue with Google | None. Submits on demand. In a **debug build only**, a secondary «حسابات التجربة» section offers the three development personas — absent from any release artefact (see §5). |
| MFA setup `/mfa-setup` | built | MfaSetupData | otpauthUrl (as QR), manualSecret, backupCodes | Copy secret, copy backup codes, confirm setup | Once on entry. Never re-fetched — a second fetch would issue a different secret. |
| MFA challenge `/mfa-challenge` | built | — | 6-digit code | Verify code | None. |
| Forgot password `/forgot` | built | — | email | Request reset | None. |
| OTP `/otp` | built | — | email, 6-digit code | Verify code, resend | None. Resend is user-initiated. |
| New password `/new-password` | built | — | new password | Set password | None. |
| Session expired `/session-expired` | built | — | — | Sign in again | Entered when the session is rejected. |
| New device `/new-device` | built | — | device description | Confirm "it was me" / "it wasn't me" | Entered on an unrecognised-device signal. |

**Capability note:** none of these are capability-gated. They are pre-session.

### 2.1a Sign-up / onboarding — Point 17A foundation, Point 17B screens, Point 17C closure

Typed in `features/auth/domain/onboarding_models.dart`; contract in
`API_CONTRACT.md` → "Sign-up and onboarding — Point 17A foundation, Point 17B
integration, Point 17C closure". **Point 17C closed 17B's storage gap:**
`flutter_secure_storage ^10.3.3` ships behind `SecureStore` /
`SecureAuthStateStore`, so "secure storage" below is what the build does
today. Two versioned, mutually exclusive records —
`mtm.auth.onboarding.v1` (challenge, or restricted token + display-only
snapshot) and `mtm.auth.full_session.v1` (opaque token) — survive a real
process kill/relaunch; a corrupt or unknown-version record is deleted, never
trusted. Google identity comes from `google_sign_in ^7.2.0`; its ID token is
sent once and never stored.

| Data | Source | Fields the client reads | Kept where | Never |
| --- | --- | --- | --- | --- |
| **Auth identity snapshot** (`OnboardingSnapshot`) | `GET /auth/onboarding` under the restricted onboarding session; also in sign-in / verify / link responses | `accountId` (canonical, provider-independent), own normalized `email`, `methods[]` (`password`/`google`; unknown dropped), `accountStatus` (the envelope's `AccountStatus`), `linkStatus` (`unlinked`/`linked`/`withdrawn`), `setupStatus` (`required`/`completed`), `tenant{displayName, role, tenantStatus}` only when linked, `displayNameSuggestion`, `authorizationExpiresAt` | memory; the **last** snapshot is kept beside the restricted token in secure storage (`mtm.auth.onboarding.v1`) so an offline relaunch routes to the right step (read-only, `stale`); an online restore always re-reads it | tenant id, Team Code, counts, Main Admin identity, capabilities, any operational datum |
| **Verification state** (`VerificationChallenge`) | sign-up, password sign-in to an unverified account, Google with an unverified address, resend | `challengeId` (opaque handle), `maskedEmail` (server-masked), `codeLength`, `expiresAt`, `resendAvailableAt`, `attemptsRemaining` | handle in **secure storage** only (restart → `/verify-email`); discarded on success, abandon, end | the code itself, anywhere |
| **Tenant-link state** | snapshot `linkStatus` + `tenant` | see above | memory / snapshot | the Team Code after the request — not in state, Drift, prefs, logs, analytics, crash reports, outbox |
| **Setup state** | snapshot `setupStatus`, `displayNameSuggestion`, `authorizationExpiresAt` | display name suggestion (inviter's name › Google profile name › none) | memory | terms/privacy acceptance (deferred) |
| **Auth-provider information** | snapshot `methods[]` | which methods sign this account in | memory | Google ID token (sent once), any provider secret |
| **Invitation / setup metadata** | snapshot only | role, tenant display name, expiry | memory | invitation id or token — the client never receives one. **17C:** the backend resolves a valid Simple Admin invitation for the verified address on every sign-in / verify / `GET /auth/onboarding`, so `/link-team`'s "check for my invitation" needs no extra field; "no invitation yet" is inferred from `linkStatus ≠ linked`, never from an existence flag |
| **Server timestamps** | challenge + snapshot | RFC 3339 with offset; read with the injected clock for display only | — | `DateTime.now()` in domain logic; local-time instants |
| **Rate-limit / retry metadata** | `429`/refusals → `OnboardingFailure.retryAvailableAt`, `attemptsRemaining` | absolute instant (converted from `Retry-After` at receipt) | memory | any client-side security throttle standing in for the server's |
| **Startup decision inputs** | `StartupInputs.entry` (`AuthEntryState`: none / restoring / verification pending / onboarding / invalid) | consulted only when there is **no full session** | memory (`onboardingControllerProvider`) | a password, code or Team Code |

Offline: every trust transition (sign-up, sign-in, Google, verify, resend,
link, setup, reset) is **online-only** and returns `Offline`; nothing is
queued. See HANDOFF "POINT 17A".

### 2.1b Startup and session states — 2026-09-07 (Point 3)

Every destination the startup classifier
(`core/startup/startup_destination.dart`) can send a launch to. All are
outside the main shell — none instantiates the tenant bottom nav or reads any
tenant repository, which is what keeps a blocked or platform session from
touching operational data at all.

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger | Offline / cache | Backend fields required |
|---|---|---|---|---|---|---|---|
| Startup `/startup` | built | — | none — the app mark and one line of copy | none | The app's `initialLocation`; left automatically the moment the session read lands | Fully local. It covers a **local** restore and says nothing about the network | none |
| Session invalid `/session-invalid` | built | — | none — the refused account is deliberately not rendered | Sign out, contact support | Entered when `AuthUser` fails the role/`saasTenantId` invariant | n/a — no session to cache | none (it is the *absence* of a valid payload) |
| **Unsupported access state `/session-unsupported`** | **built (2026-09-08)** | AuthUser | name, role label | Sign out, contact support | Entered when any `SessionAccess` gating property carries a value this build cannot parse | Blocking; nothing is cached or rendered from the refused envelope | the *presence* of an unrecognised `accountStatus` / `tenantStatus` / `demoMode` / `mfaRequired`. See `API_CONTRACT.md` §"Absent vs. present-but-unknown" |
| Access not assigned `/access-not-assigned` | built | AuthUser | name, role label | Sign out | Entered when the session holds no capability at all; re-evaluated whenever the grant changes | Works from the cached session; nothing else is read | `capabilities` (empty) — **and nothing else may be inferred from it** |
| Account suspended `/account-suspended` | built | AuthUser | name, role label | Sign out, contact support | `accountStatus` on the session read | Blocking; no tenant data beneath it | `SessionAccess.accountStatus = suspended` |
| Account revoked `/account-revoked` | built | AuthUser | name, role label | Sign out, contact support | `accountStatus` on the session read | Blocking; terminal, never phrased as an offline failure | `SessionAccess.accountStatus = revoked` |
| Tenant suspended `/tenant-suspended` | **implemented (Point 9)** | — | generic FULL BLOCK status; no organisation or internal reason | Sign out, contact support | session/lifecycle refresh and live mock lifecycle revision | Shell and operational repositories do not open. Suspension does not erase cache/data, subscription, features, capabilities, or limits | `SessionAccess.tenantStatus = suspended`; server rejects protected requests |
| Tenant deletion pending `/tenant-deletion-pending` | **implemented (Point 9)** | — | generic scheduled-deletion block only; no internal reason, tenant record, or invented schedule | Sign out, contact support | session/lifecycle refresh and live mock lifecycle revision | **FULL BLOCK**; no operational mutation or deep-link bypass; pending is not physical deletion | `SessionAccess.tenantStatus = deletion_pending`; authoritative schedule stays on the restricted platform tenant resource |
| Tenant deleted `/tenant-deleted` | **implemented (Point 9)** | — | terminal tenant-relationship copy only; no tenant/account conflation | Sign out, contact support | session/lifecycle refresh; final state fails closed | No cached tenant data is rendered. Future final-state reception must trigger the approved local cache/access-mapping invalidation policy | `SessionAccess.tenantStatus = deleted`; server rejects every tenant operation and unlinks sessions/access mappings |
| Verify email `/verify-email` | **built (Point 17B)** | — | masked email, code field, attempts remaining | Confirm, resend (cooldown), use another email (abandon), sign out | `EntryVerificationPending` | Offline notice; code kept, not submitted. The handle survives a real relaunch (secure storage, re-validated online — Point 17C) | `VerificationChallenge` (§2.1a) |
| Link team `/link-team` | **built (Point 17B; 17C invitee exit)** — Team Code path for a Main Admin seat; a valid Simple Admin invitation auto-links and never reaches it | — | Team Code field, withdrawn notice, invitation hint, neutral "no invitation yet" answer | Link, **check for my invitation** (re-reads the snapshot; links a now-valid invitation), sign out, contact support | onboarding snapshot `linkStatus` ≠ `linked` | Offline notice; code never persisted | `OnboardingSnapshot` (§2.1a) |
| Account setup `/account-setup` | **built (Point 17B)** | onboarding snapshot tenant/role; `AuthUser` (full-session case only) | tenant name, role label, display name (prefilled) | Complete setup, retry (setup-already-complete race), sign out, contact support | onboarding snapshot linked + setup; or `accountStatus = pending_setup` on a full session | Offline notice | snapshot `setupStatus`/`displayNameSuggestion` (§2.1a), or `SessionAccess.accountStatus = pending_setup` |
| Demo `/demo` | built (holding state) | — | none | Sign out | `demoMode` on the session read | Isolated by construction: no `saasTenantId`, no tenant repository | `SessionAccess.demoMode = active` |
| Demo expired `/demo-expired` | built | — | none | Sign out, contact support | `demoMode` on the session read | Blocking; no mutation, no tenant route | `SessionAccess.demoMode = expired` |
| Platform surface `/platform*` | **built (Points 4–5)** — see §2.6 | AuthUser + overview aggregate on `/platform` | platform-wide summaries only | navigate the four platform areas; refresh overview; open existing section landings | Entered for `super_admin`; overview refreshes on first read and explicit/pull refresh | mock can demonstrate process-memory cache; no durable platform cache exists | none in `Cap` — platform authorization is undesigned |
| Session-state inspector `/dev/session-states` | built, **debug only** | — | typed forced startup/access states, including deletion pending | Force a state and let the router re-decide | Development tool. Absent from any release artefact | n/a | none — it writes a client-side override, never a server fact |

**Sensitive data that must not be cached or rendered on any of these.** No
email address, no organisation name, no capability grant and no tenant record
appears on a blocked state — only the account's own display name and account
type, and only where knowing which account is held explains the screen. The
refused-payload screen shows not even that. Nothing on any of them is written
to local storage.

**Capability note:** none of these are capability-gated either. They are
*surface* decisions — see `CAPABILITIES.md` §5b.

### 2.2 Home

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger |
|---|---|---|---|---|---|
| Home `/home` | built | HomeSummary, HomeDecisionItem, Shift | detachmentName, centerName, active shift with its remaining lock time, present/total attendance, decision list, workshops this week, attendance rate, low-stock count | Act on a decision item (navigates), pull to refresh | On first open; on pull-to-refresh; on app resume; **when the active detachment changes**; after any action taken from a decision item. Point 8 omits Inventory/Statistics/Announcements quick actions and inventory alerts before loading when their tenant feature is disabled. |
| Global Search `/search` | built | typed search hits from allowed source repositories | category, title, subtitle, safe destination metadata | search, filter by the remaining allowed categories, open result | Query changes. Point 8 evaluates tenant features before source construction/loading: disabled Inventory contributes neither repository read, category nor result. Other selected optional modules are not current search sources. |

**Open:** what Home shows when the user belongs to several detachments is
unresolved — see DETACHMENT-SCOPING.md §4 and open decision #6.

### 2.3 Detachment groups and detachments

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger |
|---|---|---|---|---|---|
| Detachment group list `/detachment-groups` | built | DetachmentGroup | name, notes, status, detachmentCount, memberCount, coveragePercent | Search by name, open a group, create a group | On first open; on pull-to-refresh; after creating, editing, or deleting a group. |
| New / edit detachment group `/detachment-groups/new`, `/detachment-groups/:groupId/edit` | built | DetachmentGroup | name, notes | Save, cancel, delete (edit only, destructive — removes the group and every detachment inside it) | Loads the group once when editing. |
| Detachments inside a group `/detachment-groups/:groupId` | built | DetachmentGroup, Detachment | group name; then each detachment's name, region, mainCenter, memberCount, weeklyShiftCount, coveragePercent, status | Open a detachment, create a detachment **in this group** | On first open; on pull-to-refresh; after any detachment create/edit/archive. |
| Detachment list `/detachment` | built | Detachment | name, region, mainCenter, memberCount, weeklyShiftCount, coveragePercent, status | Search by name/centre/region, filter by status, open a detachment | On first open; on pull-to-refresh; after creating, editing, or archiving a detachment. |
| New / edit detachment `/detachment-groups/:groupId/detachment/new`, `/detachment/:id/edit` | **stub** | Detachment | name, region, mainCenter, notes, status, detachmentGroupId | Save, cancel | Loads the detachment once when editing. A detachment is always created **inside a group**, so the create route carries `:groupId`; there is no top-level `/detachment/new`. |
| Detail shell `/detachment/:id/...` | built | Detachment | name, status | Switch tab | Loads the detachment header once per detachment id. |
| Team tab `/detachment/:id/team` | built | TeamMember | name, initials, role, attendance, phoneMasked | Assign role, set attendance, open member | On tab open; on pull-to-refresh; after any role or attendance change. |
| Shifts tab `/detachment/:id/shifts` | **stub** | Shift | centre, start/end hour, assigned vs needed, coverage gap, attendees | Assign a volunteer, record attendance, create/edit a shift | On tab open; after any assignment or attendance change; **when the date or week in view changes**. |
| Storage tab `/detachment/:id/storage` | **stub** | InventoryItem | name, unit, currentStock, minimum, expiresOn, level | Record an inflow/outflow movement, open an item | On tab open; after any movement is recorded. Requires tenant feature `inventory`; the tab is omitted and direct routes render the feature-disabled state when unavailable. |
| Stats/report routes `/detachment/:id/stats`, `/detachment/:id/report*` | **stub/built as before** | DetachmentStats / report projection | attendance / coverage / stock series and report fields | read/export according to the existing capability guard | On tab open; on pull-to-refresh. Requires tenant feature `statistics_reports`; no hidden export side route bypasses it. |

**Every screen from the detail shell down is scoped by detachment id.** No
inventory or schedule screen is reachable without one. See DETACHMENT-SCOPING.md.

### 2.4 Workshop

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger |
|---|---|---|---|---|---|
| Workshop routes `/workshop*` | **stub** | Workshop and its existing detail projections | name, date, location, capacity, registered, guests, status | Existing list/create/edit/team/member actions | On first open; on pull-to-refresh; after create/edit/archive. Requires tenant feature `workshops`; the shell destination is omitted and every direct/nested route is rejected safely. Existing records remain stored and reappear after re-enable subject to capability. Workshop statistics additionally require `statistics_reports`. |
| New / edit workshop `/workshop/new`, `/workshop/:id/edit` | **stub** | Workshop | name, date, location, capacity (legacy also: registration fee, active flag) | Save, cancel | Loads the workshop once when editing. |
| Detail shell `/workshop/:id/...` | **stub** | Workshop | name, date, status | Switch tab, archive | Loads the workshop header once per workshop id. |
| Team tab `/workshop/:id/team` | **stub** | TeamMember | name, initials, role, attendance | Set attendance, edit role | On tab open; after any change. |
| Members tab `/workshop/:id/members` | **stub** | WorkshopParticipant | name, initials, kind (member/guest), attendance (legacy also: section, payment status) | Set attendance, add, edit, remove | On tab open; after any change. |
| Stats tab `/workshop/:id/stats` | **stub** | Workshop, WorkshopParticipant | totals, present count, attendance % (legacy also: paid/unpaid/unspecified per group) | — (read only) | On tab open. |

### 2.5 More / settings

Reorganized into a navigation hub plus four nested category screens (Point 1
of the Settings IA pass). No new backend data: every nested screen reads and
writes the same `SettingsRepository` methods the hub used to call directly.

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger |
|---|---|---|---|---|---|
| Settings hub `/more` | **built** | app preferences, sync status (for row summaries only), session grant | active palette/mode, active motion level/frame rate, pending/needs-review counts | Navigate to Themes, Performance, Sync, Profile, Security, Notifications, Organization; with `admin.manage`, open Simple Admin management; sign out | Row summaries follow the same providers the nested screens write to; no separate fetch. |
| Themes `/more/themes` | **built** | app preferences | one of six palettes, mode (light/dark/system), eye-protect | Change palette, mode, eye-protect | Theme preference is durably read from/written to `LocalStore`; changes take effect immediately. Unknown/corrupt names fall back without wiping other settings. |
| Performance `/more/performance` | **built** | app preferences | motion/quality level, frame-rate preference | Change motion level, change frame rate | Preferences read once at start-up; changes are written immediately and take effect without restart. |
| Sync `/more/sync` | **built** | local outbox (pending/needs-review counts, last sync time) | pending count, needs-review count, last-synced time | Trigger a manual sync, open Needs Review | On open; after any sync run (manual or automatic). |
| Profile `/more/profile` | **built** | AuthUser | name, email, orgName, avatarInitials | Edit own profile | On open. |
| Security `/more/security` | **built** | Session | device, ipMasked, locationLabel, startedAt, current | End another session, start MFA setup, start a password reset by email, sign out | On open; after a confirmed revoke. Two-step-verification state is **not** available — `AuthUser` carries no MFA field and no endpoint reports one, so the screen shows it as unknown rather than claiming it. There is no authenticated change-password endpoint either, so the password action is the reset-by-email flow. Ending the *current* session is sign-out; `DELETE /auth/sessions/{id}` refuses it with `validation`. |
| Notifications `/more/notifications` | **built** | NotificationPrefs | shiftReminders, stockAlerts, workshopUpdates, joinRequests | Toggle each preference | On open. Each toggle persists immediately. |
| Notifications Center `/notifications` | **built** | AppNotification (derived from Shift + enabled Inventory, enabled Announcement, and the local outbox) | kind, occurredAt, count, recordLabel, target, isRead | Open the record behind a row (existing shift sheet / detachment tab / Needs Review / Sync); mark one read; mark all read | On open, and whenever the outbox, read state or feature revision changes. Point 8 excludes disabled Inventory and Announcement sources before loading/merging; it does not leak their record payload or destination. Generic local sync/conflict rows remain because they contain user-owned system state, not disabled-module records. |
| Organization `/more/organization` | **built (Point 15)** | `OrganizationSnapshot` via read-only `OrganizationRepository.readCurrent()` (tenant from the bearer) | tenant display name, opaque tenant id (support reference, LTR, copyable), lifecycle status, subscription status, plan, created date, Main Admin display name | Open Plan; contact support (About); copy the reference. No edit of any kind | On open; pull to refresh; explicit refresh of a cached copy. No polling | loading; offline cached (notice + `readAt` + refresh); refresh-failed (stale) cached; offline without cache; context unavailable (demo/platform); failure + retry; unknown lifecycle/status/plan shown as unknown. **Never:** Team Code, Main Admin email/state, reasons, secrets. `/more/org` redirects here; the pre-SaaS `OrgInfo` page is gone |
| Plan & subscription `/more/plan` | **built (Point 15)** | same `OrganizationSnapshot` + `currentTenantFeatureAccessProvider` | plan (Basic/Standard/Advanced/none/unknown), subscription status + its one relevant date + neutral note, per-key effective limit (`override ?? default`, backend-computed), plan default + override marker, usage (only with `org.edit`), at/over-limit in words, four modules enabled/disabled | Contact support (About). No billing, upgrade, change or toggle | As Organization; modules follow the runtime feature revision | as Organization, plus: no-plan (no limits drawn, never "unlimited"), usage withheld note, unknown limit keys counted, omitted known key "unavailable", unreadable entitlement stated rather than drawn disabled. **Backend owes:** the tenant organisation read, a real `admins` usage aggregate (mock is a fixed 1) and server-side usage withholding |
| Simple Admin management `/more/simple-admins` | **built** | current Simple Admin accounts + invitation records | normalized email, suggested/display name, status, selected capability keys, expiry, revisions | invite, cancel pending invitation, edit an existing Simple Admin grant | On open and after each successful mutation; backend later owns delivery, expiry and audit. Commands never contain tenant/role/password/activation; tenant and `AuthRole.admin` derive server-side. |

### 2.6 Platform — Super Admin (Points 4–8)

`super_admin` only, inside `PlatformShell`. The overview reads exactly one
`PlatformOverviewRepository`; the other rows read the session or local app
preferences. **No platform row reads a tenant-operational repository** — no
detachment, detachment group, team, shift, inventory or workshop repository —
which is asserted by focused tests.

Point 4 built the shell; Point 5 added the first typed aggregate read; Point 6
adds the `SaasTenant` subscriber module; Point 7 adds the separate commercial
subscription, plan and limit module; Point 8 adds tenant product features.
**The Point 5 overview's tenant
buckets and the Point 6 list are now counted from one canonical dataset**, so a
subscriber registered on the list changes the number on the overview without a
restart — see `platform_tenant_store.dart`.
Its mock is deterministic through `Clock` and populated for the developer Super
Admin persona. Platform feature writes change only explicit entitlement rows in
that canonical process-memory store; they do not mutate lifecycle,
subscription, plan, limits or operational module data.

| Screen | State | Entities displayed | Fields used | Actions | Refresh trigger | Offline / cache | Backend fields required |
|---|---|---|---|---|---|---|---|
| Platform shell (`/platform*`) | **built** | — | the four destination labels, the selected one | Switch area; open the account screen from the header | None — it reads no data. The selected destination follows the route | Nothing to cache | none |
| Platform overview `/platform` | **built (Point 5; Point 10 canonical health/security projection)** | `PlatformOverviewSnapshot` | `generatedAt`; tenant totals and separate active/trial/grace commercial buckets, suspended/deletion-pending lifecycle counts; active Simple/Full/expiring demos; typed health/attention/activity; optional storage | pull/action refresh; lifecycle opens tenant detail; health/security open their real Point 10 modules | initial read; explicit/pull refresh; invalidated after lifecycle success; no aggressive polling | existing loading/minimal/offline/cached/stale/failure states | future `GET /platform/overview`; health signals and security attention are projected from the same canonical Point 10 fixture/source, not separate hard-coded values. Lifecycle counts remain separate from commercial status |
| SaaS tenants `/platform/tenants` | **built (Point 6; Point 9 lifecycle-aware)** | `SaasTenantPage` via `SaasTenantRepository.list(SaasTenantQuery)` | team, lifecycle-precedence status, Main Admin, relevant subscription date, Team Code, matched total | search/filter/open/register; separate commercial/access filter labels; lifecycle commands remain on detail | first read; query/debounce/pull; invalidated after create or lifecycle success | existing list/offline/cache/failure states | `GET /platform/tenants?search&status&cursor&limit`; lifecycle filters distinguish suspended and deletion-pending without deriving either from subscription. Deleted tombstones never appear as normal rows |
| Tenant create `/platform/tenants/new` | **built (Point 6)** | `SaasTenantDraft` → `SaasTenantRepository.create` | team name, Main Admin name, Main Admin email, Team Code (pre-filled with a deterministic suggestion, editable) | register the subscriber. No plan, limit, flag or initial-status control | writes once; success invalidates the list **and** the Platform Overview aggregate | idle; per-field validation; duplicate Team Code; **offline is refused, never queued** (there is no endpoint a queued write could reach); repository failure with everything typed kept; submitting (guarded against a double submit in the controller); success → the new subscriber's detail | `POST /platform/tenants`. **Sensitive:** the response must carry no password, temporary password, OTP or token. Point 8 requires the backend creation workflow to also persist an explicit feature row for every known key; the current deterministic default enables only Inventory and Announcements and is not plan-derived |
| Tenant detail/lifecycle `/platform/tenants/:tenantId` | **implemented (Point 9)** | live `SaasTenant`/lifecycle/history or a distinct minimal `DeletedTenantTombstone`; typed commands/results | legal state-specific actions; suspension time/reason; deletion request/schedule/stable remaining-day context/exact previous state/reason; tombstone shows only name snapshot, ID, deleted time | suspend/reactivate/begin/cancel/finalize with concise typed consequence confirmation; required 280-character reasons where defined; final deletion uses a non-dismissible second step, exact name, and irreversible acknowledgement | reads on open/pull; every success refreshes detail/history/list/overview/subscription/limits/features and runtime lifecycle revision; stale/window/boundary conflicts refresh current detail | full existing read states; writes refuse offline and are never queued; draft reason is retained for retry; duplicate submit blocked; all typed failures use safe localized copy | existing detail/history plus five Point 9 lifecycle endpoints. Require `expectedVersion`, `Idempotency-Key`, atomic stale protection, server authorization/enforcement, authoritative schedule, and a restricted typed tombstone read/reload seam. Final deletion is backend-controlled; Team Code retires |
| Tenant subscription `/platform/tenants/:tenantId/subscription` | **built (Point 7)** | `TenantSubscriptionDetails` + `List<SaasPlan>` through `TenantSubscriptionRepository` | tenant context; commercial status distinct from tenant access; explicit plan assignment/no-plan; version; trial/renewal/grace dates; current plan description and focused limit preview | activate administratively; extend/end trial; move active subscription to grace; select/change plan; open usage and limits. Every consequential action confirms what changes and what does not | open; pull refresh; successful mutation invalidates subscription, tenant detail/list/history and Platform Overview | loading; loaded; tenant not found; subscription unavailable; stale/cached marker; offline with/without copy; safe failure/retry. Writes are refused offline and never queued; form/selection remains local | future `GET /platform/tenants/{id}/subscription`, `GET /platform/plans`, and Point 7 mutation endpoints. `expectedVersion` + `Idempotency-Key`; typed transition/stale errors; no payment-provider claim. **Sensitive:** commercial configuration, Super Admin only. Deterministic 3-plan mock and trial/active/grace/inactive scenarios; repository/controller/widget tests |
| Tenant limits `/platform/tenants/:tenantId/limits` | **built (Point 7)** | `TenantLimitsSnapshot`: selected `SaasPlan`, plan defaults, tenant overrides, typed `TenantPlanUsage` | usage and effective value beside every typed key: detachment groups, detachments, admins, members, workshops, storage bytes; override/default indicator; safe ratio including zero/over-limit | edit an override; reset to plan default; confirm when proposed limit is below usage. No tenant-operational create guard is implemented here | open; pull refresh; successful save invalidates this projection and all related platform reads | loading; loaded; explicit no-plan; usage unavailable; tenant not found; offline; safe failure. Offline writes are refused and not queued | future `GET /platform/tenants/{id}/limits`, `PATCH .../limits/{limitKey}`. Effective value = override ?? default. Accepting below-usage never deletes existing data; backend later rejects additional creates with `plan_limit_reached`. Storage is bytes on wire. **Sensitive:** commercial capacity/aggregate usage, Super Admin only. Deterministic overrides/near-limit/below-proposal mock and widget tests |
| Tenant features `/platform/tenants/:tenantId/features` | **built (Point 8)** | `TenantFeatureSet` from `TenantFeatureRepository` | tenant name; canonical Arabic label/description/consequence; boolean enabled state; per-feature version and updated time | enable directly; disable after consequence-specific confirmation. Existing module data is explicitly retained | open; pull/retry; successful mutation invalidates this projection and increments the live tenant feature revision | loading; tenant not found; feature-state unavailable; failure/retry; offline with cached state is visibly read-only; offline without state; stale mutation refresh. Writes are refused offline, never queued, and duplicate actions are controller-guarded | future `GET /platform/tenants/{id}/features`, `PATCH .../features/{key}` using `expectedVersion` and `Idempotency-Key`. Unknown/missing/unsupported state fails closed. Backend is authoritative and must return `feature_disabled` from disabled module APIs independently of Flutter navigation. **Sensitive:** tenant product entitlement, Super Admin only; no operational repository is initialized to render it |
| Platform operations `/platform/operations` | **implemented (Points 10–12 landing)** | Break-glass current-state summary through the session-bound provider | five real modules: Platform Health, Platform Security, Audit, Emergency Access and Reports (Point 13 complete) | open a real module | Break-glass summary follows the current session grant | loading summary fails closed to no usable access | no tenant-operational repository |
| Platform Health `/platform/health` | **implemented (Point 10)** | `PlatformHealthSnapshot` through `PlatformHealthRepository` | `generatedAt`, `isPartial`; exactly the established identity/background-jobs/files signals with id, safe label/summary, typed status and `observedAt`; pure overall selector | explicit/app-bar refresh and pull-to-refresh; no mutations | initial read and explicit refresh only; no polling/live claim | fresh/stale success; offline with process-memory cached snapshot; offline without cache; safe failure; partial remains usable | future `GET /platform/health`; UTC timestamps, `healthy/degraded/unavailable/unknown`, partial semantics, unknown fail-safe, Super Admin authorization, safe product-level copy only |
| Platform Security `/platform/alerts` | **implemented (Point 10, read-only)** | `PlatformSecuritySnapshot` through `PlatformSecurityRepository` | `generatedAt`; current alert id, severity, authentication/unknown category, safe title/description, `detectedAt`, optional validated platform-safe tenant/tombstone reference | refresh; open an existing Platform tenant detail/tombstone only; no acknowledge/resolve/assign | initial read and explicit refresh only; no polling/live claim | alerts/no-alert/mixed/unknown; stale; offline cached/no-cache; safe failure | future `GET /platform/security-alerts`; severity/category fail-safe, Super Admin authorization, optional safe tenant reference, tombstone privacy. No Point 11 audit fields or mutations |
| Platform Audit `/platform/audit` | **implemented (Point 11)** | `PlatformAuditPage` through read-only `PlatformAuditRepository.listAuditEvents(PlatformAuditQuery)` | immutable event id/UTC time; historical administrator/system identity; localized action/category/target; optional minimized tenant/tombstone; typed redacted before/after detail | debounced safe search; progressive filter sheet; load more; event detail; validated Platform tenant navigation; no mutations/export | initial read, explicit/pull refresh; repository query changes reset cursor; stable pages append without duplicates; local date bounds convert to exact UTC instants | structured initial loading; no events distinct from no matches; stale and offline cached/no-cache; refresh/page failures preserve available rows; safe invalid-cursor recovery | future `GET /platform/audit?from&before&actorKind&actorId&action&category&tenantId&targetType&search&cursor&limit`; search safe identity/label fields only, never changes. Server authorization, authoritative append, pre-persistence sanitization, and authorized current/tombstone reference resolution required. No passwords/OTPs/tokens/secrets/session material/Team Codes/request bodies/medical records. Retention remains backend policy; tenant deletion does not automatically erase minimized audit or permit reconstruction |
| Break-glass access `/platform/access` + `/platform/access/request` | **Point 12 frontend complete** | `BreakGlassSnapshot` through `PlatformBreakGlassRepository`; derived `BreakGlassAccessDecision`; active tenant candidates from Platform `SaasTenantRepository` only | current state first; minimal target display name; fixed read-only scope; platform-only reason; issued/expiry/end context with stable Clock-derived remaining time; verification state; accessible persistent shell strip | separate request (active tenant + required ≤280 normalized reason; duration omitted), exactly one activation confirmation, explicit end with one confirmation; no renewal and no tenant-data viewer | read on open/restart/after commands; `PlatformShell` keeps awareness across destinations; one-shot near-expiry/`expiresAt` reevaluation, never polling; token-based strip transition is immediate when animations are disabled | none/active/near-expiry/expired/ended/revoked/unsupported/tenant-unavailable/offline/stale/not-permitted/recent-auth-required/failure; cached possibly-live grant shown but unusable; commands online-only and never queued; duplicate submit blocked | future break-glass endpoints; backend independently enforces session binding, expiry, active target, scope, Feature Flags and Plan Limits and creates Audit evidence. **Gap:** dedicated grant-scoped read endpoints and approved content are required before any emergency tenant-data surface. **Sensitive:** reason remains Platform-only; no Team Code, Main Admin contact, commercial/operational/medical/credential/session data is exposed by management; nothing persists locally |
| Platform Reports `/platform/reports` + `/platform/reports/:reportType` | **IMPLEMENTED — POINT 13 COMPLETE (13A architecture, 13B core UX, 13C visual/accessibility closure, over the Point 13A mock; wire contract unchanged)** | `SubscriptionReport`, `UsageLimitsReport`, `FeatureAvailabilityReport`, `PlatformActivityReport` through read-only `PlatformReportsRepository` (four typed methods; no generic query) | every report: `type`, `generatedAt`, opaque `snapshotId`; typed summaries whose buckets sum to `tenantCount` with an explicit unsupported bucket. Subscriptions: commercial status × plan × lifecycle, server `relevantDate`. Usage: per key usage/effective limit/override/factual band. Features: enabled/disabled/unsupported per module. Activity: counts per Point 11 action in `[from, before)`, `evidenceAvailableFrom`. Tenant rows carry only tenant id + display name | catalogue → open one report; typed filters (status, plan, lifecycle, due-before, limit key, band, feature key/state, local date range, Audit category); load more with the opaque cursor; open `/platform/tenants/:id` from a row; open `/platform/audit` pre-filtered from an activity count; ≥900 dp dense-row/table alternative for the three snapshot reports and a small keys×bands summary table for usage limits (13C). **No export, no mutation, no custom report** | first read per query; explicit/pull refresh; filter change restarts at page one; page 2…n only from the same `snapshotId`; no polling, no live claim | loading; loaded; empty dataset; filtered-empty; stale (server `generatedAt` kept); offline with a cached first page (paging refused); offline without data; not permitted; safe failure; next-page failure keeps rows; `report_cursor_expired`/snapshot change → explicit reload; unsupported values; partial Audit coverage. Nothing queued; process memory only | `GET /platform/reports/{subscriptions,usage-limits,feature-availability,platform-activity}` (see `API_CONTRACT.md` → "Platform Reports — Point 13A foundation"). Server-computed aggregates only — never assembled by opening tenant operational stores; deleted tenants never rows; real `admins` usage aggregate owed. **Sensitive:** Super Admin commercial/entitlement aggregates; no Team Code, Main Admin contact, reason, credential, session, IP/device, member, medical or operational payload |
| Main Admin account `/platform/tenants/:tenantId/main-admin` (+ `/replace`) | **POINT 14 COMPLETE (14A foundation, 14B core UX, 14C visual/accessibility closure)** | `MainAdminAccountSnapshot` through `PlatformMainAdminRepository.load`; derived `MainAdminManagementView` (`mainAdminManagementProvider`) | tenant `{id, displayName, lifecycleStatus, lifecycleVersion}`; seat `revision`; current account `{accountId, displayName, loginEmail (LTR), status pending_setup/active/suspended, createdAt, activatedAt?, setup {outstanding/expired, lastSentAt, expiresAt?}?, suspension {suspendedAt, reason}?}`; optional replacement `{id, pending, designate {accountId, displayName, loginEmail, setup}, requestedAt, reason}` | tenant-detail summary → dedicated seat page; resend setup (current or designate); suspend (normalized Platform-only reason ≤280); reactivate; full-page replace (name + email + reason; immediate when the holder never activated, otherwise pending until the designate completes Point 17 setup); cancel replacement. Exactly one confirmation per command. Access-opening actions need an `active` tenant; suspend/cancel work on any non-deleted tenant | on open; after every command; on a Point 9 lifecycle revision; pull to refresh; no polling | loading/confirmed/pending/active/suspended/replacement-pending/expired; stale/offline cached read-only (read-only notice + `readAt` + refresh read, no action buttons); offline no-cache; typed not-permitted/failure/tenant-unavailable/recent-auth/stale/idempotency/unsupported; commands online-only, never queued; single-flight | `GET /platform/tenants/{id}/main-admin`; `POST …/main-admin/setup/resend`, `…/suspend`, `…/reactivate`, `…/replacements`, `…/replacements/{rid}/cancel` with `expectedRevision` + per-attempt `Idempotency-Key`; outcomes succeeded/stale/tenant-unavailable/rejected/recent-auth/not-permitted/offline/failed. **Session consequences (server-enforced):** suspend ends all sessions; replaced ends the former holder's sessions and revokes it; cancel ends the designate's. **Sensitive:** login emails + Platform-only reasons; never passwords, hashes, OTPs, MFA material, backup codes, reset/setup tokens, session lists, device/IP, Team Code |
| Platform More `/platform/more` | **built** | app preferences, session name | active theme/motion/frame-rate, eye-protect on/off, app version, signed-in name | Open Profile, Themes & Performance, Reading comfort, Security, About; sign out | Row summaries follow the same providers the nested screens write | Preferences are local | none beyond the account endpoints |
| Super Admin account `/platform/more/profile` | **built** (shared `ProfilePage`, platform form) | AuthUser | name, email, role label | Open Security; start a password reset; sign out | On open; pull to refresh | Stale badge / offline view from the cached session | `GET /auth/me`. **Must not** carry an organisation name or a tenant capability grant for this account — neither is rendered |
| Security & sessions `/platform/more/security` | **built** (shared) | Session | device, ipMasked, locationLabel, startedAt, current | End another session; start MFA setup; start a password reset; sign out | On open; after a confirmed revoke | Offline view | `GET /auth/sessions`, `DELETE /auth/sessions/{id}` — the account's own, identical on both surfaces |
| Themes & performance `/platform/more/themes` | **built** (shared) | app preferences | theme choice, motion level, frame rate | Change each | Written immediately | Local | `SettingsRepository` |
| Reading comfort `/platform/more/eye-protect` | **built** (shared) | app preferences | eye-protect on/off | Toggle | Written immediately | Local | `SettingsRepository` |
| About & support `/platform/more/about` | **built** (shared) | — | version, build identity, support addresses | Copy an address; open a link | None — constants | Fully local | none |

**Sensitive fields.** The shared account screens show only the Super Admin's
own account facts. The overview may carry aggregate commercial/health facts and
short customer-identifying activity/attention descriptions. It shows no tenant
medical/operational records, capability grants, secrets or token-shaped data.
The current dataset and cached-mode fixture are process-memory mocks only. A
future durable cache must not use ordinary preferences and needs an explicit
platform-sensitive storage policy.

**What Point 5 deliberately leaves later.** `GET /platform/overview` is read
only. Point 10 now supplies the separate detailed Health and Security reads;
Demo workspace/CRUD and the notification centre remain later work; Platform
Reports is now complete (Point 13A architecture, 13B core UX, 13C visual and
accessibility closure). Point
11 Audit and the Point 12 break-glass frontend are now implemented, with no
grant-scoped tenant-data read. A live grant adds no Overview attention item and
no Security alert — its awareness surface is the Operations row and the Point
12 persistent indicator.

---

## 3. Cross-cutting data needs

### 3.1 Every read needs a typed outcome

Every repository call returns one of exactly three outcomes, and every screen
renders all three:

- **success** — with a flag for "this came from cache after a background refresh
  failed", so the screen can show a subtle stale indicator rather than lying;
- **failure** — with a human-readable message and an optional machine code;
- **offline** — optionally carrying the last cached value.

This is already the shape of `Result<T>` in `lib/core/result/result.dart`. The
backend developer does not need to produce this shape; the client maps whatever
arrives onto it. It is listed here so the **failure taxonomy** can be agreed:
the client needs to distinguish at least *not found*, *not permitted*, *conflict*
(someone else changed it first), *validation rejected*, and *authentication
expired*, because each renders differently.

### 3.2 Freshness expectations, in plain terms

- **Attendance and shift assignment** are the most time-sensitive data in the
  app. Two people commonly edit the same shift at the same time. The client
  needs to know when its copy is stale.
- **Inventory stock levels** change during a shift and drive the low-stock
  warnings on Home.
- **Detachment, workshop, and member records** change rarely. Cached values are
  fine for a working session.
- **Organisation info and notification preferences** change almost never.

### 3.2b The one durable local store — 2026-09-07 (Point 3)

Until Point 3 this app had **no** durable local storage: `SettingsRepository`,
`AppVersionGateStore` and `DemoSessionStore` were all in-memory mocks that lost
their record on a process restart. `core/storage/local_store.dart` is now the
one mechanism (`shared_preferences` behind a three-operation `LocalStore`
seam), and the rule is that a second storage architecture does not appear
beside it. §3.3 below still governs *what* may go in it.

Only one thing is written there today: the **development** demo persona id
(`mtm.dev.demo_persona`), plus a presence marker that distinguishes a
never-used device from one that was signed out. A release configuration is
wired to a store that reads and writes nothing, so a record left behind by a
debug build is never even loaded.

### 3.3 What must never reach local device storage

Recorded here because it constrains what the client may cache, and the research
scope is mobile security (OWASP MASVS):

- Authentication tokens, refresh tokens, and the TOTP secret — secure storage
  only, never in ordinary preferences.
- Member phone numbers — currently only ever received masked, and that should
  stay true.
- Anything identifying the SaaS tenant/organisation, if the app becomes
  multi-tenant. This is the paying-customer and data-isolation boundary, not a
  `DetachmentGroup` — see API_CONTRACT.md § Terminology.

Non-sensitive UI preferences (theme, motion level, notification toggles, last
active detachment) are the only things written to ordinary local preferences.

---

### 3.4 Development demo accounts — frontend-only, and what the backend owes

Added 2026-09-07 (Point 2). **None of this is a backend request** except the
last table: it is how the frontend authenticates during development, recorded
so nobody mistakes it for product behaviour.

### The three personas

Three development accounts, one per account level, in
`lib/features/auth/data/demo_personas.dart`:

| Persona | `role` | `saasTenantId` | Grant |
|---|---|---|---|
| Super Admin | `super_admin` | `null` | none — no capability in `Cap` describes platform authority |
| Main Admin | `main_admin` | `saas_hilal` | every key, organisation-wide |
| Simple Admin | `admin` | `saas_hilal` | the sub-Admin preset over the canonical fixture detachments |

Main and Simple share one `saasTenantId` deliberately: two administrators of
one paying customer. `saas_hilal` is the canonical development tenant record,
not a Customer Demo workspace; the stable id ties the pair to the same tenant
repositories and feature/plan context.

### Release safety

The persona selector and the persona authentication path are guarded by
`demoAccountsAllowed` (`core/env/build_mode.dart`), a compile-time constant
that is `false` outside debug — so a release build does not hide the demo
path, it does not contain one, and a development persona left on a device
cannot be restored by a production run.

### Development session persistence

`DemoSessionStore` persists **only the persona id**, not the account: the
`AuthUser` is rebuilt from the id on the next launch, so a stored grant can
never disagree with the fixture that defines it. Ordinary sign-out clears the
record, so a relaunch after signing out stays signed out.

**Durable since 2026-09-07 (Point 3).** `PersistentDemoSessionStore` writes the
persona id through `core/storage/local_store.dart` (§3.2b), so the selection
survives real process termination — which is what the in-memory implementation
could not do, and the one gap Point 2 left open. Release safety is enforced
outside the store, at three levels: `demoAccountsAllowed` (`const false` in any
shipping artefact), the `demoSessionStoreProvider` wiring (a release
configuration is handed a store with no device behind it), and
`MockAuthRepository`'s own refusal. A stored record is therefore never read by
a shipping build — and never deleted by one either.

### What the backend owes

| Field | Where | Note |
|---|---|---|
| `role` | `AuthUser` on sign-in and `GET /auth/me` | Required. One of `super_admin`, `main_admin`, `admin`, `customer_demo`. Unknown values are refused by the client. |
| `saasTenantId` | `AuthUser`, same two endpoints | Required; present-and-null for `super_admin` and `customer_demo`, real for tenant roles. Must satisfy the invariant in API_CONTRACT.md § AuthUser — the client refuses the account rather than repairing it. |
| `accountStatus` | `SessionAccess`, same two endpoints | Optional; absent means `active`. `active` / `suspended` / `revoked` / `pending_setup`. See API_CONTRACT.md § SessionAccess. |
| `tenantStatus` | `SessionAccess` | Optional; absent means `active`. `active` / `suspended` / `deletion_pending` / `deleted`; unknown values fail closed. Server/session refresh and protected requests must reflect lifecycle changes, including an already-open client. |
| `demoMode` | `SessionAccess` | Optional; absent means `none`. `none` / `active` / `expired`. A demo session carries `saasTenantId: null` and is served no real tenant data. |
| `mfaRequired` | `SessionAccess` | Optional; absent means `false`. Outranks both product surfaces in the client's startup priority. |
| `sessionExpiresAt` | `SessionAccess` | Optional RFC 3339 absolute instant with an explicit offset. At startup restore, `now >= expiry` routes to `/session-expired` using the injected `Clock` in UTC. Absent/`null` retains the existing authoritative `401 authentication_expired` path; malformed present values fail closed as unsupported access. No local lifetime or competing timer is created. |
| platform capabilities | not yet | Deliberately unspecified, and still so after Point 6. The keys in CAPABILITIES.md are tenant-operational; whatever authorizes a platform action — including `POST /platform/tenants` — is a separate question the platform surface (Points 4–13) asks. Point 6 invented no capability key and borrowed none. |
| first-time setup flow | client built (Point 17); backend not yet | `pending_setup` names the state. The steps that leave it — email OTP / verified Google, Team Code (Main Admin seat) or invitation auto-link (Simple Admin), setup completion — are specified in `API_CONTRACT.md` → "Sign-up and onboarding" and built client-side. |
| token refresh | not yet | **Point 18B — contract final:** `POST /api/v1/auth/refresh`, rotating single-use refresh token, replay revokes the family, failures one `401 authentication_expired` → `/session-expired`. Online-only. The client wires it with the real HTTP `AuthRepository`. |
| Customer Demo start/config | not yet | **Point 18B — policy final:** self-service from Login or the post-verification Team/Demo decision, only while the Platform has it globally enabled; Super Admin owns enabled/duration/cleanup, never per-user creation. Flutter has the Login action, the decision option, the isolated role/session and constrained no-tenant workspace. Backend owes the global policy, `POST /auth/customer-demo/start` (no bearer), authoritative duration/expiry, isolated dataset and enforcement. |
| Simple Admin management | not yet | Flutter has `SimpleAdminRepository`, UI and mock-to-Point-17 authorization adapter. Backend owes the list/invite/cancel/update endpoints, email delivery/expiry policy, tenant-scoped audit, optimistic revision and idempotency enforcement, and **atomic invitation consumption on setup** (`pending → accepted`, Point 18B — the mock now models it) described in API_CONTRACT.md. |

---

## 4. Open items owed to the backend developer

1. Can one volunteer belong to **more than one detachment**? The client model
   currently says no (a scalar detachment id on the member). Open decision #2.
2. The **detachment and workshop status value sets** are not decided.
3. ~~Whether **workshops belong to a detachment** or to the organisation.~~
   **Ruled: organisation-level** (`CAPABILITIES.md` §0, B/Q2 — all seven
   `workshop.*` keys are global). Struck through in Point 18A; it was still
   listed as open here.
4. Whether the **patient register** is in scope. Open decision #8.
5. Whether **shifts have a draft/published distinction**. Legacy has none;
   `shift.publish` was named in the capability brief.
6. The **failure taxonomy** in §3.1.
7. **Announcement recipient fan-out.** The client resolves *visibility* — an
   administrator sees an announcement when their grants cover one of the
   detachments it addresses. It cannot resolve *delivery*: there is no endpoint
   that answers "which administrators have access to detachment X", and the app
   has no admin directory. Who actually receives a notice (and any future push)
   is yours to decide and enforce. See `API_CONTRACT.md` § Announcements.
8. **Where announcement history lives.** The Notifications Center entry for an
   announcement outlives its expiry and its withdrawal, and is removed only when
   an administrator clears history. That cleared set is per-user and currently
   client-local, in the same shape as notification read state — a server that
   owns one would own the other.
9. **Announcement read state is deliberately absent.** No receipts, no seen
   state, no unread badge. If that is ever wanted it is a product decision, not
   a field to add quietly.
10. **Privacy Policy and Terms of Use are deferred until the backend exists.**
    After backend completion, review the actual data/security architecture —
    what is collected, where it is stored, how long it is retained, how
    authentication and sessions behave, what the server processes, which
    third-party services are involved, and what deletion actually does — and
    then implement/finalize Privacy Policy and Terms of Use.

    The About & Support screen (`/more/about`) deliberately ships **no** privacy
    or terms row, no placeholder screen and no dead route: a legal document
    written before the data handling is known would state promises nobody made,
    and a button that opens nothing is worse than an absent one. The two screens
    and their Settings entries are added in one piece when the answers exist.
    **Point 18B:** classified as a **pre-production product/legal
    requirement** (`BACKEND-HANDOFF.md` §15.4) — Terms, Privacy and any
    consent/versioning must be decided and implemented before public
    production onboarding; engineering drafts no legal text.
11. **A terminal rejection for replayed writes (Point 16).** Local-first
    writes are authorized when queued, then replayed by the sync engine. If a
    key is revoked (or a module disabled, or a limit reached) before the
    replay, the backend must refuse it — `not_permitted` /
    `feature_disabled` / `plan_limit_reached` — and it must never apply it.
    Today `SyncState` has no terminal "rejected" state: any non-`stale_write`
    refusal is classified `failed` (retryable), so such a write would be
    retried indefinitely and shown as pending. The client needs the sync
    contract to say which codes are terminal for a queued operation, and then
    one new outbox state; no data is at risk meanwhile because the server is
    the authority.
12. **Capability freshness.** The grant arrives with the session and is
    cached with it; offline, the client keeps using the last grant it was
    given (deliberately — offline-first). There is no grant revision or
    push invalidation, so a revocation reaches the UI at the next session
    refresh. The server must keep enforcing on every request; if a faster
    UI reaction is wanted, the session read needs a grant revision/etag.
13. **Plan-limit rejections on tenant creates.** No tenant create call in
    this build receives a typed server answer yet (the mocks accept, the
    writes are queued locally). The client now recognizes
    `plan_limit_reached` and renders it distinctly; the create endpoints must
    return it (`API_CONTRACT.md` → Errors) and the sync contract must carry
    it back for a queued create (item 11).
14. **Workshop statistics have no capability.** `stats.view` is
    per-detachment and workshops are organisation-level, so
    `/workshop/:id/stats` (attendance and payment totals) is gated by the
    two Feature Flags only. Whether it needs its own read key is a product
    decision; none is invented client-side.

---

*Last updated: Batch 0 analysis. No screens built yet beyond those marked
`built`, which pre-date this batch.*

15. **Point 17A — sign-up / onboarding backend (all PROVISIONAL — BACKEND
    DECISION REQUIRED where marked).** The endpoint family in
    `API_CONTRACT.md` → "Sign-up and onboarding — Point 17A foundation": the
    restricted onboarding session and its enforcement; the verification
    challenge (code length, expiry, attempt budget, resend cooldown); the
    Team Code link with one generic refusal and per-account + per-IP brute-force
    throttling; authorization records (Main Admin seat designations, Simple
    Admin invitations) matched on the normalized verified address; setup
    completion running the Point 14 seat transition atomically and issuing the
    full session; account-enumeration-safe sign-up/sign-in/reset; Google ID
    token verification and backend-owned identity mapping; idempotency on every
    mutation; Audit for setup completion. Open policy is listed in HANDOFF
    "POINT 17A" §Q.

16. **The seven live data dependencies (re-verified 2026-09-23).** These were
    found during the UI quality programme and are recorded in
    `UI-AUDIT-REPORT.md` as **BACKEND/DATA DEPENDENCY**. They are listed once,
    here, so the backend developer does not have to reconstruct them from an
    audit report. **None of them is a frontend defect**, none is masked, and no
    screen claims data it does not have. Closing one by inventing client-side
    data is explicitly refused.

    1. **Cross-detachment Home attention / summary aggregation.**
       `HomeRepository.summary(detachmentId)` is scoped to **one** detachment
       by construction. A Home that speaks for the whole organisation needs a
       truthful tenant- or organisation-level aggregate from the server; the
       client cannot fan out over detachments it may not be granted.
    2. **Statistics point dates / ranges.** The historical series on
       `DetachmentStats` are bare integer lists. A chart cannot label an axis
       it has no dates for. The contract should carry either date/range
       metadata per point or one unambiguous, documented series interval.
    3. **Historical inventory / stock unit.** Where a historical stock or count
       series exists, the backend must define its **unit and semantic meaning**
       (level at instant, movement over period, distinct items, …). The client
       must not guess, and a number without a unit is not a statistic.
    4. **`attendanceSeries` product semantics.** Undecided. No API data is to
       be invented for it until the product says what it counts and over what
       window.
    5. **Historical roster-size trend.** Not available today in any form. If
       the product wants it, it is a server-owned series — the client keeps no
       roster history.
    6. **Workshop payment mutation.** The register records and displays payment
       state locally. That display establishes **no payment authority**. If
       workshop payment becomes operational, the backend owns the authoritative
       mutation, its audit and its money semantics.
    7. **Real `.xlsx` export.** The UI is truthful: the button says «Excel
       (CSV)» and writes CSV. Genuine `.xlsx` generation and delivery is future
       backend/product work, not a label to change.

    Readiness classification for all seven: `BACKEND-HANDOFF.md` §19.4.
