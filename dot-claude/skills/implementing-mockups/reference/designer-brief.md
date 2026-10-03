# The designer brief (styling-context manifest)

Whoever produces the handoff — a design tool's export or a human designer — gets this same checklist,
so the package comes back implementation-ready instead of needing a translation pass. Keep it in the
repo («where the styling-context manifest lives») and paste or link it every time.

1. **Target stack.** Name the exact styling system the output must hit — framework + styling method
   (e.g. «CSS-custom-property tokens + CSS Modules», or the project's locked stack). These tools tailor
   output to the *declared* stack (Tailwind vs plain CSS vs React + CSS Modules), so this is the
   single highest-leverage line.
2. **Token vocabulary.** Give the semantic token names to reference (or link the tokens file): "use
   these names — don't emit raw hex/px values."
3. **Component library.** List the existing primitives to reuse (names + variants/props), so it
   doesn't re-invent buttons, cards, inputs or nav.
4. **Output rules.** Emit components + scoped styles + `var(--token)` references; no inline styles,
   no hardcoded colours/spacing, no new token system, no foreign-framework utility classes.
5. **Map + flag.** Map every value used on the canvas to a semantic token; flag any value not in the
   palette so it is added deliberately — never silently invented.
6. **Scope + format.** The structured handoff (component tree + tokens + layout hierarchy + assets)
   for all screens / the full information architecture — not a single frame, and not a flat
   screenshot or PDF.
7. **Connect the codebase if the tool supports it.** Pointing the tool at the repo so it
   auto-ingests the tokens + components is the biggest quality lever; this manifest is the fallback
   when it can't.
