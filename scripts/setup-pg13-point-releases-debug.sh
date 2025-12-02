#!/usr/bin/env bash
set -e

VERSIONS=(13.0 13.1 13.2 13.3 13.4 13.5)

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    echo "========================================="
    echo "Processing: $version"
    echo "========================================="
    
    docker rm -f $CONTAINER > /dev/null 2>&1 || true
    echo "  Removed old container"
    
    echo "  Starting container..."
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
        -c jit=off
    
    echo "  Waiting for PostgreSQL..."
    
    for i in {1..30}; do
        if docker exec $CONTAINER pg_isready > /dev/null 2>&1; then
            echo "  PostgreSQL ready"
            break
        fi
        sleep 1
    done
    
    echo "  Installing sysbench (takes 1-2 min)..."
    docker exec $CONTAINER bash -c 'apt-get update -qq && apt-get install -y -qq sysbench'
    
    echo "  Sysbench installed"
    docker exec $CONTAINER sysbench --version
    echo "  DONE with $version"
    echo ""
done

echo "All containers ready:"
docker ps --format "table {{.Names}}\t{{.Status}}"
