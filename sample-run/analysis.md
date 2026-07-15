# Analysis: Amazon Nova Premier vs Claude Opus 4.8, OpenCode harness, 8 latent-defect tasks

**Setup.** One attempt per (task, model): 16 cells, all parallel, one Daytona
sandbox each (identical 2-CPU/4-GB amd64 images, null/oracle-verified). Agent:
OpenCode with thinking enabled, orchestrated by harbor; models via OpenRouter
(`amazon/nova-premier-v1`, `anthropic/claude-opus-4.8`). Every cell produced a
full trajectory (`trajectories/`) and a fully-graded verdict set — no crashed
or vacuous cells. Headline tables are in `results.md`; raw data in
`results.json`.

## The one-line result

**Both models score 0/8 on pass@1 — and that tie is the least informative
number in this dataset.** Opus fixed 30 of the 43 planted defects and finished
*exactly one test short of full reward on six of the eight tasks*. Nova fixed
0 of 43: on every task its required-tests-passed count is byte-identical to
the untouched baseline. One model is at the frontier's edge of these tasks;
the other never landed a punch. The all-or-nothing reward — by design — hides
that gap; the per-test verdicts expose it.

## Where Opus won, and why

Opus's trajectories show the same three-beat loop on every solved defect:
**reproduce → localize by behavior → verify with a self-written script.** It
converts each symptom in the instruction into a small runnable repro (e.g.
feeding `'CHASE'` vs `'Chase'` tradelines through the dedupe helper), traces
the wrong output to a specific comparison, fixes the single token, and re-runs
its repro plus the visible suite.

Representative evidence:

- **latent-credit-normalize — 4/5.** Its four fixes are exact: restored the
  case-fold in the junk filter, the case-fold in the dedupe key, added the
  missing Equifax abbreviation to the tag regex (in a *different but
  behaviorally equivalent* position from the oracle patch — the gold tests
  accept it because they assert behavior, not the edit), and re-anchored the
  address-suffix regex.
- **latent-doc-extractors — all 4 gated defects fixed, plus the 5th
  reward-ungated defect** (a scan-floor comparison no graded test
  distinguishes). It found and fixed a planted bug it was never going to be
  paid for — the clearest sign of genuine root-cause work rather than
  test-chasing.
- **xrepo-fiu-latent — fixed precisely the two concretely-reported defects**
  (UUID regex quantifier, 12-vs-24-hour timestamp format) in a 264-file Java
  codebase, matching the fix sites through Maven-heavy exploration.

## Why Opus still scored zero, task by task

Three distinct failure modes, all instructive:

1. **One needle short (5 tasks).** On credit-normalize it fixed everything
   except the digit-leading-creditor anchor — the same defect the platform
   probe missed in 9/10 mini-swe trials. On phone-invites, financial-tools,
   txenrich, and txenrich3 the story repeats with each task's rare-trigger
   defect (no-region interpretation, single-severe-late boundary, payee
   segment slice, ₹1 mandate sentinel). These "load-bearing" defects are
   described only obliquely by the instructions, and finding them requires
   deriving intent from sibling code rather than replaying a reported symptom.
2. **One boundary too far (doc-extractors).** Opus fixed all four gated
   defects, then over-corrected the rent-roll minimum from `count >= 3` to
   `count >= 1` — even though the ticket itself states two rows is the
   smallest valid roll. The pass_to_pass test for "a single rent line is not a
   roll" caught it. A perfect fix of the reported cases, destroyed by not
   respecting a boundary the instruction explicitly stated.
3. **Endurance and breadth walls (fiu, txenrich4).** On fiu it fixed the two
   ticketed defects but never derived the three noun-level families (base64url
   alphabet, `@`-handle index, whitespace emptiness) — an exact mirror of the
   mini-swe failure spread, suggesting the miss is informational, not
   scaffold-dependent. On txenrich4 it spent its largest budget of the run (69
   steps, 862s, $4.91) and flipped nothing: five findings across two of ~35
   visually identical bank scripts was too much simultaneous localization even
   for the strongest configuration tested.

