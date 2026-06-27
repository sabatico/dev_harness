# Third-Party Services — «PROJECT»

> **The single inventory of every external service the project depends on — what it is, WHY we use it, and how it's wired** (accounts, endpoints, config by NAME — **never secret values**). Built so a human or agent can see the whole external-dependency surface at a glance before touching any integration. **Keep current when an account/endpoint/config/DNS record changes.**
> **⚠️ Secrets:** this file lists secrets **by name and location only** (which env var, which secret store) — never the value.

## Services
| Service | What it does for us | WHY this one (vs alternatives) | Status | Plan / cost | Owner-action needed |
|---------|---------------------|--------------------------------|--------|-------------|---------------------|
| «Service A» | «the capability» | «the reason we chose it over B/C» | live / trial / planned / stubbed | «tier, ~cost» | «e.g. account approval pending» |

## Configuration (per service)
### «Service A»
- **Account / project:** «id / name (not secrets)».
- **Endpoints / regions:** «what we hit».
- **Config (env vars + non-secret dev values):** `«VAR_NAME»` = «dev value or 'see secret store'».
- **Secrets by NAME:** `«SECRET_VAR»` → stored in «.env / CI secrets / cloud secret manager». *(value never here)*
- **DNS / domains:** «any records this service requires».
- **Limits / gotchas:** «rate limits, sandbox-only, approval gates, the non-obvious failure mode».

## Stubbed / not-yet-live integrations
| Service | Marker | Why stubbed | Unblock trigger |
|---------|--------|-------------|-----------------|
| «Service X» | `STUB:«NAME»` | «the gate it waits on» | «what lands to go live» |

> Read this **before touching any integration.** New service or changed config ⇒ update this file in the same slice (it's a running file — part of Done).
