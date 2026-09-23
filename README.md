# Leader / ليدر

Leader is an Arabic-first, RTL Flutter application for coordinating volunteer emergency medical teams. It covers tenant administration, detachments and groups, shifts and attendance, inventory, workshops, and a separate Super Admin platform surface. The app is offline-first and currently uses mock repositories behind documented frontend/backend seams.

## Repository map

- `flutter_app/` — runnable Flutter application, Android and iOS projects, assets, dependency manifests, and tests.
- `docs/` and `design_references/` — frontend design guidance and visual references.
- `SCREEN-ROUTE-MATRIX.md` — routes and their repository seams.
- `CLAUDE.md`, `AGENTS.md`, `HANDOFF.md` — coding guidance and current project status.

Run the frontend from `flutter_app/` with `flutter pub get`, then `flutter run`. Validate changes there with `flutter analyze` and `flutter test`. The Android application ID is `com.leader.teams`; the Dart package and some compatibility identifiers intentionally retain `MTM` names.

## Backend Developer — Start Here

1. [BACKEND-HANDOFF.md](BACKEND-HANDOFF.md) — consolidated domain model, implementation order, open decisions, and readiness (§19).
2. [API_CONTRACT.md](API_CONTRACT.md) — authoritative wire payloads, endpoints, errors, and auth contract.
3. [FRONTEND-BACKEND-INTEGRATION.md](FRONTEND-BACKEND-INTEGRATION.md) — repository seams, offline writes, conflicts, and device-local boundaries.
4. [DATA-NEEDS.md](DATA-NEEDS.md) — screen data needs and seven outstanding backend/data dependencies (§16).
5. [CAPABILITIES.md](CAPABILITIES.md) — role, feature, capability, and limit rules.
6. [PRICING-PROMOTIONS-ARCHITECTURE.md](PRICING-PROMOTIONS-ARCHITECTURE.md) — pricing, promotions, coupons, and duration model.
7. [HANDOFF.md](HANDOFF.md) — latest frontend state, validation, rationale, and external configuration needs.

There is no real backend or HTTP integration in this repository yet. Contracts and mock behavior provide the starting point; open product decisions are identified in the handoff. No backend stack should be assumed until explicitly selected. Google sign-in also needs external OAuth configuration and a backend that verifies the ID token audience before production use.
