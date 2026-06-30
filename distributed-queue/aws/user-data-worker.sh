#!/usr/bin/env bash
set -euo pipefail

# Paste this into EC2 Launch Template > Advanced details > User data.
# This uses git at launch: install git if missing, pull latest code, run workers.

QUEUE_SERVER="${QUEUE_SERVER:-https://2488-2001-4c4c-1921-f700-91d5-3307-bb54-70e0.ngrok-free.app}"
REPO_URL="${REPO_URL:-https://github.com/peoczr2/Thesis.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
APP_DIR="${APP_DIR:-/home/ubuntu/app}"
APP_USER="${APP_USER:-ubuntu}"
WORKERS_PER_INSTANCE="${WORKERS_PER_INSTANCE:-1}"
SHUTDOWN_ON_SUCCESS="${SHUTDOWN_ON_SUCCESS:-false}"
SHUTDOWN_ON_FAILURE="${SHUTDOWN_ON_FAILURE:-false}"

# Manual AMI tests often run this script from inside APP_DIR. Because the script
# git-resets APP_DIR, re-exec from /tmp first so bash is not reading a file that
# gets overwritten halfway through execution.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
APP_DIR_ABS="$(readlink -m "${APP_DIR}")"
if [[ "${MIRP_WORKER_SCRIPT_REEXEC:-0}" != "1" && "${SCRIPT_PATH}" == "${APP_DIR_ABS}"/* ]]; then
    TMP_SCRIPT="$(mktemp /tmp/mirp-user-data-worker.XXXXXX.sh)"
    cp "${SCRIPT_PATH}" "${TMP_SCRIPT}"
    chmod +x "${TMP_SCRIPT}"
    export MIRP_WORKER_SCRIPT_REEXEC=1
    exec "${TMP_SCRIPT}" "$@"
fi

if [[ "${EUID}" -eq 0 ]]; then
    LOG_FILE="${LOG_FILE:-/var/log/mirp-worker.log}"
    SUDO=()
    exec > >(tee -a "${LOG_FILE}" | logger -t mirp-worker) 2>&1
else
    LOG_FILE="${LOG_FILE:-${HOME}/mirp-worker.log}"
    SUDO=(sudo)
    exec > >(tee -a "${LOG_FILE}") 2>&1
    echo "[$(date --iso-8601=seconds)] Running outside EC2 user-data as $(id -un); using sudo for root actions"
fi

if [[ "${QUEUE_SERVER}" == *"YOUR-NGROK-URL"* ]] || [[ "${REPO_URL}" == *"yourusername"* ]]; then
    echo "Edit QUEUE_SERVER and REPO_URL in user-data-worker.sh before launching AWS workers."
    exit 2
fi

echo "[$(date --iso-8601=seconds)] Starting MIRP worker bootstrap"
echo "Queue server: ${QUEUE_SERVER}"
echo "Repository: ${REPO_URL} (${REPO_BRANCH})"
echo "App user: ${APP_USER}"
echo "Shutdown on success: ${SHUTDOWN_ON_SUCCESS}"
echo "Shutdown on failure: ${SHUTDOWN_ON_FAILURE}"

if ! command -v git >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y ca-certificates git
fi

"${SUDO[@]}" install -d -o "${APP_USER}" -g "${APP_USER}" "$(dirname "${APP_DIR}")"
"${SUDO[@]}" install -d -o "${APP_USER}" -g "${APP_USER}" "${RESULTS_DIR}"

if [ ! -d "${APP_DIR}/.git" ]; then
    "${SUDO[@]}" rm -rf "${APP_DIR}"
    sudo -H -u "${APP_USER}" git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${APP_DIR}"
else
    "${SUDO[@]}" chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
    sudo -H -u "${APP_USER}" git -C "${APP_DIR}" remote set-url origin "${REPO_URL}"
    sudo -H -u "${APP_USER}" git -C "${APP_DIR}" fetch origin "${REPO_BRANCH}"
    sudo -H -u "${APP_USER}" git -C "${APP_DIR}" reset --hard "origin/${REPO_BRANCH}"
fi

cd "${APP_DIR}/distributed-queue"
sudo -H -u "${APP_USER}" julia --project=. setup.jl

pids=()
for worker_index in $(seq 1 "${WORKERS_PER_INSTANCE}"); do
    worker_id="$(hostname)-${worker_index}"
    sudo -H -u "${APP_USER}" env \
        QUEUE_SERVER="${QUEUE_SERVER}" \
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

if [[ "${status}" == "0" && "${SHUTDOWN_ON_SUCCESS}" == "true" ]]; then
    echo "[$(date --iso-8601=seconds)] Shutting down after successful worker run"
    "${SUDO[@]}" shutdown -h now
elif [[ "${status}" != "0" && "${SHUTDOWN_ON_FAILURE}" == "true" ]]; then
    echo "[$(date --iso-8601=seconds)] Shutting down after failed worker run"
    "${SUDO[@]}" shutdown -h now
else
    echo "[$(date --iso-8601=seconds)] Leaving instance running for inspection"
    echo "Inspect logs with: tail -200 ${LOG_FILE}"
fi
