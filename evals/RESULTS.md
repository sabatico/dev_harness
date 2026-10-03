# Skill evaluation results

Newest first. Each run: the model, what was tested, per-item verdicts, and what changed because of it.

**Test models: Sonnet and Opus only.** Haiku is banned from the dev process (owner decision); the
Haiku results below are kept as history, and the fixes they prompted made the skills clearer for
every model.

## Run 2 — re-test of the two Run-1 failures (Haiku)

| Scenario | Result | Change that got it there |
|---|---|---|
| `communicating-with-the-owner` (registers unavailable) | **PASS** — looked each ID up, reported "not found", refused to invent glosses, asked for one plain sentence per ID | protocol: "glosses come from the record, never from imagination"; checklist step 2: LOOK IT UP, never guess |
| `writing-tests` (builder asked to test own code) | 1st re-test **FAIL** (step 0 present but treated as hypothetical, went on to plan tests) → 2nd re-test **PASS** — refused, offered the hand-off, no test plan | checklist step 0 "Did I build this code? YES → STOP"; then a concrete example of exactly this request with the correct answer, and "refuses to test code it built itself" in the description |

Lesson for `authoring-skills`: a rule that lives only in prose above a checklist is skipped by smaller models; put the stop condition IN the checklist and add one concrete input → correct-answer example.

## Run 1 — three models, discovery + application

**Setup.** Each model got only the 16 skill names + descriptions and 8 owner-style requests
(discovery), then read the chosen SKILL.md for three scenarios — the first scenario of
`hunting-bugs`, `writing-tests` and `communicating-with-the-owner` — and listed the concrete steps
it would take (application). Read-only. **Caveat:** the agents ran from inside a project that has its
own `CLAUDE.md`, so some project rules (e.g. "commit on dev") leaked into their answers; that biases
nothing in the skills themselves, but a cleaner run uses an empty working directory.

### Discovery (which skill would you load first?)

| Request | Expected | Haiku | Sonnet | Opus |
|---|---|---|---|---|
| quality review before a release | reviewing-code-quality | ✓ | ✓ | ✓ |
| hunt for bugs in payments | hunting-bugs | ✓ | ✓ | ✓ |
| weekly update for a non-technical owner | communicating-with-the-owner | ✓ | ✓ | ✓ |
| about to let real customers sign up — secure? | hardening-security | ✓ | ✓ | ✓ |
| spawn a builder and a tester | orchestrating-agents | ✓ | ✓ | ✓ |
| turn a checklist doc into a skill | authoring-skills | ✓ | ✓ | ✓ |
| build the page exactly like the design export | implementing-mockups | ✓ | ✓ | ✓ |
| what did we already decide about refunds? | consulting-the-librarian | ✓ | ✓ | ✓ |

24 / 24 — the descriptions route correctly for all three model sizes.

### Application

| Scenario (expected behaviour) | Haiku | Sonnet | Opus |
|---|---|---|---|
| `hunting-bugs`: coverage map first, six lenses per unit, invent-nastier → ruling, CONFIRMED/SUSPECTED, register at discovery, unit verdicts incl. NOT-HUNTED, log + `bug-hunt:` commit | PASS | PASS | PASS |
| `writing-tests`: the builder asked to test its own code **refuses** and asks for a different author | **FAIL** — wrote the tests as if it were the cross author | PASS | PASS |
| `communicating-with-the-owner`: every ID glossed in plain words **from the record**, never guessed; ends with what waits on the owner | **FAIL** — invented plausible meanings for every ID ("a button leaking student names", "sessions expire after 30 idle minutes") | PASS | PASS |

**Fixes (observe → refine → re-test):**
- `writing-tests`: the stop rule lived in prose above the checklist; Haiku copied the checklist and
  skipped it. Now checklist step 0 is "Did I build this code? YES → STOP", and the prose says MUST NOT.
- `communicating-with-the-owner`: the skill said "gloss every ID" but never said *from where*. Added
  "glosses come from the record, never from imagination" to the protocol and "LOOK IT UP … never
  guess" to checklist step 2; the eval scenario gained that expected behaviour.

Re-tested in Run 2 — both now pass on Haiku; Sonnet and Opus passed already.
