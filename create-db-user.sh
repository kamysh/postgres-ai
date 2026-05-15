#!/usr/bin/env bash
set -euo pipefail

# Usage: ./create-db-user.sh <db_name> <username>
# Env overrides:
#   PG_CONTAINER  (default: postgres-ai)
#   PGPASS_FILE   (default: ~/.pgpass)
#   PGPASS_HOST   (optional filter)
#   PGPASS_PORT   (optional filter)

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <db_name> <username>"
    exit 1
fi

DB_NAME="$1"
USERNAME="$2"

PG_CONTAINER="${PG_CONTAINER:-postgres-ai}"
PGPASS_FILE="${PGPASS_FILE:-$HOME/.pgpass}"
PGPASS_HOST="${PGPASS_HOST:-}"
PGPASS_PORT="${PGPASS_PORT:-}"

if [ ! -f "$PGPASS_FILE" ]; then
    echo "Error: $PGPASS_FILE not found"
    exit 1
fi

# Filter ~/.pgpass for matching user/db (and optional host/port)
# Format: hostname:port:database:username:password
ENTRIES=$(awk -F: -v user="$USERNAME" -v db="$DB_NAME" -v host="$PGPASS_HOST" -v port="$PGPASS_PORT" '
    $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ {
        h=$1; p=$2; d=$3; u=$4; pw=$5;
        if (u != user) next;
        if (d != db && d != "*") next;
        if (host != "" && h != host && h != "*") next;
        if (port != "" && p != port && p != "*") next;
        print h ":" p ":" d ":" u ":" pw;
    }
' "$PGPASS_FILE" || true)

if [ -z "$ENTRIES" ]; then
    echo "Error: No matching ~/.pgpass entry for user '${USERNAME}' and db '${DB_NAME}'"
    exit 1
fi

PASSWORDS=$(echo "$ENTRIES" | awk -F: '{print $5}' | sort -u)
PASSWORD_COUNT=$(echo "$PASSWORDS" | wc -l | tr -d ' ')

if [ "$PASSWORD_COUNT" -ne 1 ]; then
    echo "Error: Multiple different passwords found for ${USERNAME}/${DB_NAME}."
    echo "Set PGPASS_HOST/PGPASS_PORT to disambiguate."
    exit 1
fi

PASSWORD="$PASSWORDS"

echo "Creating/updating user '${USERNAME}' and database '${DB_NAME}' in container '${PG_CONTAINER}'..."

docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<EOF
\set db_name '${DB_NAME}'
\set user_name '${USERNAME}'
\set user_pass '${PASSWORD}'

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'user_name') THEN
    EXECUTE format('CREATE ROLE %I LOGIN', :'user_name');
  END IF;
  EXECUTE format('ALTER ROLE %I PASSWORD %L', :'user_name', :'user_pass');
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'db_name', :'user_name');
  END IF;
END
$$;

DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'user_name');
  EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'db_name', :'user_name');
END
$$;

\connect :db_name
DO $$
DECLARE
  r record;
  ro record;
BEGIN
  FOR r IN
    SELECT nspname
    FROM pg_namespace
    WHERE nspname NOT IN ('pg_catalog', 'information_schema')
      AND nspname NOT LIKE 'pg_toast%'
      AND nspname NOT LIKE 'pg_temp_%'
      AND nspname NOT LIKE 'pg_toast_temp_%'
  LOOP
    EXECUTE format('ALTER SCHEMA %I OWNER TO %I', r.nspname, :'user_name');
    EXECUTE format('GRANT ALL PRIVILEGES ON SCHEMA %I TO %I', r.nspname, :'user_name');
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I TO %I', r.nspname, :'user_name');
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I TO %I', r.nspname, :'user_name');
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA %I TO %I', r.nspname, :'user_name');
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA %I TO %I', r.nspname, :'user_name');
    EXECUTE format('GRANT ALL PRIVILEGES ON ALL TYPES IN SCHEMA %I TO %I', r.nspname, :'user_name');

    FOR ro IN
      SELECT rolname
      FROM pg_roles
      WHERE rolname NOT LIKE 'pg_%'
    LOOP
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT ALL PRIVILEGES ON TABLES TO %I',
        ro.rolname, r.nspname, :'user_name'
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT ALL PRIVILEGES ON SEQUENCES TO %I',
        ro.rolname, r.nspname, :'user_name'
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT ALL PRIVILEGES ON FUNCTIONS TO %I',
        ro.rolname, r.nspname, :'user_name'
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT ALL PRIVILEGES ON PROCEDURES TO %I',
        ro.rolname, r.nspname, :'user_name'
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT ALL PRIVILEGES ON TYPES TO %I',
        ro.rolname, r.nspname, :'user_name'
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT ALL PRIVILEGES ON SCHEMAS TO %I',
        ro.rolname, r.nspname, :'user_name'
      );
    END LOOP;
  END LOOP;
END
$$;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOF

echo "Done."
