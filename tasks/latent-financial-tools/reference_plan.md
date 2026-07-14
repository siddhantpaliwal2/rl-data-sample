# Reference plan — latent-financial-tools

## Construction (LATENT-BUG pattern)

Base image is the clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and then applies a small **defect patch** that plants five
subtle boundary / reserved-value errors in the deterministic summarization math
of the financial-data analysis tools (the bank / credit-bureau / accounting
analytics services). The agent starts from base+defects. There is **no failing
local test** pointing at any defect: the full existing suite stays green with the
defects present, because every visible test either never calls these helpers or
feeds values that sit safely inside the ranges and never lands on the exact edge
that bites.

Count and selection are calibrated against the platform gate across several
rounds. Six defects graded Opus 0/10 — not a count problem but an
**underdetermined** defect (a convention choice, not a derivable boundary) which
scores p≈0 individually and drags the whole task to zero; that one
(seasonality-band edge) was dropped. Five cleanly-derivable single-line
boundaries then graded Opus **8/10** — too easy. Swapping the easy credit-tier
anchor for a "medium" monthly-gap window still graded **7/10**: every one of ten
frontier runs found the monthly-gap defect, so it was not doing the work its
label claimed. This build removes that monthly-gap defect and, in its place,
plants a genuine **rare-trigger** defect in a different file — a reserved
sentinel value dropped from the credit `_safe_float` guard — which fires only on
an input ordinary data never carries and stays uniquely derivable from a
same-file sibling plus the module docstring. The two empirical anchors from the
7/10 run (the two-observation volatility collapse, which one run missed outright,
and the minimum-width P&L guard, which two runs mis-fixed) are kept.

