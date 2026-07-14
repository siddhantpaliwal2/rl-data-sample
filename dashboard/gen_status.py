#!/usr/bin/env python3
"""Scan harbor job dirs + scaffold workspaces, write dashboard/status.json."""
import json
import re
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # silver-tasks/
JOBS = ROOT / "jobs"
OUT = Path(__file__).resolve().parent / "status.json"

STEP_RE = re.compile(r"step (\d+), \$([0-9.]+)")

# Editorial status notes, updated as the program evolves.
TASK_NOTES = {
    "ingestion-stale-blocker": "primary candidate — difficulty r1/r2 exposed contract gaps (fixed); round 3 pending",
    "plaid-bank-report": "second candidate — easiness passed clean; difficulty needs output-shape diagnosis",
    "inbound-call-routing": "too easy (sonnet 5/5) — salvage plan: widen to full multi-defect scope, strip function hints",
    "cre-qualification-fixes": "too easy (sonnet 5/5) — parked; display contract can't be unpublished",
    "array-credit-report": "too easy (sonnet 4/5, clean) — retry option: trim schema detail from instruction",
}


def trial_state(tdir: Path) -> dict:
    st = {"name": tdir.name.split("__")[-1], "state": "running", "reward": None,
          "steps": None, "cost": None}
    rw = list(tdir.glob("**/reward.txt"))
    if rw:
        try:
            st["reward"] = int(rw[0].read_text().strip() or "0")
            st["state"] = "done"
        except ValueError:
            pass
    if (tdir / "exception.txt").exists() and st["state"] != "done":
        st["state"] = "error"
    log = tdir / "agent" / "mini-swe-agent.txt"
    if log.exists():
        try:
            hits = STEP_RE.findall(log.read_text(errors="ignore"))
            if hits:
                st["steps"], st["cost"] = int(hits[-1][0]), float(hits[-1][1])
        except OSError:
            pass
    return st


def job_meta(jdir: Path) -> tuple[str, str]:
    try:
        cfg = json.loads((jdir / "config.json").read_text())
        agent = (cfg.get("agents") or [{}])[0]
        return agent.get("name") or "?", agent.get("model_name") or ""
    except (OSError, json.JSONDecodeError, IndexError):
        return "?", ""


def scan_jobs() -> list[dict]:
    jobs = []
    if not JOBS.exists():
        return jobs
    for jdir in sorted(JOBS.iterdir()):
        if not jdir.is_dir():
            continue
        trial_dirs = [t for t in sorted(jdir.iterdir())
                      if t.is_dir() and (t / "config.json").exists()]
        trials = [trial_state(t) for t in trial_dirs]
        agent, model = job_meta(jdir)
        task = trial_dirs[0].name.split("__")[0] if trial_dirs else "?"
        name = jdir.name
        if agent in ("nop", "oracle"):
            kind = "harness"
        elif "difficulty" in name or "opus" in model:
            kind = "difficulty"
        else:
            kind = "easiness"
        solved = sum(1 for t in trials if t["reward"] == 1)
        done = sum(1 for t in trials if t["state"] in ("done", "error"))
        errors = sum(1 for t in trials if t["state"] == "error")
        total = len(trials)
        finished = (jdir / "result.json").exists() and done == total
        void = total == 0 or (finished and errors > total / 2)
        jobs.append({
            "job": name, "task": task, "agent": agent, "model": model,
            "kind": kind, "trials": trials, "solved": solved, "done": done,
            "errors": errors, "total": total,
            "cost": round(sum(t["cost"] or 0 for t in trials), 2),
            "finished": finished, "void": void,
            "mtime": jdir.stat().st_mtime,
        })
    return jobs


def gate_from(jobs: list[dict], task: str, kind: str) -> dict | None:
    """Latest clean finished probe job for (task, kind)."""
    cands = [j for j in jobs if j["task"] == task and j["kind"] == kind
             and not j["void"] and j["total"] > 0]
    if not cands:
        return None
    cands.sort(key=lambda j: j["mtime"])
    running = [j for j in cands if not j["finished"]]
    pick = running[-1] if running else cands[-1]
    return {"job": pick["job"], "solved": pick["solved"], "total": pick["total"],
            "finished": pick["finished"]}


def verdict(task: str, ease: dict | None, diff: dict | None) -> str:
    if ease and ease["finished"]:
        if ease["solved"] > 1:
            return f"too easy — sonnet {ease['solved']}/{ease['total']}"
        if diff and diff["finished"]:
            if 1 <= diff["solved"] <= 4:
                return f"SUBMISSION READY — easiness {ease['solved']}/{ease['total']}, difficulty {diff['solved']}/{diff['total']}"
            if diff["solved"] == 0:
                return f"easiness passed {ease['solved']}/{ease['total']} — difficulty 0/{diff['total']} (unverifiable, iterating)"
            return f"difficulty too high pass rate {diff['solved']}/{diff['total']}"
        return f"easiness passed {ease['solved']}/{ease['total']} — difficulty pending"
    if ease and not ease["finished"]:
        return "easiness probe running"
    return "probes pending"


def scan_tasks(jobs: list[dict]) -> list[dict]:
    tasks = []
    for tdir in sorted(ROOT.iterdir()):
        if not tdir.is_dir() or tdir.name in ("jobs", "dashboard"):
            continue
        name = tdir.name
        rep = tdir / "SCAFFOLD_REPORT.json"
        entry = {"task": name, "state": "scaffolding", "f2p": None, "p2p": None,
                 "null_reward": None, "oracle_reward": None}
        if rep.exists():
            try:
                data = json.loads(rep.read_text())
                f2p = data.get("f2p") or data.get("fail_to_pass") or []
                p2p = data.get("p2p") or data.get("pass_to_pass") or []
                entry.update({
                    "state": "verified" if data.get("oracle_reward") == 1 and
                             data.get("null_reward") == 0 else "scaffolded",
                    "f2p": len(f2p), "p2p": len(p2p),
                    "null_reward": data.get("null_reward"),
                    "oracle_reward": data.get("oracle_reward"),
                })
            except (json.JSONDecodeError, OSError):
                pass
        elif (tdir / "tests" / "config.json").exists():
            entry["state"] = "scaffolded"
        if name == "ingestion-stale-blocker":
            entry.update({"state": "verified", "f2p": 9, "p2p": 8,
                          "null_reward": 0, "oracle_reward": 1})
        ease = gate_from(jobs, name, "easiness")
        diff = gate_from(jobs, name, "difficulty")
        entry["ease_gate"] = ease
        entry["diff_gate"] = diff
        entry["verdict"] = verdict(name, ease, diff)
        entry["note"] = TASK_NOTES.get(name, "")
        entry["spend"] = round(sum(j["cost"] for j in jobs if j["task"] == name), 2)
        tasks.append(entry)
    return tasks


def scan() -> dict:
    jobs = scan_jobs()
    tasks = scan_tasks(jobs)
    running = sum(1 for j in jobs for t in j["trials"] if t["state"] == "running")
    return {
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "jobs": jobs, "tasks": tasks,
        "summary": {
            "total_spend": round(sum(j["cost"] for j in jobs), 2),
            "trials_running": running,
            "candidates": sum(1 for t in tasks if "candidate" in t["note"] or "SUBMISSION" in t["verdict"]),
            "too_easy": sum(1 for t in tasks if t["verdict"].startswith("too easy")),
        },
    }


if __name__ == "__main__":
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(scan(), indent=1))
    tmp.replace(OUT)
