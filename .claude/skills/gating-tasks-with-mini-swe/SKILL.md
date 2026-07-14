---
name: gating-tasks-with-mini-swe
description: Use when measuring a silver task's difficulty or easiness, before banking any task, when trials show NonZeroAgentExitCodeError or reward=null, or when choosing which API env file to source for a harbor run.
---

# Gating Tasks with mini-swe-agent

## Overview
A task banks iff, measured with **mini-swe-agent**: Sonnet-4.6 solves ≤1/5 AND Opus-4.8 solves 0–6/10 (0/10 only after the fairness triage in designing-latent-defect-tasks). Difficulty (Opus) runs first — it's the discriminator; easiness (Sonnet) only if Opus lands.

## The Iron Rule: mini-swe-agent ONLY

**Never gate with a strong scaffold (Claude Code agent loop).** Strong scaffolds solve these tasks bimodally — every task reads all-or-nothing, nothing lands mid-band — and the numbers are meaningless for this dataset. AfterQuery's own probe is `mini-swe-agent --yolo`. A strong-scaffold re-measurement once invalidated a whole day of numbers here.

| Rationalization | Reality |
|---|---|
| "Claude Code is a more realistic solver" | The consumer's probe is mini-swe-agent. Match the measure, not realism. |
| "I'll just sanity-check with my own loop" | Its bimodal result will tempt you to re-tune good tasks. Don't generate the number. |

## Commands

```sh
cd silver-tasks && set -a; source .harbor_env3; set +a   # match key to model! (below)
# DIFFICULTY first:
harbor run -p <task-dir> -o jobs --job-name <name>--opus-cN \
  -k 10 -n 4 -q -y -a mini-swe-agent -m openrouter/anthropic/claude-opus-4.8
# EASINESS (only when opus is in-band — or the moment it's mathematically in-band):
harbor run -p <task-dir> -o jobs --job-name <name>--sonnet-cN \
  -k 5 -n 5 -q -y -a mini-swe-agent -m openrouter/anthropic/claude-sonnet-4.6
```

## Key ↔ Model Matching (two real incidents)

| Env file | Keys | Use with |
|---|---|---|
| `.harbor_env` | Anthropic only | `-m anthropic/claude-opus-4-8`, `anthropic/claude-sonnet-4-6` |
| `.harbor_env3` / `3b` | Anthropic + OpenRouter | `-m openrouter/anthropic/claude-opus-4.8` |

- Anthropic key + `openrouter/...` model → every trial crashes `ValueError: Unset OPENROUTER_API_KEY` → bogus 0/10.
- **OpenRouter credits can run out MID-BATCH** → every in-flight trial crashes `NonZeroAgentExitCodeError` wrapping `402 Insufficient credits`. Results before the first 402 stay valid. Fallback: `.harbor_env` + `anthropic/claude-opus-4-8` — same model, same scaffold, gate-equivalent (ran zero crashes at 10–14 concurrent). Top up at openrouter.ai/settings/credits for AfterQuery-naming parity.

## Crash Discipline

- Per trial: `jobs/<job>/<trial>/result.json` → `verifier_result.rewards.reward` (1.0 solved, 0.0 failed, null/`exception_info` = CRASH). The job-level `result.json` is an aggregate — don't confuse it with a trial.
- **Crash ≠ fail.** Count `exception_info` per job; >1 crash → the run is untrustworthy, rerun clean. Read the crash cause in `<trial>/agent/mini-swe-agent.txt` (tail) before rerunning — a 402/key error means fix the env, not the load.
- A crashed trial can still carry `reward=1.0` (solved, then crashed) — count solves as solves, never count crash-fails as fails.

## Verdict Math — kill early

Stop a job the moment its verdict is mathematically decided and free the slots: 7 solves → too easy, kill. Sonnet 0/4 → ≤1/5 guaranteed, kill the 5th. Opus with `solved ≥1` and `solved + remaining ≤ 6` → in-band locked, fire the Sonnet gate immediately in parallel.

## Diagnosing a hard/failed task
Aggregate which f2p tests failed across trials: grep `FAILED ...::(test_name)` over `jobs/<job>/*/verifier/test-stdout.txt`. Universal-miss tests identify the blocking defects; p2p tests failing means agents broke correct behavior while overcorrecting.

**RELATED:** scaling-gate-throughput (concurrency, monitors, Daytona).
