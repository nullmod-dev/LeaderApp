# DETACHMENT-SCOPING

The report required by Domain Note 3, to be worked through and delivered
**before** building. Status: analysis and proposals. Nothing implemented.

Premise: **the detachment is the container.** There is no central warehouse and
no global schedule. Each detachment owns its own stock and its own schedule.
Every inventory and schedule screen is reached through a detachment, never
standalone.

---

## 1. Where the current code already honours this, and where it does not

### Already correct

- Every inventory, shift, and team provider is a Riverpod **family keyed by
  detachment id**: `inventoryListProvider(detachmentId)`,
  `todaysShiftsProvider(detachmentId)`, `teamListProvider(detachmentId)`.
- The mock inventory and shift repositories **filter by detachment id** rather
  than returning a global list.
- The routes already nest inventory and schedule **under** the detachment:
  `/detachment/:id/storage`, `/detachment/:id/shifts`. Neither is reachable
  standalone.
- The mock data has **four active detachments** with distinct names, regions, and
  centres.

### Four real defects that will leak state between detachments

**D1 — `byId` falls back to the first record instead of failing.**
`MockDetachmentRepository.byId` uses `orElse: () => _seed.first`, and
`MockInventoryRepository.byId` uses `orElse: () => _items.first`. Ask for a
detachment or an item that does not exist — or, worse, one belonging to a
*different* detachment — and you silently get Damascus Central's first record
rendered as if it were yours. This is exactly the cross-detachment leak Domain
Note 3 warns about, and today it is a guaranteed silent wrong answer rather than
an error state. **Both must return `Failure` (not found).** The legacy program
got this right: every mutation filters by parent id as well as row id
specifically so an id from one record can never act on another.

**D2 — no provider is `autoDispose`.**
A non-disposing family keeps one cached instance **per detachment id, forever**.
Switch from Damascus to Homs and back and you are shown the Damascus data as it
was minutes ago, with no refetch and no loading state. Memory also grows with
every detachment visited.

**D3 — item- and shift-level providers are keyed by the child id only.**
`inventoryItemProvider(itemId)` and `inventoryMovementsProvider(itemId)` carry no
detachment id, so nothing in the type system or the cache key ties them to the
detachment whose screen is open. Combined with D1 this is how an item from
another detachment gets rendered.

**D4 — mock stock and schedules are not actually distinct across detachments.**
Your brief requires at least three detachments with different inventory and
different schedules so isolation is visible. Today:

| Detachment | Inventory items | Shifts |
|---|---:|---:|
| Damascus Central | 5 | 3 |
| Damascus Rural | 1 | 1 |
| Homs | **0** | **0** |
| Coast | **0** | **0** |

Two of four detachments have no stock and no schedule at all, so switching
between them cannot demonstrate isolation — an empty screen looks the same
whether isolation works or is broken.

---

## 2. How state is prevented from leaking — the five rules

Proposed for Batch 0 item C, to be applied to every detachment-scoped provider.

**Rule 1 — the detachment id is part of every cache key.**
Every provider that reads detachment-owned data is a family whose key contains
the detachment id. For child records the key is a **record**, not a bare string:
`(detachmentId: ..., itemId: ...)`. Dart record types give value equality for
free, so two different detachments can never collide on one cache entry. This
also removes D3 by construction: it becomes impossible to write the provider
without supplying the detachment.

**Rule 2 — every detachment-scoped provider is `autoDispose`.**
When the last widget watching a detachment's data goes away, the state goes with
it. Leaving a detachment therefore *cannot* show yesterday's data on return; the
screen re-enters its loading state and refetches. This is the single most
effective measure and it fixes D2. Where a genuine cache is wanted for the
active detachment, it is held explicitly with a keep-alive link and a stated
expiry, never by accident.

**Rule 3 — UI state is scoped too, not just data.**
Search text, filters, sort order, selected tab, selected week, expanded rows —
all of it is per-detachment family state. A search typed in Damascus must not be
sitting in the field when Homs opens. The legacy program already did this
correctly (`detachmentMemberSearchQueryProvider` is a family keyed by detachment
id) and it is worth copying.

**Rule 4 — a wrong-scope read is a `Failure`, never a fallback.**
No `orElse` that returns the first record. If the requested id is not in the
requested detachment, the repository returns *not found*. This fixes D1, and it
makes a scoping bug visible as an error screen during development instead of as
plausible-looking wrong data in production.

**Rule 5 — the mocks must make a leak visible.**
Each detachment gets a visibly different inventory and a visibly different
schedule, so a leak shows up as obviously-wrong content rather than as a subtly
wrong number. Concretely: different medicine sets, different item counts,
different stock levels, different centres, different shift times, different
coverage gaps. Fixes D4.

**Verification I propose to add:** a test that loads detachment A, loads
detachment B, returns to A, and asserts the emitted data never contains a record
whose detachment id is B's. That test fails today because of D1.

---

## 3. Deep links and route structure

The current structure already carries the detachment id and should be kept:

```
/detachment                          list
/detachment/new                      create
/detachment/:id/<tab>                the tabbed shell
/detachment/:id/edit                 edit
```

Rules for every route added from here:

1. **Nothing detachment-owned gets a top-level route.** There is no `/inventory`
   and no `/schedule`. Child detail routes extend the detachment path:
   `/detachment/:id/storage/:itemId`, `/detachment/:id/shifts/:shiftId`. A link
   is then self-describing and always resolvable.
2. **A deep link into a detachment the user cannot access resolves to the
   permission-denied state**, not to a redirect that silently swaps in a
   different detachment.
3. **A deep link to a missing detachment resolves to a not-found state.** Same
   reasoning as Rule 4 above.
4. The **active detachment follows the route**, not the other way around. Opening
   a link to detachment B makes B active. Otherwise a shared link shows the
   recipient their own detachment's data under B's URL.

