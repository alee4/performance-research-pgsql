#!/usr/bin/env bash
set -e

VERSIONS=(13.0 13.1 13.2 13.3 13.4 13.5)
DURATION=${1:-60}
WARMUP_TIME=${2:-10}

OUTPUT_DIR="../results/pg13-point-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

SUMMARY_FILE="$OUTPUT_DIR/results.csv"
echo "Version,TPS,Latency_Avg_ms,Latency_95th_ms" > "$SUMMARY_FILE"

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    echo "Testing $version..."
    
    echo "  Preparing..."
    docker exec $CONTAINER sysbench oltp_write_only \
        --db-driver=pgsql --pgsql-user=postgres --pgsql-password=test \
        --tables=10 --table-size=100000 \
        prepare > /dev/null 2>&1
    
    echo "  Analyzing..."
    docker exec $CONTAINER psql -U postgres -c "ANALYZE;" > /dev/null 2>&1
    
    echo "  Warmup..."
    docker exec $CONTAINER sysbench oltp_write_only \
        --db-driver=pgsql --pgsql-user=postgres --pgsql-password=test \
        --tables=10 --table-size=100000 \
        --threads=4 --time=$WARMUP_TIME \
        run > /dev/null 2>&1
    
    echo "  Benchmarking..."
    docker exec $CONTAINER sysbench oltp_write_only \
        --db-driver=pgsql --pgsql-user=postgres --pgsql-password=test \
        --tables=10 --table-size=100000 \
        --threads=4 --time=$DURATION \
        run > "$OUTPUT_DIR/$version.txt"
    
    TPS=$(grep "transactions:" "$OUTPUT_DIR/$version.txt" | awk '{print $3}' | tr -d '()')
    LAT=$(grep "avg:" "$OUTPUT_DIR/$version.txt" | awk '{print $2}')
    LAT_95=$(grep "95th" "$OUTPUT_DIR/$version.txt" | awk '{print $3}')
    
    echo "$version,$TPS,$LAT,$LAT_95" >> "$SUMMARY_FILE"
    
    echo "  $TPS TPS"
done

cat "$SUMMARY_FILE" | column -t -s,
echo ""
echo "Saved to: $SUMMARY_FILE"
