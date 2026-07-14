# Substrate Repositories

The eight tasks were built on three real, private production codebases (two
Python, one Java), all from the fintech-lending domain. Each was frozen into a
pinned Docker base image (`<name>-repo:v1`) that contains the working tree with
dependencies installed and any required dummy env baked in; every task's
`environment/Dockerfile` starts `FROM` one of these images and plants that
task's defects on top.

A lesson encoded in this selection: **substrate size is the difficulty
lever.** Candidate tasks built on small repos (200–900 LOC, one or two files)
were all rejected as too easy - the agent simply reads the whole codebase and
there is no localization challenge. Every surviving task sits on a repo large
enough that finding the defective boundaries is most of the work.

---

## loangenus - `loangenus-repo:v1`

- **Language / size:** Python - 338 files, ~72k LOC
- **Domain:** AI-assisted commercial-real-estate lending platform: document
  ingestion and field extraction, credit-report parsing, bank/bureau/accounting
  analytics, CRE deal qualification and lender matching, CRM integrations.
- **Structure:** `loangen-agent/` (the agent backend the tasks target -
  `agent/documents/`, `agent/analytics/services/`,
  `agent/services/cre_qualification/`, `agent/integrations/`) plus
  `loangen-app/` (product app, out of scope for all tasks).
- **Test stack:** pytest, unittest-style suites with AsyncMock/MagicMock;
  fully offline and deterministic (pydantic Settings satisfied by dummy env
  baked into the image).
- **Tasks built on it (4):** `latent-credit-normalize`,
  `latent-doc-extractors`, `latent-financial-tools`, `latent-phone-invites`.
- **Why it's good substrate:** the workhorse. Deep, layered business logic
  with many pure deterministic helpers (string normalization, thresholding,
  ratio math) whose edge behavior is pinned by neighboring code - ideal for
  latent boundary defects that existing tests never touch.

## transaction-enrichment-python - `txenrich-repo:v1`

- **Language / size:** Python - 52 files, ~11k LOC
- **Domain:** bank-statement enrichment engine (2022-era production code):
  per-bank categorization scripts that read raw description/remark/amount/type
  off each transaction and derive category, subcategory and payee.
- **Structure:** `categorizationapp/categorizationapp/BankScripts/` - ~35
  bank-specific scripts (HDFC, ICICI, Axis, …) built on pandas/numpy
  `np.select` condition tables.
- **Environment quirks:** pinned 2022-era numpy/pandas so the original logic
  runs unchanged; several files carry CRLF line endings, which the task image
  preserves byte-exactly (defects are planted by byte-level replacement).
- **Tasks built on it (3):** `xrepo-txenrich-latent` (HDFC/ICICI),
  `xrepo-txenrich3-latent` (IDBI/Indusind), `xrepo-txenrich4-latent`
  (PNB/Canara) - disjoint bank pairs, so no two tasks share a defect site.
- **Why it's good substrate:** the condition-table idiom repeats across 35
  scripts, so the intended behavior of any one line is pinned by dozens of
  sibling occurrences - perfect for single-token sentinel/offset defects.

## fiu_adapter - `fiu-repo:v1`

- **Language / size:** Java - 264 files, ~16k LOC (Maven, Java 8 /
  `maven:3.9-eclipse-temurin-8`)
- **Domain:** FIU (Financial Information User) adapter for the Indian Account
  Aggregator ecosystem: consent/data-flow webservice with parsing, validation,
  crypto (Diffie-Hellman services, JWS signatures) and timestamp handling.
- **Structure:** multi-module Maven build (`webservice`, `kms`,
  `jws-signature`, `diffie-hellman-services`, …); the graded suite is pure
  JUnit 5 over parsing/validation/timestamp helpers - no Spring context, no
  DB, no network.
- **Environment notes:** the base image pre-installs sibling modules, warms
  the Maven cache and the Surefire JUnit-platform provider at build time so
  agent-side and grading-side `mvn test` runs are fast and offline.
- **Task built on it (1):** `xrepo-fiu-latent` - the only Java task in the
  bank, and proof the task recipe transfers across languages and build
  systems.

---

## Common properties

- **Frozen and offline.** Each base image pins the repo at a fixed commit;
  task images scrub git history down to a single synthetic commit so agents
  cannot diff their way to the defects. No task needs network access, real
  credentials, or external services at solve or grade time.
- **Green under their own tests.** Every planted defect is invisible to the
  repo's existing test suite - that is the "latent" property. Only the gold
  boundary tests (injected at grade time from `tests/config.json`) expose
  them.
- **Private substrate.** These are private codebases; the base images are
  distributed directly rather than rebuilt from source. To run the tasks you
  need the three `*-repo:v1` images present locally (`docker images | grep
  repo:v1`).
