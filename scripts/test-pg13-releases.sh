#!/usr/bin/env bash
set -e

RELEASES_FILE=${1:-"../pg13-first6.txt"}
DURATION=${2:-60}
WARMUP_TIME=${3:-10}

OUTPUT_DIR="../results/pg13-releases-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

SUMMARY_FILE="$OUTPUT_DIR/results.csv"
echo "Release,TPS,Latency_Avg_ms,Latency_95th_ms" > "$SUMMARY_FILE"

while read -r RELEASE; do
    CONTAINER="postgres-test"
    
    echo "Testing $RELEASE..."
    
    docker rm -f $CONTAINER > /dev/null 2>&1 || true
    
    docker run -d \
        --name $CONTAINER \
        --tmpfs /dev/shm:rw,size=2g \
        --shm-size=2g \
        --memory=3g \
        --cpus=4 \
        postgres-git:$RELEASE > /dev/null
    
    echo "  Setting up..."
    docker exec $CONTAINER mkdir -p /dev/shm/pgdata
    docker exec $CONTAINER chown postgres:postgres /dev/shm/pgdata
    
    docker exec -u postgres $CONTAINER /usr/local/pgsql/bin/initdb -D /dev/shm/pgdata > /dev/null 2>&1
    
    docker exec -u postgres $CONTAINER bash -c 'cat > /dev/shm/pgdata/postgresql.conf <<CONFIG
shared_buffers = 1GB
fsync = off
synchronous_commit = off
autovacuum = off
jit = off
CONFIG'
    
    docker exec -u postgres -d $CONTAINER /usr/local/pgsql/bin/postgres -D /dev/shm/pgdata > /dev/null 2>&1
    
    sleep 5
    
    for i in {1..30}; do
        docker exec $CONTAINER /usr/local/pgsql/bin/pg_isready > /dev/null 2>&1 && break
        sleep 1
    done
    
    echo "  Creating sbtest database..."
    docker exec -u postgres $CONTAINER /usr/local/pgsql/bin/psql -c "CREATE DATABASE sbtest;" > /dev/null 2>&1
    
    echo "  Preparing..."
    docker exec $CONTAINER sysbench oltp_write_only \
        --db-driver=pgsql --pgsql-user=postgres --pgsql-db=sbtest \
        --tables=10 --table-size=100000 \
        prepare > /dev/null 2>&1
    
    echo "  Analyzing..."
    docker exec $CONTAINER /usr/local/pgsql/bin/psql -U postgres -d sbtest -c "ANALYZE;" > /dev/null 2>&1
    
    echo "  Warmup (${WARMUP_TIME}s)..."
    docker exec $CONTAINER sysbench oltp_write_only \
        --db-driver=pgsql --pgsql-user=postgres --pgsql-db=sbtest \
        --tables=10 --table-size=100000 \
        --threads=4 --time=$WARMUP_TIME \
        run > /dev/null 2>&1
    
    echo "  Benchmarking (${DURATION}s)..."
    docker exec $CONTAINER sysbench oltp_write_only \
        --db-driver=pgsql --pgsql-user=postgres --pgsql-db=sbtest \
        --tables=10 --table-size=100000 \
        --threads=4 --time=$DURATION \
        run > "$OUTPUT_DIR/$RELEASE.txt"
    
    TPS=$(grep "transactions:" "$OUTPUT_DIR/$RELEASE.txt" | awk '{print $3}' | tr -d '()')
    LAT=$(grep "avg:" "$OUTPUT_DIR/$RELEASE.txt" | awk '{print $2}')
    LAT_95=$(grep "95th" "$OUTPUT_DIR/$RELEASE.txt" | awk '{print $3}')
    
    echo "$RELEASE,$TPS,$LAT,$LAT_95" >> "$SUMMARY_FILE"
    
    echo "  $TPS TPS"
    
    docker stop $CONTAINER > /dev/null 2>&1
    docker rm $CONTAINER > /dev/null 2>&1
    
done < "$RELEASES_FILE"

echo ""
cat "$SUMMARY_FILE" | column -t -s,
echo ""
echo "Saved to: $SUMMARY_FILE"
