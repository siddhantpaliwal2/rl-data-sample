# Amazon Nova vs. Claude — Agentic SWE Benchmark (Harbor / mini-swe-agent)

**Status: IN PROGRESS** — this report is being filled as jobs complete. Last updated during run.

## Setup

- **Harness:** Harbor 0.18.0, agent `mini-swe-agent` (tool-calling mode: every turn must emit a `bash` tool call), `-k 5 -n 5` (5 trials/job).
- **Tasks:** 6 real bug-fix/feature tasks from the `loangenus` fintech codebase, graded by fail-to-pass (f2p) + pass-to-pass (p2p) pytest suites. Reward = 1.0 only if ALL f2p pass and no p2p regresses (all-or-nothing).
- **Models under test:** `amazon/nova-premier-v1` (flagship), `amazon/nova-pro-v1`, `amazon/nova-2-lite-v1` — all via OpenRouter → Amazon Bedrock.
- **Claude baselines:** measured `claude-sonnet-4-6` and `claude-opus-4-8` runs on the same tasks/harness.
- **Key harness note:** Bedrock Nova has **no prompt caching** on this route, so mini-swe-agent's growing context is billed in full each step (Claude runs are ~99% cache-hit).

## Difficulty ladder & Claude baselines (measured, same harness)

| Task | f2p / p2p | Sonnet | Opus | Notes |
|---|---|---|---|---|
| plaid-bank-report | 6 / 3 | 0/5 | 10/10 | easiest; single-file fallback fix |
| quickbooks-sync | 12 / 3 | 0/10 | 7/10 | |
| calls-v2 | 14 / 18 | 0/5 | 8/10 | large repo, ~5M tok/trial |
| cre-scoring-latent-4 | 9 / 12 | 0/5 | 0/10 | hardest; latent multi-defect, opus also 0 |
| latent-financial-tools | 8 / 10 | 0/5 | 8/10 (opusB recut) | 5-defect recut |
| latent-market-structure | 7 / 20 | 3/5 | 9/10 | 5-defect |

## Solve-rate table (task × model)

_(Nova columns filled as jobs complete; k=5 for Nova, sonnet k=5–10, opus k=10)_

| Task | Sonnet | Opus | Nova Premier | Nova Pro | Nova 2 Lite |
|---|---|---|---|---|---|
| plaid-bank-report | 0/5 | 10/10 | _pending_ | **0/5** | **0/5** |
| quickbooks-sync | 0/10 | 7/10 | _pending_ | _pending_ | _pending_ |
| calls-v2 | 0/5 | 8/10 | _pending_ | _pending_ | n/a |
| cre-scoring-latent-4 | 0/5 | 0/10 | _pending_ | _pending_ | n/a |
| latent-financial-tools | 0/5 | 8/10 | _pending_ | _pending_ | n/a |
| latent-market-structure | 3/5 | 9/10 | _pending_ | _pending_ | _pending_ |

## Failure-mode taxonomy

- **(a) format/protocol** — malformed/absent tool calls; mini-swe aborts with `RepeatedFormatError` after 3 consecutive turns lacking a tool call.
- **(b) early-give-up / step-limit** — little progress, hit step cap or bailed.
- **(c) localization** — never found/edited the right file(s).
- **(d) partial fix** — some f2p pass, some fail.
- **(e) regression** — broke p2p (includes edits that corrupt the module so it no longer imports → all tests fail).
- **(f) context/verbosity** — pathological token blow-up with no progress.

## Preliminary findings (calibration on plaid-bank-report)

1. **Nova 2 Lite cannot sustain the tool-calling protocol.** 5/5 trials aborted with `RepeatedFormatError` after 1–3 steps. It makes an initial `bash` tool call, then reverts to emitting plain prose with no tool call; mini-swe rejects three in a row and kills the trial. (Zero Claude trials across 336 exhibited this.)
2. **Nova Pro localizes but corrupts the file.** 2/5 trials ran full trajectories (17 steps), correctly found `report_service.py` and targeted `build_bank_report_view`, but their sed/heredoc edits introduced a syntax error — pytest then "collected 0 items / 1 error" (module import failure), failing all 6 f2p AND all 3 p2p. The other 3/5 Pro trials also hit `RepeatedFormatError`. Pro also hallucinated environment limits ("environment does not support changing directories… ask the user to run the tests manually") and never verified its edit.

_(more to come)_
