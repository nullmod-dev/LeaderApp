# Leader repository guide

- Read `CLAUDE.md` and the current summary at the top of `HANDOFF.md` before changing code. The Flutter frontend is in `flutter_app/`; the canonical GitHub branch is `main`.
- For backend work, start with `BACKEND-HANDOFF.md`. `API_CONTRACT.md` is the wire authority; `FRONTEND-BACKEND-INTEGRATION.md`, `DATA-NEEDS.md`, `CAPABILITIES.md`, `PRICING-PROMOTIONS-ARCHITECTURE.md`, and `SCREEN-ROUTE-MATRIX.md` define their respective seams. Update these documents when backend-critical behavior changes. Do not assume a backend stack.
- Preserve the product boundaries: `SaasTenant` is the subscriber and isolation boundary; `DetachmentGroup` groups `Detachment` field units. `super_admin` belongs to the platform control plane; `main_admin` and `admin` belong to a tenant. Never conflate their data or permissions.
- Enforce authorization in order: auth/session → account lifecycle → tenant lifecycle → role/surface → feature flag → capability → plan limit. Demo uses `DemoPolicy` and `DemoSession`, is isolated from production tenants, expires or terminates, and has no production sync/outbox.
- Preserve documented technical `MTM` identifiers, including the Dart package and compatibility keys, despite the Leader brand. Keep Arabic RTL layout and accessibility requirements intact.
- Palette, appearance, Eye Protection, motion, and performance preferences are device-local under the current contract; do not add backend APIs for them without a product change.
- Do not commit secrets, signing material, tokens, local machine configuration, caches, or build outputs. Run relevant Flutter tests, `flutter analyze`, and `git diff --check` for affected changes.
