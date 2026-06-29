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
sudo apt-get install -y ca-certificates curl git tar gzip awscli

if ! command -v julia >/dev/null 2>&1; then
    curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
        -o "/tmp/julia-${JULIA_VERSION}-linux-x86_64.tar.gz"
    sudo tar -xzf "/tmp/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" -C /usr/local --strip-components=1
fi

sudo mkdir -p "${APP_DIR}"
sudo chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"

if [ ! -d "${APP_DIR}/.git" ]; then
    git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${APP_DIR}"
else
    git -C "${APP_DIR}" fetch origin "${REPO_BRANCH}"
    git -C "${APP_DIR}" reset --hard "origin/${REPO_BRANCH}"
fi

cd "${APP_DIR}/distributed-queue"
julia --project=. setup.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

echo "Base AMI is ready. Create an AMI from this EC2 instance now."
