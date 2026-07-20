# Coding RL from Enterprise Codebases

Eight fail-to-pass coding tasks mined from real production codebases (fintech
lending, transaction enrichment, credit-bureau tooling - Python and Java).
Each task plants five latent single-token boundary defects into a working repo:
every existing test stays green, and only untested edge inputs come out wrong.
The agent gets the repo and a symptom-style bug report; the gold tests are
injected only at grade time, so they can never be read or weakened.

> Sample content (`tasks/`, `instructions/`, `gold-tests/`, `sample-run/`,
> the reproduction harness) lives on the **`general-sample`** branch
> (recipient-neutral) and the **`Amazon-sample`** branch; this branch carries
> the pipeline plus this combined report.

## Task–verifier alignment report

Alignment is enforced in both directions and then validated against agent
trajectories.

**Direction 1 — every gold test traces to task language.** Each hidden
fail-to-pass test exists because the instruction reported that exact problem.
A concrete example from `xrepo-txenrich4-latent`, whose instruction is a QA
regression report listing five findings:

> **F-5.** A small nominal deposit that a bank posts purely to confirm an
> account is reachable — the token "is this account live" credit rather than
> a real payment — is being filed as an ordinary transfer instead of being
> recognised as an account-verification entry.

maps to exactly one hidden test:

```python
def test_rupee_one_validation_is_verification(self):
    # feeds a ₹1 confirmation credit; asserts category == ACCOUNT_VERIFICATION
```

That pattern holds across the bank — each thing the instruction reports, one
hidden test verifies. In plain terms, per task:

| Task | What the agent reads | Hidden tests | How they line up |
|---|---|---|---|
| latent-credit-normalize | an audit memo reporting 4 data-quality problems in parsed credit reports | 5 | one test per problem; the problem described with two variants gets two tests |
| latent-doc-extractors | a bug ticket with 4 cases of document fields coming back empty | 4 | one test per case |
| latent-financial-tools | an incident write-up describing 4 kinds of wrong financial figures | 9 | each kind covered by 1–3 tests |
| latent-phone-invites | an escalation email listing 5 CRM data-quality complaints | 5 | one test per complaint |
| xrepo-fiu-latent | 2 partner tickets with concrete symptoms + a triage note that 3 more helpers drift the same way | 5 | one test per ticket, one per drifting helper |
| xrepo-txenrich-latent | a forum digest: 3 user posts + 1 maintainer repro about mislabeled bank transactions | 5 | one test per described mislabel |
| xrepo-txenrich3-latent | a SEV-1 incident report listing 5 label regressions | 5 | one test per regression |
| xrepo-txenrich4-latent | a QA report with findings F-1 to F-5 | 5 | one test per finding |

No hidden test asserts behavior the instruction gives no basis for: a hidden
test may only reference names that exist in the visible codebase, are stated
in the instruction, or are forced by a visible import site.

**Direction 2 — every key instruction claim is tested.** Each stated symptom
has a gold test that fails at the planted state and passes after the fix, and
each instruction's "nothing that currently works may change" clause is
enforced by 12–20 pass-to-pass guardrail tests per task pinning adjacent
behavior on both sides of every boundary. This is not just designed but
observed: in one measured attempt, a frontier model fixed every reported case
and then widened a minimum one notch past what the ticket stated — a
pass-to-pass test caught it and correctly withheld reward. The verifier
enforces the instruction's stated boundary, not merely the bug list.

**Mechanical alignment gates (run per task before acceptance):**

- **Null**: the untouched planted state scores 0 and every f2p test fails
  individually (no collection errors) — the defects are real and the tests
  detect exactly them.
- **Oracle**: the reference fix scores 1 with all f2p and p2p green — the
  task is solvable and the verifier satisfiable.
- **Partial**: fixing roughly half the defects still scores 0 — reward
  tracks complete task success, not test-count progress.
- **Alternative-implementation audit**: for each defect, materially different
  correct fixes (different edit site or idiom with the same behavior) also
  pass — verified in practice when models fixed defects with different edits
  than the oracle patch and were rewarded. The tests assert behavior, never
  the oracle's implementation.

**Trajectory-verified alignment (~780 valid attempts analyzed).** Following
per-test verdicts across every attempt: failures concentrate on the planted
defects themselves, not on missing context. Example — on the Java task,
misses across 10 frontier-model attempts spread over four distinct defect
families (10/10, 10/10, 4/10, 3/10), each family's correct fix pinned by
visible same-file evidence; no attempt failed on an assertion the instruction
and codebase gave no path to. Where an attempt was invalidated by
infrastructure rather than the model (missing per-test verdicts), it was
excluded from every reported number.

**Disclosed exceptions** (stated in-repo rather than papered over): one task
reward-gates four of its five planted defects (the fifth is fixed by the
oracle but no graded test distinguishes it), and two agent configurations
were excluded from the matrix after trace review showed harness-level faults
rather than model failures.

