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

---

# Addendum: 14-way frontier matrix (8 models × 4 harnesses, ~780 valid trials)

The two-model comparison above was extended to every major lab's latest
API-available frontier coding model (July 2026) and across five agent
harnesses, with n≈10 attempts per (model, task) cell on OpenCode and n≈3 on
the other harnesses. All numbers in the README's pass@k matrix; per-trial
data in `passk_matrix.json`; one representative trajectory per cell (a
solving one where any exists) in `trajectories-matrix/`.

## Findings and patterns

**1. The bank ranks the frontier cleanly.** GPT-5.6 Sol (mean pass@1 0.200,
pass@10 0.750) > Opus 4.8 / GPT-5.5 / GLM-5.2 (≈0.10) > Gemini 3.5 Flash >
DeepSeek V4 Pro > Nova 2 Lite = Nova Premier (0.000 over ~160 combined
trials). The ordering is stable across tasks, not driven by a single outlier
cell.

**2. Harness choice is worth as much as a model generation.** The same
Opus 4.8 scores 0.075 (mini-swe), 0.100 (OpenCode), 0.271 (claude-code);
Sol scores 0.156 (terminus-2), 0.200 (OpenCode), 0.396 (codex). The
codex+Sol pairing at pass@3 0.625 is the strongest configuration measured.
Aider+Opus scored zero — its diff-oriented editing loop never survived the
must-fix-all-five bar. Difficulty numbers are meaningless without naming the
harness; the matrix format forces this.

**3. pass@1 vs pass@10 separates "can't" from "won't always".** Sol's 0.200
pass@1 becomes 0.750 pass@10 — six of eight tasks fall to repeated attempts.
The zero-rows stay zero at every k: ~80 attempts each for Muse Spark and the
two Novas produced not one reward. On this bank, attempt-scaling rescues
capable models and does nothing for incapable ones — exactly the property an
RL reward should have.

**4. Every task is now empirically solvable, and two remain frontier-hard.**
txenr4, unsolved by 13 of 14 rows including every Sol and Opus
configuration, fell once to GLM-5.2 (1/13). fin-tools fell only to
Gemini 3.5 Flash (2/10) — interestingly, a task every other model failed.
Cross-model coverage beats any single-model probe for verifiability
evidence: the two hardest tasks were each validated by a *different*
unexpected model.

**5. Zero- and low-rows fail for different reasons (trajectory evidence).**
The Novas edit plausible-but-wrong code and validate against the green
visible suite (see the original two-model analysis). Gemini 3.5 Flash and
DeepSeek V4 Pro localize partially but rarely complete all five fixes within
their attempt budgets. Distinct failure taxonomies, all visible in
`trajectories-matrix/`. (Muse Spark 1.1 and aider+Opus were excluded after
trace review: their attempts died on provider auth / parameter errors before
any model work — infrastructure faults, not model results.)

**6. Task difficulty spread maps the frontier.** doc-extract is farmable by
strong pairs (codex+Sol 3/3, claude-code+Opus 3/3), while fin-tools and
txenr4 hold under 3% pass@1 across all 14 configurations. A bank whose
easiest task is ~40-60% for the best pairing and whose hardest is ~2%
brackets the July-2026 frontier from both sides.

## Methodology notes

- 16 initial cells ran as a 40-cell parallel wave plus 648-trial top-up; a
  Daytona org-capacity overrun invalidated most of the first top-up wave
  (sandbox-starved trials produced no verdicts). All invalid trials were
  excluded by the non-empty-verdicts rule and re-run through a
  bounded-concurrency orchestrator (12 jobs at a time). Nothing vacuous
  entered the matrix.
- Muse Spark 1.1 runs via the Meta Model API (OpenAI-compatible surface)
  through OpenCode's `openai` provider with a custom base URL; all other
  non-Anthropic models via OpenRouter; Claude via the Anthropic API.
- Costs: ~$385 OpenRouter + ~$175 Anthropic + <$20 Meta across ~880 trials.
