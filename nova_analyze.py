#!/usr/bin/env python3
"""Analysis harness for nova-* harbor jobs.
Extracts per-trial rewards, cost/tokens, verifier test breakdown (f2p/p2p),
and classifies the dominant failure mode for failed trials using OBJECTIVE
signals (verifier tests, trajectory exit_status/steps/edits, exception_info).

Usage:
  python3 nova_analyze.py <job_dir> [<job_dir> ...]      # per-job detail
  python3 nova_analyze.py --json jobs/nova-*             # machine-readable JSON
"""
import json, os, sys, glob, re

TASKS_DIR = os.path.dirname(os.path.abspath(__file__))

TASK_DIRS = {
    "plaid": "plaid-bank-report",
    "qb": "quickbooks-sync",
    "calls": "calls-v2",
    "cre4": "cre-scoring-latent-4",
    "fintools": "latent-financial-tools",
    "market": "latent-market-structure",
}

# harbor/litellm reports cost_usd=0 for Nova (no pricing), so compute from tokens.
# $ per token (in, out). Source: OpenRouter model endpoints.
MODEL_PRICE = {
    "premier": (2.5e-6, 12.5e-6),
    "pro": (0.8e-6, 3.2e-6),
    "lite": (0.3e-6, 2.5e-6),
}

def price_for(job_name):
    for short, pr in MODEL_PRICE.items():
        if ("-" + short + "-") in job_name or job_name.endswith("-" + short) or job_name.startswith("nova-" + short):
            return pr
    return None

# exception types that are infra/transient, not model-quality failures
INFRA_EXC = {"NetworkConnectionError", "ApiRateLimitError", "CancelledError",
             "AgentSetupTimeoutError", "UnknownApiError", "ContextWindowExceededError",
             "AgentExecutionTimeoutError", "EnvironmentBuildError"}
# exception types that indicate the agent/protocol itself broke
AGENT_EXC = {"NonZeroAgentExitCodeError", "RuntimeError"}

EDIT_PAT = re.compile(r"(sed -i|cat\s*<<|cat\s*>|apply_patch|python\s*-\s*<<|>>?\s*[\w./]+\.py|git apply|patch <|tee\s|>\s*/|echo .*>)", re.I)

def load_scaffold(task_dir):
    p = os.path.join(TASKS_DIR, task_dir, "SCAFFOLD_REPORT.json")
    if not os.path.exists(p):
        return set(), set(), []
    d = json.load(open(p))
    return set(d.get("f2p", [])), set(d.get("p2p", [])), d.get("source_files_in_patch") or []

def norm_test(name):
    m = re.search(r'(tests/.*)$', name)
    return m.group(1) if m else name

def guess_task(job_name):
    # job names: nova-<model>-<taskshort>
    for short, d in TASK_DIRS.items():
        if job_name.endswith("-" + short):
            return short, d
    for short, d in TASK_DIRS.items():
        if short in job_name.split("-"):
            return short, d
    for short, d in TASK_DIRS.items():
        if short in job_name:
            return short, d
    return None, None

def parse_trajectory(trial_dir):
    """Return dict: n_steps, exit_status, edited_src(bool given src basenames), n_edit_cmds, made_diff."""
    tj = os.path.join(trial_dir, "agent", "mini-swe-agent.trajectory.json")
    info = {"n_steps": 0, "exit_status": None, "n_edit_cmds": 0, "asst_text": "", "tool_text": "", "n_noncall": 0, "made_diff": False}
    if not os.path.exists(tj):
        return info
    try:
        m = json.load(open(tj)).get("messages", [])
    except Exception:
        return info
    asst = [x for x in m if x.get("role") == "assistant"]
    info["n_steps"] = len(asst)
    ex = [x for x in m if x.get("role") == "exit"]
    if ex:
        info["exit_status"] = (ex[0].get("extra") or {}).get("exit_status")
    a_text = "\n".join(x.get("content") or "" for x in asst)
    t_text = "\n".join(x.get("content") or "" for x in m if x.get("role") == "tool")
    all_text = "\n".join(x.get("content") or "" for x in m)
    info["asst_text"] = a_text
    info["tool_text"] = t_text
    info["n_edit_cmds"] = len(EDIT_PAT.findall(a_text))
    info["made_diff"] = "diff --git" in t_text
    # count protocol misses (mini-swe rejects turns with no tool call)
    info["n_noncall"] = all_text.count("No tool calls found in the response")
    return info

