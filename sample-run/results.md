# sample-run: Amazon Nova Premier vs Claude Opus 4.8 on the OpenCode harness

One attempt (k=1) per (task, model) cell — 16 cells, all launched in parallel,
one Daytona sandbox each (identical 2-CPU / 4-GB amd64 environments, every
image null/oracle-verified before use). Agent: **OpenCode** (`opencode run
--thinking`, installed fresh per sandbox) driven by harbor. Models via
OpenRouter: `amazon/nova-premier-v1` (Amazon's flagship frontier model) and
`anthropic/claude-opus-4.8`. Full agent trajectories for every cell are in
`trajectories/`, machine-readable data in `results.json`.

## pass@1 (reward = every fail_to_pass AND pass_to_pass test green)

| Task | Nova Premier | Opus 4.8 |
|---|---|---|
| latent-credit-normalize | 0 | 0 |
| latent-doc-extractors | 0 | 0 |
| latent-financial-tools | 0 | 0 |
| latent-phone-invites | 0 | 0 |
| xrepo-fiu-latent | 0 | 0 |
| xrepo-txenrich-latent | 0 | 0 |
| xrepo-txenrich3-latent | 0 | 0 |
| xrepo-txenrich4-latent | 0 | 0 |
| **pass@1** | **0/8** | **0/8** |

## Partial progress — planted defects actually fixed (f2p flipped to green)

| Task | Nova f2p fixed | Opus f2p fixed | Opus distance from reward 1 |
|---|---|---|---|
| latent-credit-normalize | 0/5 | 4/5 | 1 test (digit-leading creditor anchor) |
| latent-doc-extractors | 0/4 | 4/4 | 1 test (over-fix broke a pass_to_pass) |
| latent-financial-tools | 0/9 | 8/9 | 1 test |
| latent-phone-invites | 0/5 | 4/5 | 1 test |
| xrepo-fiu-latent | 0/5 | 2/5 | 3 tests (base64, handle, whitespace) |
| xrepo-txenrich-latent | 0/5 | 4/5 | 1 test (payee segment slice) |
| xrepo-txenrich3-latent | 0/5 | 4/5 | 1 test (₹1 mandate sentinel) |
| xrepo-txenrich4-latent | 0/5 | 0/5 | 5 tests |
| **Total** | **0/43** | **30/43** | |

Nova's required-tests-passed count equals the null baseline on **all eight
tasks**: nothing it edited moved a single graded test in either direction.
Opus finished exactly one test short of full reward on six of eight tasks.

## Wall-clock, steps, cost (per attempt)

| Task | Nova wall | Opus wall | Nova steps | Opus steps | Nova $ | Opus $ |
|---|---|---|---|---|---|---|
| latent-credit-normalize | 212s | 153s | 16 | 21 | 0.46 | 0.63 |
| latent-doc-extractors | 332s | 189s | 15 | 23 | 0.64 | 0.72 |
| latent-financial-tools | 118s | 227s | 10 | 22 | 0.25 | 1.11 |
| latent-phone-invites | 193s | 192s | 21 | 20 | 0.64 | 0.55 |
| xrepo-fiu-latent | 91s | 622s | 9 | 53 | 0.27 | 1.89 |
| xrepo-txenrich-latent | 227s | 496s | 12 | 44 | 0.32 | 2.83 |
| xrepo-txenrich3-latent | 130s | 449s | 17 | 42 | 0.49 | 4.17 |
| xrepo-txenrich4-latent | 179s | 862s | 16 | 69 | 0.43 | 4.91 |
| **Total** | **1482s (24.7m)** | **3190s (53.2m)** | **116** | **294** | **$3.50** | **$16.81** |

All 16 attempts ran concurrently; end-to-end wall time for the whole benchmark
was bounded by the slowest single cell (txenrich4 × Opus, ~14.4 min of agent
time plus sandbox setup).

See `analysis.md` for the comparative analysis and failure taxonomy.
