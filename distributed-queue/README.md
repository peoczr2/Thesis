# Dynamic Pull Queue Smoke Test

This folder contains a small central coordinator and Julia worker client for running MIRP jobs across Windows lab machines.

The server owns the queue in `task_queue.json`. Workers repeatedly pull one task, run it, and post completion. If a worker disappears, any task left `In_Progress` for more than 4 hours is automatically returned to `Pending`.

## Files

- `server.py`: FastAPI queue server.
- `setup.jl`: Julia environment setup for workers.
- `worker.jl`: Julia pull-worker client with a dummy optimization workload.
- `task_queue.json`: created automatically by the server on first start.

## 1. Start The Python Server

On the remote Linux server:

```bash
cd /path/to/beam_search_thesis/distributed-queue
uv run --with fastapi --with uvicorn python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

In another terminal on the same remote server, start ngrok:

```bash
ngrok http 8000
```

Copy the public `https://...ngrok-free.app` forwarding URL. Workers on the university PCs will use that URL as `QUEUE_SERVER`; they do not need to be on the same network as the server.

Check queue status from the remote server:

```bash
curl http://127.0.0.1:8000/status
```

Or check it through ngrok from any machine:

```bash
curl https://YOUR-NGROK-URL.ngrok-free.app/status
```

Expected first status with the default `server.py` batch is 450 pending tasks: 15 instances x 3 horizons x 10 seeds x `gra`.

```json
{"pending":450,"in_progress":0,"completed":0,"stale_reset":0}
```

## 2. Set Up Julia On Each Worker Machine

Open a terminal on each Windows lab machine:

```powershell
cd distributed-queue
julia --project=. setup.jl
```

## 3. Run Multiple Workers

Replace `YOUR-NGROK-URL.ngrok-free.app` with the public forwarding host from `ngrok http 8000`.

Terminal 1:

```powershell
cd distributed-queue
$env:QUEUE_SERVER="https://YOUR-NGROK-URL.ngrok-free.app"
$env:WORKER_ID="lab-worker-01"
julia --project=. worker.jl
```

Terminal 2:

```powershell
cd distributed-queue
$env:QUEUE_SERVER="https://YOUR-NGROK-URL.ngrok-free.app"
$env:WORKER_ID="lab-worker-02"
julia --project=. worker.jl
```

Terminal 3:

```powershell
cd distributed-queue
$env:QUEUE_SERVER="https://YOUR-NGROK-URL.ngrok-free.app"
$env:WORKER_ID="lab-worker-03"
julia --project=. worker.jl
```

You should see lines like:

```text
Starting BS-ILS | Instance: LR1_DR02_VC01_V6a | Horizon: 120 | Seed: 1 | Scorer: gra
Completed LR1_DR02_VC01_V6a, horizon=120, seed=1, scorer=gra
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
uv run --with fastapi --with uvicorn python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

Then restart any number of Julia workers. Tasks already completed will not be repeated.

## 5. Reset The Queue

To start over, stop the server and delete `task_queue.json`:

```powershell
Remove-Item task_queue.json
uv run --with fastapi --with uvicorn python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

## 6. Replacing The Dummy Workload

The worker already calls `run_instance(Symbol(instance), horizon, seed; scorer = Symbol(scorer))` from `replication_runner.jl`. To change the experiment grid, edit these values in `server.py` before creating `task_queue.json`:

- `DEFAULT_INSTANCES`
- `DEFAULT_HORIZONS`
- `DEFAULT_SEEDS`
- `DEFAULT_SCORERS`

If `task_queue.json` already exists, the server resumes that saved queue. Delete it before restart when you want a freshly generated queue from the updated defaults.
