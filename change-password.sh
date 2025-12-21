#!/usr/bin/env bash
set -e

# Usage: ./change-password.sh <username> [host]
# Example: ./change-password.sh chiron
#          ./change-password.sh chiron chiron.ai.home

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <username> [host]"
    echo "Example: $0 chiron"
    echo "         $0 chiron chiron.ai.home"
    exit 1
fi

USERNAME="$1"
HOST="${2:-}"
PGPASS_FILE="${HOME}/.pgpass"

if [ ! -f "$PGPASS_FILE" ]; then
    echo "Error: ~/.pgpass file not found"
    exit 1
fi

# Search for all entries for the user
# Format: hostname:port:database:username:password
ENTRIES=$(grep ":${USERNAME}:" "$PGPASS_FILE" || true)

if [ -z "$ENTRIES" ]; then
    echo "Error: No entries found for user ${USERNAME} in ~/.pgpass"
    exit 1
fi

ENTRY_COUNT=$(echo "$ENTRIES" | wc -l | tr -d ' ')

if [ -z "$HOST" ]; then
    # Host not provided
    if [ "$ENTRY_COUNT" -eq 1 ]; then
        # Only one entry, use it
        HOST=$(echo "$ENTRIES" | cut -d: -f1)
        PASSWORD=$(echo "$ENTRIES" | cut -d: -f5)
        echo "Using entry for ${USERNAME}@${HOST}"
    else
        # Multiple entries, ask for host
        echo "Multiple entries found for user ${USERNAME}:"
        echo "$ENTRIES" | cut -d: -f1,4 | sed 's/:/ @ /'
        echo ""
        echo "Please specify host as second argument"
        exit 1
    fi
else
    # Host provided, find matching entry
    MATCHING_ENTRY=$(echo "$ENTRIES" | grep "^${HOST}:" || true)

    if [ -z "$MATCHING_ENTRY" ]; then
        echo "Error: No entry found for ${USERNAME}@${HOST} in ~/.pgpass"
        exit 1
    fi

    PASSWORD=$(echo "$MATCHING_ENTRY" | cut -d: -f5)
fi

echo "Changing password for ${USERNAME}@${HOST}..."

# Connect via docker exec and change password
docker exec -i postgres-ai psql -U postgres -d postgres <<EOF
ALTER USER ${USERNAME} PASSWORD '${PASSWORD}';
EOF

echo "Password changed successfully for user: ${USERNAME}"