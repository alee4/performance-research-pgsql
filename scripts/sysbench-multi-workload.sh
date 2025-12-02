#!/usr/bin/env bash
set -e

VERSIONS=(13 14 15 16 17 18)  # Skip 11-12 due to repo issues
DURATION=${1:-60}
THREADS=${2:-4}
TABLE_SIZE=${3:-100000}

# All workloads to test
WORKLOADS=(
#    "oltp_read_write"
#    "oltp_read_only"
    "oltp_write_only"
#    "oltp_point_select"
#    "oltp_update_index"
#    "select_random_ranges"
)

OUTPUT_DIR="../results/sysbench-multi-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

for workload in "${WORKLOADS[@]}"; do
    echo "========================================="
    echo "Workload: $workload"
    echo "========================================="
    
    SUMMARY_FILE="$OUTPUT_DIR/${workload}_results.csv"
    echo "Version,TPS,Latency_Avg_ms,Latency_95th_ms" > "$SUMMARY_FILE"
    
    for version in "${VERSIONS[@]}"; do
        CONTAINER="postgres-$version"
        
        if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
            continue
        fi
        
        echo "  PG$version..."
        
        # Cleanup
        docker exec $CONTAINER sysbench \
            --db-driver=pgsql \
            --pgsql-user=postgres \
            --pgsql-password=test \
            --pgsql-db=postgres \
            $workload \
            --tables=10 \
            --table-size=$TABLE_SIZE \
            cleanup > /dev/null 2>&1 || true
        
        # Prepare
        docker exec $CONTAINER sysbench \
            --db-driver=pgsql \
            --pgsql-user=postgres \
            --pgsql-password=test \
            --pgsql-db=postgres \
            $workload \
            --tables=10 \
            --table-size=$TABLE_SIZE \
            prepare > /dev/null 2>&1
        
        # Run
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
        
        # Extract metrics
	TPS=$(grep "transactions:" "$OUTPUT_DIR/${workload}-pg$version.txt" | awk '{print $3}' | tr -d '()')
	LAT_AVG=$(grep "avg:" "$OUTPUT_DIR/${workload}-pg$version.txt" | awk '{print $2}')
	LAT_95=$(grep "95th percentile:" "$OUTPUT_DIR/${workload}-pg$version.txt" | awk '{print $3}')

        echo "$version,$TPS,$LAT_AVG,$LAT_95" >> "$SUMMARY_FILE"
        
        echo "    $TPS TPS"
    done
    
    echo ""
done

echo "Results saved to: $OUTPUT_DIR"
echo ""
echo "CSVs created:"
ls -1 "$OUTPUT_DIR"/*.csv