## Pass@k summary

Every model attempted every task ~10 times on the OpenCode harness (one
isolated 2-CPU/4-GB sandbox per attempt; a trial counts only if the verifier
emitted real per-test verdicts). pass@k uses the unbiased estimator
1 − C(n−c,k)/C(n,k), averaged over the eight tasks.

| Model (OpenCode, n≈10/cell) | mean pass@1 | mean pass@10 | tasks solved ≥ once |
|---|---|---|---|
| gpt-5.6-sol | 0.200 | 0.750 | 6/8 |
| claude-opus-4.8 | 0.100 | 0.375 | 3/8 |
| gpt-5.5 | 0.100 | 0.250 | 2/8 |
| glm-5.2 | 0.097 | 0.471 | 4/8 |
| gemini-3.5-flash | 0.025 | 0.125 | 1/8 |
| deepseek-v4-pro | 0.013 | 0.125 | 1/8 |
| nova-2-lite | 0.000 | 0.000 | 0/8 |
| nova-premier | 0.000 | 0.000 | 0/8 |

Harness axis (flagships, n≈3 per cell): codex+gpt-5.6-sol 0.396 pass@1 /
0.625 pass@3 · claude-code+opus-4.8 0.271 / 0.375 · terminus-2+sol 0.156 /
0.344 · terminus-2+opus 0.083 / 0.250 · mini-swe-agent+opus 0.075 pass@1
(n=10). The same model spans up to 3.6× on harness choice alone.

Properties worth noting: attempt-scaling rescues capable models and does
nothing for incapable ones (Sol 0.20→0.75 across k; the zero rows stay zero
across ~160 attempts); every task has at least one non-oracle solve — the
two hardest fell to unexpected models (GLM-5.2 alone cracked one at 1/13,
Gemini alone the other at 2/10) — while those two hold under 3% pass@1
across all twelve valid configurations. The per-cell c/n matrix, per-trial
data (`sample-run/passk_matrix.json`), a full analysis with failure
taxonomies (`sample-run/analysis.md`), and one complete trajectory per
model×task cell — a solving one wherever any exists, with step counts,
wall-clock, and cost — are on the sample branches.

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

For convenience, `instructions/` holds a readable copy of every task's
`instruction.md` (one file per task) so the eight agent-facing prompts can be
skimmed side by side, and `gold-tests/` holds the extracted source of every
task's hidden gold test suite (the exact code the verifier runs). The canonical
copies remain `tasks/<name>/instruction.md` and the `test_patch` field inside
`tasks/<name>/tests/config.json`; the gold tests never exist anywhere the agent
can see them at solve time.

One calibration note: `latent-doc-extractors` reward-gates four of its five
planted defects. The fifth (a personal-financial-statement scan floor) is
planted and reversed by the oracle, but no graded test distinguishes it - an
agent that fixes the four gated boundaries scores 1 whether or not it also
finds that one. Every other task gates all five of its defects.

## Gates and measured results

Every task clears four gates **in order** - two mechanical checks, then two
model probes. Each gate must pass before the next runs:

| # | Gate | Threshold | What it proves |
|---|---|---|---|
| 1 | Null (nop) | reward 0; every `fail_to_pass` FAILS | the defects are real and the gold tests catch them |
| 2 | Oracle | reward 1 with `solution/solve.sh` | the task is solvable and the verifier is satisfiable |
| 3 | Easiness probe | Sonnet 4.6 × 5 attempts, ≤ 1/5 solved | a mid-tier model can't crack it at baseline |
| 4 | Difficulty probe | Opus 4.8 × 10 attempts, ≤ 4/10 solved | a frontier model fails most of the time |

The order is cost-driven: null/oracle are free (no model calls) and kill
mechanically broken tasks instantly; the Sonnet probe is the cheap screen - if
a mid-tier model solves the task 2+ times out of 5, the defects are greppable
rather than latent and there is no point spending the ~10x more expensive Opus
runs; only tasks that survive Sonnet get the full 10-attempt Opus difficulty
measurement that decides the table below.

Both probes are measured with
**[mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent)** - the minimal
(~100-line agent class) agent from the Princeton/Stanford team behind SWE-bench
and SWE-agent; bash-only, linear history, yet >74% on SWE-bench Verified. We
gate on a deliberately *simple* harness: strong scaffolds
(Claude Code-style agent loops with rich tooling) solve these tasks bimodally
and mask the difficulty signal RL training needs.

A hard task (down to 0/10) is acceptable **only** after a fairness audit:
per-test failures must spread across defects (not one universally-missed
unpinnable assertion), every defect's correct fix must be uniquely derivable
from visible code, and a materially different correct fix must also pass the
verifier. The 0–1/10 tasks below carry that audit in their `reference_plan.md`.

