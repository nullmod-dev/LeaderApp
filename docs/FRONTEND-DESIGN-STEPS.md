# Frontend design steps

Adapted from the MTM-PRO frontend and motion workflow for this Flutter frontend.

1. **Understand the surface.** Identify the user, their immediate task, the data and states the screen must represent, and the existing feature/theme/motion code that governs it. Inspect `design_references/` when it applies.
2. **Plan before building.** For a new or substantially revised screen, write a compact plan: hierarchy, layout, palette/token use, typography, component states, and one appropriate visual signature. The plan must serve this medical-team workflow, not a generic dashboard pattern.
3. **Use the visual-design sequence.** Consult `frontend-design`, then `impeccable`, then `emil-design-eng`. Reconcile their advice with the existing Flutter design system and the requirements in this repository.
4. **Implement in Flutter.** Reuse existing theme tokens, shared widgets, and motion helpers. Convert design intent into Flutter widgets; never port CSS, JSX, Framer Motion, or web package recommendations directly.
5. **Design every state.** Include usable loading, empty, offline, error, retry, permission, and success states. Communicate failures clearly without exposing technical details to an end user.
6. **Add motion only when it helps.** Use `animate` for the decision, `apple-design` for interaction/physics guidance, and `animation-vocabulary` to identify an effect. Prefer the current implicit Flutter animations; use an `AnimationController` and `SpringSimulation` only when they are genuinely needed.
7. **Make it accessible and RTL-correct.** Honor disabled/reduced motion. Use directional layout APIs and explicitly check horizontal transitions under Arabic RTL; `SlideTransition` offsets do not flip automatically.
8. **Review before handoff.** Use `find-animation-opportunities` and `improve-animations` to inspect possible improvements, then use `review-animations` for any motion change. Check visual consistency, interaction interruption/exit behavior, and the relevant Flutter analysis/tests.
