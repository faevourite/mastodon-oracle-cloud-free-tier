#!/usr/bin/env bash

set -eou pipefail

cd "{{ root }}"

echo "starting statuses cleanup"
docker-compose exec -T web tootctl statuses remove --days 90

echo "starting accounts cleanup"
docker-compose exec -T web tootctl accounts prune

echo "starting media cleanup"
docker-compose exec -T web tootctl media remove --days 1

echo "starting profiles cleanup"
docker-compose exec -T web tootctl media remove --days 1 --prune-profiles

echo "starting headers cleanup"
docker-compose exec -T web tootctl media remove --days 1 --remove-headers

echo "starting orphans cleanup"
docker-compose exec -T web tootctl media remove-orphans

echo "starting emoji cleanup"
docker-compose exec -T web tootctl emoji purge --remote-only


echo "done"
