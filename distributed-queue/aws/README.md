# AWS Hybrid AMI Workers

Use this folder for the AWS version of the distributed queue. The Python server still runs on your remote Linux server and is exposed through ngrok. AWS Spot instances run Julia workers.

The launch flow uses git. The AMI carries Julia and precompiled packages; at boot each worker installs git if needed, pulls the latest repo code, skips expensive package compilation, and starts `distributed-queue/worker.jl`.

## Experiment Grid

The queue is configured in `../server.py`:

- `DEFAULT_INSTANCES`: the MIRP instances
- `DEFAULT_HORIZONS`: `[120, 180, 360]`
- `DEFAULT_SEEDS`: `1:10`
- `DEFAULT_SCORERS`: `["gra"]`

With the current defaults, a fresh queue creates 450 tasks: 15 instances x 3 horizons x 10 seeds x `gra`.

If `../task_queue.json` already exists, the server resumes that saved queue. Delete it before starting the server when you want a fresh AWS run from the updated defaults.

## 1. Start The Queue Server

On your remote Linux server:

```bash
cd /path/to/beam_search_thesis/distributed-queue
uv run --with fastapi --with uvicorn python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

In another terminal on the same server:

```bash
ngrok http 8000
```

Check the queue:

```bash
curl https://YOUR-NGROK-URL.ngrok-free.app/status
```

## 2. Build The Base AMI Once

Launch one temporary Ubuntu EC2 instance, for example `c6a.large`, SSH into it, and run. Prefer Ubuntu 24.04 LTS; newer Ubuntu images can require the `patchelf` fix that `prepare-base-ami.sh` now applies automatically:

```bash
sudo apt-get update
sudo apt-get install -y git

git clone https://github.com/peoczr2/Thesis.git /home/ubuntu/app
cd /home/ubuntu/app/distributed-queue/aws
REPO_URL=https://github.com/peoczr2/Thesis.git ./prepare-base-ami.sh
```

Then create an AMI from that instance in the AWS Console and name it something like `julia-mirp-precompiled-base`.

This AMI contains:

- Ubuntu packages needed by the worker
- git
- Julia 1.11 by default, because `MIRPLib` is incompatible with Julia 1.10
- a patched Julia `libopenlibm.so` executable-stack flag for newer Ubuntu images
- the `distributed-queue` Julia environment
- precompiled Julia packages under `/home/ubuntu/.julia`

## 3. Create The Launch Template

Create an EC2 Launch Template using the AMI from step 2.

Recommended settings:

- Instance type: start with `c6a.large`
- Market: Spot
- Storage: enough for repo, packages, and logs, usually 16-32 GB
- IAM role: not required for the queue itself
- Security group: outbound HTTPS allowed

Paste `user-data-worker.sh` into Advanced details > User data, and edit these values at the top:

```bash
QUEUE_SERVER="https://YOUR-NGROK-URL.ngrok-free.app"
REPO_URL="https://github.com/yourusername/beam_search_thesis.git"
REPO_BRANCH="main"
APP_USER="ubuntu"
WORKERS_PER_INSTANCE="1"
```

The user-data script installs `git` if it is missing, then runs:

```bash
git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
# or, if already cloned:
git -C "$APP_DIR" fetch origin "$REPO_BRANCH"
git -C "$APP_DIR" reset --hard "origin/$REPO_BRANCH"
```

Keep `APP_USER="ubuntu"` if you built the AMI as the default Ubuntu user. The scripts use `sudo -H -u ubuntu` for git and Julia, so `$HOME` is `/home/ubuntu` and packages/precompile caches land in `/home/ubuntu/.julia`, not `/root/.julia`.

Use `WORKERS_PER_INSTANCE=1` unless you know one machine can run multiple optimization jobs without slowing each other down.

## User Context And Auto-Start Notes

The `~/.julia` user-context issue is real. Do not run Julia package setup as root. `prepare-base-ami.sh` and `user-data-worker.sh` force git and Julia through `sudo -H -u "$APP_USER"` to keep the Julia depot under `/home/ubuntu/.julia`.

The ghost-worker issue is solved by the Launch Template user-data: every new instance runs `user-data-worker.sh` at boot, starts the worker, and shuts down when the queue is drained. A systemd service is only needed if you want the AMI to auto-run workers without Launch Template user-data.

## 4. Launch The Spot Fleet

From any machine with AWS CLI configured:

```bash
cd distributed-queue/aws
LAUNCH_TEMPLATE_NAME=julia-worker-template COUNT=40 ./run-spot-workers.sh
```

The instances will boot, pull latest GitHub code, run `distributed-queue/worker.jl`, drain tasks from your ngrok queue, and shut themselves down when no tasks remain.

## 5. Iterate

For code changes that do not alter Julia dependencies:

```bash
git add .
git commit -m "Tune optimization heuristic"
git push origin main
```

Then launch another batch of Spot workers. They will reuse the precompiled environment from the AMI and pull only your updated scripts through git.

If you add Julia packages, rebuild the AMI by rerunning `prepare-base-ami.sh` on a temporary instance and creating a new AMI. `MIRPLib` requires a newer Julia than 1.10, so leave the script default at Julia 1.11 unless the package compat changes.

## Logs

On an EC2 worker:

```bash
sudo tail -f /var/log/mirp-worker.log
```

The queue server status remains the source of truth:

```bash
curl https://YOUR-NGROK-URL.ngrok-free.app/status
```
