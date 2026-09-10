# Skill Test Spec: /vertical-slice

## Skill Summary

`/vertical-slice` runs the Pre-Production validation gate. It builds a
production-quality, end-to-end build demonstrating one complete
[start → challenge → resolution] cycle, answering *"can we build this full game
loop at production quality, on schedule?"* — a different question from
`/prototype`, which only asks whether the concept is fun.

It runs late in Pre-Production, after GDDs, architecture, and UX specs are
complete, and gates the Pre-Production → Production transition. Output is a
`REPORT.md` under `prototypes/[concept-name]-vertical-slice/` plus a
PROCEED / PIVOT / KILL verdict. PIVOT is re-runnable: the skill may be run as
many times as needed until PROCEED or KILL is reached.

Unlike `/prototype`, this skill **does** invoke a director gate — `CD-PLAYTEST`
via `creative-director` — in `full` review mode. It declares `agent: prototyper`
and `isolation: worktree`, so the build runs in an isolated git worktree.

---

## Static Assertions (Structural)

Verified automatically by `/skill-test static` — no fixture needed.

- [ ] Has required frontmatter fields: `name`, `description`, `argument-hint`, `user-invocable`, `allowed-tools`
- [ ] Declares `model: sonnet` (alias, not a literal model ID)
- [ ] Declares `agent: prototyper`
- [ ] Declares `isolation: worktree`
- [ ] `allowed-tools` includes `Task` (required to spawn `creative-director`)
- [ ] `allowed-tools` includes `AskUserQuestion` (review-mode resolution)
- [ ] `argument-hint` documents the review modes: `[--review full|lean|solo]`
- [ ] Has ≥2 phase headings (actual: 8)
- [ ] Contains verdict keywords: PROCEED, PIVOT, KILL
- [ ] Contains "May I write" language before writing REPORT.md
- [ ] References `.claude/docs/director-gates.md` for the gate pattern
- [ ] Has a next-step handoff to `/gate-check pre-production`

---

## Director Gate Checks

**Gate ID:** `CD-PLAYTEST` (creative-director), invoked in Phase 7.

- [ ] `full` mode → spawns `creative-director` via Task with gate `CD-PLAYTEST`
- [ ] `lean` mode → skips, emitting "CD-PLAYTEST skipped — Lean mode."
- [ ] `solo` mode → skip behaviour is stated explicitly, not silent
- [ ] Director verdict is final; REPORT.md is updated if it differs from the
      skill's own recommendation

---

## Test Cases

### Case 1: Happy Path — Slice built, loop validated, PROCEED

**Fixture:**
- GDDs, architecture, and UX specs complete
- No existing `prototypes/lantern-keeper-vertical-slice/`

**Input:** `/vertical-slice lantern-keeper --review full`

**Expected behavior:**
1. Phase 1 resolves review mode to `full` and loads GDD/architecture/UX context
2. Phase 2 states the validation question and slice scope
3. Phases 3–4 plan and implement one complete start → challenge → resolution cycle
4. Phase 5 runs a playtest debrief
5. Phase 6 asks "May I write this report to
   `prototypes/lantern-keeper-vertical-slice/REPORT.md`?"
6. Phase 7 spawns `creative-director` for `CD-PLAYTEST`
7. Phase 8 recommends `/gate-check pre-production`
8. Verdict is PROCEED

**Assertions:**
- [ ] "May I write" is asked before REPORT.md is created
- [ ] REPORT.md contains `### Executive Summary` with verdict + rationale
- [ ] Build is isolated to `prototypes/` (not `src/`)
- [ ] `CD-PLAYTEST` gate is invoked and its verdict recorded
- [ ] Handoff explicitly names `/gate-check pre-production`
- [ ] Verdict is PROCEED

---

### Case 2: Lean Mode — Director gate skipped, skip is announced

**Fixture:** Same as Case 1.

**Input:** `/vertical-slice lantern-keeper --review lean`

**Expected behavior:**
1. Phase 7 does not spawn `creative-director`
2. Skill emits "CD-PLAYTEST skipped — Lean mode."
3. Verdict still produced from the skill's own analysis

**Assertions:**
- [ ] No `creative-director` Task call is made
- [ ] The skip is explicitly announced, not silent
- [ ] A verdict is still produced
- [ ] REPORT.md notes that the gate was skipped

