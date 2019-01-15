#!/usr/bin/env bash

set -e

eval "$(jq -r '@sh "HOST=\(.host)"')"

MANAGER=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$HOST docker swarm join-token manager -q)
WORKER=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$HOST docker swarm join-token worker -q)

jq -n --arg manager "$MANAGER" --arg worker "$WORKER" '{"manager":$manager,"worker":$worker}'