# Reference plan — finscore-xrepo-finscore-latent-bugs

First JAVA LATENT-BUG task. Source repo: `finscore` (Spring Boot 2.4.5 / Java 8 /
Maven, ~130 Java files, a financial-analysis aggregation service). All five
planted defects live in one class of deterministic scoring/aggregation math,
`src/main/java/com/finbit/finscore/mapper/FinScoreAnalysisMapper.java`, which
rolls the upstream bank-score / spending / merchant analyses up into the
customer-facing `FinScoreAnalysisResponseDTO` via the public static entry point
`getAnalysisReport(...)`. Every planted line is reachable from that one public
method, so all defects are live code and every gold assertion drives the public
API (the defective line sits 2+ call hops below the asserted response field).

## Construction (LATENT-BUG pattern)

The base image `finscore-repo:v1` is `maven:3.9-eclipse-temurin-8` + git +
python3, with the repo's working tree LF-normalized and the Maven cache warmed
offline at build time (`dependency:go-offline`, `-DskipTests package`, and one
throwaway JUnit-5 run to pull the Surefire `junit-platform` provider). This
makes verify-time `mvn -o test` fully offline — no network, no DB, no secrets.

The environment `Dockerfile` plants a small **defect patch** (five single-token
edits) into the working tree, deletes the shipped `FinscoreApplicationTests`
(an `@SpringBootTest` context-load smoke test that needs a live Postgres +
Keycloak and cannot run offline — unrelated to the math bugs), then collapses
history (`rm -rf .git && git init && commit "import codebase"`). The agent
starts from base+defects with an **empty, green** visible test tree.

The gold tests (`FinscoreBoundaryTest.java`) are injected only at grade time
from `config.json`'s `test_patch`. They feed the exact edge inputs the defects
corrupt and assert the correct outputs. "Green build" is not the bar — the
grader's edge tests are.

## Defects planted (all in FinScoreAnalysisMapper.java)

Mix: 2 EASY (sibling-pinned on/near the line) + 3 MEDIUM (pinned only by
cross-line / cross-method tracing). Zero convention-picks, zero grep-able twins
(five distinct edit shapes), zero syntax breaks.

1. **[EASY] getCreditCardUtilization** (line 263) — `.stream().max(...)` →
   `.stream().min(...)`. The "highest" credit-card month becomes the lowest.
   Pinned by the local `highestValue` / `setHighestCreditCardUtilization` names.
2. **[EASY] getIncomeAndExpenses** (line 151) — percent scale `* 100` → `* 10`.
   Average-monthly-income percent comes out 10× too small. Pinned by the seven
   sibling percentage formulas that all `* 100`.
3. **[MEDIUM] getSpendingCategories** (line 194) — leading element `.get(0)` →
   `.get(1)`. Share-of-income uses the 2nd-largest category. Pinned only by the
   descending `Collections.sort(..., reversed())` set earlier in the method.
4. **[MEDIUM] getMonthlyObligations** (line 330) — divisor
   `bankAnalysisDetailDTO.getAverage()` → `.getTotal()`. The obligation ratio
   divides by total income instead of average income. Pinned by the
   `percentageAverageMonthlyIncome` field + the average numerator + the sibling
   income resolver that reads `getAverage()` for "average income".
5. **[MEDIUM] getMerchantSpendingList** (line 289) — top-N cap `.limit(5)` →
   `.limit(4)`. With ≥5 merchants one top merchant is dropped. Pinned by the
   `size() >= 5` guard immediately above it.

Each oracle value is derivable from the surrounding code (naming, the sort
direction, the sibling formulas, the guard), never from convention alone.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch, restoring `max`, `* 100`,
`get(0)`, `getAverage()`, and `limit(5)`. Any equivalent boundary correction
also passes the gold tests.

## Verifier design (Java / Maven adaptation of the canonical contract)

- `tests/test.sh` (structurally identical to the canonical) locates the repo
  root by `.git`+`pom.xml`, applies `test_patch` from verifier-controlled
  config, runs `run_script.sh`, parses per-test verdicts, and awards reward 1
  only if every `fail_to_pass` and `pass_to_pass` test passed.
- `tests/run_script.sh` runs `mvn -o -B -Dtest=FinscoreBoundaryTest test`
  offline; Surefire writes JUnit XML to `target/surefire-reports/`.
- `tests/parser.py` parses `target/surefire-reports/TEST-*.xml` into
  `{"tests":[{"name","status"}]}` with names `FinscoreBoundaryTest::<method>`
  (`<failure>`/`<error>` → failed, `<skipped>` → skipped, else passed).
- `fail_to_pass` = the 5 gold boundary tests (one per defect; fail at
  base+defects, pass once corrected).
- `pass_to_pass` = 11 gold tests that pass throughout — they pin the unchanged
  behavior on the same data paths (per-category percents, the sort order, the
  leading-child investment percent using the *untouched* `get(0)`, an obligation
  ratio where average==total so the divisor swap is a no-op, a sub-5 merchant
  list, roundOff, score-analysis passthrough, customer mapping).

## Verification ladder (all offline, `--network none`)

- In-image leak check: `git log --oneline | wc -l` == 1, `git diff` empty, no
  `src/test/*.java` present, defects live in the tree but absent from history.
- NULL run (planted image): reward 0; all 5 f2p report FAILED with per-test
  lines (no collection errors); all 11 p2p pass.
- ORACLE run (`solve.sh`): reward 1, 16/16 pass.
- PARTIAL run (fix 2 of 5): reward 0 (13/16; the other 3 f2p still fail).

## Fairness

- All five defected methods are reachable from `getAnalysisReport`, so they are
  live code, not dead paths. Gold tests use only plain POJO inputs (Lombok
  getters/setters) — no mocks, no Spring context, no reflection — so no test
  encodes the oracle's implementation choice.
- Cross-defect isolation: each f2p test provides ≥2 spending categories where
  needed so the `get(1)` slip never throws `IndexOutOfBounds`; each f2p fails
  only on its own asserted field.
- The instruction reports observed wrong behavior at the report level with two
  concrete examples; it names neither the class, the methods, the lines, the
  edit direction, the trigger values, nor the defect count. An agent that fixes
  only the two reported symptoms still fails ≥2 hidden tests.
