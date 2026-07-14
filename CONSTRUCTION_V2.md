# Construction rules v2 — what round 1 proved (2026-07-13)

Read SCAFFOLD_RECIPE.md first for the mechanical 9-file workspace contract.
This file OVERRIDES it where they conflict. Canonical structure example:
`silver-tasks/ingestion-stale-blocker/`. Round-1 gate data:

| task | sonnet (≤1/5 to pass) | opus (1–4/10 to pass) | why it failed |
|---|---|---|---|
| cre-qualification-fixes | 5/5 | — | instruction published the band table = checklist |
| inbound-call-routing | 5/5 | — | instruction published function-level contract |
| array-credit-report | 4/5, 3/5 | — | tests assert private methods → signatures published |
| ingestion-stale-blocker | 0/5×3 then 3/4 | 0/10×2 | unpublished method name = unfair; published = too easy |
| loangen-agent-multibug | — | 9/9 | defects were UNCOMMITTED (visible via `git diff`), f2p tests visible in tree, instruction listed the 10 files + "single-line" |
| plaid-bank-report | 0/5 | 0/10 | MagicMock module-attr patching encodes oracle's impl choice |

## The five hard rules

1. **No leak via git.** Planted defects MUST NOT be visible to `git diff`,
   `git log -p`, `git stash`, or reflog. For forge (planted-defect) tasks the
   environment/Dockerfile must, after planting:
   `rm -rf .git && git init -qb main && git config user.email t@t && git config user.name t && git add -A && git commit -qm "import codebase"`.
   Verify inside the image: `git log --oneline | wc -l` == 1 and `git diff` empty.
   (test.sh only needs *a* .git to locate the repo root and `git apply` the gold
   patch — a fresh init satisfies it.)

2. **No leak via visible tests.** Every fail_to_pass test enters ONLY through
   config.json's test_patch at verify time. If an existing repo test file would
   fail against your planted defects, DELETE that file in the defect patch and
   have test_patch restore it (full-file add). The agent-visible suite must be
   GREEN at the planted state. Check: run pytest in the built image — 0 failures.

3. **No leak via instruction.** Instructions are symptom reports written as a
   maintainer would file them: observed wrong behavior at the user/API level,
   with 1–2 concrete examples. NEVER: file paths, module names, defect counts,
   defect shape ("single-line"), private method names, threshold tables,
   field-by-field contracts. Public API names (route paths, response field
   names, documented request fields) are allowed ONLY when a gold test imports
   or asserts them and a competent dev could not derive them from the codebase.
   Litmus test: could a strong dev, given only your instruction, locate the
   defect file in <2 minutes without running anything? If yes, rewrite.

4. **No unfair hidden coupling.** Before finalizing, audit every gold test:
   - Mocks: never `patch("<consumer_module>.<CollaboratorClass>", MagicMock())`.
     Patch the class at its DEFINING module (`patch("agent.x.models.Doc.find_one")`)
     or use `SimpleNamespace`/typed fakes with EXPLICIT attribute values
     (including explicit `None`s) so no bare MagicMock can leak into pydantic
     or business logic. A near-correct implementation that reads a legitimate
     attribute of a collaborator must not crash on a Mock.
   - Names: a hidden test may only reference names that (a) exist at base,
     (b) are published in the instruction, or (c) are forced by an existing
     import site visible to the agent.
   - Run the ALTERNATIVE-IMPLEMENTATION audit: write down 2 materially
     different correct implementations of the symptom fix; if any hidden test
     fails one of them, the test is asserting the oracle's implementation, not
     the behavior — rewrite it.

5. **Difficulty comes from construction, not obscurity.** Combine at least two:
   - **Breadth**: ≥8 hidden f2p tests spanning ≥3 source files, covering
     permutations the symptom report only implies (an agent that fixes only
     the literal reported example must fail ≥2 hidden tests).
   - **Distance**: ≥1 defect whose visible symptom manifests ≥2 call-hops from
     the defective line (e.g. wrong normalization upstream surfaces as a wrong
     qualification verdict downstream).
   - **Interaction**: ≥1 pair of defects on the same data path (fixing one
     without the other changes the failure mode rather than fixing the test).
   - Natural-looking defects only: plausible logic slips (inverted guard,
     wrong fallback order, off-by-one boundary, swapped operands, stale alias)
     — never syntax errors, never `raise Exception("bug")`.

## Verification ladder (all required before a task enters the probe queue)

a. Static: `python3 static_check.py <task>` if present in scratchpad; else skim
   Dockerfile rules in ~/Downloads/AQI-Alpha/aqi-ocr-batch1-7.md.
b. In-image leak check (forge): git history len 1, git diff empty, pytest green.
c. NULL run: verifier on unmodified planted image → reward 0, and EVERY f2p
   test reports FAILED with a per-test line (no collection ERRORs).
d. ORACLE run: apply solution/solve.sh → reward 1, all f2p+p2p pass.
e. PARTIAL run (forge only): apply oracle fix for HALF the defects → reward 0.
f. Mock/fairness audit per rule 4, recorded in SCAFFOLD_REPORT.json as
   `"fairness_audit": "<2-3 sentences>"`.

Record everything in SCAFFOLD_REPORT.json (copy schema from
loangen-agent-multibug/SCAFFOLD_REPORT.json, add `fairness_audit`).

## Env & harness facts (save yourself an hour)

- Image `loangenus-repo:v1` has JWT_SECRET_KEY + LIVEKIT_* baked in. Known
  dummy-env sets per module are in the round-1 task Dockerfiles — copy from
  the task nearest your module.
- Settings patching: mutate the singleton via `patch.object(settings_obj, ...)`,
  never `patch("<module>.settings", ...)`.
- Tests importing modules that don't exist at base: import inside test bodies.
- `test_config_document_intelligence.py::test_defaults_disable_ingestion_and_qa`
  conflicts with task env — never in pass_to_pass.
- Docker network pool exhausts ~30 concurrent compose projects. Scaffold-time
  verification runs are fine; never run probe fleets yourself — the chain
  driver owns that.