**Note on the current shell:** the detachment tabs are a `ShellRoute` nested
inside a `StatefulShellBranch`. The branch preserves navigation state per
bottom-nav tab, which is desirable, but it means the previous detachment's route
stack survives a bottom-nav switch. With Rule 2 (autoDispose) the *data* is
correctly discarded; the *route* is not. Whether returning to the detachment tab
should land on the last detachment or on the list is a UX decision — I recommend
landing on the last detachment, since that is the container the user is working
in.

---

## 4. Home when a user belongs to several detachments

This is unresolved and depends on open decision #2 (below). Current state:
`HomeSummary` carries a single `detachmentName` and a single `centerName`, so
today's model assumes exactly one.

**Proposal — one active detachment at a time.**

1. Home always renders **one** detachment: the active one. Its name is in the
   header and is the control that switches it.
2. Tapping the header opens a picker of the detachments the user belongs to,
   with today's coverage and low-stock count beside each so the choice is
   informed.
3. The active detachment id is **persisted locally** as a non-sensitive UI
   preference, so the app reopens where the user left off.
4. Selection order on first launch: the only detachment if there is one;
   otherwise the last active one if it is still valid; otherwise the one where
   the user has a shift today; otherwise the first alphabetically. Every step is
   deterministic — no "best guess" that reorders itself between launches.
5. If the user belongs to exactly one detachment, the switcher **is not
   rendered**. No affordance for a choice that does not exist.
6. Changing the active detachment invalidates every detachment-scoped provider,
   which under Rule 2 they already are.

**The rejected alternative, and why.** An aggregated Home showing all
detachments at once reads well on the dashboard but breaks the container
premise everywhere below it: every decision item, every stock warning, and every
shift on that screen would have to carry its own detachment badge, and every tap
would have to switch context silently. It also makes the coverage number a
cross-detachment average, which is not a number anyone acts on. If you want
aggregation, it belongs on the Super Admin web dashboard, not here.

---

## 5. The tab set — proposal for your ruling

Current tabs (built or stubbed): **Team / Shifts / Storage / Stats**.

**Recommendation — four tabs, RTL order first (rightmost) to last:**

| Position | Tab | Contents |
|---|---|---|
| 1 | **Overview** | Header identity, today's shift, coverage, low-stock count, and the 7-day trend charts currently living in the Stats tab. |
| 2 | **Schedule** | The week's shifts, coverage gaps, assignment, attendance. |
| 3 | **Inventory** | Stock list, levels, expiry, movements. |
| 4 | **Members** | The roster, roles, contact. |

Reasoning:

- **Stats is folded into Overview.** A separate tab holding three sparklines
  earns a quarter of the tab bar for something nobody opens twice. The overview
  is where a lead glances; the trend belongs there.
- **Schedule before Inventory before Members** follows how often each is opened
  during a working day. Members is reference data; the schedule is the job.
- **"Storage" is renamed "Inventory"** for consistency with the domain language
  used everywhere else in your brief.
- Four tabs is the practical ceiling for Arabic labels on a narrow screen before
  the labels truncate. Adding Patients (open decision #8) would need five and
  would force a different navigation pattern.

**Alternative if you want Stats to stay separate:** Overview merges into the
detail header (not a tab), giving **Schedule / Inventory / Members / Stats**.
This keeps four tabs and keeps stats prominent, at the cost of a heavier header.

Either way the tab identifiers appear in the route path, so the choice must be
made before the tab screens are built rather than after.

---

## 6. Consequences I found while working this through

Raised rather than designed around:

1. **The current `Shift` model does not match the container premise well.** It is
   a single dated shift with a centre name. The legacy model — a weekly template
   per detachment plus dated occurrences — is genuinely better and already
   proven. The scheduling redesign should reconcile these before either is built
   on.
2. **`TeamMember.detachmentId` is scalar**, which is a design commitment to
   one-detachment-per-person made before the question was asked. Open decision #2.
3. **The legacy program surfaced a pending-sync state in the UI** — a per-row
   badge and a list filter for "not yet synced". This app has an offline layer
   planned but no equivalent affordance. Whether an operator needs to see which
   of their edits are still local is a real UX question for the offline layer.
4. **Coverage percent is computed somewhere.** `Detachment.coveragePercent` and
   `Shift.hasCoverageGap` arrive pre-computed. If coverage is derived from the
   schedule, the client will show a stale number whenever the schedule changes
   locally. Worth stating in DATA-NEEDS as a freshness constraint.

---

## 7. THE OPEN QUESTION — not designed around, per your instruction

> **Can one volunteer belong to more than one detachment?**

I am not guessing. Here is the evidence and the consequence, so you can rule.

**What both codebases currently say: no.**
- New app: `TeamMember.detachmentId` is a single string.
- Legacy app: a detachment member row belongs to exactly one detachment, and a
  person working in two detachments would be two unrelated records.

**If the answer is yes, three things break:**

1. **Shift conflicts can span detachments that cannot see each other's
   schedule.** A volunteer assigned 08:00–14:00 in Damascus and 10:00–16:00 in
   Rural is double-booked, and neither detachment's admin can see the other's
   schedule. Detecting this requires a cross-detachment read that the container
   premise otherwise forbids — which is a question about who is allowed to see
   what, not just about data structure.
2. **The member identity model changes.** A person becomes an entity that
   *belongs to* detachments, rather than a row inside one. Roles, attendance
   history, and statistics all become per-membership rather than per-person.
3. **Home's active-detachment switcher becomes mandatory** rather than a
   convenience, and every "my shifts" view has to span detachments.

**If the answer is no**, the current scalar model is correct and nothing above
applies.

**I have not designed for either.** Awaiting your answer.
