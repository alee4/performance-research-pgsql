#!/usr/bin/env bash
set -e

RELEASES=(REL_14_0 REL_14_1 REL_14_2 REL_14_3 REL_14_4 REL_14_5 REL_14_6 REL_14_7 REL_14_8 REL_14_9 REL_14_10 REL_14_11 REL_14_12 REL_14_13 REL_14_14 REL_14_15 REL_14_16 REL_14_17 REL_14_18 REL_14_19)
DURATION=${1:-60}
WARMUP=${2:-10}
RUNS=${3:-3}

OUTPUT_DIR="../results/pg13-multi-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

SUMMARY="$OUTPUT_DIR/results.csv"
echo "Release,Run,TPS,Latency_Avg_ms,Latency_95th_ms" > "$SUMMARY"

for RUN in $(seq 1 $RUNS); do
    echo "========================================="
    echo "Run $RUN/$RUNS (randomized order)"
    echo "========================================="
    
    SHUFFLED=($(shuf -e "${RELEASES[@]}"))
    
    for RELEASE in "${SHUFFLED[@]}"; do
        CONTAINER="postgres-test"
        
        echo "  Testing $RELEASE..."
        
        docker rm -f $CONTAINER > /dev/null 2>&1 || true
        
        docker run -d --name $CONTAINER --tmpfs /dev/shm:rw,size=2g --shm-size=2g --memory=3g postgres-git:$RELEASE > /dev/null
        
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
        
        docker exec -u postgres $CONTAINER /usr/local/pgsql/bin/psql -c "CREATE DATABASE sbtest;" > /dev/null 2>&1
        
        docker exec $CONTAINER sysbench oltp_write_only --db-driver=pgsql --pgsql-user=postgres --pgsql-db=sbtest --tables=10 --table-size=100000 prepare > /dev/null 2>&1
        
        docker exec $CONTAINER /usr/local/pgsql/bin/psql -U postgres -d sbtest -c "ANALYZE;" > /dev/null 2>&1
        
        docker exec $CONTAINER sysbench oltp_write_only --db-driver=pgsql --pgsql-user=postgres --pgsql-db=sbtest --tables=10 --table-size=100000 --threads=4 --time=$WARMUP run > /dev/null 2>&1
        
        docker exec $CONTAINER sysbench oltp_write_only --db-driver=pgsql --pgsql-user=postgres --pgsql-db=sbtest --tables=10 --table-size=100000 --threads=4 --time=$DURATION run > "$OUTPUT_DIR/${RELEASE}_run${RUN}.txt"
        
        TPS=$(grep "transactions:" "$OUTPUT_DIR/${RELEASE}_run${RUN}.txt" | awk '{print $3}' | tr -d '()')
        LAT=$(grep "avg:" "$OUTPUT_DIR/${RELEASE}_run${RUN}.txt" | awk '{print $2}')
        LAT_95=$(grep "95th" "$OUTPUT_DIR/${RELEASE}_run${RUN}.txt" | awk '{print $3}')
        
        echo "$RELEASE,$RUN,$TPS,$LAT,$LAT_95" >> "$SUMMARY"
        
        echo "    $TPS TPS"
        
        docker stop $CONTAINER > /dev/null 2>&1
        docker rm $CONTAINER > /dev/null 2>&1
        
        sleep 5
    done
    
    echo ""
done

echo ""
cat "$SUMMARY" | column -t -s,
echo ""
echo "Saved to: $SUMMARY"
echo "Analyze on Mac with Pandas to get statistics"