def classify(reward, exc_info, tests, f2p, p2p, src_files, tr):
    """Return (mode_code, detail). Modes: solved, infra, a_format, b_giveup,
    c_localization, d_partial, e_regression, f_verbosity."""
    if reward is not None and reward >= 1.0:
        return "solved", ""

    # exit_status is the cleanest protocol signal
    es = tr.get("exit_status")
    if es == "RepeatedFormatError":
        return "a_format", f"RepeatedFormatError; {tr.get('n_noncall',0)} 'no tool call' rejections; steps={tr['n_steps']}"
    if es in ("ModuleNotFoundError",) or (es and es not in ("Submitted", None)):
        # non-standard agent exit -> protocol/agent error unless it's a known infra exc handled below
        if not exc_info:
            return "a_format", f"agent exit={es}; steps={tr['n_steps']}"

    exc_type = ""
    if exc_info:
        exc_type = exc_info.get("exception_type") or exc_info.get("type") or ""
        if not exc_type:
            exc_type = str(exc_info)[:60]
        base = exc_type.split(".")[-1].split("'")[0].strip()
        if base in INFRA_EXC:
            return "infra", f"infra exc: {base}"
        if base in AGENT_EXC:
            # NonZeroAgentExitCodeError/RuntimeError with NO trajectory = setup/install
            # failure (e.g. uv/pip download died) -> infra, not a model failure.
            if tr.get("n_steps", 0) == 0:
                return "infra", f"setup-phase {base} (agent never ran)"
            return "a_format", f"agent exc mid-run: {base}; steps={tr['n_steps']}"
        return "a_format", f"exc: {base}"

    status = {norm_test(t["name"]): t.get("status") for t in tests}
    f2p_n = {norm_test(x) for x in f2p}
    p2p_n = {norm_test(x) for x in p2p}
    f2p_pass = [t for t in f2p_n if status.get(t) == "passed"]
    f2p_fail = [t for t in f2p_n if status.get(t) != "passed"]
    p2p_fail = [t for t in p2p_n if t in status and status.get(t) != "passed"]

    have_tests = len(status) > 0

    if not have_tests:
        # verifier collected 0 tests: usually the agent's edit broke the module import
        made_edits = tr.get("n_edit_cmds", 0) > 0 or tr.get("made_diff")
        if es == "Submitted" or made_edits:
            return "e_regression", f"edits broke module import (0 tests collected); steps={tr['n_steps']}"
        if tr["n_steps"] <= 3:
            return "b_giveup", f"no tests ran, no edits; steps={tr['n_steps']}"
        return "a_format", f"verifier empty, no edits despite {tr['n_steps']} steps"

    # regression: broke a p2p that should stay green
    if p2p_fail:
        return "e_regression", f"broke {len(p2p_fail)}/{len(p2p_n)} p2p; f2p {len(f2p_pass)}/{len(f2p_n)}"

    # partial: fixed some f2p but not all
    if f2p_pass and f2p_fail:
        return "d_partial", f"f2p {len(f2p_pass)}/{len(f2p_n)} pass; missed {len(f2p_fail)}"

    # zero f2p fixed
    if not f2p_pass:
        edited_src = False
        if src_files:
            for sf in src_files:
                b = os.path.basename(sf)
                if b and (b in tr["asst_text"] or b in tr["tool_text"]):
                    edited_src = True
                    break
        step_limit = tr["n_steps"] >= 90
        if src_files and not edited_src:
            return "c_localization", f"never opened {','.join(os.path.basename(s) for s in src_files)}; steps={tr['n_steps']}"
        if tr["n_edit_cmds"] == 0 and not tr["made_diff"]:
            return "c_localization", f"no edit commands issued; steps={tr['n_steps']}"
        if step_limit:
            return "b_giveup", f"hit step limit ({tr['n_steps']}), 0 f2p, edits ineffective"
        if tr["n_steps"] <= 5:
            return "b_giveup", f"very short ({tr['n_steps']} steps), 0 f2p"
        return "b_giveup", f"edited but 0 f2p fixed; steps={tr['n_steps']}"

    return "d_partial", "unclassified"

