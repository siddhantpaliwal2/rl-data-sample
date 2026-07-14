# RL Coding-Agent Environments - Sample Bank

Eight fail-to-pass coding tasks mined from real production codebases (fintech
lending, transaction enrichment, credit-bureau tooling - Python and Java).
Each task plants five latent single-token boundary defects into a working repo:
every existing test stays green, and only untested edge inputs come out wrong.
The agent gets the repo and a symptom-style bug report; the gold tests are
injected only at grade time, so they can never be read or weakened.

## Task format

Each directory under `tasks/` is a
[Harbor](https://github.com/harbor-framework/harbor) task. Harbor is the
Terminal-Bench team's evaluation harness: the directory layout below comes
from Terminal-Bench, not from SWE-bench. The SWE-bench connection is one level
down - the grading config inside `tests/` follows SWE-bench-Pro conventions
(`config.json`'s instance/commit/patch/test fields, and the
run_script + parser pattern) - and the probe agent (mini-swe-agent) comes from
the SWE-bench authors. Layout:

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
**[mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent)** - the minimal
(~100-line agent class) agent from the Princeton/Stanford team behind SWE-bench
and SWE-agent; bash-only, linear history, yet >74% on SWE-bench Verified. We
gate on a deliberately *simple* harness: strong scaffolds
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
| latent-financial-tools | loangenus | Python | 0/10 | 0/5 |
| latent-phone-invites | loangenus | Python | 1/10 | 0/5 |
| xrepo-fiu-latent | fiu_adapter (264 files) | Java | 1/10 | 1/5 |
| xrepo-txenrich-latent | transaction-enrichment | Python | 1/10 | 0/5 |
| xrepo-txenrich3-latent | transaction-enrichment | Python | 4/10 | 0/5 |
| xrepo-txenrich4-latent | transaction-enrichment | Python | 0/10 | 0/5 |



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
distributed out-of-band with this sample. If `docker images | grep
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

**3. Install the agent harness:**

```sh
uv tool install mini-swe-agent
uv pip install --python "$(uv tool dir)/mini-swe-agent/bin/python" fastapi orjson
```

## How the harness works

The probe harness is two pieces: **mini-swe-agent** (the solver) and
`harness/run_attempt.py` (the runner that wraps one full attempt end to end).

**The solver.** [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent)
is the minimal agent from the SWE-bench/SWE-agent authors - a single LLM loop
(~100 lines) whose only tool is a bash shell inside the task container. The
runner imports the actual `minisweagent` package; nothing is re-implemented. No file viewers, no search index, no sub-agents -
the model reads code with `grep`/`cat`/`sed` and edits with shell commands.
The harness loads its canonical `swebench.yaml` benchmark config verbatim:
250-step limit, $3 cost cap per attempt, 30-minute wall clock. That weak,
standardized scaffold is the point - it is the same probe the task platform
uses, and difficulty numbers only mean something if everyone measures with the
same agent.

**The runner.** One invocation of `run_attempt.py <task> <attempt-no> <out-dir>`
does the whole lifecycle:

1. Starts a fresh container from the task image (`docker run` of `<task>`),
   working directory `/app` - the planted repo with sealed git history.
2. Instantiates mini-swe-agent against that container with the model from
   `PROBE_MODEL` (default `anthropic/claude-opus-4-8`).
3. Hands it `tasks/<task>/instruction.md` as the task prompt. The agent
   explores and edits `/app` until it submits or hits a limit.
4. Grades in place: copies `tasks/<task>/tests/` into the still-running
   container and executes `test.sh` - this is the first moment the gold tests
   exist anywhere the agent could have touched, so they cannot have been read
   or weakened. `test.sh` applies `config.json`'s `test_patch`, runs the suite,
   and requires every `fail_to_pass` and `pass_to_pass` test to pass.
5. Tears the container down and writes three artifacts to `<out-dir>`:
   `<task>-a<N>.json` (reward 0/1, tests passed, cost, model calls, exit
   status), `<task>-a<N>.traj.json` (the full agent trajectory - every command
   and model message), and `<task>-a<N>.grade.log` (verbatim verifier output,
   including exactly which gold tests failed).

Attempts are independent, so parallelism is just running several invocations
at once (see the concurrency caution below). The solve counts in the table are
literally `grep -c '"reward": 1'` over those result files; the `.grade.log`
files are what we used to see which planted defect stopped each failed run.

**4. Run the harness.** `harness/run_attempt.py <task> <attempt-no> <out-dir>`
is one complete probe attempt: it starts a fresh container from the task image,
runs mini-swe-agent inside it, grades the result with the hidden verifier, and
writes the result JSON + full trajectory + grade log to `<out-dir>`. One task's
row in the table:

```sh
PY="$(uv tool dir)/mini-swe-agent/bin/python"
# difficulty probe (Opus, the default model): 10 attempts
for i in $(seq 1 10); do "$PY" harness/run_attempt.py latent-credit-normalize "$i" results/; done
# easiness probe (Sonnet): 5 attempts
for i in $(seq 1 5); do PROBE_MODEL=anthropic/claude-sonnet-4-6 "$PY" harness/run_attempt.py latent-credit-normalize "$i" results-sonnet/; done
```

To reproduce the whole table, run both probes for every task directory (build
each image first per step 2). Attempts are independent, so parallelize with
`xargs -P` - just keep total concurrent attempts under ~15 machine-wide:

```sh
PY="$(uv tool dir)/mini-swe-agent/bin/python"
for t in $(ls tasks); do
  docker build -q -t "$t" "tasks/$t/environment"
  for i in $(seq 1 10); do echo "$t $i"; done
done | xargs -P 10 -L 1 sh -c "\"$PY\" harness/run_attempt.py \$0 \$1 results/"
# then the Sonnet pass: same loop with seq 1 5 and PROBE_MODEL=anthropic/claude-sonnet-4-6
```

Count solves per task: `grep -l '"reward": 1' results/latent-credit-normalize-a*.json | wc -l`
- that number over 10 is the row in the table above. Keep concurrent attempts
≤ 15 machine-wide. A trial that crashes under load records `"reward": null` or
a non-`Submitted` exit_status - rerun that attempt number; never count a crash
as a fail.

## Optional: verifier sanity check (no agent)

To confirm a task's mechanics without spending any model calls - the planted
state really fails the gold tests, and the gold fix really passes them - run
the hidden verifier directly:

```sh
# null: no fix applied - expect "reward: 0" and every fail_to_pass FAILED
docker run --rm -v "$PWD/tasks/latent-credit-normalize/tests":/vt:ro \
  latent-credit-normalize sh /vt/test.sh

# oracle: gold fix applied - expect "reward: 1"
docker run --rm -v "$PWD/tasks/latent-credit-normalize/tests":/vt:ro \
  -v "$PWD/tasks/latent-credit-normalize/solution":/vs:ro \
  latent-credit-normalize sh -c 'sh /vs/solve.sh && sh /vt/test.sh'
```