**Calibration note — this pass (5/10 → target ~3).** The five-defect build above
graded Opus 4.8 (mini-swe-agent) **5/10**, gated by two of the five defects:
near-limit (found ~8/10) and severe-delinquency `late_90` (found ~7/10); the
product of those two `p(found)` values, not the defect count, sets the score. The
trajectories showed the other four are found on the first read because each is
pinned by a **copyable in-code sibling** (`_safe_int` vs `_safe_float`;
`_row_to_line_item`'s `>= num_months+2`; `statistics.stdev`'s n≥2) that this
harness reads reliably — so relocating a gate to a sibling-pinned cross-trace
would raise `p→~1` and make the task *easier*. Both survivable gates lower `p` for
the same reason: their pin is **not** a copyable sibling. Near-limit's pin is the
spec doc `docs/BANK_ANALYTICS_CHECKLIST.md` (`>= 75`), reached via the function
docstring's `See ...` pointer; agents who instead trust the natural
`high_utilization_credit` sibling (`> 75`, a different metric) miss it (~2/10).
Severe's is domain judgment on a subtle off-by-one — agents *spot* `> 1` but ~30%
decline to commit (run a8 committed only after the instruction's "single item …
counted rather than dismissed" clause tipped it).

Two calibration passes were run against the re-gate:

- **Pass A (overshoot, reverted).** Deepened near-limit hard by *also* removing the
  docstring's `See docs/BANK_ANALYTICS_CHECKLIST.md` pointer, leaving the doc the
  sole pin but invisible in-code. Re-gate: **0/10** — all ten runs then trusted the
  plausible `high_util > 75` sibling and missed near-limit (`p≈0`). An unreferenced
  doc as sole pin is too weak; it borders on unfair. The docstring hunk was
  dropped.

- **Pass B (this build — middle setting).** Near-limit keeps its docstring pointer;
  only the `>= 75.0 → > 75.0` token is planted (all five boundary tokens are
  byte-identical to the 5/10 build, and no code differs from 5/10). Two *light*
  instruction levers modestly deepen the two gates instead: (1) the "documented"
  nudges are blurred ("a **documented** cut-off" → "a cut-off"; "the **documented**
  rule" → "the rule") so the write-up no longer steers the agent to the doc — the
  docstring still does, but the write-up stops reinforcing it; and (2) severe's
  "single item" tell is lightly blurred out of the prose (the clause that tipped
  a8), keeping the even-pair (volatility) tell, the terse Testing-notes `single/pair`
  enumeration, and the general margin description. Expected joint:
  `p(near-limit)≈0.6 × p(severe)≈0.55 → ~3/10`. Monotonic-safe: instruction blurs
  only reduce guidance (no `p→1` backfire), and neither boundary is underdetermined
  — near-limit's doc + retained docstring pointer still uniquely pin `>= 75`, and
  severe's sibling `> 0`, cross-repo `late_90 > 0` call-sites, and domain still pin
  `> 0`.

The gold tests (`tests/test_financial_tools_boundaries.py`) are injected only at
grade time from `config.json`'s `test_patch`. They feed exactly the edge inputs
the defects corrupt and assert the correct outputs. "Green locally" is not the
bar — the grader's edge tests are.

## Defects planted (file : function : boundary : derivability signal)

1. `analytics/services/credit_bureau_analytics.py`
   `build_credit_analytics_checklist_v1` — severe-delinquency guard
   `late_90 > 0` tightened to `late_90 > 1`. A tradeline with exactly one
   90-day-late mark (no charge-off) stops counting as severe. DERIVABLE (easy by
   derivation, but empirically ~30% of runs *spot* the off-by-one and decline to
   commit): the sibling `delinquent_open_count` treats `late_90 > 0` as
   delinquent, other repo call-sites (`credit_report_pdf.py`, `xactus.py`) use
   `late_90 > 0`, and a single 90-DPD is unambiguously severe by domain
   convention. This pass lightly blurs the instruction's "single item" tell (the
   clause that tipped run a8 into committing) to nudge `p(severe)` down toward
   ~0.55 — a pure instruction change; the boundary token is untouched.

2. `analytics/services/plaid_analytics.py` `_compute_volatility` — the
   single-point guard `len(values) < 2` widened to `len(values) <= 2`. A
   two-observation series wrongly collapses to 0.0 volatility. DERIVABLE (easy):
   `statistics.stdev` is defined for n >= 2, so the guard must exclude only
   n < 2. **Empirical anchor** — one of ten frontier runs missed this outright.

3. `analytics/services/plaid_analytics.py`
   `build_bank_analytics_checklist_v1` — near-limit cutoff
   `utilization_pct >= 75.0` weakened to `> 75.0`. A revolving line at exactly
   75% utilization is dropped from the near-limit count. DERIVABLE (**medium**):
   the authoritative rule lives in `docs/BANK_ANALYTICS_CHECKLIST.md` ("accounts
   with `utilization_pct >= 75`"), reached via the function docstring's
   `See docs/BANK_ANALYTICS_CHECKLIST.md` pointer (**kept** — Pass A's removal of
   it drove the gate to `p≈0`; see calibration note). The difficulty is that the
   *natural, in-code* sibling misleads: `_compute_plaid_analytics`'s
   `high_utilization_credit` flag legitimately uses `(a.utilization_pct or 0) > 75`
   (a different metric with its own threshold) and reads as consistent with the
   weakened `> 75.0`, so an agent who trusts it without opening the doc misses the
   slip. This round the instruction no longer nudges toward "documented" rules, so
   the doc is reached via the docstring pointer or domain reasoning rather than
   being handed over.

4. `analytics/services/credit_bureau_analytics.py` `_safe_float` — the reserved
   special-value set `if v in (-3.0, -4.0, -5.0)` narrowed to
   `if v in (-3.0, -4.0)`, dropping the `-5` sentinel. Array.com uses `-5` for
   "Not applicable for this bureau"; with `-5` no longer discarded, a field that
   carries it is echoed back as a real figure of `-5.0` instead of falling to the
   caller's default. DERIVABLE (**medium**, rare-trigger): the correct set is not
   deducible from the guard line alone, but two same-file signals pin it — the
   module docstring's "Special values" table lists `-3 / -4 / -5`, and the
   adjacent sibling `_safe_int` still discards the full `(-3, -4, -5)` set for the
   identical purpose. The trigger (`-5`) never appears in ordinary bureau data,
   so the whole visible suite stays green. This is this round's replacement for
   the found-by-everyone monthly-gap defect.

5. `analytics/services/quickbooks_analytics.py` `_extract_monthly_from_summary`
   — minimum-width guard `len(col_data) < num_months + 2` widened to
   `<= num_months + 2`. A P&L summary at its minimum valid column width
   (`[label, month..., TOTAL]`) returns an empty monthly series. DERIVABLE
   (medium): the sibling `_row_to_line_item` accepts monthly data at the same
   `len(values) >= num_months + 2`, pinning `num_months + 2` as the minimum
   valid width. **Empirical anchor** — two of ten frontier runs mis-fixed this
   (they corrected the boundary but chose the wrong width, breaking the
   too-narrow pin).

## Derivability + difficulty audit (why these five, and what was swapped out)

Each candidate is checked twice: (a) can a strong engineer determine the
uniquely-correct side of the boundary / value set at all (else it is
underdetermined and sinks the whole task to 0), and (b) how hard is that
determination (a board of all-easy defects grades too high because each is ~95%
solvable, and every-run-finds-it defects contribute nothing to the joint).

- severe `late_90` — DERIVABLE, easy (sibling `> 0` + 90-DPD is severe); ~30%
  spot-but-don't-commit. Instruction "single item" tell lightly blurred this pass
  to nudge `p` down. KEPT (code byte-identical).
- `_compute_volatility` n=2 — DERIVABLE, easy; empirically an anchor. KEPT.
- near-limit 75 — DERIVABLE, **medium** (BANK_ANALYTICS_CHECKLIST.md says `>= 75`,
  reached via the retained docstring pointer; a natural sibling `> 75` misleads).
  Instruction "documented" nudges blurred this pass. Docstring pointer KEPT after
  Pass A's removal drove it to `p≈0`.
- monthly min-width — DERIVABLE, medium (sibling `_row_to_line_item`);
  empirically an overfix anchor. KEPT.
- `_safe_float` `-5` sentinel — DERIVABLE, **medium / rare-trigger** (docstring
  table + adjacent sibling `_safe_int`). ADDED this round.
- monthly-gap window `>= 2` vs `>= 3` — DERIVABLE but **found by all ten runs**;
  its cross-function pin turned out easy to trace. REMOVED this round: the guard
  is left correct (`>= 2`) in the image and its test class dropped entirely.
- `_classify_risk_tier` 740 — DERIVABLE but **easy** (graded p≈1.0). Removed a
  prior round; its band is left correct and its three tier tests are pass_to_pass.
- `_compute_seasonality` ratio 2.0 — **UNDERDETERMINED**. DROPPED an earlier
  round; its whole test class was removed.

Resulting dispersion: credit-bureau (defects 1 and 4, ~340 lines and two
unrelated shapes apart), plaid (defects 2 and 3, two different functions), and
quickbooks (defect 5) — five single-token / single-literal boundary slips spread
across all three services, none clustered.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch at `base_commit`, restoring
the original `> 0`, `< 2`, `>= 75.0`, `(-3.0, -4.0, -5.0)`, and
`< num_months + 2` logic. That is the minimal correct fix; any equivalent
boundary / set correction also passes the gold tests. (The docstring pointer is
left in place in the planted state this pass, so the patch no longer touches it.)

## Verifier design

- `tests/test.sh` (verbatim from the canonical latent task) applies `test_patch`
  from verifier-controlled config, runs `run_script.sh`, parses per-test
  verdicts, and awards reward 1 only if every `fail_to_pass` and `pass_to_pass`
  test passed.
- `fail_to_pass` = 9 gold boundary tests (fail at base+defects, pass once the
  boundaries are corrected), spanning all five defects across the three services.
- `pass_to_pass` = 14 gold tests pinning the just-off-edge behavior adjacent to
  each defect (values one tick above/below the boundary, larger/smaller sets, the
  other reserved codes and a real negative that must survive) plus the three
  now-correct credit-tier tests — all pass at both the planted and the fixed
  state. Two of them are overfix guards: `test_too_narrow_summary_yields_empty`
  (a width fix that goes one column too far breaks it) and
  `test_real_negative_value_is_kept` (a sentinel fix that rejects all negatives
  breaks it).
- `run_script.sh` runs only the gold file; every f2p and p2p node lives there.

## Fairness

- All five defected functions are live code: `build_credit_analytics_checklist_v1`
  feeds the credit dashboard/chat summaries, `_safe_float` sanitizes every
  numeric field parsed out of the raw bureau payload, the
  `build_bank_analytics_checklist_v1` cutoff and `_compute_volatility` feed the
  bank checklist, and `_extract_monthly_from_summary` feeds `parse_profit_and_loss`
  / `compute_qb_analytics` (monthly income) — none are dead paths.
- The instruction is a symptom-only incident write-up: it names the domain area
  (bank/credit/accounting summarization) and the symptom shapes (wrong numbers on
  exact thresholds, minimum-width reports, single/pair collections, and reserved
  placeholder codes echoed as data). It gives no file names, function names,
  boundary directions, trigger values, or defect count — the agent must read and
  reason about each boundary to locate and correct the slip, and each slip has a
  uniquely-derivable correct answer.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`. The gold
  tests are pure-input (dict/list/scalar in, scalar/list/dict out) and use zero
  mocks, so no oracle implementation choice is encoded.
