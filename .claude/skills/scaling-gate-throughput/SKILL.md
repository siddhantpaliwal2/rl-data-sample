---
name: scaling-gate-throughput
description: Use when running multiple harbor gate jobs, when trials crash under load, when a candidate gets rejected and the pipeline stalls, when watching long-running trial jobs, or when local Docker concurrency caps throughput (Daytona/Modal setup).
---

# Scaling Gate Throughput

## Overview
Local Docker caps clean throughput at **~15 concurrent trials** — at 45–86 containers roughly half of mini-swe-agent trials crash, and crashes contaminate the numbers as false fails. Speed comes from scheduling inside that ceiling and never letting the pipeline go empty, not from raising `-n`.

## Concurrency Budget (local)

- ≤15 trials total: 3 jobs × `-n 4`–`5`, or 2 × `-n 5` + 1 × `-n 3`. Count `docker ps -q | wc -l` — anything else on the daemon (other sessions!) eats the same budget.
- Gate 3 candidates in parallel when 2 slots are open — rejections are common (3 of 5 candidates busted in one batch here).
- **Kill jobs the moment their verdict is mathematically decided** (see gating-tasks-with-mini-swe) and immediately launch the next candidate in the freed slots.
- Fire the Sonnet easiness job as soon as Opus is mathematically in-band — don't wait for the job to finish.

## Never an Empty Pipeline

While gates run, a **builder subagent authors the next candidate** (it uses CPU/disk, not gate slots). The brief that worked: read the canonical approved sibling + CONSTRUCTION_V2.md, pick a disjoint substrate, plant 5 defects per designing-latent-defect-tasks, verify the full ladder, do NOT run harbor (the parent owns the concurrency budget). A ladder-verified spare was ready before the last gate finished.

## Monitoring Long Runs (gotchas that bit)

- Emit per-trial rewards from a poll loop over `jobs/<job>/*/result.json`; use `find`, not globs — zsh errors on unmatched globs and kills the monitor.
- Job-level `result.json` (aggregate, reward=None while running) matches the same patterns as trial results — expect and ignore it.
- **Sandboxed monitor shells cannot `kill` other processes** — it silently no-ops (docker rm still works). Kill PIDs from a direct Bash call with sandbox disabled.
- A monitor whose script text contains the pattern it greps for matches itself; break self-match with a character class: `pgrep -f 'mini_prob[e]'`.
- `pkill -f <job-substring>` kills your own monitor if its command line contains the substring.
- Foreign processes competing for the daemon: sweep containers by **image prefix** (rename-proof — scripts get renamed; images don't), and kill the PPID-1 orchestrator, not just workers (workers respawn).

## Daytona / Cloud Sandboxes — the real fix

The local ceiling is the throughput limit AND the crash source. Harbor supports `-e daytona` (also `-e modal`): one cloud sandbox per trial, no shared daemon, so 10 tasks × 10 trials can run simultaneously with no contamination.

Setup once:
1. Get a Daytona API key → export `DAYTONA_API_KEY` (add to the `.harbor_env*` files).
2. Push every `<repo>-repo:v1` and `<task>-task:v1` image to a registry Daytona can pull (`docker tag` + `docker push`); rebuild task Dockerfiles to reference the registry path.
3. Same harbor commands + `-e daytona`; drop the ≤15 rule — bound instead by API rate limits and spend.

Worth it the moment gating is a recurring pipeline rather than a final top-up; a full 10-task re-gate that takes an evening locally collapses to ~one trial-duration.

## Common Mistakes
- Raising `-n` to go faster on local Docker — produces crash-fails that read as difficulty.
- Trusting a run with >1 crash instead of rerunning clean.
- Waiting for a doomed job to finish out of tidiness — kill it, the slots are the scarce resource.
- Polling with sleep loops in the foreground instead of arming a monitor and doing other work.

**RELATED:** gating-tasks-with-mini-swe (verdict math, key matching), selecting-task-substrates, designing-latent-defect-tasks.
