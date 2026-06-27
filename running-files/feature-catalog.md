# Feature & Module Catalog — «PROJECT»

> **The ONE enumerable inventory of everything the product does** — user-facing features (Part A) and core/internal modules (Part B) — with status, where it lives, and how it's tested. Built so anyone can answer *"what does this do, end to end?"* without stitching five docs together. Gives every capability a **stable ID** to plan/audit/experiment against.
> **⚠️ Maintenance is part of Done:** when a slice adds/changes/removes a capability, update its row **in the same slice**. A stale catalog is a bug.

**Status legend:** ✅ done & wired · 🔨 partial (e.g. backend only) · ⛔ gated/blocked on an external dep · ⬜ planned.

## Part A — User-facing features (by persona/area)
### «Persona / area 1»
| ID | Feature | Status | Surface (screen / route / CLI) | Key endpoints / entrypoints | Tests | Notes |
|----|---------|--------|--------------------------------|-----------------------------|-------|-------|
| «AREA-01» | «what the user can do» | ✅ | «where» | «how» | ✅ | «caveats, ADR, stub markers» |

## Part B — Core / internal modules
| ID | Module | Status | Path | Responsibility | Tests | Notes |
|----|--------|--------|------|----------------|-------|-------|
| «CORE-01» | «module» | ✅ | «path» | «what it owns» | ✅ | … |

## Stub / intentionally-incomplete inventory
| Marker | What's stubbed | Why (the external gate) | Where it's tracked |
|--------|----------------|-------------------------|--------------------|
| `STUB:«NAME»` | «the integration» | «the dependency it waits on» | «registry» |
