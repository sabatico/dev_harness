# Architecture Overview — «PROJECT»

> The big-picture map of the system: the major components, how they connect, where the data/control flows, and the boundaries that matter. Deep specifics live in their own docs + ADRs; this is the **one diagram + one page** that orients anyone before they go deeper. Update when a structural boundary changes.

## 1. The shape (one diagram)
```
«ASCII or linked diagram: the major components and the arrows between them.
 e.g.  client ──HTTP──▶ API ──▶ domain/core ──▶ store
                                   │
                                external services (see third-party-services.md)»
```

## 2. Components
| Component | Responsibility | Tech | Lives in | Key ADRs |
|-----------|----------------|------|----------|----------|
| «API» | «what it owns» | «stack» | «path» | «ADR-…» |
| «Core/domain» | «…» | | | |
| «Store» | «…» | | | |

## 3. The boundaries that matter
- **Trust / security boundary:** «where untrusted input enters; what's authenticated where». Ties to the project **invariants** in `CLAUDE.md`.
- **Contract boundaries:** «the interfaces the lead freezes so builders can work in parallel (API schema, module interfaces)».
- **Data flow:** «how a request/event moves through the system; where state is persisted».

## 4. Cross-cutting
- **Config & environments:** «dev/staging/prod; how config is injected». External deps → `third-party-services.md`.
- **Observability:** «logging/tracing/metrics approach».
- **Build & deploy:** «how it's built, tested, shipped». Gates → `ci/gates.md`.

## 5. Where to go deeper
«Links: the data-model doc, the API contract, the relevant ADRs, the infra doc.»
