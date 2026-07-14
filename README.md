# RL Coding-Agent Environments — Sample Bank

Nine fail-to-pass coding tasks mined from real production codebases (fintech
lending, transaction enrichment, credit-bureau tooling — Python and Java).
Each task plants a small set of latent boundary defects into a working repo:
every existing test stays green, and only untested edge inputs come out wrong.
The agent gets the repo and a symptom-style instruction; the gold tests are
injected only at grade time, so they can never be read or weakened.

## Task format

Each directory under `tasks/` follows the Harbor / SWE-bench-Pro task spec:

```
tasks/<name>/
├── instruction.md          what the agent reads (symptoms + expected behavior, never the fix)
├── reference_plan.md       author notes: root cause, oracle fix, verifier design
├── task.toml               metadata: difficulty, category, timeouts, resources
├── environment/Dockerfile  FROM <repo base image>; plants the defects; the agent's world
├── solution/solve.sh       gold patch; applies cleanly at base, fixes every defect
└── tests/
    ├── config.json         fail_to_pass[], pass_to_pass[], test_patch (gold tests, injected at grade time)
    ├── test.sh             verifier entrypoint; writes reward 1/0 to /logs/verifier/reward.txt
    ├── run_script.sh       language test runner (pytest / mvn)
    └── parser.py           runner stdout → [{name, status}]
```

A task rewards 1 only when **every** `fail_to_pass` and `pass_to_pass` test
passes — partial fixes score 0.

## Why these thresholds

Every task must pass four gates, measured with **mini-swe-agent** — the
~100-line open-source recreation of the SWE-bench reference agent
(`SWE-agent/mini-swe-agent`). We gate on a deliberately *weak* harness: strong
scaffolds (Claude Code-style agent loops with rich tooling) solve these tasks
bimodally and mask the difficulty signal that RL training needs.

| Gate | Threshold | Why |
|---|---|---|
| Null (nop) | reward 0, every `fail_to_pass` FAILS | proves the defects are real and the tests catch them |
| Oracle | reward 1 with `solution/solve.sh` | proves the task is solvable and the verifier is satisfiable |
| Easiness probe | Sonnet 4.6 × 5 attempts, **≤ 1/5 solved** | a mid-tier model shouldn't crack it at baseline; ≥2/5 means the defect is greppable, not latent |
| Difficulty probe | Opus 4.8 × 10 attempts, **1–4/10 solved** | the band that makes RL data useful (see below) |

The difficulty band is bounded on both sides for a reason:

- **0/10 is a reject, not a badge.** A task no frontier model ever solves is
  indistinguishable from a broken or unfair one (an intended behavior that is
  pinned only by the hidden test, not by anything in the repo). Zero solves
  provides no positive reward signal to learn from.
- **5+/10 is a reject.** If the model already solves it half the time, the
  remaining headroom is small and the sample is training noise, not signal.
- Inside 1–4/10 the task is verified-solvable but failure-dominated — exactly
  the regime where reward gradients are informative.

Probe results are only trusted from **clean runs**: a crashed trial counts as
a failure in raw tallies, so any run with more than one infrastructure error
is re-run rather than recorded (crash-contaminated numbers systematically
overstate difficulty).

## Measured results (mini-swe-agent + claude-opus-4-8, 10 clean attempts/task)

| Task | Substrate | Lang | Opus solves/10 |
|---|---|---|---|
| latent-credit-normalize | loangenus (66k LOC) | Python | 4/10 |
| latent-doc-extractors | loangenus | Python | 4/10 |
| latent-financial-tools | loangenus | Python | 7/10 |
| latent-market-structure | loangenus | Python | 7/10 |
| latent-phone-invites | loangenus | Python | 0/10 |
| xrepo-correlation-latent | correlation-core | Python | 0/10 |
| xrepo-loangenai-latent | loan-genai-backend | Python | 10/10 |
| xrepo-txenrich-latent | transaction-enrichment | Python | 0/4 so far (6 attempts in flight) |
| xrepo-fiu-latent | fiu_adapter (264 files) | Java | 3/8 so far (2 attempts in flight) |

Every task passes null/oracle mechanically. The common failure mode on the
0/10 tasks is instructive: agents consistently fix 4 of 5 planted defects and
miss the same one, so revision work targets that single weakly-pinned defect
rather than the whole task.

## Reproducing these numbers

Everything below assumes Docker is running and you are at the repo root.

**1. Get an Anthropic API key into your shell:**

```sh
export ANTHROPIC_API_KEY=sk-ant-...
```

**2. Build a task image.** Each task's Dockerfile starts `FROM <repo base
image>` (e.g. `loangenus-repo:v1`) — the pre-built image of the underlying
private codebase with dependencies installed. With the base image present:

```sh
docker build -t latent-credit-normalize tasks/latent-credit-normalize/environment
```

**3. Sanity-check the task (null and oracle):**

```sh
# null: no fix applied — expect "reward: 0" and every fail_to_pass FAILED
docker run --rm -v "$PWD/tasks/latent-credit-normalize/tests":/vt:ro \
  latent-credit-normalize sh /vt/test.sh

# oracle: gold fix applied — expect "reward: 1"
docker run --rm -v "$PWD/tasks/latent-credit-normalize/tests":/vt:ro \
  -v "$PWD/tasks/latent-credit-normalize/solution":/vs:ro \
  latent-credit-normalize sh -c 'sh /vs/solve.sh && sh /vt/test.sh'
```

**4. Install the agent harness:**

```sh
uv tool install mini-swe-agent
uv pip install --python "$(uv tool dir)/mini-swe-agent/bin/python" fastapi orjson
```

**5. Run probe attempts** (one agent attempt in a fresh container, graded by
the hidden verifier, result JSON + full trajectory written to `results/`):

```sh
PY="$(uv tool dir)/mini-swe-agent/bin/python"
for i in $(seq 1 10); do "$PY" harness/run_attempt.py latent-credit-normalize "$i" results/; done
```

Count solves: `grep -l '"reward": 1' results/latent-credit-normalize-a*.json | wc -l`
— that number over 10 is the row in the table above. Keep concurrent attempts
≤ 15 machine-wide; trials that crash under load record as false failures.
