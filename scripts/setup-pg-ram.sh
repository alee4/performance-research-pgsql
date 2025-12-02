#!/usr/bin/env bash
set -e

VERSIONS=(13 14 15 16 17 18)

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    docker rm -f $CONTAINER > /dev/null 2>&1 || true
    
    echo "Starting PG$version (RAM-only)..."
    docker run -d \
        --name $CONTAINER \
        -e POSTGRES_PASSWORD=test \
        -e PGDATA=/dev/shm/pgdata \
        -v $(pwd)/workloads:/workload \
        --tmpfs /dev/shm:rw,size=4g \
        --shm-size=4g \
        --cap-add=SYS_PTRACE \
        --security-opt seccomp=unconfined \
        postgres:$version \
        -c shared_buffers=1GB \
        -c fsync=off \
        -c synchronous_commit=off \
        -c full_page_writes=off \
        > /dev/null
    
    for i in {1..30}; do
        docker exec $CONTAINER pg_isready > /dev/null 2>&1 && break
        sleep 1
    done
    echo "  Ready"
    
    # Install sysbench
    echo "  Installing sysbench..."
    docker exec $CONTAINER bash -c 'apt-get update -qq && apt-get install -y -qq sysbench' > /dev/null 2>&1
    echo "  Sysbench installed"
done

echo ""
echo "RAM-optimized PostgreSQL ready with sysbench"
docker ps --format "table {{.Names}}\t{{.Status}}"
