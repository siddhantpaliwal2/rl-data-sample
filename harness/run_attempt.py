#!/usr/bin/env python
"""Run one mini-swe-agent attempt against a task image, then grade it.

Usage:
    python harness/run_attempt.py <task-name> <attempt-no> <results-dir>

Prerequisites (see root README.md):
  - the task image is built:  docker build -t <task-name> tasks/<task-name>/environment
  - ANTHROPIC_API_KEY is exported
  - mini-swe-agent is installed:  uv tool install mini-swe-agent
    (plus `uv pip install --python $(uv tool dir)/mini-swe-agent/bin/python fastapi orjson`
     to satisfy litellm's lazy imports)

The attempt runs in a fresh container from the task image with the canonical
mini-swe-agent SWE-bench configuration (swebench.yaml: 250-step limit, $3 cost
cap). After the agent submits, the hidden verifier (tasks/<task>/tests/test.sh)
is copied into the same container and grades the working tree; reward 1 means
every fail_to_pass and pass_to_pass test passed.
"""
import json
import pathlib
import subprocess
import sys

import yaml

from minisweagent.agents.default import DefaultAgent
from minisweagent.config import builtin_config_dir
from minisweagent.environments.docker import DockerEnvironment
from minisweagent.models import get_model

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
TASKS = REPO_ROOT / "tasks"
import os

# difficulty probe by default; set PROBE_MODEL=anthropic/claude-sonnet-4-6 for the easiness probe
MODEL_NAME = os.environ.get("PROBE_MODEL", "anthropic/claude-opus-4-8")

task, attempt, out_dir = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
out_dir.mkdir(parents=True, exist_ok=True)

cfg = yaml.safe_load((builtin_config_dir / "benchmarks" / "swebench.yaml").read_text())
env_cfg = {**cfg["environment"]}
env_cfg.pop("environment_class", None)
env_cfg.update(image=task, cwd="/app")

model = get_model(config={**cfg["model"], "model_name": MODEL_NAME, "set_cache_control": "default_end"})
env = DockerEnvironment(**env_cfg)
agent = DefaultAgent(model, env, **{**cfg["agent"], "wall_time_limit_seconds": 1800,
                                    "output_path": out_dir / f"{task}-a{attempt}.traj.json"})

instruction = (TASKS / task / "instruction.md").read_text()
try:
    exit_status = agent.run(instruction).get("exit_status", "?")
except Exception as e:  # noqa: BLE001
    exit_status = f"error:{type(e).__name__}:{e}"

reward, required = None, None
try:
    cid = env.container_id
    subprocess.run(["docker", "cp", str(TASKS / task / "tests"), f"{cid}:/grade-vt"],
                   check=True, capture_output=True, timeout=120)
    g = subprocess.run(["docker", "exec", cid, "sh", "/grade-vt/test.sh"],
                       capture_output=True, text=True, timeout=900)
    for line in g.stdout.splitlines():
        if line.startswith("required passed:"):
            required = line.split(":", 1)[1].strip()
        if line.startswith("reward:"):
            reward = int(line.split(":", 1)[1].strip())
except Exception as e:  # noqa: BLE001
    exit_status += f" | grade-error:{e}"
finally:
    env.cleanup()

result = {"task": task, "attempt": int(attempt), "model": MODEL_NAME,
          "exit_status": exit_status, "reward": reward, "required": required,
          "cost_usd": round(agent.cost, 4), "model_calls": agent.n_calls}
(out_dir / f"{task}-a{attempt}.json").write_text(json.dumps(result))
print(json.dumps(result))
