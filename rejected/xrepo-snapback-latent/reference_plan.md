# Reference plan — xrepo-snapback-latent

## Construction (LATENT-BUG pattern)

Substrate is the isolated `packages/shared` workspace of the snapback
internal-telegram monorepo (a TypeScript/bun standup bot). That package is
pure, dependency-light (only `zod`), and ships its own `bun:test` unit suite, so
it can be built and graded fully offline.

The base image `snapback-repo:v1` is a clean, offline-warm copy of
`packages/shared` on `oven/bun:1` (with `git` + `python3` added and `bun install`
run at build time). The environment Dockerfile plants five subtle boundary
defects into the clean working tree and then collapses git history to a single
`import codebase` commit, so the planted state is invisible to `git diff/log`.
The agent starts from base+defects.

There is **no failing local test** at the planted state: all 37 existing shared
unit tests stay green, because every visible test feeds mid-range values (or the
exact guards it already pins) and never lands on the edge that bites.

The gold tests (`tests/shared_boundaries.test.ts`) are injected only at grade
time from `config.json`'s `test_patch`. They feed exactly the edge inputs the
defects corrupt and assert the correct outputs. "Green locally" is not the bar —
the grader's edge tests are.

## Defects planted (file : symptom : trigger the visible tests never feed)

1. `packages/shared/src/time.ts` `toTimeKey` — `hour12: false` → `hour12: true`.
   The 24-hour schedule key is rendered in 12-hour form, so any afternoon
   instant (13:00–23:59) and midnight lose their hour (1:30 PM → "01:30",
   00:15 → "12:15"). Morning/noon are identical in both forms, and **no visible
   test calls `toTimeKey` at all** — its 24-hour intent is derivable from the
   sibling `toDateKey`, which builds the same canonical `Intl` key.

2. `packages/shared/src/dates.ts` `tomorrowDateKey` — `Date.now() + DAY` →
   `Date.now() - DAY`. "Tomorrow" resolves to yesterday. `dates.test.ts` only
   exercises `toDateKey`; `tomorrowDateKey` is untested. Correct direction is
   derivable from the function name and from `toDateKey` (today's key).

3. `packages/shared/src/callbacks.ts` `callbackActionSchema` — the `"instagram"`
   member is dropped from the enum. `parseCallback("standup:instagram:…")`
   returns `null`, so that button's callback is ignored. Visible tests
   round-trip only `"task"` and reject `"wake"`/unknown; none route `"instagram"`.
   Membership is derivable from the parallel `instagram_check` standup step in
   `domain.ts` / `schemas.ts`.

4. `packages/shared/src/schemas.ts` `integrationItemSchema.title` —
   `z.string().min(1)` → `z.string().min(0)`. A blank title is accepted. Visible
   tests reject a blank *id* (title incidental) and never feed a blank title.
   Derivable from the sibling `id: z.string().min(1)` in the same object.

5. `packages/shared/src/schemas.ts` `standupStateSchema.habitIndex` —
   `z.number().int().min(0)` → `z.number().min(0)` (drop `.int()`). A fractional
   habit index is accepted. The visible reject case for `habitIndex` uses `-1`
   (still caught by `min`), and the `.int()` case it pins is on the sibling
   `taskIndex` (`1.5`), which is left intact. Derivable from that sibling
   `taskIndex: z.number().int().min(0)`.

## Oracle fix

`solution/solve.sh` reverse-applies the planted defect patch, restoring
`hour12: false`, `Date.now() + DAY`, the `"instagram"` enum member,
`title.min(1)`, and `habitIndex.int()`. That is the minimal correct fix; any
equivalent boundary correction that satisfies the gold tests also passes.

## Verifier design

- `tests/test.sh` (canonical contract) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `run_script.sh` runs `bun test` on the gold file plus the four existing shared
  test files, emitting a JUnit XML report.
- `parser.py` maps that JUnit XML to `{"tests":[{"name","status"}]}`; test names
  are `"<file>::<classname>::<testname>"`. It is regex-based so it needs no
  `pyexpat`/libexpat.
- `fail_to_pass` = 5 gold boundary tests (one per defect; fail at base+defects,
  pass once corrected).
- `pass_to_pass` = 14 tests that pass throughout: 6 gold-file control tests
  (guarding against lazy over-fixes) + 8 existing shared unit tests (the "green
  locally" lull).

## Fairness

- Every defected symbol is exported from `packages/shared` and reachable by
  consumers; the shared package's own `bun install` + suite prove they are live.
- The instruction is a symptom report: it names no file, function, value, count,
  or defect shape. It describes user-visible wrong behavior and points only at
  "the shared helper package."
- Each defect's correct side is derivable from a sibling in the same file (or
  the package's own type definitions), never from a hidden test's assertion.
- Gold tests are pure input/output on exported functions and schemas — no
  collaborator mocks. The only time control is `bun:test`'s `setSystemTime`,
  used solely to pin the wall clock for `tomorrowDateKey`; it encodes no
  implementation choice (any correct "day after today" passes).
- Deterministic and fully offline; the verifier runs with `--network none`.
