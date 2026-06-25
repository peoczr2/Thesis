# Dynamic Pull Queue Smoke Test

This folder contains a small central coordinator and Julia worker client for running MIRP jobs across Windows lab machines.

The server owns the queue in `task_queue.json`. Workers repeatedly pull one task, run it, and post completion. If a worker disappears, any task left `In_Progress` for more than 4 hours is automatically returned to `Pending`.

## Files

- `server.py`: FastAPI queue server.
- `setup.jl`: Julia environment setup for workers.
- `worker.jl`: Julia pull-worker client with a dummy optimization workload.
- `task_queue.json`: created automatically by the server on first start.

## 1. Start The Python Server

Open a terminal on the coordinator machine:

```powershell
cd distributed-queue
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install fastapi uvicorn
python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

In another coordinator terminal, check queue status:

```powershell
curl http://127.0.0.1:8000/status
```

Expected first status:

```json
{"pending":150,"in_progress":0,"completed":0,"stale_reset":0}
```

## 2. Set Up Julia On Each Worker Machine

Open a terminal on each Windows lab machine:

```powershell
cd distributed-queue
julia --project=. setup.jl
```

## 3. Run Multiple Workers

Replace `COORDINATOR_IP` with the IP address or hostname of the server machine.

Terminal 1:

```powershell
cd distributed-queue
$env:QUEUE_SERVER="http://COORDINATOR_IP:8000"
$env:WORKER_ID="lab-worker-01"
julia --project=. worker.jl
```

Terminal 2:

```powershell
cd distributed-queue
$env:QUEUE_SERVER="http://COORDINATOR_IP:8000"
$env:WORKER_ID="lab-worker-02"
julia --project=. worker.jl
```

Terminal 3:

```powershell
cd distributed-queue
$env:QUEUE_SERVER="http://COORDINATOR_IP:8000"
$env:WORKER_ID="lab-worker-03"
julia --project=. worker.jl
```

You should see lines like:

```text
Starting C-BEAT optimization | Instance: LR1_DR02_VC01_V6a | Seed: 1
Completed LR1_DR02_VC01_V6a, seed=1
```

Meanwhile, refresh the server status:

```powershell
curl http://127.0.0.1:8000/status
```

The `pending` count should decrease and `completed` should increase until the queue is drained.

## 4. Pause And Resume

Stop workers with `Ctrl+C`. The server keeps state in `task_queue.json`.

To resume later:

```powershell
cd distributed-queue
.\.venv\Scripts\Activate.ps1
python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

Then restart any number of Julia workers. Tasks already completed will not be repeated.

## 5. Reset The Queue

To start over, stop the server and delete `task_queue.json`:

```powershell
Remove-Item task_queue.json
python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

## 6. Replacing The Dummy Workload

In `worker.jl`, replace `run_dummy_optimization` with the real call to your MIRP code. Keep the pull/complete protocol unchanged so the server can continue handling stragglers and restarts.
