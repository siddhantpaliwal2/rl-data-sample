# Reference plan — linkshort-boundary-latent-bugs

## Construction (LATENT-BUG pattern)

Base is the clean HEAD of the LinkShortner FastAPI backend (`backend/`), carried
in the reusable repo image `linkshort-repo:v1` (python:3.11-slim + a curated,
security-reviewed dependency set — the repo's own UTF-16 `requirements.txt` is
NOT installed verbatim; it lists several typosquat-shaped packages that no code
under test imports). The environment Dockerfile applies a small **defect patch**
that plants five subtle single-token boundary slips across three modules, then
collapses git history to a single commit so nothing is recoverable via
`git diff`/`log`/`reflog`.

The agent starts from base+defects. There is **no failing local test** pointing
at any defect: the visible suite (`tests/test_links.py`, 16 tests driving the
HTTP app via `TestClient`) stays fully green with the defects present, because
every visible test feeds values comfortably inside the ranges and never lands on
the exact edge that bites. `list_links` still has visible green coverage via the
owner-scoping test, so no path looks conspicuously untested.

The gold tests (`tests/test_linkshort_boundaries.py`) are injected only at grade
time from `config.json`'s `test_patch`. They feed exactly the edge inputs the
defects corrupt and assert the correct outputs. "Green locally" is not the bar —
the grader's edge tests are.

## Defects planted (file : boundary slip : edge the visible tests never feed)

1. `config.py` `parse_authorized_parties` — whitespace-only CSV element filter
   `if party.strip()` weakened to `if party`. A blank/whitespace element is kept
   as `""` instead of dropped. The adjacent `parse_cors_allowed_origins` still
   uses `if origin.strip()`, so the two parsers disagree.

2. `main.py` `_rate_limit_key` — bearer-token slice `auth[7:]` shifted to
   `auth[6:]`. The scheme guard matches `"bearer "` (7 chars), so the key gains a
   stray leading space (`"user: TOK"` instead of `"user:TOK"`).

3. `services.py` `_as_utc` — the tz-aware branch `value.astimezone(timezone.utc)`
   replaced with `value.replace(tzinfo=timezone.utc)`. A non-UTC offset is
   relabelled UTC (offset dropped) rather than converted; the naive branch above
   legitimately uses `.replace`, which is what makes the slip read as natural.

4. `services.py` `list_links` — pagination offset `(page - 1) * page_size`
   changed to `page * page_size`. Page 1 skips the first `page_size` rows.

5. `config.py` `prefer_psycopg_driver` — `str.replace(old, new, 1)` loses its
   count argument, so an embedded second `postgresql://` (e.g. in a callback
   query param) is rewritten too; only the leading scheme should change.

Only `test_links.py::test_paginated_list` would go red under defect #4; it is
removed from the visible tree in the environment (invisible after history
collapse) so the visible suite stays green. It is NOT restored — grading runs
only the boundary file.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring `if
party.strip()`, `auth[7:]`, `.astimezone(timezone.utc)`, `(page - 1) *
page_size`, and `.replace(..., 1)`. Any equivalent boundary correction also
passes the gold tests.

## Verifier design

- `tests/test.sh` (verbatim canonical) applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts,
  and awards reward 1 only if every `fail_to_pass` and `pass_to_pass` test
  passed.
- `fail_to_pass` = the 5 gold boundary tests (one per defect, disjoint; fail at
  base+defects, pass once corrected).
- `pass_to_pass` = 12 adjacent-correct boundary pins (list passthrough, plain
  CSV, the sibling CORS parser, anonymous rate-limit key, naive/None/UTC
  `_as_utc`, count/empty-owner listing, single/non-postgres/already-psycopg URL).
- `run_script.sh` runs only `tests/test_linkshort_boundaries.py`.

## Fairness

- All five defected functions are live code reachable from the HTTP handlers
  (`create_short_link` → `_persist_link` → `_as_utc`; `list_short_links` →
  `list_links`; the limiter key func; `Settings` construction at startup).
- The instruction names the three modules and the five symptoms at the
  behavior level but not the functions, lines, boundary directions, trigger
  values, or the count — the agent must read and reason about each boundary to
  locate and correct the slip.
- No mocks in the gold tests: pure function calls plus a real in-memory SQLite
  session (mirroring `tests/conftest.py`) for the pagination case.
- Deterministic, offline, single required env var (`LINK_SHORTENER_DATABASE_URL`,
  baked into the image as `sqlite://`).