def analyze_job(job_dir):
    job_name = os.path.basename(job_dir.rstrip("/"))
    short, task_dir = guess_task(job_name)
    f2p, p2p, src_files = load_scaffold(task_dir) if task_dir else (set(), set(), [])
    jr_path = os.path.join(job_dir, "result.json")
    job_res = json.load(open(jr_path)) if os.path.exists(jr_path) else {}
    finished = job_res.get("finished_at")
    stats = job_res.get("stats") or {}

    trials = []
    for td in sorted(glob.glob(os.path.join(job_dir, (task_dir + "__*") if task_dir else "*__*"))):
        if not os.path.isdir(td):
            continue
        rp = os.path.join(td, "result.json")
        res = {}
        if os.path.exists(rp):
            try:
                res = json.load(open(rp))
            except Exception:
                res = {}
        vr = res.get("verifier_result") or {}
        reward = (vr.get("rewards") or {}).get("reward") if isinstance(vr, dict) else None
        # fallback: read verifier/reward.txt (written even when harbor finalization hangs)
        if reward is None:
            rwp = os.path.join(td, "verifier", "reward.txt")
            if os.path.exists(rwp):
                try:
                    reward = float(open(rwp).read().strip())
                except Exception:
                    reward = None
        # skip trials that have not produced a reward yet (still running)
        if reward is None and not os.path.exists(os.path.join(td, "verifier", "output.json")):
            continue
        exc = res.get("exception_info")
        tests = []
        vout = os.path.join(td, "verifier", "output.json")
        if os.path.exists(vout):
            try:
                tests = (json.load(open(vout)) or {}).get("tests", [])
            except Exception:
                pass
        ar = res.get("agent_result") or {}
        tr = parse_trajectory(td)
        mode, detail = classify(reward, exc, tests, f2p, p2p, src_files, tr)
        nin = ar.get("n_input_tokens") or 0
        nout = ar.get("n_output_tokens") or 0
        cost = ar.get("cost_usd")
        price = price_for(job_name)
        if (not cost) and price and (nin or nout):
            cost = nin * price[0] + nout * price[1]
        trials.append({
            "trial": os.path.basename(td),
            "reward": reward,
            "cost_usd": cost,
            "n_input_tokens": ar.get("n_input_tokens"),
            "n_output_tokens": ar.get("n_output_tokens"),
            "n_steps": tr["n_steps"],
            "exit_status": tr["exit_status"],
            "n_noncall": tr.get("n_noncall", 0),
            "exception": exc_type_of(exc),
            "mode": mode,
            "detail": detail,
        })
    solved = sum(1 for t in trials if (t["reward"] or 0) >= 1.0)
    n_infra = sum(1 for t in trials if t["mode"] == "infra")
    computed_cost = sum((t["cost_usd"] or 0) for t in trials)
    from collections import Counter
    mode_dist = dict(Counter(t["mode"] for t in trials))
    return {
        "job": job_name, "task": short, "finished": bool(finished),
        "n_trials": len(trials), "solved": solved,
        "solve_rate": f"{solved}/{len(trials)}" if trials else "0/0",
        "n_infra": n_infra,
        "job_cost_usd": stats.get("cost_usd"),
        "computed_cost_usd": round(computed_cost, 4),
        "mode_dist": mode_dist,
        "trials": trials,
    }

def exc_type_of(exc):
    if not exc:
        return None
    t = exc.get("exception_type") or exc.get("type") or str(exc)[:40]
    return t.split(".")[-1].split("'")[0].strip()

if __name__ == "__main__":
    as_json = "--json" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dirs = []
    for a in args:
        dirs.extend(glob.glob(a))
    dirs = [d for d in dirs if os.path.isdir(d) and os.path.exists(os.path.join(d, "result.json"))]
    out = [analyze_job(d) for d in sorted(set(dirs))]
    if as_json:
        print(json.dumps(out, indent=1))
    else:
        for j in out:
            print(f"\n### {j['job']}  task={j['task']}  solve={j['solve_rate']}  infra={j['n_infra']}  finished={'Y' if j['finished'] else 'RUNNING'}  cost=${j['computed_cost_usd']}  modes={j['mode_dist']}")
            for t in j["trials"]:
                r = t["reward"]
                tag = "SOLVED" if (r or 0) >= 1.0 else t["mode"]
                exc = f" exc={t['exception']}" if t["exception"] else ""
                cost = f"${round(t['cost_usd'],3)}" if t["cost_usd"] else "$?"
                nc = f" noncall={t['n_noncall']}" if t.get("n_noncall") else ""
                print(f"  {t['trial']:26s} r={r} steps={t['n_steps']:<3} {cost:<8} exit={t['exit_status']}{nc}{exc}  [{tag}] {t['detail']}")
