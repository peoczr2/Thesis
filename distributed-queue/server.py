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
DEFAULT_SEEDS = list(range(1, 11))

# Edit this list before the first server start, or delete task_queue.json and
# restart the server after changing it. The default creates 15 x 10 = 150 tasks.
DEFAULT_INSTANCES = [
    "LR1_DR02_VC01_V6a",
    "LR1_DR02_VC02_V6a",
    "LR1_DR02_VC03_V7a",
    "LR1_DR02_VC03_V8a",
    "LR1_DR02_VC04_V8a",
    "LR1_DR02_VC05_V8a",
    "LR1_DR04_VC01_V12a",
    "LR1_DR04_VC02_V13a",
    "LR1_DR04_VC03_V14a",
    "LR1_DR04_VC04_V15a",
    "LR1_DR04_VC05_V17b",
    "LR1_DR08_VC01_V25a",
    "LR1_DR08_VC02_V30a",
    "LR1_DR08_VC03_V35a",
    "LR1_DR08_VC05_V40b",
]

app = FastAPI(title="Dynamic MIRP Task Queue", version="1.0.0")
lock = threading.Lock()


class CompleteTaskRequest(BaseModel):
    instance: str
    seed: int
    worker_id: str | None = None
    result_path: str | None = None
    status: str = "completed"
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
        for seed in DEFAULT_SEEDS:
            pending.append(
                {
                    "instance": instance,
                    "seed": seed,
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
    return {"Pending": pending, "In_Progress": [], "Completed": []}


def normalize_state(state: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    return {
        "Pending": list(state.get("Pending", [])),
        "In_Progress": list(state.get("In_Progress", [])),
        "Completed": list(state.get("Completed", [])),
    }


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


def task_key(task: dict[str, Any]) -> tuple[str, int]:
    return str(task["instance"]), int(task["seed"])


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
            "seed": task["seed"],
            "attempts": task["attempts"],
        }


@app.post("/complete_task")
def complete_task(payload: CompleteTaskRequest) -> dict[str, Any]:
    wanted = (payload.instance, payload.seed)

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
                return {"message": "completed", "instance": payload.instance, "seed": payload.seed}

        for task in state["Completed"]:
            if task_key(task) == wanted:
                return {"message": "already_completed", "instance": payload.instance, "seed": payload.seed}

        save_state(state)
        raise HTTPException(status_code=404, detail="Task not found in In_Progress")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
