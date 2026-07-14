# Reference plan — fiu-xrepo-fiu2-latent-bugs

Replacement JAVA LATENT-BUG task on the `fiu_adapter` substrate (FinBit FIU
adapter — Spring Boot 2.3.0 / Java 8 / **multi-module** Maven: `jws-signature`,
`diffie-hellman-services`, `webservice`, `kms`; 264 Java files). Disjoint from
the approved sibling `xrepo-fiu-latent`, which consumed the pure-util surface
(`Base64Decoder`, `ConsentInitServiceImpl`, `GeneralConstants`, `DateTimeUtil`,
`NullEmptyUtils`, `UUIDGenerator`). This task's five planted defects live in a
fresh set of deterministic surfaces — object copy, token parsing, request
validation counting, api-key segment guarding, and config mapping — all in the
`webservice` module (only that module is recompiled by `mvn -o -pl webservice
test`; the siblings resolve from the pre-built local-repo jars).

## Construction (LATENT-BUG pattern)

Base image `fiu-repo:v1` is `maven:3.9-eclipse-temurin-8` + git + python3, with
the repo LF-normalized, all four modules **installed** to the local Maven repo,
and the Surefire `junit-platform` provider warmed offline at build time. So
verify-time `mvn -o -pl webservice test` is fully offline — no network, no DB,
no secrets — and rebuilds only the graded module.

The environment `Dockerfile` plants a small **defect patch** (five single-token
edits across five files) into the working tree, deletes **all** shipped test
sources (`webservice/src/test`, `jws-signature/src/test`) plus the stale warm
test class, then collapses history (`rm -rf .git && git init && commit "import
codebase"`). The shipped tests are JUnit 4 / PowerMock and are never run by the
junit-platform provider (junit-vintage excluded); none touch the planted
helpers, so the agent starts from base+defects with an **empty, green** visible
test tree.

The gold tests (`FiuHelperBoundaryTest.java`, JUnit 5) are injected only at grade
time from `config.json`'s `test_patch`. They feed the exact edge inputs the
defects corrupt and assert the correct outputs. The class is placed in the
`service.externalentity` package so it can reach one package-private pure mapper
(`mapOneMoneyConfigResponse`) directly while calling every other target through
its public entry point (all defected paths are reached with no Spring context,
no mock, no reflection).

## Defects planted (5 — 3 breadth + 2 gate, five distinct shapes, five files)

1. **[GATE] Array/segment index** — `utils/GetDetachedBody.getDetached`
   `body.split("\\.")[2]` → `[1]`. The detached signature of a JWS compact
   serialization (`header.payload.signature`) is the third (last) segment.
   Pinned by the JWS 3-part structure and cross-file by
   `ConsentArtifactServiceImpl.getConsentDetail`, which decodes the *payload* as
   `signedConsent.split("\\.")[1]` — so index 2 is uniquely the signature. Shape
   described qualitatively in the instruction (no index value). p≈0.55.

2. **[BREADTH] Guard inversion** — `utils/BeansUtils.getNullPropertyNames`
   `getPropertyValue(propertyName) == null` → `!= null`. The method returns the
   names of the **null** source properties so that `copyProperties(...,
   ignoreNullProperties=true)` skips them; inverted, it skips the filled
   properties and copies the nulls. Pinned by the self-documenting method name
   `getNullPropertyNames` and the `ignoreNullProperties` semantics. Symptom given
   concretely (filled values dropped, blanks overwrite). p≈0.9.

3. **[GATE, RARE-TRIGGER] Numeric segment bound** —
   `service/signature/verification/HeaderTokenSignatureVerificationServiceImpl.verifyAAApiKey`
   `split_string.size() < 3` → `< 2`. A signed api key is a JWS compact token
   (header.payload.signature = 3 parts); a token with fewer parts must be
   rejected. Only a two-segment key whose second segment is *valid* base64
   reveals it (a well-formed 3-part key, an empty key, and a one-part key are all
   invariant). Pinned by the JWS 3-part structure. Shape described qualitatively
   (no bound value, no direction). p≈0.55.

4. **[BREADTH] Count equality (odd-one-out)** —
   `service/consentnotification/ConsentNotificationValidationImpl.validateRequestFields`
   `errorMsg.split(",").length == 1` → `== 2`. Exactly one invalid field must
   yield the singular `ERROR_MESSAGE` ("field is invalid"); the plural
   `SCHEMATIC_ERROR_MSG` ("fields are invalid") is for two or more. Pinned by
   four identical sibling lines (`errorMsg.split(",").length == 1`) in the other
   validators (`FIDataNotificationValidationImpl`, `ConsentServiceImpl`,
   `FiRequestServiceImpl`, `FiDataServiceImpl`) plus the singular/plural message
   pair. Symptom given concretely (single missing field returns the generic
   multi-field message). p≈0.9.

