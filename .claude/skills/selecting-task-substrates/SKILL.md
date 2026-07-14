---
name: selecting-task-substrates
description: Use when picking a repository or module cluster for a new silver/latent-defect RL task, when a candidate repo seems "good enough", or when preparing a repo Docker image (arm64 pip failures, CRLF files, langchain-gated imports, offline Maven).
---

# Selecting Task Substrates

## Overview
The substrate decides task difficulty before a single defect is planted. Small or narrow substrates are unfixable-too-easy; only large repos with rule-dense, deterministic pure-logic code produce Opus-hard tasks.

## Substrate Criteria (all required)

| Criterion | Bar | Evidence |
|---|---|---|
| Size | ≥10k LOC or ≥100 files | 4 small repos rejected: 872 LOC → 10/10 solved, 205 LOC → 9/10, single 200-line file → 9/10 (unfixable regardless of defect quality) |
| Logic type | Deterministic pure logic: parsers, categorizers, scoring/financial math | Rule-dense = hundreds of near-identical rules to audit |
| Testability | Functions drivable by pure inputs (small DataFrames, strings, numbers), zero mocks | Gold tests must be fair |
| Offline | Imports work with `--network none`, or stub-loadable | See gotchas below |
| Disjointness | Modules unused by every prior task — check each `approved/*/SCAFFOLD_REPORT.json` `modules_used` / `banks_used` | Tasks on shared files leak each other's fixes |

**Small repo? Reject immediately. No defect quality can fix it** — the agent reads the whole codebase and localization (the real work) disappears.

## Proven Veins (this pipeline)

- **transaction-enrichment-python `BankScripts/`** — best vein: 35 bank categorization scripts, each hundreds of np.select rules. Scores: 1/10, 0/10 (Opus). Used so far: HDFC, ICICI, Kotak, SBI, IDBI, Indusind (~29 free). Each fresh pair clones the winner.
- **loangenus (66k LOC Python)** — 5 banked tasks from multi-file clusters. Caution: single-file clusters here failed (see designing-latent-defect-tasks).
- **Java FinBit repos** — fiu_adapter (264 files) gated 4/10. Caution: finscore gated 9/10 because its defects were greppable easies — Java alone isn't hardness.

## Repo Image Prep (`<repo>-repo:v1`)

- **arm64 pip failures**: ancient version pins fail to build on arm64 — modernize pins in the image, never in the task.
- **CRLF files**: plant/edit bytes with python `open('rb')`/`replace`/`open('wb')` — sed or text-mode round-trips corrupt line endings and leak the edit.
- **np.select is first-match**: when crafting edge inputs, confirm no earlier rule shadows the targeted rule.
- **langchain/langgraph-gated pure modules**: load offline via `sys.modules` stubs for leaf imports AND bare parent-package stubs (`Workflow`, `Workflow.v1`, …) before `spec_from_file_location().exec_module()` — parent stubs stop Python executing the real `__init__.py`.
- **Java offline**: warm the surefire junit-platform provider with one throwaway online test at image build, then `mvn -o test` works offline; parse surefire XML; delete `@SpringBootTest` tests; LF-normalize.
- **Git sealing** happens in the task Dockerfile: `rm -rf .git && git init && git commit -m "import codebase"` so fixes aren't recoverable from history.

## Common Mistakes
- "This 900-line repo is really intricate" — intricacy ≠ localization work. Reject.
- Reusing a file another task planted in (breaks disjointness; check SCAFFOLD_REPORTs, not memory).
- Preparing deps at task level instead of repo image level (slow rebuilds, divergent bases).

**REQUIRED NEXT:** designing-latent-defect-tasks (defect placement), then gating-tasks-with-mini-swe.
