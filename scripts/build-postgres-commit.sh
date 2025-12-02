#!/usr/bin/env bash
set -e

COMMIT=$1

if [ -z "$COMMIT" ]; then
    echo "Usage: $0 <commit-hash-or-tag>"
    echo "Example: $0 REL_14_0"
    echo "Example: $0 abc123def"
    exit 1
fi

echo "Building PostgreSQL from commit: $COMMIT"

cd ../dockerfiles

docker build \
    --build-arg PG_COMMIT=$COMMIT \
    -t postgres-git:$COMMIT \
    -f Dockerfile.postgres-git \
    .

echo "✓ Built: postgres-git:$COMMIT"
