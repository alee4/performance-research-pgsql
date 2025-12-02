#!/usr/bin/env bash
set -e

VERSIONS=(11 12 13 14 15 16 17 18)

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
        continue
    fi
    
    docker exec $CONTAINER bash -c 'apt-get update -qq && apt-get install -y -qq sysbench' > /dev/null 2>&1
done
