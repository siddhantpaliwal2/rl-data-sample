# Ready-to-build brief: xrepo-linkshort-latent (analysis pre-done by main session)

Repo (staged, third-party, NOT user's): `audit-repos/24f3005028-LinkShortner-90edf9d5/LinkShortner/backend`
Python 3.11 / FastAPI / SQLAlchemy / bcrypt / pydantic-settings. No .git. **requirements.txt is UTF-16-LE + CRLF — decode to UTF-8 before pip install.** Only required env for Settings: `LINK_SHORTENER_DATABASE_URL` (use `sqlite://` for gold tests / a dummy for import). Visible suite `tests/test_links.py` drives the HTTP app via TestClient — plant only where those HTTP paths don't feed the edge (all 5 below are safe: verified the visible tests don't exercise these edges).

Standard pytest harness — copy tests/{test.sh,parser.py,run_script.sh} from cre-scoring-latent-4 verbatim; run_script runs `python -m pytest tests/test_linkshort_boundaries.py`.

## The 5 calibrated defects (2 easy + 3 medium, all derivable, distinct shapes)

1. **[EASY] config.py `parse_authorized_parties`** (~line 33): `if party.strip()` → `if party`.
   Edge: input "a, ,b" keeps the whitespace-only "" instead of filtering it. Pinned by the SIBLING `parse_cors_allowed_origins` (next method) doing the identical comprehension WITH `if origin.strip()`. Pure — call the classmethod / construct Settings with a comma env string.

2. **[EASY] main.py `_rate_limit_key`** (~line 52): `token = auth[7:]` → `auth[6:]`.
   Edge: `Authorization: "Bearer abc"` → key becomes "user: abc" (leading space) instead of "user:abc". Pinned same-line by `startswith("bearer ")` — "bearer " is exactly 7 chars. Pure — pass a fake request `SimpleNamespace(headers={"Authorization":"Bearer TOK"})`; bearer branch returns before `get_remote_address`.

3. **[MEDIUM] services.py `_as_utc`** aware branch (line 55): `return value.astimezone(timezone.utc)` → `return value.replace(tzinfo=timezone.utc)`.
   Edge: tz-aware non-UTC input (e.g. +05:30 14:00) must convert to 08:30 UTC; defect relabels as 14:00 UTC (loses the shift). Pinned by the two-branch structure (naive→attach with `.replace`, aware→convert with `.astimezone`) — flipping the aware branch to `.replace` collapses the distinction. Pure — `_as_utc(datetime(2024,1,1,14,0,tzinfo=timezone(timedelta(hours=5,minutes=30))))`.

4. **[MEDIUM] services.py `list_links`** (line 161): `offset = (page - 1) * page_size` → `page * page_size`.
   Edge: page=1 must return the first `page_size` rows (offset 0); defect skips the first page. Pinned by 1-indexed pagination convention + `PaginatedLinks` schema echoing `page` (page 1 is the first page). Needs in-mem SQLite: create N links for one owner, assert `list_links(page=1)` returns the newest page (order_by created_at desc, id desc). Use the models.Base + a sqlite:// engine like tests/conftest.py.

5. **[MEDIUM] config.py `prefer_psycopg_driver`** (~line 47): `value.replace("postgresql://", "postgresql+psycopg://", 1)` → drop the `, 1` (replace ALL).
   Edge: a database_url whose query/callback contains the literal "postgresql://" again — only the scheme prefix should be rewritten. Pinned by the `startswith("postgresql://")` guard = rewrite the SCHEME only. Pure — `Settings(database_url="postgresql://u@h/d?cb=postgresql://x").database_url` should keep the second occurrence intact.

## Build steps
- Repo image `linkshort-repo:v1`: FROM python:3.11-slim + git; COPY the `backend/` subtree to /app; decode requirements.txt UTF-16→UTF-8; `pip install -r requirements.txt` (fastapi, sqlalchemy, bcrypt, pydantic, pydantic-settings, slowapi, httpx for TestClient — trim clerk/uvicorn if they drag); `git init && add && commit`.
- Task env/Dockerfile: FROM linkshort-repo:v1 + plant patch + `rm -rf .git && git init -qb main && ... commit -qm "import codebase"` + mkdir -p /logs/verifier + WORKDIR /app. Set `ENV LINK_SHORTENER_DATABASE_URL=sqlite://` so import/Settings works.
- gold test `tests/test_linkshort_boundaries.py`: 5 f2p (one per defect, disjoint) + 10-14 p2p pinning adjacent-correct behavior. Import target funcs inside test bodies. For #4 use an in-mem sqlite session; the other 4 are pure.
- solve.sh doubled-heredoc reverse-apply. Verify offline (--network none): git len 1 + diff empty; run visible tests/test_links.py → 0 new failures (may need httpx/TestClient; if the full app import is heavy, it's OK for the visible suite to be the boundary file only — but confirm the plant doesn't break test_links.py on its inputs); NULL reward 0 (5 f2p FAILED per-test); ORACLE reward 1; PARTIAL (2 of 5) reward 0.

Return the standard JSON.
