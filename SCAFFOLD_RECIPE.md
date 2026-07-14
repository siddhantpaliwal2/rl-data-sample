# Silver task scaffolding recipe (loangenus)

Canonical example: `silver-tasks/ingestion-stale-blocker/` — READ ALL 9 FILES FIRST
and copy its structure exactly. Repo: `/Users/siddhantpaliwal/Desktop/boostmoney-audit/loangenus`
(never modify its working tree). Repo image `loangenus-repo:v1` is already built and
contains the full git history; env vars `JWT_SECRET_KEY`, `LIVEKIT_*` are baked in.

## Workspace layout (all 9 files required)
```
silver-tasks/<task-name>/
├── instruction.md          symptom-framed, WHAT not HOW, never leaks the fix.
│                           Starts with <uploaded_files>/app</uploaded_files>.
│                           May specify public API (module path + signatures) the
│                           gold tests import — that's contract, not leak.
├── reference_plan.md       root cause, oracle fix, verifier design, fairness note
├── task.toml               copy from canonical, change title/base_commit/difficulty
├── environment/Dockerfile  FROM loangenus-repo:v1; git reset --hard <BASE>; git clean -fdq;
│                           ENV block with ONLY the dummy env this task's tests need;
│                           starts with "# check=skip=SecretsUsedInArgOrEnv";
│                           mkdir -p /logs/verifier; WORKDIR /app/loangen-agent
├── solution/solve.sh       heredoc-embedded unified diff + git apply (see canonical
│                           for the double-heredoc check+apply pattern)
└── tests/                  test.sh, run_script.sh, parser.py: copy from canonical;
                            edit ONLY the test file list in run_script.sh.
                            config.json: instance_id, repo, base_commit (full 40-hex),
                            patch, test_patch, fail_to_pass, pass_to_pass,
                            selected_test_files_to_run
```

## Procedure
1. `git show <FIX> --stat` and read the full diff. BASE = `git rev-parse <FIX>^`.
2. Solution patch: `git diff BASE FIX -- <agent source files only>` — only
   `loangen-agent/agent/**` files needed to make gold tests pass. Never test files,
   never `loangen-app/`. For multi-defect commits, restrict to your assigned defect
   scope (files listed in your assignment).
3. Gold tests:
   - If the fix commit touched `loangen-agent/tests/`, use `git diff BASE FIX -- <test files>`
     as the starting test_patch, BUT move any module-level import of a module that
     does not exist at BASE into the test method bodies (collection must succeed at
     BASE; each test must fail individually with a per-test FAILED line — file-level
     collection ERROR lines break the parser's name matching).
   - Otherwise author a new `tests/test_<topic>.py` in the style of existing tests
     (unittest + AsyncMock/MagicMock, hermetic, no network). Assert observable
     behavior of the FIXED code. Verify each new test fails at BASE.
   - Generate test_patch via a scratch worktree:
     `git worktree add <UNIQUE_SCRATCH_PATH> BASE`, write test files there,
     `git add -N loangen-agent/tests/ && git diff -- loangen-agent/tests/`,
     then `git worktree remove --force <path>`. Use a path unique to your task.
4. Discover required env: run the candidate test files in docker at FIX; every
   pydantic Settings ValidationError names the missing env var — add dummies until
   the suite collects. Record them for environment/Dockerfile. (Known set from the
   canonical task: DOCUMENT_INGESTION_ENABLED, DOCUMENT_QA_ENABLED,
   AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT/KEY, QDRANT_URL/API_KEY,
   EMBEDDING_DEPLOYMENT_NAME, LLM_API_KEY.)
5. f2p = tests that FAIL at BASE (with test_patch) and PASS at FIX. p2p = tests
   passing at both, from the same files plus 1 stable extra file that exists at BASE
   (check `git ls-tree BASE -- loangen-agent/tests/`). NEVER include a test whose
   assertion conflicts with the task env (e.g. test_defaults_disable_ingestion_and_qa).
6. Verify the contract in docker (adapt env flags):
   NULL:   docker run --rm -v "$PWD/silver-tasks/<name>/tests":/vt:ro <task-image> sh /vt/test.sh
           → expect "required passed: <p2p>/<total>" and reward: 0, with every f2p FAILED
   ORACLE: docker run --rm -v tests + -v solution mounts <task-image>
           sh -c 'sh /vs/solve.sh && sh /vt/test.sh' → reward: 1
   Build the task image first: docker build -t silver-task-<name> silver-tasks/<name>/environment/
7. Write `silver-tasks/<name>/SCAFFOLD_REPORT.json`:
   {"task": name, "fix_commit": .., "base_commit": .., "f2p": [..], "p2p": [..],
    "null_reward": 0, "oracle_reward": 1, "env": {..}, "notes": ".."}

## Hard rules
- Do NOT run harbor. Do NOT touch silver-tasks/jobs/. Do NOT modify the loangenus
  working tree (scratch worktrees only, removed afterward).
- Workspace limits: ≤64 files, ≤256KB/file, ≤768KB total.
- Dockerfile static rules: pinned FROM, --no-install-recommends, no eval, ≤200 lines.
- instruction.md: concrete symptom + expected outcome; do not name the fix commit,
  do not prescribe implementation steps, do not mention the gold tests.
- Difficulty target: the task should NOT be solvable by grepping alone — if the fix
  is a one-liner with an obvious symptom→location mapping, widen scope (combine with
  an adjacent defect from the same commit) or note it as easy in the report.
