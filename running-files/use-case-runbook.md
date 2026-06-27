# Use-Case Runbook — «PROJECT»

> Every action a user can take, as **user stories with concrete, click/command-by-step instructions** + the expected result. Doubles as the **manual-test script** and the **how-to playbook**. Grounded in the *real* surfaces (routes, commands, buttons) — not invented. **Update changed flows + add a story for any new capability as part of Done.**
> **Legend per run:** ✅ pass · ❌ fail (defect) · ⚠️ partial/blocked.

## Before you start — environment realities
«Anything a tester/operator must know: which env, what's stubbed, how to obtain tokens, how to simulate hard-to-reach states.»

## «Persona / area 1»
### «AREA-01» — «short title»
**As a «persona», I want to «goal» so that «benefit».**
1. «Step: go to X / run Y.»
2. «Step: enter Z / click W.»
3. ✔ Expect: «the observable result». «Any invariant check.»

### «AREA-02» — …
**As a … I want to …**
1. …

## Golden end-to-end paths (the flows to demo / regression-test)
- **«Primary lifecycle»:** «AREA-01 → AREA-04 → AREA-07 …» (string the stories into the main journey).
- **«Secondary / failure path»:** «…»
