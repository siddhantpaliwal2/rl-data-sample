# Reference plan — fiu-xrepo-fiu-latent-bugs

Second JAVA LATENT-BUG task. Source repo: `fiu_adapter` (FinBit FIU adapter —
Spring Boot 2.3.0 / Java 8 / **multi-module** Maven: `jws-signature`,
`diffie-hellman-services`, `webservice`, `kms`; 264 Java files). The five
planted defects live in the deterministic, side-effect-free helper layer of the
`webservice` module — the parsing / validation / date-and-timestamp utilities the
adapter uses on every request. All five are single-token edits reachable and
exercisable as pure POJO / static logic (no Spring context, no DB, no network).

## Construction (LATENT-BUG pattern)

Base image `fiu-repo:v1` is `maven:3.9-eclipse-temurin-8` + git + python3, with
the repo LF-normalized, all four modules **installed** to the local Maven repo,
and the Surefire `junit-platform` provider warmed offline at build time (one
throwaway JUnit-5 run). Because the siblings are installed, verify-time
`mvn -o -pl webservice test` is fully offline — no network, no DB, no secrets —
and rebuilds only the graded module.

The environment `Dockerfile` plants a small **defect patch** (five single-token
edits across five files) into the working tree, deletes **all** shipped test
sources (`webservice/src/test`, `jws-signature/src/test`) plus the stale warm
test class, then collapses history
(`rm -rf .git && git init && commit "import codebase"`). The shipped tests are
JUnit 4 / PowerMock unit tests that the junit-platform provider (junit-vintage
excluded) never executes and none of which touch the planted helpers, so the
agent starts from base+defects with an **empty, green** visible test tree.

The gold tests (`FiuBoundaryTest.java`, JUnit 5) are injected only at grade time
from `config.json`'s `test_patch`. They feed the exact edge inputs the defects
corrupt and assert the correct outputs.

## Defects planted (5 — 1 EASY + 4 MEDIUM, five distinct shapes)

1. **[MEDIUM] Base64 alphabet (URL-safe vs standard)** — `utils/Base64Decoder.getDecodedObject`
   `Base64.getUrlDecoder()` → `Base64.getDecoder()`. The helper decodes JWS/JWT
   compact payloads (its sole caller passes `signedConsent.split("\.")[1]`),
   which are base64url per RFC 7515; the standard decoder rejects the URL-safe
   characters `-`/`_`, so any signed-consent payload whose encoding contains them
   throws instead of decoding. Pinned by the sole caller
   (`ConsentArtifactServiceImpl`), which decodes the *same* `split("\.")[1]`
   payload with `getUrlDecoder()` one line earlier, and by the base64url nature
   of JWS. Fires only on payloads containing `-`/`_`; plain `[A-Za-z0-9]`
   encodings decode identically under both alphabets. Live: consent-artifact
   detached-payload decode / signature verification.

2. **[MEDIUM] Token index** — `service/consentinit/ConsentInitServiceImpl.validateCustomerId`
   `customerId.trim().split("@")[1]` → `[0]`. A `user@aa-handle` virtual address
   resolves to the user part instead of the handle. Pinned by the `"@" +`
   re-prepend, the `if(customerIdSplit.size() > 1)` guard immediately above, and
   the doc "return the AA ID" — the handle is the token *after* `@` (index 1).
   Live: `ConsentServiceImpl` calls it to look up the AA entity.

3. **[MEDIUM] Regex quantifier** — `constants/GeneralConstants.VALID_PATTERN_UUID`
   final group `[0-9a-f]{12}$` → `{11}$`. A canonical UUID's last group is 12 hex
   digits, so valid v4 UUIDs stop matching. Pinned by the canonical 8-4-4-4-12
   layout spelled out in the same literal (`{8}-{4}-{4}-{4}-{12}`). Live:
   `UUIDGenerator.regaxUUIDvalidation` guards txnid / sessionId / consentHandle /
   consentId across every notification validator.

4. **[EASY] Whitespace normalization** — `utils/NullEmptyUtils.isNullorEmpty(String)`
   `val.trim().isEmpty()` → `val.isEmpty()`. A whitespace-only string is no longer
   "empty". Pinned by the sibling clause `val.equals("null")` in the same
   expression: the emptiness notion is deliberately lenient (even the literal
   string `"null"` counts), so a blank-after-trim string must too. Live: this is
   the adapter's ubiquitous required-field guard.

