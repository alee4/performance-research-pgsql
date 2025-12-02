#!/usr/bin/env bash
set -e

VERSIONS=(13.0 13.1 13.2 13.3 13.4 13.5)

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    docker rm -f $CONTAINER > /dev/null 2>&1 || true
    
    echo "Starting PostgreSQL $version..."
    docker run -d \
        --name $CONTAINER \
        -e POSTGRES_PASSWORD=test \
        --tmpfs /dev/shm:rw,size=2g \
        --shm-size=2g \
        --memory=3g \
        postgres:$version \
        -c shared_buffers=1GB \
        -c fsync=off \
        -c synchronous_commit=off \
        -c autovacuum=off \
        -c jit=off \
        > /dev/null
    
    for i in {1..30}; do
        docker exec $CONTAINER pg_isready > /dev/null 2>&1 && break
        sleep 1
    done
    
    echo "  Installing sysbench..."
    docker exec $CONTAINER bash -c 'apt-get update -qq && apt-get install -y -qq sysbench' > /dev/null 2>&1
    
    echo "  Ready"
done

echo ""
docker ps --format "table {{.Names}}\t{{.Status}}"
