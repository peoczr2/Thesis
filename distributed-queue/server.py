from __future__ import annotations

import json
import os
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

QUEUE_FILE = Path(os.environ.get("QUEUE_FILE", "task_queue.json"))
STALE_HOURS = float(os.environ.get("STALE_HOURS", "4"))
MAX_TASK_ATTEMPTS = int(os.environ.get("MAX_TASK_ATTEMPTS", "3"))
DEFAULT_SEEDS = list(range(1, 2))
DEFAULT_HORIZONS = [120]
DEFAULT_SCORERS = ["gra"]
""", 180, 360"""
# Edit this list before the first server start, or delete task_queue.json and
# restart the server after changing it. The default creates
# len(instances) x 3 horizons x 10 seeds x 1 scorer tasks.
DEFAULT_INSTANCES = [
    "LR1_DR02_VC01_V6a",
    "LR1_DR02_VC02_V6a",
    "LR1_DR02_VC03_V7a",
    "LR1_DR02_VC03_V8a",
    "LR1_DR02_VC04_V8a",

]
"""
    "LR1_DR02_VC05_V8a",
    "LR1_DR03_VC03_V10b",
    "LR1_DR03_VC03_V13b",
    "LR1_DR03_VC03_V16a",
    "LR1_DR04_VC03_V15a",
    "LR1_DR04_VC03_V15b",
    "LR1_DR04_VC05_V17a",
    "LR1_DR04_VC05_V17b",
    "LR1_DR05_VC05_V25a",
    "LR1_DR05_VC05_V25b",
"""

app = FastAPI(title="Dynamic MIRP Task Queue", version="1.0.0")
lock = threading.Lock()


class CompleteTaskRequest(BaseModel):
    instance: str
    horizon: int
    seed: int
    scorer: str = "gra"
    worker_id: str | None = None
    result_path: str | None = None
    status: str = "completed"
    runtime_seconds: float | None = None


class FailTaskRequest(BaseModel):
    instance: str
    horizon: int
    seed: int
    scorer: str = "gra"
    worker_id: str | None = None
    error_message: str | None = None
    runtime_seconds: float | None = None


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def make_initial_state() -> dict[str, list[dict[str, Any]]]:
    pending: list[dict[str, Any]] = []
    for instance in DEFAULT_INSTANCES:
        for horizon in DEFAULT_HORIZONS:
            for scorer in DEFAULT_SCORERS:
                for seed in DEFAULT_SEEDS:
                    pending.append(
                        {
                            "instance": instance,
                            "horizon": horizon,
                            "seed": seed,
                            "scorer": scorer,
                            "state": "Pending",
                            "attempts": 0,
                            "created_at": now_iso(),
                            "started_at": None,
                            "completed_at": None,
                            "worker_id": None,
                            "result_path": None,
                            "runtime_seconds": None,
                        }
                    )
    return {"Pending": pending, "In_Progress": [], "Completed": [], "Failed": []}


def normalize_state(state: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    normalized = {
        "Pending": list(state.get("Pending", [])),
        "In_Progress": list(state.get("In_Progress", [])),
        "Completed": list(state.get("Completed", [])),
        "Failed": list(state.get("Failed", [])),
    }
    for bucket, tasks in normalized.items():
        for task in tasks:
            if "horizon" not in task:
                raise ValueError(
                    f"Existing {QUEUE_FILE} has old-format task in {bucket}. "
                    "Delete it before starting the multi-horizon queue."
                )
            task.setdefault("scorer", "gra")
    return normalized


def load_state() -> dict[str, list[dict[str, Any]]]:
    if not QUEUE_FILE.exists():
        state = make_initial_state()
        save_state(state)
        return state
    with QUEUE_FILE.open("r", encoding="utf-8") as handle:
        return normalize_state(json.load(handle))


def save_state(state: dict[str, list[dict[str, Any]]]) -> None:
    tmp_file = QUEUE_FILE.with_suffix(QUEUE_FILE.suffix + ".tmp")
    with tmp_file.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
    tmp_file.replace(QUEUE_FILE)


def task_key(task: dict[str, Any]) -> tuple[str, int, int, str]:
    return (
        str(task["instance"]),
        int(task["horizon"]),
        int(task["seed"]),
        str(task.get("scorer", "gra")),
    )


def reset_stale_tasks(state: dict[str, list[dict[str, Any]]]) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_HOURS)
    still_running: list[dict[str, Any]] = []
    reset_count = 0

    for task in state["In_Progress"]:
        started_at = parse_time(task.get("started_at"))
        if started_at is not None and started_at < cutoff:
            task["state"] = "Pending"
            task["started_at"] = None
            task["worker_id"] = None
            state["Pending"].append(task)
            reset_count += 1
        else:
            still_running.append(task)

    state["In_Progress"] = still_running
    return reset_count


