#!/usr/bin/env bash
set -e

VERSIONS=(13 14 15 16 17 18)
DURATION=${1:-60}
THREADS=${2:-4}
TABLE_SIZE=${3:-100000}
OUTPUT_DIR="../results/sysbench-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUTPUT_DIR"

SUMMARY_FILE="$OUTPUT_DIR/benchmark_results.csv"
echo "Version,Transactions,TPS,Queries,QPS,Latency_Avg_ms,Latency_95th_ms,Latency_99th_ms,Latency_Max_ms" > "$SUMMARY_FILE"

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
        continue
    fi
    
    echo "Testing PG$version..."
    
    docker exec $CONTAINER sysbench \
        --db-driver=pgsql \
        --pgsql-user=postgres \
        --pgsql-password=test \
        --pgsql-db=postgres \
        /usr/share/sysbench/oltp_read_write.lua \
        --tables=10 \
        --table-size=$TABLE_SIZE \
        cleanup > /dev/null 2>&1 || true
    
    docker exec $CONTAINER sysbench \
        --db-driver=pgsql \
        --pgsql-user=postgres \
        --pgsql-password=test \
        --pgsql-db=postgres \
        /usr/share/sysbench/oltp_read_write.lua \
        --tables=10 \
        --table-size=$TABLE_SIZE \
        prepare > /dev/null 2>&1
    
    docker exec $CONTAINER sysbench \
        --db-driver=pgsql \
        --pgsql-user=postgres \
        --pgsql-password=test \
        --pgsql-db=postgres \
        /usr/share/sysbench/oltp_read_write.lua \
        --tables=10 \
        --table-size=$TABLE_SIZE \
        --threads=$THREADS \
        --time=$DURATION \
        run > "$OUTPUT_DIR/sysbench-pg$version.txt"
    
    TRANSACTIONS=$(grep "transactions:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $3}' | sed 's/(//')
    TPS=$(grep "transactions:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $4}' | sed 's/(//')
    QUERIES=$(grep "queries:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $3}' | sed 's/(//')
    QPS=$(grep "queries:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $4}' | sed 's/(//')
    LAT_AVG=$(grep "avg:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $2}')
    LAT_95=$(grep "95th percentile:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $3}')
    LAT_99=$(grep "99th percentile:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $3}')
    LAT_MAX=$(grep "max:" "$OUTPUT_DIR/sysbench-pg$version.txt" | awk '{print $2}')
    
    echo "$version,$TRANSACTIONS,$TPS,$QUERIES,$QPS,$LAT_AVG,$LAT_95,$LAT_99,$LAT_MAX" >> "$SUMMARY_FILE"
    
    echo "PG$version: $TPS TPS, ${LAT_AVG}ms avg latency"
done

echo ""
echo "Results:"
cat "$SUMMARY_FILE" | column -t -s,
echo ""
echo "Saved to: $SUMMARY_FILE"
