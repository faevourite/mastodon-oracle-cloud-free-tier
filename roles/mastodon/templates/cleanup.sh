#!/usr/bin/env bash

set -eou pipefail

cd "{{ root }}"

echo "starting media removal"
docker-compose exec -T web tootctl media remove --days 1 --prune-profiles
echo "done media removal"

echo "starting orphans cleanup"
docker-compose exec -T web tootctl media remove-orphans
echo "done orphans cleanup"
