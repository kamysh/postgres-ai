#!/bin/bash
set -e

PGDATA=/var/lib/postgresql/data
CNF=/etc/postgresql
PGBIN=@POSTGRESQL_BIN@

# Initialize database if PGDATA is empty
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    $PGBIN/initdb -D "$PGDATA"

    echo "Starting PostgreSQL temporarily for initialization..."
    $PGBIN/pg_ctl start -D "$PGDATA" -o "-c config_file=$CNF/postgresql.conf" -w

    echo "Running initialization scripts..."
    for f in /var/lib/postgresql/initdb.d/*.sql; do
        if [ -f "$f" ]; then
            echo "Running $f..."
            $PGBIN/psql -d postgres -f "$f"
        fi
    done

    echo "Stopping temporary PostgreSQL..."
    $PGBIN/pg_ctl stop -D "$PGDATA" -m fast -w

    echo "Initialization complete."
fi

# Start PostgreSQL
echo "Starting PostgreSQL..."
exec $PGBIN/postgres -c config_file=/etc/postgresql/postgresql.conf