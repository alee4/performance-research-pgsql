#!/usr/bin/env bash
set -e

VERSIONS=(11 12 13 14 15 16 17 18)
WORKLOAD_FILE=${1:-"../workloads/benchmark.sql"}
DURATION=${2:-30}
OUTPUT_DIR="../results/perf-results-$(date +%Y%m%d-%H%M%S)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}PostgreSQL Performance Profiling (v14, 15, 16)${NC}"
echo "Workload: $WORKLOAD_FILE"
echo "Duration: $DURATION seconds"
echo ""

if ! command -v perf &> /dev/null; then
    echo -e "${RED}Error: perf not installed${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [ ! -f "$WORKLOAD_FILE" ]; then
    echo -e "${RED}Error: Workload file not found${NC}"
    exit 1
fi

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    echo -e "${GREEN}PostgreSQL $version${NC}"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
        echo "Container not running, skipping..."
        continue
    fi
    
    PID=$(docker inspect -f '{{.State.Pid}}' $CONTAINER 2>/dev/null)
    
    if [ -z "$PID" ] || [ "$PID" = "0" ]; then
        echo "Could not get PID, skipping..."
        continue
    fi
    
    echo "  PID: $PID, recording..."
    
    perf record \
        -p $PID \
        -g \
        -F 99 \
        --call-graph dwarf \
        -o "$OUTPUT_DIR/perf-pg$version.data" \
        -- sleep $DURATION &
    PERF_PID=$!
    
    sleep 1
    
    WORKLOAD_BASENAME=$(basename $WORKLOAD_FILE)
    docker exec $CONTAINER psql -U postgres -f /workload/$WORKLOAD_BASENAME \
        > "$OUTPUT_DIR/pg$version-query-output.log" 2>&1
    
    wait $PERF_PID
    
    echo "  Generating report..."
    perf report \
        -i "$OUTPUT_DIR/perf-pg$version.data" \
        --stdio \
        --percent-limit 1 \
        -g none \
        > "$OUTPUT_DIR/perf-pg$version-report.txt"
    
    echo "  ✓ Done"
    echo ""
done

echo -e "${BLUE}Summary - Top 5 Functions${NC}"
for version in "${VERSIONS[@]}"; do
    REPORT="$OUTPUT_DIR/perf-pg$version-report.txt"
    if [ -f "$REPORT" ]; then
        echo -e "${GREEN}v$version:${NC}"
        grep -A 8 "Overhead" "$REPORT" | tail -n 5
        echo ""
    fi
done

echo -e "${GREEN}✓ Complete! Results in: $OUTPUT_DIR${NC}"
