#!/usr/bin/env bash
set -e

#VERSIONS=(13 14 15 16 17 18)
VERSIONS=(13.10 13.15 13.20 13.22)

echo "Setting up ULTRA-optimized PostgreSQL..."

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    docker rm -f $CONTAINER > /dev/null 2>&1 || true
    
    echo "PG$version..."
    docker run -d \
        --name $CONTAINER \
        -e POSTGRES_PASSWORD=test \
        -e PGDATA=/dev/shm/pgdata \
        -v $(pwd)/workloads:/workload \
        --tmpfs /dev/shm:rw,size=4g \
        --shm-size=4g \
        --cpuset-cpus=0-3 \
        --cpu-quota=400000 \
        --memory=3g \
        --memory-swap=6g \
        --cap-add=SYS_PTRACE \
        --security-opt seccomp=unconfined \
        postgres:$version \
        -c shared_buffers=2GB \
        -c work_mem=128MB \
        -c maintenance_work_mem=512MB \
        -c effective_cache_size=3GB \
        -c temp_buffers=128MB \
        -c fsync=off \
        -c synchronous_commit=off \
        -c full_page_writes=off \
        -c wal_level=minimal \
        -c max_wal_senders=0 \
        -c autovacuum=off \
        -c bgwriter_delay=10000ms \
        -c checkpoint_timeout=1h \
        -c max_wal_size=10GB \
        -c log_statement=none \
        -c log_duration=off \
        -c track_activities=off \
        -c track_counts=off \
        -c track_io_timing=off \
        -c track_functions=none \
        -c random_page_cost=1.0 \
        -c seq_page_cost=1.0 \
        -c cpu_tuple_cost=0.01 \
        -c jit=off \
        -c max_connections=20 \
        -c huge_pages=try \
        > /dev/null
    
    for i in {1..30}; do
        docker exec $CONTAINER pg_isready > /dev/null 2>&1 && break
        sleep 1
    done
    
    docker exec $CONTAINER bash -c 'apt-get update -qq && apt-get install -y -qq sysbench' > /dev/null 2>&1
    echo "  Ready"
done

echo ""
echo "Ultra-optimized setup complete"
