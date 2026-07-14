#!/usr/bin/env python3
"""Parallel gate-probe chain for silver tasks.

queue2.txt: one task dir per line ('#' comments). Up to TASK_WORKERS tasks run
concurrently; within a task, stages are sequential and gated:
  nop (expect 0) -> oracle (expect 1) -> sonnet x5 (pass if <=1 solved)
  -> opus x10 (pass if 1..4 solved). Verdicts land in chain_state2.json.

Docker default-address-pools is expanded (512 nets), so trials run full-width:
sonnet n=5, opus n=10; 4 task workers ~= up to 40 concurrent trials.

Run from silver-tasks/:  nohup python3 probe_chain.py >> chain.log 2>&1 &
Idempotent: finished stages are reused on restart; edit queue2.txt live.
"""
import json, os, subprocess, time, glob, shutil, datetime, threading
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(ROOT, "chain_state2.json")
QUEUE = os.path.join(ROOT, "queue2.txt")
ENVF = os.path.join(ROOT, ".harbor_env")

TASK_WORKERS = int(os.environ.get("TASK_WORKERS", "4"))
SONNET = "anthropic/claude-sonnet-4-6"
OPUS = "anthropic/claude-opus-4-8"

STAGES = [
    ("nop",    ["-a", "nop"],                            1,  1, 30 * 60),
    ("oracle", ["-a", "oracle"],                         1,  1, 30 * 60),
    ("sonnet", ["-a", "mini-swe-agent", "-m", SONNET],   5,  5, 3 * 3600),
    ("opus",   ["-a", "mini-swe-agent", "-m", OPUS],    10, 10, 6 * 3600),
]

_lock = threading.Lock()


def log(msg):
    print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


def load_state():
    if os.path.exists(STATE):
        return json.load(open(STATE))
    return {}


def mutate_state(fn):
    with _lock:
        st = load_state()
        fn(st)
        tmp = STATE + ".tmp"
        json.dump(st, open(tmp, "w"), indent=1)
        os.replace(tmp, STATE)
        return st


def read_queue():
    if not os.path.exists(QUEUE):
        return []
    out = []
    for line in open(QUEUE):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def harbor_env():
    env = dict(os.environ)
    for line in open(ENVF):
        line = line.strip()
        if line.startswith("export "):
            k, v = line[len("export "):].split("=", 1)
            env[k] = v
    return env


def job_solved_counts(job_dir):
    rewards = []
    for f in glob.glob(os.path.join(job_dir, "*", "result.json")):
        try:
            d = json.load(open(f))
        except Exception:
            rewards.append(None)
            continue
        vr = d.get("verifier_result") or {}
        rewards.append((vr.get("rewards") or {}).get("reward"))
    solved = sum(1 for r in rewards if r is not None and r >= 1.0)
    errs = sum(1 for r in rewards if r is None)
    return solved, len(rewards), errs


def run_stage(task, stage_name, agent_flags, k, n, timeout):
    job_name = f"{task}--{stage_name}-c2"
    job_dir = os.path.join(ROOT, "jobs", job_name)
    if os.path.exists(job_dir):
        s, t, e = job_solved_counts(job_dir)
        if t >= k - e and t > 0:
            log(f"{task}/{stage_name}: reusing {job_dir} ({s}/{t})")
            return s, t, e
        shutil.rmtree(job_dir, ignore_errors=True)
    cmd = (["harbor", "run", "-p", task, "-o", "jobs", "--job-name", job_name,
            "-k", str(k), "-n", str(n), "-q", "-y"] + agent_flags)
    log(f"{task}/{stage_name}: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, cwd=ROOT, env=harbor_env(), timeout=timeout,
                       stdout=open(os.path.join(ROOT, f"jobs/{job_name}.out"), "w"),
                       stderr=subprocess.STDOUT)
    except subprocess.TimeoutExpired:
        log(f"{task}/{stage_name}: TIMEOUT after {timeout}s")
    subprocess.run(["docker", "network", "prune", "-f"], capture_output=True)
    return job_solved_counts(job_dir)


def verdict_for(entry):
    r = entry["stages"]
    if r.get("nop", {}).get("solved", 1) != 0:
        return "BROKEN:nop_nonzero"
    if r.get("oracle", {}).get("solved", 0) != 1:
        return "BROKEN:oracle_failed"
    s = r.get("sonnet", {})
    if s.get("errors", 0) > 1:
        return "RERUN:sonnet_errors"
    if s.get("solved", 99) > 1:
        return f"TOO_EASY:sonnet_{s.get('solved')}of{s.get('total')}"
    o = r.get("opus", {})
    if o.get("errors", 0) > 2:
        return "RERUN:opus_errors"
    solved = o.get("solved")
    if solved is None:
        return "PENDING"
    if solved == 0:
        return "TOO_HARD:opus_0of10"
    if solved > 4:
        return f"TOO_EASY:opus_{solved}of10"
    return f"PASS:sonnet_{s.get('solved')}of{s.get('total')}_opus_{solved}of{o.get('total')}"


def process_task(task):
    log(f"{task}: claimed")
    for stage_name, flags, k, n, tmo in STAGES:
        st = load_state()
        if stage_name in st.get(task, {}).get("stages", {}):
            continue
        solved, total, errs = run_stage(task, stage_name, flags, k, n, tmo)
        rec = {"solved": solved, "total": total, "errors": errs}
        mutate_state(lambda s: s.setdefault(task, {"stages": {}})["stages"].__setitem__(stage_name, rec))
        if stage_name == "nop" and solved != 0:
            break
        if stage_name == "oracle" and solved != 1:
            break
        if stage_name == "sonnet" and (solved > 1 or errs > 1):
            break

    def finish(s):
        e = s.setdefault(task, {"stages": {}})
        e["verdict"] = verdict_for(e)
        e["finished_at"] = datetime.datetime.now().isoformat()
        e.pop("claimed", None)
    st = mutate_state(finish)
    log(f"{task}: VERDICT {st[task]['verdict']}")


def main():
    log(f"parallel chain driver up: TASK_WORKERS={TASK_WORKERS}, sonnet n=5, opus n=10")
    with ThreadPoolExecutor(max_workers=TASK_WORKERS) as pool:
        inflight = {}
        while True:
            inflight = {t: f for t, f in inflight.items() if not f.done()}
            st = load_state()
            for task in read_queue():
                if task in inflight:
                    continue
                e = st.get(task, {})
                if str(e.get("verdict", "")).startswith(("PASS", "TOO_", "BROKEN")):
                    continue
                if not os.path.isdir(os.path.join(ROOT, task)):
                    continue
                if len(inflight) >= TASK_WORKERS:
                    break
                mutate_state(lambda s: s.setdefault(task, {"stages": {}}).__setitem__("claimed", True))
                inflight[task] = pool.submit(process_task, task)
            time.sleep(30)


if __name__ == "__main__":
    main()