5. **[BREADTH] Mapper source swap (odd-one-out)** —
   `service/externalentity/AAEntityServiceImpl.mapOneMoneyConfigResponse`
   `setCompanyName(entityDetails.getCompanyName())` →
   `getCompanyColor()`. The company-name field must map from the company name.
   Pinned by the two adjacent sibling mappings
   (`setCompanyLogo(getCompanyLogo())`, `setCompanyColor(getCompanyColor())`).
   Symptom given concretely (company name shows the brand-colour value). p≈0.9.

Five distinct edit shapes (array index, null-guard inversion, relational size
bound, count equality, getter source swap) with no grep-able twin, no syntax
breaks, no crashes, across five distinct files in four packages. Estimated Opus
solve ≈ (0.9·0.9·0.9)·(0.55·0.55) ≈ 0.22 → ~2/10; Sonnet lower (the two gates
are the wall).

## Oracle fix

`solution/solve.sh` reverse-applies the defect patch (temp-file form), restoring
`[2]`, `== null`, `< 3`, `== 1`, and `getCompanyName()`. Any equivalent boundary
correction also passes the gold tests (fairness-verified with last-segment
indexing, `Objects.isNull`, `!= 3`, `< 2`).

## Verifier design (multi-module Maven adaptation)

- `tests/test.sh` (verbatim from sibling) locates the repo root by `.git`+
  `pom.xml` (here `/app`, the reactor root), applies `test_patch` from
  verifier-controlled config, runs `run_script.sh`, parses per-test verdicts from
  `webservice/target/surefire-reports`, and awards reward 1 only if every
  `fail_to_pass` and `pass_to_pass` test passed.
- `tests/run_script.sh` runs `mvn -o -B -q -pl webservice -Dtest=FiuHelperBoundaryTest
  test` offline.
- `tests/parser.py` (verbatim) parses `TEST-*.xml` into `{"tests":[{"name",
  "status"}]}` with `FiuHelperBoundaryTest::<method>` ids.
- `fail_to_pass` = 5 gold boundary tests (one per defect).
- `pass_to_pass` = 12 gold tests pinning unchanged behavior on the same helpers
  (equal-tail split stability; copy-all without ignore; empty/null/one-segment
  api-key rejection; multi-field plural message for 3 and 4 misses; company
  colour/logo mapping, app-identifier passthrough, literal-"null" identifier
  blanking).

## Verification ladder (all offline, `--network none`) — RESULTS

- Leak: `git log --oneline | wc -l` == 1; `git status` clean; `git diff` empty;
  no `src/test/*.java`; oracle `[2]` absent from history; all 5 markers present.
  PASS.
- NULL (planted image): reward 0; 17 run / 5 failures (all 5 f2p) / 0 errors;
  all 12 p2p passed. PASS.
- ORACLE (`solve.sh`): reward 1; 17/17. PASS.
- PARTIAL (revert 2 of 5 — the getDetached index and mapper swap): reward 0;
  14/17; the other 3 f2p (copy inversion, api-key bound, count) still fail. PASS.
- FAIRNESS (materially-different alt-fixes: last-segment, `Objects.isNull`,
  `!= 3`, `< 2`): reward 1; 17/17. PASS.

## Fairness

- All five defected sites are live code reachable from the adapter's request
  paths (fi-request signature extraction, DTO copy in signup/update, api-key
  header verification, consent-notification validation, one-money config
  response), not dead helpers. Gold tests use only static calls and
  bare-constructed stateless services whose tested paths touch no injected field
  — no mocks, no Spring context, no reflection, no private-name coupling — so no
  test encodes the oracle's implementation. Each oracle value is derivable from
  the code itself (JWS 3-part structure + a cross-file payload decode, the
  self-naming `getNullPropertyNames`, the JWS segment count, four identical
  sibling count-lines + singular/plural messages, two adjacent sibling
  mappings), never from convention alone; any equivalent boundary fix passes.
- Cross-defect isolation: the five sites are in five distinct files with no
  shared output path, so each f2p fails solely on its own asserted behaviour
  (NULL run: exactly 5 failures, 0 errors). The api-key defect only fires on a
  two-segment token with a valid base64 payload; empty / one-segment p2p pin that
  ordinary rejections are unaffected.
- The instruction is a partner-bank escalation email chain — symptom-level, names
  no file, method, line, edit direction, trigger value, or defect count. The two
  gate symptoms (wrong dotted-token segment; too-few-part token accepted) are
  stated at shape level with no values or direction; the three breadth symptoms
  carry concrete example values. An agent that fixes only the highlighted
  breadth symptoms still fails the two gate f2p.
