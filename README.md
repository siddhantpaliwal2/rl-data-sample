# RL Coding-Agent Environments - Sample Bank

Eight fail-to-pass coding tasks mined from real production codebases (fintech
lending, transaction enrichment, credit-bureau tooling - Python and Java).
Each task plants five latent single-token boundary defects into a working repo:
every existing test stays green, and only untested edge inputs come out wrong.
The agent gets the repo and a symptom-style bug report; the gold tests are
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
    ├── config.json         fail_to_pass[], pass_to_pass[], patch, test_patch (gold tests, injected at grade time)
    ├── test.sh             verifier entrypoint; writes reward 1/0 to /logs/verifier/reward.txt
    ├── run_script.sh       language test runner (pytest / mvn)
    └── parser.py           runner stdout → [{name, status}]
```

A task rewards 1 only when **every** `fail_to_pass` and `pass_to_pass` test
passes - partial fixes score 0.

## Gates and measured results

Every task passes four mechanical gates plus two model probes, measured with
**mini-swe-agent** - the ~100-line open-source recreation of the SWE-bench
reference agent. We gate on a deliberately *weak* harness: strong scaffolds
(Claude Code-style agent loops with rich tooling) solve these tasks bimodally
and mask the difficulty signal RL training needs.

| Gate | Threshold |
|---|---|
| Null (nop) | reward 0; every `fail_to_pass` FAILS |
| Oracle | reward 1 with `solution/solve.sh` |
| Easiness probe | Sonnet 4.6 × 5 attempts, ≤ 1/5 solved |
| Difficulty probe | Opus 4.8 × 10 attempts, ≤ 4/10 solved |

A hard task (down to 0/10) is acceptable **only** after a fairness audit:
per-test failures must spread across defects (not one universally-missed
unpinnable assertion), every defect's correct fix must be uniquely derivable
from visible code, and a materially different correct fix must also pass the
verifier. The 0–1/10 tasks below carry that audit in their `reference_plan.md`.

All numbers below are clean runs (zero crashed trials counted) via
`harness/run_attempt.py` (mini-swe-agent, canonical swebench.yaml config,
250-step limit, $3 cost cap per attempt):

| Task | Substrate | Lang | Opus solves/10 | Sonnet solves/5 |
|---|---|---|---|---|
| latent-credit-normalize | loangenus (66k LOC) | Python | 4/10 | 1/5 |
| latent-doc-extractors | loangenus | Python | 4/10 | 0/5 |
| latent-financial-tools | loangenus | Python | 0/10 | -² |
| latent-phone-invites | loangenus | Python | 1/10 | 0/5 |
| xrepo-fiu-latent | fiu_adapter (264 files) | Java | 1/10 | 1/5 |
| xrepo-txenrich-latent | transaction-enrichment | Python | 1/10 | 0/4¹ |
| xrepo-txenrich3-latent | transaction-enrichment | Python | 4/10 | 0/5³ |
| xrepo-txenrich4-latent | transaction-enrichment | Python | 0/10 | -² |

¹ one Sonnet trial crashed and was excluded; 0 of the 4 clean trials solved.
² easiness probe skipped by design: Opus at 0/10 already upper-bounds the
  weaker model (Sonnet has never matched Opus on any measured pair in this
  bank).
³ measured against an earlier, strictly easier variant of the instruction
  (more concrete symptom examples); on the shipped, vaguer variant the bound
  holds a fortiori.

The common failure mode on the hard tasks is instructive: agents fix 3–4 of
the 5 planted defects and consistently miss the same one or two - the reward
signal concentrates exactly on the defects that require cross-code derivation
rather than search.

## Reproducing these numbers

Everything below assumes Docker is running and you are at the repo root.

**0. Base images (read this first).** Every task Dockerfile starts
`FROM <repo>-repo:v1` (e.g. `loangenus-repo:v1`) - a pre-built image of the
underlying **private** codebase with dependencies installed. These images are
not on a public registry and cannot be rebuilt from this repo alone; they are
distributed out-of-band with this sample (on the AfterQuery platform they are
the approved repo images, referenced by digest). If `docker images | grep
-- -repo:v1` comes back empty, request the image bundle from the maintainer
before proceeding - `docker build` will otherwise fail at the `FROM` line with
`pull access denied`.

**1. Get an Anthropic API key into your shell** (a probe attempt typically
costs $0.40–1.60 and is hard-capped at $3):

```sh
export ANTHROPIC_API_KEY=sk-ant-...
```

**2. Build a task image:**

```sh
docker build -t latent-credit-normalize tasks/latent-credit-normalize/environment
```

**3. Sanity-check the task (null and oracle):**

```sh
# null: no fix applied - expect "reward: 0" and every fail_to_pass FAILED
docker run --rm -v "$PWD/tasks/latent-credit-normalize/tests":/vt:ro \
  latent-credit-normalize sh /vt/test.sh

# oracle: gold fix applied - expect "reward: 1"
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
# difficulty probe (Opus, the default model):
for i in $(seq 1 10); do "$PY" harness/run_attempt.py latent-credit-normalize "$i" results/; done
# easiness probe (Sonnet):
for i in $(seq 1 5); do PROBE_MODEL=anthropic/claude-sonnet-4-6 "$PY" harness/run_attempt.py latent-credit-normalize "$i" results-sonnet/; done
```

Count solves: `grep -l '"reward": 1' results/latent-credit-normalize-a*.json | wc -l`
- that number over 10 is the row in the table above. Keep concurrent attempts
≤ 15 machine-wide. A trial that crashes under load records `"reward": null` or
a non-`Submitted` exit_status - rerun that attempt number; never count a crash
as a fail.
