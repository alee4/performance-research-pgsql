#!/usr/bin/env bash
set -e

RELEASES_FILE=${1:-"../pg14-all.txt"}

echo "Building all releases from: $RELEASES_FILE"
echo "Started: $(date)"
echo ""

TOTAL=$(wc -l < "$RELEASES_FILE")
COUNT=0

while read -r TAG; do
    COUNT=$((COUNT + 1))
    echo "[$COUNT/$TOTAL] Building $TAG..."
    
    cd ../dockerfiles
    
    docker build \
        --build-arg PG_COMMIT=$TAG \
        -t postgres-git:$TAG \
        -f Dockerfile.postgres-git \
        . > /dev/null 2>&1
    
    echo "  ✓ Built"
    
    cd ../scripts
    
done < "$RELEASES_FILE"

echo ""
echo "Finished: $(date)"
echo "Built $COUNT images"