All numbers below are clean runs (zero crashed trials counted; a trial only
counts when the verifier emitted real per-test verdicts). Five tasks were
measured with `harness/run_attempt.py` (mini-swe-agent, canonical
swebench.yaml config, 250-step limit, $3 cost cap per attempt). Three
(`latent-credit-normalize`, `latent-doc-extractors`, `xrepo-fiu-latent`) were
re-gated after their instructions were rewritten into bug-report/ticket form:
same solver and invocation (`mini-swe-agent --yolo --model=…`), run at scale
on Daytona cloud sandboxes (amd64 images of the same task environments; every
image null/oracle-verified first).

| Task | Substrate | Lang | Opus solves/10 | Sonnet solves/5 |
|---|---|---|---|---|
| latent-credit-normalize | loangenus (66k LOC) | Python | 0/10 | 0/5 |
| latent-doc-extractors | loangenus | Python | 4/10 | 0/5 |
| latent-financial-tools | loangenus | Python | 0/10 | 0/5 |
| latent-phone-invites | loangenus | Python | 1/10 | 0/5 |
| xrepo-fiu-latent | fiu_adapter (264 files) | Java | 0/10 | 0/5 |
| xrepo-txenrich-latent | transaction-enrichment | Python | 1/10 | 0/5 |
| xrepo-txenrich3-latent | transaction-enrichment | Python | 4/10 | 0/5 |
| xrepo-txenrich4-latent | transaction-enrichment | Python | 0/10 | 0/5 |

`xrepo-fiu-latent` note: its 0/10 carries the required fairness audit — misses
spread across distinct defects (base64 alphabet 10/10, handle-index 10/10,
UUID-regex precision 4/10, whitespace-emptiness 3/10), each pinned by visible
same-file evidence, and all 10 trials produced full per-test verdicts.



The common failure mode on the hard tasks is instructive: agents fix 3–4 of
the 5 planted defects and consistently miss the same one or two - the reward
signal concentrates exactly on the defects that require cross-code derivation
rather than search.

## Frontier-model pass@k matrix

