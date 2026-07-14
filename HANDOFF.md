# Silver-task pipeline — session handoff

You are taking over a task-authoring pipeline. Goal: produce **10 "silver" coding tasks** where a
frontier LLM agent fails most of the time — for an AfterQuery-style RL dataset. **8 are banked; you
need 2 more (plus polish).** Everything below is self-contained; read it fully before acting.

---

## 0. The one-line goal
A task passes the gate iff, measured with **mini-swe-agent** (NOT a strong scaffold):
- **Easiness:** Sonnet-4.6 ×5 attempts, solved **≤1/5**.
- **Difficulty:** Opus-4.8 ×10 attempts, solved **1–6/10** (user relaxed AfterQuery's 1–4 to ≤6).
- Plus mechanical validity: nop reward 0, oracle reward 1 (already verified for all built tasks).

**CRITICAL — gate with mini-swe-agent only.** A strong scaffold (Claude Code agent loop) solves these
tasks bimodally (all-or-0) and is the WRONG measure. AfterQuery's own probe uses
`mini-swe-agent --yolo --model=openrouter/anthropic/claude-opus-4.8`. Match it. Ignore any
strong-scaffold "re-measurement."

---

## 1. Where everything lives
- **Working dir / git repo:** `/Users/siddhantpaliwal/Desktop/boostmoney-audit/silver-tasks/`
  (git repo, remote `https://github.com/siddhantpaliwal2/rl-data-sample.git`, branch master, private).
- **Task layout:** `approved/<name>/` = the 8 banked. `<name>/` (top-level) = built candidates awaiting gate.
  `rejected/<name>/` = failed attempts (reference). `banked/` = frozen snapshots + CHECKSUMS.json.
- **Ledger:** `BANK.json` (banked list, gate_of_record, rejected_notes). `CONSTRUCTION_V2.md` = the recipe.
  `SCAFFOLD_RECIPE.md` = mechanical 9-file task layout.
- **Source repos (to mine for new tasks):**
  - `/Users/siddhantpaliwal/Desktop/boostmoney-audit/loangenus` (66k LOC Python — the workhorse; 5 banks from it)
  - `/Users/siddhantpaliwal/Desktop/boostmoney-audit/loan-genai-backend`, `.../correlation-core`
  - `/Users/siddhantpaliwal/Downloads/Backup-FinBit/transaction-enrichment-python` (35 bank-categorization scripts!)
  - FinBit Java repos: `.../Backup-FinBit/{fiu_adapter, finscore, finbit-fipconnect, ...}`
- **Gate trial logs:** `jobs/<job-name>/` (gitignored, heavy). Read per-trial reward at
  `jobs/<job>/<trial>/result.json` → `verifier_result.rewards.reward` (1.0 = solved; `null` = errored/crashed).

## 2. API keys — MATCH KEY TO MODEL (this bug wasted a batch)
- `.harbor_env` → **ANTHROPIC_API_KEY only**. Use with `-m anthropic/claude-opus-4-8` / `anthropic/claude-sonnet-4-6`.
- `.harbor_env3`, `.harbor_env3b` → ANTHROPIC **+ OPENROUTER**. Use with `-m openrouter/anthropic/claude-opus-4.8`.
- `.openrouter_env` → OPENROUTER only.
- **If you source `.harbor_env` (anthropic key) but run an `openrouter/...` model, every trial errors with
  `ValueError: Unset OPENROUTER_API_KEY` and you get a bogus 0/10.** Always match.

## 3. How to gate a task (exact commands)
```sh
cd /Users/siddhantpaliwal/Desktop/boostmoney-audit/silver-tasks
set -a; source .harbor_env3; set +a          # openrouter key for the openrouter model below
# DIFFICULTY (run first — it's the discriminator):
harbor run -p <path-to-task> -o jobs --job-name <name>--opus-c2 \
  -k 10 -n 5 -q -y -a mini-swe-agent -m openrouter/anthropic/claude-opus-4.8
# EASINESS (only if opus lands 1-6):
harbor run -p <path-to-task> -o jobs --job-name <name>--sonnet-c2 \
  -k 5 -n 5 -q -y -a mini-swe-agent -m openrouter/anthropic/claude-sonnet-4.6
```
- `<path-to-task>` = `approved/latent-financial-tools` for banked, or `xrepo-txenrich2-latent` for candidates.
- **CONCURRENCY DISCIPLINE (the biggest lesson):** mini-swe-agent trials CRASH under load, and crashes count
  as fails → contaminated numbers. Keep **≤ ~15 concurrent trials total** (use `-n 3` to `-n 5`, ≤3 tasks at once).
  At 45–86 containers, ~half of trials crashed and I recorded false-hard numbers. After each job, **check error
  count**: `sum(1 for t if json.load(t).get('exception_info'))`; if >1, the result is untrustworthy — rerun clean.
- Each repo needs its base image present (`docker images | grep repo:v1`): `loangenus-repo:v1`, `correlation-repo:v1`,
  `loangenai-repo:v1`, `txenrich-repo:v1`, `fiu-repo:v1`, `finscore-repo:v1` all exist. Task images (`*-task:v1`) exist too.

## 4. Current state
**8 BANKED** (in `approved/`, all mini-swe clean or crash-affected-but-≤6):
| task | repo | opus |
|---|---|---|
| latent-phone-invites | loangenus | 1/10 |
| xrepo-txenrich-latent | transaction-enrichment-python | 1/10 |
| latent-doc-extractors | loangenus | 1/10 |
| latent-credit-normalize | loangenus | 3/10 |
| latent-financial-tools | loangenus | 4/10 (6 crashes in run — clean re-gate optional) |
| latent-market-structure | loangenus | 6/10 (7 crashes — may be too-easy clean; verify) |
| xrepo-correlation-latent | correlation-core | 1/10 |
| xrepo-loangenai-latent | loan-genai-backend | 6/10 (4 crashes) |

**6 CANDIDATES BUILT + ladder-verified (nop 0 / oracle 1), NOT yet clean-gated** — gate these to fill slots 9-10:
`xrepo-txenrich2-latent` (top pick — clone of the 1/10 txenrich, Kotak/SBI banks), `xrepo-fiu-latent` (Java),
`xrepo-loangenai2-latent`, `latent-doc-qa`, `latent-doc-scoring` (last two disjoint, both usable).

**IMMEDIATE NEXT STEP:** gate `xrepo-txenrich2-latent` and one other candidate (opus first, ≤15 concurrent).
If opus lands 1–6, run sonnet ≤1/5, then bank. Two in-band candidates = 10 done. Then `git add -A && commit && push`.

## 5. The construction recipe (CONSTRUCTION_V2.md has full detail)
Tasks are **planted-latent-defect** tasks: take a large repo at a base commit, plant **5 single-token defects**
(e.g. `>= → >`, `max → min`, an index/slice off-by-one) in **deterministic pure-logic** code (parsers,
categorizers, scoring/financial math), so:
- The visible test suite stays GREEN (defects bite only edge inputs the visible tests never feed).
- Gold tests live ONLY in `tests/config.json`'s `test_patch` (never in the agent's tree).
- Git history is sealed: Dockerfile does `rm -rf .git && git init && commit -m "import codebase"` so the fix
  isn't recoverable from history.
