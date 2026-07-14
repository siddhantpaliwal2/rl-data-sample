#!/usr/bin/env python3
"""Aggregate all nova-* jobs into report tables + AMAZON_MODEL_REPORT.json.
Usage: python3 nova_report.py
"""
import json, glob, os
from collections import defaultdict, Counter
from nova_analyze import analyze_job, TASK_DIRS

HERE = os.path.dirname(os.path.abspath(__file__))

MODELS = ["premier", "pro", "lite"]
MODEL_LABEL = {"premier": "Nova Premier", "pro": "Nova Pro", "lite": "Nova 2 Lite"}
TASK_ORDER = ["plaid", "qb", "calls", "cre4", "fintools", "market"]
TASK_LABEL = {k: v for k, v in TASK_DIRS.items()}

# measured Claude baselines (from finished --sonnet-c2 / --opus-c2 jobs)
CLAUDE_BASE = {
    "plaid":    {"sonnet": "0/5",  "opus": "10/10"},
    "qb":       {"sonnet": "0/10", "opus": "7/10"},
    "calls":    {"sonnet": "0/5",  "opus": "8/10"},
    "cre4":     {"sonnet": "0/5",  "opus": "0/10"},
    "fintools": {"sonnet": "0/5",  "opus": "8/10"},
    "market":   {"sonnet": "3/5",  "opus": "9/10"},
}

def model_of(job_name):
    for m in MODELS:
        if job_name.startswith("nova-" + m + "-"):
            return m
    return None

def main():
    jobs = {}
    for d in sorted(glob.glob(os.path.join(HERE, "jobs", "nova-*"))):
        if not os.path.isdir(d):
            continue
        if not os.path.exists(os.path.join(d, "result.json")) and not glob.glob(os.path.join(d, "*", "verifier", "reward.txt")):
            continue
        j = analyze_job(d)
        jobs[j["job"]] = j

    # index by (model, task)
    grid = {}
    for name, j in jobs.items():
        m = model_of(name)
        t = j["task"]
        if m and t:
            grid[(m, t)] = j

    # solve-rate table
    solve_table = {}
    for t in TASK_ORDER:
        row = {"task": TASK_LABEL.get(t, t),
               "sonnet": CLAUDE_BASE.get(t, {}).get("sonnet", "-"),
               "opus": CLAUDE_BASE.get(t, {}).get("opus", "-")}
        for m in MODELS:
            j = grid.get((m, t))
            row[m] = j["solve_rate"] if j else "-"
        solve_table[t] = row

    # failure-mode distribution per model (aggregate across that model's jobs)
    mode_dist = {m: Counter() for m in MODELS}
    infra_by_model = {m: 0 for m in MODELS}
    cost_by_model = {m: 0.0 for m in MODELS}
    solved_by_model = {m: 0 for m in MODELS}
    trials_by_model = {m: 0 for m in MODELS}
    for (m, t), j in grid.items():
        for tr in j["trials"]:
            mode_dist[m][tr["mode"]] += 1
            trials_by_model[m] += 1
            if tr["mode"] == "infra":
                infra_by_model[m] += 1
            if (tr["reward"] or 0) >= 1.0:
                solved_by_model[m] += 1
            cost_by_model[m] += (tr["cost_usd"] or 0)

    cost_per_solved = {}
    for m in MODELS:
        s = solved_by_model[m]
        cost_per_solved[m] = round(cost_by_model[m] / s, 4) if s else None

    report = {
        "generated_from": "jobs/nova-*",
        "n_jobs": len(jobs),
        "claude_baselines": CLAUDE_BASE,
        "solve_table": solve_table,
        "failure_mode_distribution": {m: dict(mode_dist[m]) for m in MODELS},
        "infra_errors_by_model": infra_by_model,
        "cost_usd_by_model": {m: round(cost_by_model[m], 4) for m in MODELS},
        "trials_by_model": trials_by_model,
        "solved_by_model": solved_by_model,
        "cost_per_solved_task_usd": cost_per_solved,
        "jobs": {name: {k: v for k, v in j.items() if k != "trials"} for name, j in jobs.items()},
        "job_trials": {name: j["trials"] for name, j in jobs.items()},
    }
    with open(os.path.join(HERE, "AMAZON_MODEL_REPORT.json"), "w") as f:
        json.dump(report, f, indent=1)

    # print markdown tables
    print("## Solve-rate table (task x model)\n")
    print("| Task | Sonnet | Opus | Nova Premier | Nova Pro | Nova 2 Lite |")
    print("|---|---|---|---|---|---|")
    for t in TASK_ORDER:
        r = solve_table[t]
        print(f"| {r['task']} | {r['sonnet']} | {r['opus']} | {r['premier']} | {r['pro']} | {r['lite']} |")
    print("\n## Failure-mode distribution per model\n")
    print("| Mode | Nova Premier | Nova Pro | Nova 2 Lite |")
    print("|---|---|---|---|")
    all_modes = ["solved", "a_format", "b_giveup", "c_localization", "d_partial", "e_regression", "f_verbosity", "infra"]
    for mode in all_modes:
        cells = [str(mode_dist[m].get(mode, 0)) for m in MODELS]
        if any(c != "0" for c in cells):
            print(f"| {mode} | {cells[0]} | {cells[1]} | {cells[2]} |")
    print("\n## Cost\n")
    for m in MODELS:
        print(f"- {MODEL_LABEL[m]}: total ${round(cost_by_model[m],3)} over {trials_by_model[m]} trials, "
              f"solved {solved_by_model[m]}, cost/solved={cost_per_solved[m]}")
    print(f"\nWrote AMAZON_MODEL_REPORT.json ({len(jobs)} jobs)")

if __name__ == "__main__":
    main()