Every cell below is measured: one Daytona sandbox per attempt (identical
2-CPU/4-GB amd64 environments), the agent harness named in the table, models
via OpenRouter (Claude via the Anthropic API, Muse Spark via the Meta Model
API). A trial counts toward n only if the verifier emitted real per-test
verdicts. pass@k uses the unbiased estimator
**pass@k = 1 − C(n−c, k) / C(n, k)** over n valid attempts with c solves,
averaged across the eight tasks (k is capped at a cell's n). Full per-trial
data and trajectories: `sample-run/`.

Model selection (July 2026): each lab's latest frontier coding model available
by API — GPT-5.6 Sol (Terminal-Bench 2.1 leader) plus GPT-5.5, Gemini 3.5
Flash (Google's strongest agentic/coding model), GLM-5.2, DeepSeek V4 Pro,
Claude Opus 4.8, and both accessible Amazon Novas. Two configurations were
run but excluded from the matrix after trace review showed their attempts
never actually exercised the model: Meta's Muse Spark 1.1 (a key-forwarding
fault on our side meant its agent errored on auth before doing any work) and
aider + Opus 4.8 (aider sends a `temperature` parameter the Opus 4.8 API
rejects, so every attempt died on the first call). Neither zero is a model
result, so neither is reported as one. Amazon's Nova 2 Pro is preview-gated
(not on OpenRouter or generally on Bedrock) and could not be included.

### OpenCode harness — 8 models, n≈10 attempts per cell (c/n)

| Model | credit-norm | doc-extract | fin-tools | phone-inv | fiu | txenr | txenr3 | txenr4 | mean pass@1 | mean pass@10 |
|---|---|---|---|---|---|---|---|---|---|---|
| gpt-5.6-sol | 4/10 | 5/10 | 0/10 | 1/10 | 1/10 | 4/10 | 1/10 | 0/10 | 0.200 | 0.750 |
| claude-opus-4.8 | 0/10 | 3/10 | 0/10 | 0/10 | 0/9 | 2/10 | 3/10 | 0/10 | 0.100 | 0.375 |
| gpt-5.5 | 1/10 | 0/10 | 0/10 | 7/10 | 0/10 | 0/10 | 0/10 | 0/10 | 0.100 | 0.250 |
| glm-5.2 | 0/8 | 5/10 | 0/9 | 1/10 | 0/10 | 1/10 | 0/10 | 1/13 | 0.097 | 0.471 |
| gemini-3.5-flash | 0/10 | 0/10 | 2/10 | 0/10 | 0/10 | 0/10 | 0/10 | 0/10 | 0.025 | 0.125 |
| deepseek-v4-pro | 0/10 | 0/10 | 0/10 | 1/10 | 0/10 | 0/14 | 0/10 | 0/10 | 0.013 | 0.125 |
| nova-2-lite | 0/10 | 0/10 | 0/9 | 0/10 | 0/10 | 0/10 | 0/10 | 0/10 | 0.000 | 0.000 |
| nova-premier | 0/11 | 0/10 | 0/10 | 0/9 | 0/9 | 0/10 | 0/11 | 0/10 | 0.000 | 0.000 |

### Harness axis — flagships across 5 harnesses, n≈3 per cell (c/n)

| Harness + model | credit-norm | doc-extract | fin-tools | phone-inv | fiu | txenr | txenr3 | txenr4 | mean pass@1 | mean pass@3 |
|---|---|---|---|---|---|---|---|---|---|---|
| codex + gpt-5.6-sol | 1/3 | 3/3 | 0/3 | 2/4 | 0/3 | 2/3 | 2/3 | 0/3 | 0.396 | 0.625 |
| claude-code + claude-opus-4.8 | 0/3 | 3/3 | 0/3 | 0/3 | 0/2 | 2/3 | 1/2 | 0/3 | 0.271 | 0.375 |
| terminus-2 + gpt-5.6-sol | 0/3 | 2/3 | 0/3 | 1/4 | 0/3 | 0/3 | 1/3 | 0/3 | 0.156 | 0.344 |
| terminus-2 + claude-opus-4.8 | 0/3 | 0/3 | 0/3 | 0/2 | 0/1 | 1/3 | 1/3 | 0/3 | 0.083 | 0.250 |

The mini-swe-agent gate table above is the third harness reference point:
Opus 4.8 at n=10 per task scores mean pass@1 0.075 there, versus 0.100 on
OpenCode, 0.271 on claude-code — the same model spans a 3.6× solve-rate range
on harness choice alone. Two structural observations: (1) every task has at
least one solve from some (model, harness) pair — including txenr4, cracked
only by GLM-5.2 — so no task is unverifiable; (2) `fin-tools` and `txenr4`
hold under 3% pass@1 across all 14 rows, while `doc-extract` is farmable by
the strongest pairs, mapping the bank's difficulty spread at the current
frontier.

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

## Reproducing these numbers

Everything below assumes Docker is running and you are at the repo root.

**0. Base images (read this first).** Every task Dockerfile starts
`FROM <repo>-repo:v1` (e.g. `loangenus-repo:v1`) - a pre-built image of the
underlying **private** codebase with dependencies installed. These images are
not on a public registry and cannot be rebuilt from this repo alone; they are
distributed out-of-band with this sample. If
`docker images --format '{{.Repository}}:{{.Tag}}' | grep repo:v1`
comes back empty, request the image bundle from the maintainer
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

**4. Run the harness.** One invocation of
`harness/run_attempt.py <task> <attempt-no> <out-dir>` is one complete probe
attempt (container, agent, hidden-verifier grading, artifacts - see "How the
harness works" above).

**4a. Run an individual task** (reproduces one row of the table; image built
per step 2):

```sh
PY="$(uv tool dir)/mini-swe-agent/bin/python"
# difficulty probe (Opus, the default model): 10 attempts
for i in $(seq 1 10); do "$PY" harness/run_attempt.py latent-credit-normalize "$i" results/; done
# easiness probe (Sonnet): 5 attempts
for i in $(seq 1 5); do PROBE_MODEL=anthropic/claude-sonnet-4-6 "$PY" harness/run_attempt.py latent-credit-normalize "$i" results-sonnet/; done
```

Count solves: `grep -l '"reward": 1' results/latent-credit-normalize-a*.json | wc -l`
- that number over 10 is the task's cell in the table.

**4b. Run all tasks** (reproduces the whole table). Attempts are independent,
so parallelize with `xargs -P`; builds every task image, then fans out
attempts:

```sh
PY="$(uv tool dir)/mini-swe-agent/bin/python"
# Opus pass (10 attempts per task):
for t in $(ls tasks); do
  docker build -q -t "$t" "tasks/$t/environment"
  for i in $(seq 1 10); do echo "$t $i"; done
done | xargs -P 10 -L 1 sh -c "\"$PY\" harness/run_attempt.py \$0 \$1 results/"
# Sonnet pass (5 attempts per task):
for t in $(ls tasks); do
  for i in $(seq 1 5); do echo "$t $i"; done
done | PROBE_MODEL=anthropic/claude-sonnet-4-6 xargs -P 10 -L 1 sh -c "\"$PY\" harness/run_attempt.py \$0 \$1 results-sonnet/"
```

Keep concurrent attempts ≤ 15 machine-wide. A trial that crashes under load
records `"reward": null` or a non-`Submitted` exit_status - rerun that attempt
number; never count a crash as a fail.

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
