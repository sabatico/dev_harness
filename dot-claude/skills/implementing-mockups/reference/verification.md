# Verification, token tiers and tooling gotchas

## Step 4 — verify a screen

With the full spec done up front, this step confirms; it is not where the design is discovered.

1. **Computed-style diff.** Render BOTH sides to HTML with all styles resolved inline, then diff
   element by element. Because the structures are parallel, the trees line up and a mismatch is a
   fact (`color #7A6F60 vs #9A8F7D`), not an opinion. This diff is the source of truth for exact
   values.
2. **Quantify, don't eyeball.** Screenshot both at an identical viewport; generate a pixel-diff
   heatmap (identical = black, differences = hot) and a **%-match score, overall and per region**.
   Track it across iterations; target ≥ «threshold, e.g. 95%». Per-region scoring localizes the worst
   offender.
3. **Mask text when scoring layout.** Font rasterization differs between renderers and never reaches
   100% (layout-only tops out around 99.8%) — judge text fidelity with the computed-style diff
   instead. Pixel-matching alone is brittle (anti-aliasing and fonts cause false positives), which is
   why the inline-style DOM diff is the primary check.
4. **Fix order: structure/alignment first, then aesthetics.** Layout errors compound (a 1px row delta
   × 6 rows = a visible 6px drift) and masquerade as many separate bugs — fix the root cause,
   re-score, then refine colour/type.
5. **Per-element checklist:** background · border (colour / width / radius) · text (colour, family,
   size, weight, letter-spacing, transform) · padding & gap · the exact copy · icons / pills ·
   interactive states. Fix every mismatch, re-diff, then commit with the side-by-side as the
   approval artifact.

## Token tiers

**Primitive** (raw values, never used directly in components) → **Semantic** (role-named:
`--color-bg`, `--space-4` …) → **Component** (a primitive's resolved set). One source of truth;
names convey purpose, not value; define core tokens (colour, type, spacing) before anything
composite.

## Gotchas (build them into the tooling)

- **Fonts:** wait for `document.fonts.ready` before any capture — otherwise the shot renders the
  fallback font and lies.
- **Secure context:** if the app needs one (WebCrypto etc.), drive it over `localhost` or https, not
  a bare-IP http origin.
- **Ignore the export's chrome:** exports often wrap each screen in a preview frame, inject a runtime
  or source-map attributes, and stack all sections on one page. Align crops/subtrees to the real
  screen edges; don't sample the frame.
- **Reach gated screens:** seed an account or use a harness to get past auth/billing/verification so
  every screen is capturable.
- **Data vs copy:** the mockup uses stub persona data. Match the design copy and styling; let real
  data differ. Don't chase data as if it were a design defect.

## Drift audit (keep it locked)

Beyond the no-inline-styles lint, periodically re-diff the locked tokens against the mockup and flag
any hardcoded colour/spacing ("magic numbers") that bypassed a token — catches drift before it
spreads.

## "Pixel-perfect" — the honest definition

With a token system it means **computed values match + indistinguishable to the eye**, not
byte-identical. The realistic, verifiable bar is the computed-style diff + the %-match score + an
approved side-by-side.
