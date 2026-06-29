#!/usr/bin/env bash
set -euo pipefail

# Paste this into EC2 Launch Template > Advanced details > User data.
# This uses git at launch: install git if missing, pull latest code, run workers.

QUEUE_SERVER="${QUEUE_SERVER:-https://YOUR-NGROK-URL.ngrok-free.app}"
REPO_URL="${REPO_URL:-https://github.com/yourusername/beam_search_thesis.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
APP_DIR="${APP_DIR:-/home/ubuntu/app}"
APP_USER="${APP_USER:-ubuntu}"
WORKERS_PER_INSTANCE="${WORKERS_PER_INSTANCE:-1}"
RESULTS_DIR="${RESULTS_DIR:-/home/ubuntu/results/distributed_queue}"

exec > >(tee -a /var/log/mirp-worker.log | logger -t mirp-worker -s 2>/dev/console) 2>&1

if [[ "${QUEUE_SERVER}" == *"YOUR-NGROK-URL"* ]] || [[ "${REPO_URL}" == *"yourusername"* ]]; then
    echo "Edit QUEUE_SERVER and REPO_URL in user-data-worker.sh before launching AWS workers."
    exit 2
fi

echo "[$(date --iso-8601=seconds)] Starting MIRP worker bootstrap"
echo "Queue server: ${QUEUE_SERVER}"
echo "Repository: ${REPO_URL} (${REPO_BRANCH})"
echo "App user: ${APP_USER}"

if ! command -v git >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates git
fi

install -d -o "${APP_USER}" -g "${APP_USER}" "$(dirname "${APP_DIR}")"
install -d -o "${APP_USER}" -g "${APP_USER}" "${RESULTS_DIR}"

if [ ! -d "${APP_DIR}/.git" ]; then
    rm -rf "${APP_DIR}"
    sudo -u "${APP_USER}" git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${APP_DIR}"
else
    chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
    sudo -u "${APP_USER}" git -C "${APP_DIR}" remote set-url origin "${REPO_URL}"
    sudo -u "${APP_USER}" git -C "${APP_DIR}" fetch origin "${REPO_BRANCH}"
    sudo -u "${APP_USER}" git -C "${APP_DIR}" reset --hard "origin/${REPO_BRANCH}"
fi

cd "${APP_DIR}/distributed-queue"
sudo -u "${APP_USER}" julia --project=. -e 'using Pkg; Pkg.instantiate()'

pids=()
for worker_index in $(seq 1 "${WORKERS_PER_INSTANCE}"); do
    worker_id="$(hostname)-${worker_index}"
    sudo -u "${APP_USER}" env \
        QUEUE_SERVER="${QUEUE_SERVER}" \
        QUEUE_RESULTS_DIR="${RESULTS_DIR}" \
        WORKER_ID="${worker_id}" \
        julia --project=. worker.jl &
    pids+=("$!")
done

status=0
for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
        status=1
    fi
done

echo "[$(date --iso-8601=seconds)] Worker processes finished with status ${status}"
sudo shutdown -h now
