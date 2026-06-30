#!/usr/bin/env bash
set -euo pipefail

# Run this once on a temporary Ubuntu EC2 instance, then create an AMI from it.
# It installs Julia and precompiles the distributed queue worker environment.

JULIA_VERSION="${JULIA_VERSION:-1.10.4}"
REPO_URL="${REPO_URL:-https://github.com/yourusername/beam_search_thesis.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
APP_DIR="${APP_DIR:-/home/ubuntu/app}"
APP_USER="${APP_USER:-ubuntu}"

sudo apt-get update
sudo apt-get install -y ca-certificates curl git tar gzip awscli patchelf

if ! command -v julia >/dev/null 2>&1; then
    curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
        -o "/tmp/julia-${JULIA_VERSION}-linux-x86_64.tar.gz"
    sudo tar -xzf "/tmp/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" -C /usr/local --strip-components=1
fi

fix_julia_execstack() {
    local openlibm="/usr/local/lib/julia/libopenlibm.so"
    if [ -f "${openlibm}" ]; then
        sudo patchelf --clear-execstack "${openlibm}"
    fi
}

fix_julia_execstack

run_as_app_user() {
    sudo -H -u "${APP_USER}" "$@"
}

sudo mkdir -p "$(dirname "${APP_DIR}")"
sudo chown "${APP_USER}:${APP_USER}" "$(dirname "${APP_DIR}")"

if [ ! -d "${APP_DIR}/.git" ]; then
    sudo rm -rf "${APP_DIR}"
    run_as_app_user git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${APP_DIR}"
else
    sudo chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
    run_as_app_user git -C "${APP_DIR}" remote set-url origin "${REPO_URL}"
    run_as_app_user git -C "${APP_DIR}" fetch origin "${REPO_BRANCH}"
    run_as_app_user git -C "${APP_DIR}" reset --hard "origin/${REPO_BRANCH}"
fi

cd "${APP_DIR}/distributed-queue"
run_as_app_user julia --project=. setup.jl
run_as_app_user julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

echo "Base AMI is ready. Create an AMI from this EC2 instance now."
