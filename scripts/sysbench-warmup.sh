#!/usr/bin/env bash
set -e

VERSIONS=(13 14 15 16 17 18)
DURATION=${1:-60}
WARMUP_TIME=${2:-10}
THREADS=${3:-4}
TABLE_SIZE=${4:-100000}

WORKLOADS=("oltp_write_only")

OUTPUT_DIR="../results/sysbench-warmup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

for workload in "${WORKLOADS[@]}"; do
    echo "Workload: $workload"
    
    SUMMARY_FILE="$OUTPUT_DIR/${workload}_results.csv"
    echo "Version,TPS,Latency_Avg_ms,Latency_95th_ms" > "$SUMMARY_FILE"
    
    for version in "${VERSIONS[@]}"; do
        CONTAINER="postgres-$version"
        
        if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
            continue
        fi
        
        echo "  PG$version..."
        
        docker exec $CONTAINER sysbench \
            --db-driver=pgsql \
            --pgsql-user=postgres \
            --pgsql-password=test \
            --pgsql-db=postgres \
            $workload \
            --tables=10 \
            --table-size=$TABLE_SIZE \
            cleanup > /dev/null 2>&1 || true
        
        echo "    Preparing..."
        docker exec $CONTAINER sysbench \
            --db-driver=pgsql \
            --pgsql-user=postgres \
            --pgsql-password=test \
            --pgsql-db=postgres \
            $workload \
            --tables=10 \
            --table-size=$TABLE_SIZE \
            prepare > /dev/null 2>&1
        
        echo "    Analyzing..."
        docker exec $CONTAINER psql -U postgres -c "ANALYZE;" > /dev/null 2>&1
        
        echo "    Warmup (${WARMUP_TIME}s)..."
        docker exec $CONTAINER sysbench \
            --db-driver=pgsql \
            --pgsql-user=postgres \
            --pgsql-password=test \
            --pgsql-db=postgres \
            $workload \
            --tables=10 \
            --table-size=$TABLE_SIZE \
            --threads=$THREADS \
            --time=$WARMUP_TIME \
            run > /dev/null 2>&1
        
        echo "    Benchmarking (${DURATION}s)..."
        docker exec $CONTAINER sysbench \
            --db-driver=pgsql \
            --pgsql-user=postgres \
            --pgsql-password=test \
            --pgsql-db=postgres \
            $workload \
            --tables=10 \
            --table-size=$TABLE_SIZE \
            --threads=$THREADS \
            --time=$DURATION \
            run > "$OUTPUT_DIR/${workload}-pg$version.txt"
        
        TPS=$(grep "transactions:" "$OUTPUT_DIR/${workload}-pg$version.txt" | awk '{print $3}' | tr -d '()')
        LAT_AVG=$(grep "avg:" "$OUTPUT_DIR/${workload}-pg$version.txt" | awk '{print $2}')
        LAT_95=$(grep "95th percentile:" "$OUTPUT_DIR/${workload}-pg$version.txt" | awk '{print $3}')
        
        echo "$version,$TPS,$LAT_AVG,$LAT_95" >> "$SUMMARY_FILE"
        
        echo "    Result: $TPS TPS"
    done
    
    echo ""
done

cat "$OUTPUT_DIR"/*.csv | column -t -s,
echo ""
echo "Saved to: $OUTPUT_DIR"
