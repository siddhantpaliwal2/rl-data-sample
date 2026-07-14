# Reference plan — xrepo-meetnotes-latent

## Construction (LATENT-BUG pattern)

Substrate is a clean, isolated, fully-offline slice of the `meeting-notes-app`
repo (a TypeScript Expo/Node app). Two files carry genuinely pure, dependency-
light logic and are the only planted surface:

- `frontend/src/lib/format.ts` — display formatters (`formatDuration`,
  `formatBytes`, plus untouched `formatStatus` / `formatDate` / `truncate`).
  Zero runtime imports (its only import is a type-only `./types`, erased by bun).
- `backend/src/services/search.services.ts` — the keyword search layer. Its pure
  helpers (`includesQuery`, `getTextPreview`, `searchRecordingsByKeyword`) are
  module-private, so the gold tests drive them through the exported
  `searchRecordings` entrypoint in keyword mode. The four collaborator modules it
  imports (embeddings / recordings / qdrant / usage) are replaced by tiny offline
  test doubles; only `recording.services` is exercised (as the data source via
  `__setRecordings`), and it is never mocked — it returns the array the test
  stages, so no bare mock can leak into the logic under test.

The base image `meetnotes-repo:v1` is `oven/bun:1` + `git` + `python3` with this
flattened workspace copied to `/app`. No `bun install`: the targeted code has no
third-party runtime deps and the gold suite uses only `bun:test`. Fully offline.

The task image (`environment/Dockerfile`) builds `FROM meetnotes-repo:v1`, plants
five subtle boundary defects into the clean tree by **exact single-token byte-
substring replacement** (CRLF-safe; each target must occur exactly once or the
build aborts), then collapses git history to a single `import codebase` commit so
the planted state is invisible to `git diff/log/reflog`. The agent starts from
base+defects. There is **no failing local test** at the planted state — the
gold suite is injected only at grade time.

The gold tests (`tests/lib_boundaries.test.ts`) enter only from `config.json`'s
`test_patch`. They feed exactly the edge inputs the defects corrupt and assert the
correct outputs. "Green locally" is not the bar — the grader's edge tests are.

## Defects planted (file : shape : symptom : trigger the mid-range tests never feed)

1. `format.ts` `formatDuration` — hour cutoff `minutes >= 60` → `minutes > 60`
   (comparison flip, MEDIUM). A duration of exactly 60 minutes (3600–3659 s)
   renders as `"60:00"` instead of `"1h 0m"`. Pinned by the hour arithmetic right
   below it (`hours = floor(minutes/60)`, `remMin = minutes % 60`): at 60 minutes
   the hours branch is the consistent one. Mid-range durations (sub-hour, and
   61 min+) render identically under both.

2. `format.ts` `formatBytes` — megabyte precision `.toFixed(1)` → `.toFixed(0)`
   on the MB branch only (numeric-precision constant, EASY). A megabyte-scale
   size loses its decimal (`"5 MB"` / rounds `1.5` to `"2 MB"`) instead of
   `"5.0 MB"` / `"1.5 MB"`. Pinned by the sibling KB branch, which keeps
   `.toFixed(1)`. Byte and kilobyte sizes are untouched.

3. `search.services.ts` `includesQuery` — drops the value-side `.toLowerCase()`
   (`value.toLowerCase().includes(query)` → `value.includes(query)`) (dropped
   normalization, MEDIUM). Case-insensitive keyword matching becomes case-
   sensitive on the stored text, so a lowercase query misses a differently-cased
   title/transcript. Pinned by the query being lowercased before it arrives
   (`normalizedQuery = query.toLowerCase()`): matching is meant to be case-fold on
   both sides. Same-case matches still work.

4. `search.services.ts` `searchRecordingsByKeyword` — result cap
   `results.slice(0, limit)` → `results.slice(0, limit + 1)` (off-by-one on a
   count bound, MEDIUM). With more matches than the limit, one extra result comes
   back. Pinned by the sibling semantic branch, which caps with the identical
   `.slice(0, limit)`. Under-limit result sets are unchanged.

5. `search.services.ts` `getTextPreview` — no-match guard `index < 0` →
   `index <= 0` (comparison flip, EASY). When the query sits at position 0 of the
   transcript, the match is wrongly treated as "not found" and the fallback
   whole-head slice (180 chars) is returned instead of the leading match window
   (120 chars). Pinned by `indexOf` semantics: a found position is `>= 0` and only
   `-1` means absent. Mid-transcript matches (index > 0) are identical under both.

## Oracle fix

`solution/solve.sh` reverse-applies the five single-token replacements, restoring
`minutes >= 60`, the MB `.toFixed(1)`, the value-side `.toLowerCase()`, the
`.slice(0, limit)` cap, and the `index < 0` guard. That is the minimal correct
fix; any equivalent boundary correction that satisfies the gold tests also passes
(e.g. a manual case-fold, `Math.min(results.length, limit)`, or an explicit
found-index check).

## Verifier design

- `tests/test.sh` (canonical SWE-Bench-Pro contract, verbatim from the proven
  bun harness) applies `test_patch` from verifier-controlled config, runs
  `run_script.sh`, parses per-test verdicts, and awards reward 1 only if every
  `fail_to_pass` and `pass_to_pass` test passed.
- `run_script.sh` runs `bun test tests/lib_boundaries.test.ts --reporter=junit`.
- `parser.py` (verbatim) maps the JUnit XML to `{"tests":[{"name","status"}]}`,
  names `"<file>::<describe>::<it>"`; regex-based, no `pyexpat` dependency.
- `fail_to_pass` = 5 gold boundary tests (one per defect; fail at base+defects,
  pass once corrected).
- `pass_to_pass` = 12 gold-file control tests that pass throughout — sub-hour and
  above-hour durations, byte/KB sizes, same-case and absent keyword matches,
  under-limit counts, mid-transcript and title-fallback previews, and the empty
  semantic-mode result set. They guard against lazy over-fixes and pin the
  "green locally" mid-range behaviour.

## Fairness

- Every defected line is on the live path of an exported entrypoint
  (`formatDuration` / `formatBytes` are exported; the search helpers run under the
  exported `searchRecordings`). No dead code.
- The instruction is a symptom report: it names the two source files but no
  function, value, count, boundary direction, or defect shape. With no failing
  local test there is no red-test gradient — the agent must read the boundary
  logic, find each slip among many boundaries, and derive the correct side from a
  sibling.
- Gold tests are pure input/output on the exported formatters and the exported
  search entrypoint. The only collaborator involved is the recordings data
  source, supplied as a typed offline double with explicit values (no bare mock,
  no module-attribute patching), and it is never the thing under assertion.
- Alternative-implementation audit: for each defect, a materially different
  correct fix passes both its f2p and the controls (see Oracle fix). No control
  asserts an implementation detail — the split of the 180-char preview window into
  before/after is never asserted (only the leading-window length, which the
  `< 0` vs `<= 0` guard alone determines).
- Deterministic and fully offline; the verifier runs with `--network none`.