5. **[MEDIUM] 24- vs 12-hour clock** — `utils/DateTimeUtil.getISOTimeStamp`
   pattern `...'T'HH:mm:ss.SSS'Z'` → `...'T'hh:mm:ss.SSS'Z'`. Afternoon times
   render as morning. Pinned by the `'Z'` (UTC) ISO-8601 literal and by every
   other date pattern in the repo using 24-hour `HH`; these stamps are re-parsed
   downstream (`DateTime.parse(...)`), which a 12-hour render breaks. Live: used
   for every outgoing timestamp (consent/FI notifications, error responses).

Distinct shapes (base64-alphabet, token-index, regex-quantifier,
trim-normalization, hour-format) with no grep-able twin, no syntax breaks, no
crashes. The five sites now sit in five distinct files (Base64Decoder,
ConsentInitServiceImpl, GeneralConstants, DateTimeUtil, NullEmptyUtils), so no
two defects are co-located or co-discovered. `getAddedDate` is left fully
correct and is exercised only by pass_to_pass tests (zero-delta, month-add and
day-add), which also pin that the day-field path is undisturbed.

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch (temp-file form), restoring
`Base64.getUrlDecoder()`, `split("@")[1]`, `{12}`, `val.trim().isEmpty()`, and
`HH`. Any equivalent boundary correction also passes the gold tests.

## Verifier design (multi-module Maven adaptation)

- `tests/test.sh` locates the repo root by `.git`+`pom.xml` (here `/app`, the
  reactor root), applies `test_patch` from verifier-controlled config, runs
  `run_script.sh`, parses per-test verdicts from
  `webservice/target/surefire-reports`, and awards reward 1 only if every
  `fail_to_pass` and `pass_to_pass` test passed.
- `tests/run_script.sh` runs `mvn -o -B -q -pl webservice -Dtest=FiuBoundaryTest
  test` offline (root has `pom.xml` but no `src/`; sources live under
  `webservice/`, so detection checks `webservice/src`).
- `tests/parser.py` parses `webservice/target/surefire-reports/TEST-*.xml` into
  `{"tests":[{"name","status"}]}` with `FiuBoundaryTest::<method>` ids.
- `fail_to_pass` = 5 gold boundary tests (one per defect; fail at base+defects,
  pass once corrected).
- `pass_to_pass` = 14 gold tests pinning unchanged behavior on the same helpers
  (plain-alphabet base64 decode, null/empty-string/literal-"null"/list emptiness,
  malformed and wrong-version UUID rejection, zero-delta / month-add / day-add
  dates, the date/minute/second of a timestamp, null-VUA handling, and the
  leading `@` prepend).

## Verification ladder (all offline, `--network none`) — RESULTS

- In-image leak check: `git log --oneline | wc -l` == 1, `git diff` empty, no
  `src/test/*.java` present, defects live in the tree but the oracle values are
  absent from history (`git log -p | grep 'getUrlDecoder().decode(body'` == 0,
  `grep 'split("@")[1]'` == 0, `grep '{12}'` == 0). PASS.
- NULL run (planted image): reward 0; all 5 f2p FAILED with per-test lines (no
  collection errors); all 14 p2p passed (14/19). PASS.
- ORACLE run (`solve.sh`): reward 1, 19/19 pass. PASS.
- PARTIAL run (fix 2 of 5 — the base64 and trim defects): reward 0 (16/19; the
  other 3 f2p still fail). PASS.

## Fairness

- All five defected sites are live code reachable from the adapter's request
  paths, not dead helpers. Gold tests use only static calls and a bare
  `new ConsentInitServiceImpl()` whose tested method touches no injected field —
  no mocks, no Spring context, no reflection, no private-name coupling — so no
  test encodes the oracle's implementation. Each oracle value is derivable from
  the code itself (the sole caller decoding the same `split("\.")[1]` payload with
  `getUrlDecoder()` plus the base64url nature of JWS, a `size()>1` guard plus
  `"@"` re-prepend, the canonical UUID layout, a lenient sibling emptiness
  clause, a UTC ISO-8601 literal + repo-wide `HH`), never from convention alone;
  any equivalent boundary fix passes.
- Cross-defect isolation: the five sites are in five distinct files with no
  shared output path, so each f2p fails solely on its own asserted behaviour
  (NULL run: exactly 5 failures, 0 errors). The base64 f2p only fires on a
  payload whose base64url contains `-`/`_`; a plain-alphabet p2p pins that
  ordinary payloads are unaffected.
- The instruction is a report-level symptom writeup with two highlighted
  examples (valid ids rejected; afternoon timestamps read as morning) and names
  no file, method, line, edit direction, trigger value, or defect count. An
  agent that fixes only the two highlighted symptoms still fails ≥2 hidden f2p.
