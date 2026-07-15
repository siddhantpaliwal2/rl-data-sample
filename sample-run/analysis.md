# Analysis: frontier-model pass@k matrix (8 models × 4 harnesses, ~780 valid trials)

Every major lab's latest API-available frontier coding model (July 2026) was
run against the eight tasks with n≈10 attempts per (model, task) cell on the
OpenCode harness, and the flagship models across four additional harnesses at
n≈3. All numbers are in the README's pass@k matrix; per-trial data in
`passk_matrix.json`; one representative trajectory per cell (a solving one
where any exists) in `trajectories-matrix/`.

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
visible suite (a repeated pattern: plausible-looking edits to the wrong lines, validated only against the already-green visible suite, with flat 9–21-step effort regardless of task difficulty). Gemini 3.5 Flash and
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

**7. The strongest trajectories share a repro-first loop.** Models that
solve tasks write a small script reproducing the reported symptom before
editing, trace it to a root cause rather than the first plausible file,
re-run the reproduction after each fix, and scale effort with difficulty
(roughly 3× more steps on the hardest tasks). Models that never solve
anything skip the reproduction step and validate against the visible test
suite — which is green by construction.

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
