# Coding RL from Enterprise Codebases

Eight verifier-gated coding tasks planted in real production fintech codebases
(Python and Java), with a measured 8-model × 4-harness pass@k matrix and full
agent trajectories. Sample content lives on the **`general-sample`** branch
(recipient-neutral) and the **`Amazon-sample`** branch; this page is the
front door: the task–verifier alignment report and the pass@k report.

Each task takes a large private repo, plants five single-token latent defects
(the visible test suite stays green; only untested edge inputs go wrong), and
gives the agent a realistic symptom report. Gold tests are injected only at
grade time — the agent can never read or weaken them — and reward is
all-or-nothing: every hidden fail-to-pass test must flip green and no passing
test may regress.

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

## Pass@k report

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

## Where to look

- `general-sample` branch — the shareable sample: `tasks/`, `instructions/`
  (task prompts as they'd arrive from a PM/QA/partner), `gold-tests/`
  (extracted verifier suites), `sample-run/` (matrix data, analysis,
  96-trajectory corpus), reproduction harness and image recipes.
- `Amazon-sample` branch — same bank plus a two-model deep-dive study.
- Two-minute verification, zero model calls: build any task image and run
  its null and oracle checks (`HANDOFF.md` on the sample branches).
