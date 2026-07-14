# Reference plan — forge-chat-pipeline (author only)

## Construction (FORGE / planted-defect, edge-conditioned)

Base image is clean HEAD of loangenus (`04b8abc`). The environment Dockerfile
resets to that commit and applies a **defect patch** planting six natural
one-line slips across the chat conversation pipeline and its config. The agent
starts from base+defects. Git history is collapsed to a single "import codebase"
commit so the plants are invisible to `git diff/log/reflog`.

There is **no failing local test** pointing at any defect: the entire existing
suite is identical in pass/fail with and without the plants, because nothing in
`loangen-agent/tests/` imports or exercises these seams. Beyond that, each defect
is **edge-conditioned**: it produces CORRECT output on the common/obvious input
an agent would try first at a REPL, and goes wrong only on inputs the visible
suite (and casual spot checks) never feed. The gold tests
(`tests/test_chat_pipeline_seams.py`), injected only at grade time from
`config.json`'s `test_patch`, drive the public seams with exactly those inputs.

## Defects planted (correct -> defect)

1. `pipeline._extract_loan_details` — `raw = match.group(1).replace(",", "")`
   gains `.replace(".", "")`. A separator-stripping slip: it removes the decimal
   point along with commas, so a FRACTIONAL amount is inflated ~10x
   ("$2.5k" -> 25 -> 25,000; "$1.5m" -> 15 -> 15,000,000). Round amounts
   ("$5k", "$3m", "$50,000") have no decimal point and stay correct — so casual
   round-number probing sees nothing wrong. EDGE: decimal-suffixed amounts only.

2. `pipeline.detect_intent` — iteration wrapped in
   `sorted(INTENT_PATTERNS.items())`, turning intent precedence alphabetical.
   Only messages matching TWO topics flip: "credit score" -> gap_coaching
   (not personal_credit), "dscr" -> gap_coaching (not qb_financials).
   Single-topic messages are unchanged. EDGE: two-topic overlap only. DISTANCE:
   the visible symptom (wrong/empty enrichment) surfaces two call-hops downstream
   in `enrich_user_message`.

3. `pipeline.get_greeting` — the partial-connect guard `if connected:` weakened
   to `if connected is not None:` (a truthiness-vs-None confusion). A list is
   never None, so the ZERO-connected case (connected == []) now wrongly enters
   the "some connected" branch and emits "I have access to your ." instead of the
   new-user advisor intro. Partial and all-connected states are unchanged. EDGE:
   empty connection set only.

4. `context_builder.get_missing_data_response` — `missing_required` guard
   `if k in missing_keys` flipped to `if k not in missing_keys`: flags a
   connected required source as missing, and returns a non-None response when
   nothing required is missing.

5. `context_builder.get_missing_data_response` — `connected_keys` guard
   `if k not in missing_keys` flipped to `if k in missing_keys`: the connected
   list is inverted to the missing set. Defects 4+5 are the INTERACTION pair
   (same function/path; fixing one leaves the other's assertion failing). Their
   symptom is a wrong LABEL/set surfaced only by calling a structured internal
   method with a partial `missing_sources` — not something casual message-probing
   reveals (per the edge-conditioning rationale: "wrong label, not wrong number").

6. `config.Settings.chat_enrichment_refresh_credit_from_raw_db` default flipped
   `True -> False`, so credit questions never load the full DB credit report and
   fall back to the thin session summary. The symptom manifests only through the
   Mongo-backed enrichment path (requires DB data), so a casual offline REPL probe
   cannot observe it.

## Edge-conditioning summary (per team-lead directive)

- Edge-conditioned so casual probing sees correct output: #1 (decimals only),
  #2 (two-topic only), #3 (empty set only).
- Kept observable-but-non-casual per the point-3 escape (wrong label / DB-only
  symptom, not reachable by typing a message): #4, #5 (structured-seam label
  error), #6 (DB-path-only symptom). Flagged as not numerically edge-conditionable
  without contrivance — the missing-data logic is pure set membership and the
  config flag is a boolean.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch (temp-file `git apply -R`;
the shared double-heredoc pattern is broken — see the memory note). Any
equivalent behavioral correction also passes (tests assert observable outputs).

## Verifier design

- `tests/test.sh` restores tracked tests, removes the gold file, applies
  `test_patch` from verifier-controlled config, runs `run_script.sh` (gold file
  only; p2p are in-file controls), parses per-test verdicts, rewards 1 iff every
  fail_to_pass and pass_to_pass passed.
- **10 fail_to_pass** (fail at base+defects, pass at oracle): 2 fractional
  amount, 2 intent precedence + 1 intent-driven enrichment (distance), 1 empty
  greeting, 3 missing-data, 1 config default.
- **8 pass_to_pass** (pass at both) — controls proving no over-correction on the
  common inputs: round + plain amounts (x3), single-topic intents (x2), and the
  one/two/all-connected greetings (x3). These are the exact inputs a casual probe
  would try; they are correct at base, which is what makes the defects latent.

## Difficulty levers (CONSTRUCTION_V2 rule 5)

- **Breadth**: 10 f2p across 3 source files; fixing only one reported symptom
  still fails >=8 tests.
- **Distance**: defect 2 manifests two hops away in `enrich_user_message`.
- **Interaction**: defects 4+5 on the same missing-data path.
- **Latency**: no failing-test gradient AND each defect is correct on the first
  obvious input, so the only discovery channel is reading the code.

## Fairness

- All six defected functions are live code on the chat/voice request path.
- Gold tests assert only at PUBLIC seams (`detect_intent`, `get_greeting`,
  `enrich_user_message`, `get_missing_data_response`, the `settings` singleton);
  `_extract_loan_details` is reached only through its public caller. Collaborator
  is an explicit typed fake (no Mock); the settings singleton is mutated via
  `patch.object`. No hidden name is used that isn't already in base code.
- Instruction names no file/module/method/config-key/count/shape and gives NO
  concrete trigger values (a literal "$2.5k" would hand over the decimal edge);
  it reports observed user-level symptom classes only.
- Deterministic, offline, no secrets beyond the baked `JWT_SECRET_KEY`.