@app.on_event("startup")
def startup() -> None:
    with lock:
        state = load_state()
        reset_stale_tasks(state)
        save_state(state)


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "MIRP dynamic queue server is running"}


@app.get("/status")
def status() -> dict[str, int]:
    with lock:
        state = load_state()
        reset_count = reset_stale_tasks(state)
        save_state(state)
        return {
            "pending": len(state["Pending"]),
            "in_progress": len(state["In_Progress"]),
            "completed": len(state["Completed"]),
            "failed": len(state["Failed"]),
            "stale_reset": reset_count,
        }


@app.get("/get_task")
def get_task(worker_id: str | None = None) -> dict[str, Any]:
    with lock:
        state = load_state()
        reset_stale_tasks(state)

        if not state["Pending"]:
            save_state(state)
            return {"message": "done"}

        task = state["Pending"].pop(0)
        task["state"] = "In_Progress"
        task["attempts"] = int(task.get("attempts", 0)) + 1
        task["started_at"] = now_iso()
        task["worker_id"] = worker_id
        state["In_Progress"].append(task)
        save_state(state)

        return {
            "instance": task["instance"],
            "horizon": task["horizon"],
            "seed": task["seed"],
            "scorer": task.get("scorer", "gra"),
            "attempts": task["attempts"],
        }


@app.post("/complete_task")
def complete_task(payload: CompleteTaskRequest) -> dict[str, Any]:
    wanted = (payload.instance, payload.horizon, payload.seed, payload.scorer)

    with lock:
        state = load_state()
        reset_stale_tasks(state)

        for index, task in enumerate(state["In_Progress"]):
            if task_key(task) == wanted:
                completed = state["In_Progress"].pop(index)
                completed["state"] = "Completed"
                completed["completed_at"] = now_iso()
                completed["worker_id"] = payload.worker_id or completed.get("worker_id")
                completed["result_path"] = payload.result_path
                completed["runtime_seconds"] = payload.runtime_seconds
                completed["completion_status"] = payload.status
                state["Completed"].append(completed)
                save_state(state)
                return {
                    "message": "completed",
                    "instance": payload.instance,
                    "horizon": payload.horizon,
                    "seed": payload.seed,
                    "scorer": payload.scorer,
                }

        for task in state["Completed"]:
            if task_key(task) == wanted:
                return {
                    "message": "already_completed",
                    "instance": payload.instance,
                    "horizon": payload.horizon,
                    "seed": payload.seed,
                    "scorer": payload.scorer,
                }

        save_state(state)
        raise HTTPException(status_code=404, detail="Task not found in In_Progress")


@app.post("/fail_task")
def fail_task(payload: FailTaskRequest) -> dict[str, Any]:
    wanted = (payload.instance, payload.horizon, payload.seed, payload.scorer)

    with lock:
        state = load_state()
        reset_stale_tasks(state)

        for index, task in enumerate(state["In_Progress"]):
            if task_key(task) == wanted:
                failed = state["In_Progress"].pop(index)
                failed["worker_id"] = payload.worker_id or failed.get("worker_id")
                failed["failed_at"] = now_iso()
                failed["last_error"] = payload.error_message
                failed["runtime_seconds"] = payload.runtime_seconds

                attempts = int(failed.get("attempts", 0))
                if attempts < MAX_TASK_ATTEMPTS:
                    failed["state"] = "Pending"
                    failed["started_at"] = None
                    state["Pending"].append(failed)
                    message = "requeued"
                else:
                    failed["state"] = "Failed"
                    state["Failed"].append(failed)
                    message = "failed"

                save_state(state)
                return {
                    "message": message,
                    "instance": payload.instance,
                    "horizon": payload.horizon,
                    "seed": payload.seed,
                    "scorer": payload.scorer,
                    "attempts": attempts,
                    "max_attempts": MAX_TASK_ATTEMPTS,
                }

        for task in state["Completed"]:
            if task_key(task) == wanted:
                return {
                    "message": "already_completed",
                    "instance": payload.instance,
                    "horizon": payload.horizon,
                    "seed": payload.seed,
                    "scorer": payload.scorer,
                }

        save_state(state)
        raise HTTPException(status_code=404, detail="Task not found in In_Progress")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