**Calibration rules that actually matter (learned the hard way):**
1. **Derivability:** each defect's correct side must be uniquely derivable from visible code (a sibling line, a
   named constant, a docstring, a math definition). A "convention-pick" (unpinned `>=` vs `>`, `+` sign on 0) is
   solved ~0/10 and sinks the WHOLE task to 0 (must-find-all). ZERO convention-picks.
2. **Mix:** 2 EASY (adjacent-sibling-pinned) + 3 MEDIUM (pinned only by cross-function tracing). 5 distinct shapes,
   no grep-twins, no obvious inverted-guard drops (Sonnet finds those).
3. **Substrate SIZE:** the repo/file must be big enough that *localization is real work*. Small repos
   (LinkShortner 872 LOC, single-file TS formatters) → agent reads everything → too easy (Opus 9-10/10). All 8
   banks are in large repos. Reject small ones.
4. **Load-bearing defect:** the Opus-1/10 tasks each have ONE rare-trigger MEDIUM defect that fails ~9/10
   (e.g. txenrich's "-1 sentinel verification debit", extractors' "sum two rent lines"). Include one to pull hard.
- **Fastest source of new hard tasks:** `transaction-enrichment-python` has 35 bank-categorization scripts
  (only HDFC/ICICI/Kotak/SBI used) — each is rule-dense and clones the 1/10 winner. Also loangenus has many
  unused module clusters. Use disjoint files per task (check each `approved/*/SCAFFOLD_REPORT.json` `modules_used`).

## 6. How to build a new task (if you need more than the 6 candidates)
Spawn a subagent per task with a brief that says: read `approved/latent-financial-tools/` (canonical 9-file
layout + Dockerfile-from-`<repo>-repo:v1` + tests harness) and `CONSTRUCTION_V2.md`; pick a disjoint pure-logic
cluster in a LARGE repo; plant 5 single-token defects (2 easy + 3 medium, zero convention-picks, ≥1 load-bearing
rare-trigger); author `tests/test_<x>_boundaries.py` (pure-input, zero-mock, 5 f2p + 10-14 p2p, in `test_patch`
only); seal git; verify ladder in docker `--network none` (git len 1, diff empty, NULL reward 0 with all f2p
per-test FAILED, ORACLE reward 1, PARTIAL 0). Java tasks: copy the `xrepo-fiu-latent` / `finscore` Maven+Surefire
harness (warm the junit-platform provider with one throwaway online test, then `mvn -o test` offline).

## 7. Infra note (optional, for scale)
All gating is on ONE local Docker daemon → the concurrency ceiling (~15 clean) is the main throughput limit and
the source of the crash-contamination. Harbor supports `-e daytona` / `-e modal` (cloud sandboxes, one per trial)
which removes the ceiling — worth setting up (needs a Daytona key + pushing the `*-repo:v1` images to a registry)
if this becomes an ongoing/scaled pipeline. Not needed to finish the last 2.

## 8. Don't repeat these mistakes
- Don't gate with a strong scaffold. mini-swe-agent only.
- Don't run >~15 concurrent trials; check `exception_info` count before trusting any result.
- Match the API-key env file to the model provider.
- Don't build tasks on small repos or with convention-pick defects.
- Don't trust a single 10-trial run with crashes — rerun clean.
