# postgres-ai

PostgreSQL 16 with [pgvector](https://github.com/pgvector/pgvector) and [Apache AGE](https://age.apache.org/) pre-installed and pre-configured. Drop-in base for applications that need vector similarity search and/or graph (Cypher) queries on top of PostgreSQL.

## What's included

| Extension | Version | Purpose |
|-----------|---------|---------|
| pgvector | 0.8.1 | Vector similarity search (embeddings, semantic search) |
| Apache AGE | 1.6.0 | Property graph queries via Cypher |
| uuid-ossp | bundled | UUID generation |
| pgcrypto | bundled | Cryptographic functions |

All extensions are pre-installed in `template1` — available in every new database automatically, no `CREATE EXTENSION` required.

`shared_preload_libraries = 'age'` and the correct `search_path` for AGE are set in `postgresql.conf`.

## Quick start

```bash
docker run -d \
  --name postgres-ai \
  -e POSTGRES_PASSWORD=yourpassword \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  kamysh/postgres-ai:latest
```

Or with Docker Compose:

```yaml
services:
  postgres:
    image: kamysh/postgres-ai:latest
    environment:
      POSTGRES_PASSWORD: yourpassword
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

## Authentication

- **Unix socket** (via `docker exec`): peer authentication, no password
- **Network connections**: `scram-sha-256`, password required
- The `postgres` superuser is not accessible over the network

## Create a database and user

```bash
# Connect as superuser inside the container
docker exec -it postgres-ai psql -U postgres

# Then in psql:
CREATE USER myapp WITH PASSWORD 'secret';
CREATE DATABASE myapp OWNER myapp;
\c myapp
-- Extensions are already available (pre-installed in template1)
```

## Source

[github.com/kamysh/postgres-ai](https://github.com/kamysh/postgres-ai)
