# scripts/ — the executable layer

Everything else in this kit is conventions and SOPs: the agent reads them and follows them. **This
directory is the part that does not depend on anyone reading anything.**

It exists because of a measurement worth repeating (see the README's evidence section): over one
audited session, of ten defects, the count caught by *a rule that was read and being complied with*
was **zero**. Gates caught three. So the prose sets direction; these scripts hold the line.

## ⛔ STATUS — READ BEFORE YOU TRUST ANY OF THESE

**These are reference implementations. They have not been run against your tree, and a gate you have
not watched fail is not a control.** That is `gates.md` G7, and it applies to the gates shipped *with*
the harness exactly as it applies to ones you write.

Adopting a gate is two steps, not one:

1. **G7 — logic.** Plant a violation, watch it exit non-zero, remove it, watch it pass, confirm the
   restore was byte-identical.
2. **G8 — wiring.** Trigger it the way production will: through the real hook, the real runner. Calling
   the script in a terminal proves the script, and the script is not the part that usually breaks.

Do this **especially** for a gate that reports a clean tree on its first run. One gate in the field
was written specifically to catch a class of error, reported clean, and was only discovered to be
scanning nothing when someone planted a violation and it stayed quiet.

## Setup

```sh
cp harness.conf.example <your-repo>/harness.conf   # then edit every path
cp -r scripts <your-repo>/scripts
scripts/run-all-gates.sh
```

`harness.conf` is the only file you edit. Nothing in `scripts/` hardcodes a language, directory
layout, or project name; everything comes from that config. A setting left empty **disables** the gate
that needs it, and the gate says so out loud — an unconfigured check reports INCOMPLETE, never PASS.

## What is here

| Script | Enforces | Notes |
|---|---|---|
| `run-all-gates.sh` | the whole fast tier, then optional suites | tiered: bare, `--full`, `--lint`, `--all` |
| `hook-fast-gates.sh` | the sub-second gates **at the moment of the write** | see `ci/control-timing.md`; blocking on docs, advisory on code |
| `check-doc-links.sh` | every markdown link resolves | **blocking** at write time — a dead link is a fact error |
| `check-doc-paths.sh` | every **bare backticked** path exists | ratcheted; links are only half the surface |
| `check-doc-index.sh` | every doc is registered | proves *declared*, never *accurate* (G5) |
| `check-markers.sh` | marker ⇄ registry pairing | fully config-driven; add your own marker types |
| `check-bug-evidence.sh` | a closed bug names its mutation + the test that went red | contract is in the header |
| `check-conditional-skips.sh` | no test skips from an **error branch** | heuristic; suppress with `harness:allow-conditional-skip` |
| `check-citations.sh` | a function you touched cites the decision governing it | ratcheted vs `HARNESS_BASE_REF`; `--measure` first |
| `check-log-hygiene.sh` | no secret-shaped identifier reaches a log call | name-based heuristic — a floor, not a proof |
| `lib/common.sh` | the shared exit vocabulary, config loading, ratchet helpers | source it from any new gate |
| `lib/manifest.sh` | `ci/run-integrity.md` R1–R4 in ~90 lines | for multi-stage jobs |

## The exit vocabulary — honour it in every gate you add

```
0  PASS        the check ran and found nothing wrong
1  FAIL        the check ran and found something wrong
3  INCOMPLETE  the check COULD NOT RUN — missing config, missing tool, no target
```

**`3` is the one that matters.** A check that scanned nothing must never exit `0`. Every expensive
failure this harness is built around comes from "nothing was checked" rendering as "nothing was
wrong". If you add a gate and skip this, you have added a control that lies in the reassuring
direction.

## Measure before you enforce

```sh
scripts/check-citations.sh --measure
```

Prints the current adoption rate and fails nothing. **A rule with no baseline is a wish** — and the
number is usually not what anyone guessed. Freeze what exists (`--write-baseline` where supported),
then enforce forward. See `gates.md` G3 for what keeps a baseline honest, including the requirement to
**triage before freezing**: burying real findings among false ones is the standard way a ratchet goes
wrong.

## Portability

Bash 3.2 compatible (stock macOS — no associative arrays, no `mapfile`) and BSD-safe (no GNU-only
flags). The harness has to run on the machine the developer actually has, not the one CI has.
