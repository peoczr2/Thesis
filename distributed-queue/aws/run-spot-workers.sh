#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper after your Launch Template has the AMI and user-data set.

LAUNCH_TEMPLATE_NAME="${LAUNCH_TEMPLATE_NAME:-julia-worker-template}"
LAUNCH_TEMPLATE_VERSION="${LAUNCH_TEMPLATE_VERSION:-1}"
COUNT="${COUNT:-40}"

aws ec2 run-instances \
    --launch-template "LaunchTemplateName=${LAUNCH_TEMPLATE_NAME},Version=${LAUNCH_TEMPLATE_VERSION}" \
    --count "${COUNT}" \
    --instance-market-options '{"MarketType":"spot"}'
