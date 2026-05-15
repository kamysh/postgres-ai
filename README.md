# postgres-ai

A reproducible PostgreSQL 16 Docker image with [pgvector](https://github.com/pgvector/pgvector) and [Apache AGE](https://age.apache.org/) extensions, built with Nix flakes.

Intended as a reusable base for projects that need vector similarity search and/or graph (Cypher) queries on top of PostgreSQL. Each consuming project creates its own users and databases on top of this image.

## Extensions

| Extension | Version | Purpose |
|-----------|---------|---------|
| pgvector | 0.8.1 | Vector similarity search (embeddings, semantic search) |
| Apache AGE | 1.6.0 | Property graph queries via Cypher |
| uuid-ossp | bundled | UUID generation |
| pgcrypto | bundled | Cryptographic functions |

All four extensions are pre-installed in `template1`, so they are automatically available in every new database without requiring a superuser `CREATE EXTENSION` call.

## Configuration

**`shared_preload_libraries = 'age'`** is set in `postgresql.conf` — required by AGE. `search_path` is set to `ag_catalog, "$user", public` for correct AGE operator resolution.

**Authentication:**
- Unix socket (local): `peer` (no password required — use `docker exec`)
- Network: `scram-sha-256` (password required)
- `postgres` superuser is not reachable over the network

## Usage

### Build

```bash
./build.sh           # current platform (auto-detected)
./build.sh x86_64    # or aarch64
```

On macOS, the script runs Nix inside a Linux Docker container so the output image is Linux-compatible.

### Run

```bash
docker compose up -d
```

The container exposes port `5432` (or `$POSTGRES_PORT`) on `127.0.0.1`.

### Create a project database and user

After the container is running, use the included utility script:

```bash
./create-db-user.sh <db_name> <username>
```

This creates the role and database, grants privileges, and enables the extensions in that database. The user's password is read from `~/.pgpass`:

```
# ~/.pgpass (chmod 600)
localhost:5432:<db_name>:<username>:<password>
```

### Set or rotate a password

```bash
./change-password.sh <username>
```

### Connect

```bash
# From the host (password required)
psql -h localhost -U <username> -d <db_name>

# From inside the container (peer auth, no password)
docker exec -it postgres-ai psql -U postgres -d postgres
```

## Project structure

```
flake.nix              Nix flake — PostgreSQL with extensions
docker-image.nix       Layered Docker image build (dockerTools.buildLayeredImage)
docker-entrypoint.sh   Container startup: initdb + run init scripts + start postgres
init.sql               Enable extensions in template1
postgresql.conf        Server config (AGE preload, search_path, etc.)
pg_hba.conf            Authentication rules
build.sh               Cross-platform build script
create-db-user.sh      Create a project user + database
change-password.sh     Rotate a user's password via ~/.pgpass
docker-compose.yml     Run the container locally
```

## Architecture note

The image uses `dockerTools.buildLayeredImage` (not a traditional `FROM postgres` Dockerfile). This is necessary because Apache AGE must be compiled against the exact PostgreSQL binaries — using Nix's `postgresql.withPackages` ensures the extension and the server share the same store path, avoiding the "wrong binary" class of errors. The entrypoint uses `@POSTGRESQL_BIN@` substitution at build time to guarantee all commands (`initdb`, `postgres`, `psql`) come from `postgresql-with-plugins`, not the base package.

## License

Apache License 2.0
