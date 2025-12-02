#!/usr/bin/env bash
set -e

VERSIONS=(11 12 13 14 15 16 17 18)

echo "Setting up PostgreSQL test environment (versions 14, 15, 16)..."

if [ ! -f workloads/benchmark.sql ]; then
    cat > workloads/benchmark.sql <<'SQL'
DROP TABLE IF EXISTS test_table;
CREATE TABLE test_table AS 
    SELECT 
        generate_series(1, 1000000) AS id,
        md5(random()::text) AS data,
        random() * 1000 AS value;

CREATE INDEX idx_test_value ON test_table(value);

SELECT COUNT(*) FROM test_table WHERE value < 500;
SELECT AVG(value) FROM test_table;
SELECT id, data FROM test_table WHERE value BETWEEN 100 AND 200 ORDER BY value LIMIT 100;
SQL
    echo "✓ Created sample workload: workloads/benchmark.sql"
fi

for version in "${VERSIONS[@]}"; do
    CONTAINER="postgres-$version"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
        echo "Removing existing $CONTAINER..."
        docker rm -f $CONTAINER > /dev/null 2>&1
    fi
    
    echo "Starting PostgreSQL $version..."
    docker run -d \
        --name $CONTAINER \
        -e POSTGRES_PASSWORD=test \
        -v $(pwd)/data:/data \
        -v $(pwd)/workloads:/workload \
        --cap-add=SYS_PTRACE \
        --security-opt seccomp=unconfined \
        postgres:$version > /dev/null
    
    echo "  Waiting for PostgreSQL $version..."
    for i in {1..30}; do
        if docker exec $CONTAINER pg_isready -U postgres > /dev/null 2>&1; then
            echo "  ✓ Ready"
            break
        fi
        sleep 1
    done
done

echo ""
echo "✓ Setup complete!"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""
echo "Next: cd scripts && sudo ./pg-perf-all.sh"