---

### Case 3: PIVOT — Loop not achievable as specified, re-runnable

**Fixture:**
- Slice built; playtest shows the loop does not hold together at production quality

**Input:** `/vertical-slice lantern-keeper`

**Expected behavior:**
1. Verdict is PIVOT with a specific reason
2. Skill asks "May I write this to
   `prototypes/lantern-keeper-vertical-slice/PIVOT-NOTE.md`?"
3. PIVOT-NOTE.md records what to do differently next run
4. Skill states the slice may be re-run after the pivot

**Assertions:**
- [ ] Verdict is PIVOT (not KILL)
- [ ] "May I write" is asked before PIVOT-NOTE.md
- [ ] PIVOT-NOTE.md names a specific change, not vague advice
- [ ] Re-runnability after PIVOT is stated
- [ ] Prior build artifacts are retained, not deleted

---

### Case 4: PIVOT-NOTE consumed on re-run

**Fixture:**
- `prototypes/lantern-keeper-vertical-slice/PIVOT-NOTE.md` exists from a prior run

**Input:** `/vertical-slice lantern-keeper`

**Expected behavior:**
1. Skill checks `prototypes/` for a `PIVOT-NOTE.md`
2. It uses the note to frame the new validation question in Phase 2

**Assertions:**
- [ ] Existing PIVOT-NOTE.md is detected and read
- [ ] The new validation question references the prior pivot
- [ ] The skill does not silently start from scratch

---

### Case 5: KILL — Soundness check, then GRAVEYARD entry

**Fixture:**
- Slice built; core fantasy is not reachable by the player

**Input:** `/vertical-slice procedural-court`

**Expected behavior:**
1. Before abandoning, the skill runs the KILL soundness checklist
2. 2+ boxes apply → KILL is confirmed sound (0–1 → suggests one targeted PIVOT)
3. Skill documents the kill in `prototypes/GRAVEYARD.md`, creating it if absent
4. GRAVEYARD entry records the kill reason — what specifically prevented the
   player from experiencing the core fantasy

**Assertions:**
- [ ] KILL soundness checklist is run before the verdict is finalised
- [ ] A 0–1 box result recommends PIVOT instead of KILL
- [ ] GRAVEYARD.md is created/appended with a specific kill reason
- [ ] Verdict is KILL
- [ ] Build artifacts are retained for reference

---

### Case 6: Velocity log appended to the vertical slice table

**Fixture:** Slice complete with a PROCEED verdict.

**Input:** `/vertical-slice lantern-keeper`

**Expected behavior:**
1. Skill appends one row to the vertical slice table: concept name, date,
   verdict, and velocity data
2. Table is created if it does not exist

**Assertions:**
- [ ] Exactly one row is appended per run
- [ ] Row includes concept name, date, and verdict
- [ ] Velocity data is captured (flagged in the skill as high-value data)

---

## Protocol Compliance

- [ ] Asks "May I write" before REPORT.md, PIVOT-NOTE.md, and GRAVEYARD.md
- [ ] Creates all files under `prototypes/` (not `src/`)
- [ ] Runs in an isolated worktree per `isolation: worktree`
- [ ] Delegates the build to the `prototyper` agent per `agent: prototyper`
- [ ] Verdict is exactly one of PROCEED / PIVOT / KILL
- [ ] Director gate behaviour matches the resolved review mode
- [ ] Handoff names the next skill (`/gate-check pre-production` on PROCEED)

---

## Coverage Notes

- **Known skill defect:** Phase 6's REPORT.md skeleton describes the executive
  summary as "PROCEED / PIVOT / **STOP**" while every other reference in the
  skill — including its own `description` — uses **KILL**. A verdict-token
  assertion will fail against the Phase 6 heading until the skill is corrected.
  Tracked separately; not a defect in this spec.
- Slice implementation quality is held to production standards here, unlike
  `/prototype` — but the *code style* itself is still not assertion-tested;
  that belongs to `/code-review`.
- The `solo` review mode is exercised only for its skip announcement; its full
  behaviour is not distinguished from `lean` in the current skill text.
- Worktree isolation is asserted structurally (frontmatter) but the actual
  worktree lifecycle is not integration-tested.
- Engine-specific slice scaffolding follows the same flow with engine-appropriate
  file types.