## Where Nova failed, and the pattern behind it

Nova's eight trajectories share one shape, visible end to end in
`trajectories/*--nova-premier.trajectory.json`:

1. **Glob → read → plausible edit → visible-suite green → stop.** On fiu
   (9 steps, 91s) it modified a UUID *string-comparison* helper rather than
   the validation regex the symptom traces to, and added a timezone to a
   date formatter that is not the one rendering the wrong hour. Both edits
   are superficially on-topic — right nouns, wrong code.
2. **It validates against the wrong oracle.** In every trajectory Nova's
   final action is running the *visible* test suite (green by construction —
   that is the latent-defect premise) or nothing at all, then stopping
   without a summary. It never writes its own repro for a reported symptom,
   so it has no way to notice its edits changed nothing.
3. **It attempts a minority of the findings.** Instructions list 4–5 symptom
   families; Nova's edits engage 1–2 of them, always the most concrete ones.
   The abstractly-described families are never attempted.
4. **Uniform low effort regardless of difficulty.** 9–21 steps and
   $0.25–0.64 on every task, hard or easy. Opus's effort scales with task
   difficulty (20 steps on the easiest → 69 on the hardest); Nova's is flat —
   the signature of a model that stops when its first hypothesis is exhausted
   rather than when the problem is solved.

The net effect is remarkable: **zero graded tests moved in either direction
across all eight tasks.** Nova was not wrong so much as inert — its edits
were behaviorally invisible to the graded surface.

## Where Nova won

Economics and latency, decisively: $3.50 total vs $16.81 (4.8×), 24.7 min of
agent time vs 53.2 min (2.2×), and it never broke a passing test (a low bar it
clears mostly by touching little that matters). If the metric were
cost-per-attempt, Nova wins every row. On cost-per-fixed-defect, Nova's ratio
is undefined — $3.50 for zero defects — while Opus paid ~$0.56 per fixed
defect. There was no task, and no individual graded test, where Nova succeeded
and Opus failed.

## Patterns worth keeping

- **Binary reward at the frontier compresses real signal.** A pass@1 tie of
  0/8 vs 0/8 coexists with a 30-vs-0 defect-fix gap. For RL data, that is the
  intended property (the reward concentrates on the last, hardest defect), but
  any *evaluation* use of these tasks should report required-tests-passed
  alongside reward.
- **The load-bearing-defect design works against strong scaffolds too.** The
  same rare-trigger defects that held the mini-swe probe to 0–4/10 are the
  ones that stopped OpenCode+Opus. The difficulty is in the information
  structure of the task, not the weakness of the harness.
- **Concrete symptoms get fixed; noun-level families don't.** Across both
  models and both harnesses, every concretely-reported symptom was fixed by
  Opus and every obliquely-gestured one was hit-or-miss. Instruction
  specificity is the difficulty dial, with roughly a full difficulty tier per
  notch.
- **Frontier separation shows up first in *how* models fail.** Opus fails by
  missing the last needle or overshooting a boundary; Nova fails by editing
  the wrong code and trusting the wrong oracle. The trajectories, not the
  scores, are where the capability gap lives.

## Caveats

- k=1 per cell: single attempts, so per-task results carry binomial noise;
  the aggregate pattern (30/43 vs 0/43 over eight independent tasks) does not.
- OpenCode is a stronger scaffold than the mini-swe-agent probe used for the
  bank's difficulty calibration; numbers here are not comparable to the
  README's gate table. (The planned pivot to mini-swe was unnecessary: Opus
  solved nothing outright on OpenCode, so the harness was not saturating.)
- Nova Premier was routed via OpenRouter → Bedrock without prompt caching;
  its cost advantage here is real but its latency/cost profile could differ
  under a cached route.
