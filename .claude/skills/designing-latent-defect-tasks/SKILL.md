---
name: designing-latent-defect-tasks
description: Use when planting defects for a silver/latent-bug RL task, authoring its gold tests, or when a gated task came back too easy (7+/10) or suspiciously 0/10 and you must decide fair-hard vs broken.
---

# Designing Latent-Defect Tasks

## Overview
A task = a large repo with **5 single-token defects** whose visible test suite stays green; gold tests exist only in `tests/config.json`'s `test_patch`. The agent must find ALL 5 (single reward gates on everything), so one bad defect sinks the whole task.

Target band (mini-swe-agent): **Sonnet-4.6 ≤1/5, Opus-4.8 0–6/10** (0/10 acceptable ONLY after the fairness audit below; AfterQuery-strict is 1–4).

## The Dispersion Rule (top predictor — learned from 3 same-day rejections)

**Spread the 5 defects across 2+ rule-dense files. Never cluster them in one file, however large the repo.**

Single-file clusters gated 7/10, 8/8, ~80% (doc-qa, loangenai2, doc-scoring) — the instruction's symptom description maps to one named surface, the agent greps it, reads the file, wins. The hard tasks (1/10, 0/10, 4/10) spread defects across files with hundreds of near-identical rules. The instruction must describe symptoms only — never name files, functions, or the specific modules.

## Defect Recipe

- **Count/mix**: exactly 5; 2 EASY (adjacent-sibling-pinned) + 3 MEDIUM (same-line literal or cross-function trace).
- **5 distinct shapes, no grep-twins** (no two findable by the same search). Proven shapes: regex quantifier bound (`{3,5}`→`{3,4}`), integer sentinel (`amount.eq(1)`→`eq(2)`), dash-slice segment index, string-literal casing (`SAVING`→`SAVINGS`), capture-group index (`index=0`→`1`).
- **≥1 load-bearing rare-trigger**: fires only on an edge input ordinary data never feeds (bare N-digit cheque number, ₹1 sentinel credit). This is what pulls 1/10–0/10; it alone fails ~9/10 agents.
- **ZERO convention-picks.** An unpinned `>=` vs `>`, `<` vs `<=`, sign-of-zero, or inverted guard is NOT a defect — it's a coin flip the agent can't derive, solves ~0/10 unfairly, and Sonnet finds inverted guards instantly. If the correct side isn't uniquely derivable from visible code, don't plant it.

**Derivability test for every defect**: name the visible evidence that pins the correct side — an adjacent identical sibling line, N repo-wide occurrences of the idiom, a same-line literal whose structure dictates the value (a 4-dash-token prefix pins segment index 4; a single capture group pins `index=0`). "It's the sensible convention" is not evidence.

## Gold Tests (test_patch only)

- 5 fail-to-pass (one per defect) + 10–14 pass-to-pass pinning adjacent correct behavior.
- Pure-input, zero-mock unittests asserting observable outputs (category/payee/amount), no private-name coupling.
- **Fairness run**: a materially different correct fix must also pass (`isin([1])` vs `eq(1)`, `!=CURRENT` vs `==SAVING`).

## Verification Ladder (docker `--network none`, all must pass before gating)

| Rung | Expect |
|---|---|
| Leak | `git log --oneline \| wc -l` == 1, status clean, diff empty, all 5 markers present |
| NULL (no fix) | reward 0; all 5 f2p report per-test FAILED (no collection errors); all p2p pass |
| ORACLE (solution/) | reward 1 |
| PARTIAL (revert 2 of 5) | reward 0; other 3 f2p still FAILED |
| FAIRNESS (alt fixes) | reward 1 |

## 0/10 Triage: Fair-Hard vs Broken

Before accepting 0/10: (1) count per-f2p failures across trials from `jobs/<job>/*/verifier/test-stdout.txt` — universal-miss defects identify what's blocking; (2) re-verify those defects' pins exist in the shipped image (grep it, don't trust the report); (3) confirm the gold test asserts domain-obvious behavior. Misses spread across defects + valid pins = fair-hard. All trials dying on one unpinnable assertion = broken; fix or soften that defect.

## Common Mistakes
- Planting the shape the baseline agent suggests first (`<` vs `<=`) — that's the convention-pick trap.
- Gold test written against the planted behavior instead of the derivably-correct behavior.
- Two regex defects grep-discoverable by the same idiom scan.
- solve.sh double-heredoc: the body must be DUPLICATED (2 delimiters); temp-file form is simpler.

**REQUIRED NEXT:** gating-tasks-with-mini-swe.
