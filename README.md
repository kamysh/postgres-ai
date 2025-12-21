# PostgreSQL with Extensions using Nix Flakes

A reproducible PostgreSQL 16 Docker image with pgvector and Apache AGE extensions, built using Nix flakes.

## Project Goals

The primary goal was to create a **reproducible, declarative** PostgreSQL Docker image with the following requirements:

- PostgreSQL 16 with pgvector (vector similarity search) and Apache AGE (graph database) extensions
- Chiron user and database with passwordless initial setup
- Cross-platform support (x86_64 and aarch64)
- Optimized Docker layer caching for fast rebuilds
- Alignment with Nix philosophy: no hacks, pure evaluation, reproducible builds

## Architecture

### Core Components

**flake.nix** - Defines project structure and dependencies
- Uses `postgresql_16.withPackages` to bundle PostgreSQL with extensions
- Supports both x86_64-linux and aarch64-linux architectures
- Extensions: pgvector (0.8.1), Apache AGE (1.6.0)

**docker-image.nix** - Docker image build configuration
- Uses `dockerTools.buildLayeredImage` for optimal layer caching
- Separates configurations into distinct derivations:
  - `postgresConfigs`: pg_hba.conf, pg_ident.conf, postgresql.conf
  - `initScripts`: init.sql database initialization
  - `entrypoint`: docker-entrypoint.sh with substituted binary paths
- Explicitly sets PATH to use postgresql-and-plugins binaries

**docker-entrypoint.sh** - Container startup script
- Uses `@POSTGRESQL_BIN@` placeholder replaced during build with full path to postgresql-and-plugins
- Initializes database on first run
- Runs SQL initialization scripts

**init.sql** - Database initialization
- Creates chiron user without password (uses peer authentication)
- Creates chiron database owned by chiron
- Enables vector and age extensions

**build.sh** - Cross-platform build script
- Auto-detects platform or accepts argument
- Handles macOS by running Nix in Docker container
- Cleans up old images to prevent dangling `<none>` images

**change-password.sh** - Password management utility
- Reads passwords from ~/.pgpass file
- Smart host detection (optional if only one entry exists)
- Changes PostgreSQL user passwords via docker exec

### Authentication Strategy

- **Local connections**: peer authentication (Unix socket, no password required)
- **Network connections**: scram-sha-256 (password required)
- Initial setup creates chiron user without password
- Passwords set post-deployment using change-password.sh utility

## Development Journey

### Early Attempts: nixos/nix Base Image

The initial approach was to use the `nixos/nix` Docker image as a base and install PostgreSQL with extensions on top of it, similar to traditional Dockerfile approaches:

```dockerfile
FROM nixos/nix
RUN nix-env -iA nixpkgs.postgresql_16
# ... attempt to add extensions, create users, etc.
```

**Problems Encountered**:
1. **User Account Creation**: The nixos/nix image has a minimal environment with limited user management tools. Creating the postgres user with proper UID/GID and permissions was problematic.
2. **Multiple Base Image Trials**: Tried several different base images attempting to find one that would work well with Nix while providing necessary system utilities.
3. **Extension Installation**: Even after getting PostgreSQL installed, adding extensions and managing their paths was error-prone.
4. **Layer Inefficiency**: Every change to the Dockerfile meant rebuilding large layers.
5. **Not the Nix Way**: Using a traditional Dockerfile approach defeated the purpose of using Nix for reproducible builds.

**The Pivot**: After struggling with these issues, realized that Nix provides `dockerTools.buildLayeredImage` - a proper, declarative way to build Docker images that:
- Handles user creation through `fakeRootCommands`
- Manages dependencies correctly through Nix derivations
- Optimizes layer caching automatically
- Aligns with Nix philosophy of declarative, reproducible builds

This was the turning point that led to the current implementation.

### Password Management Attempt

**Attempt: Password from ~/.pgpass during build**
```nix
# WRONG APPROACH - Violates Nix purity
let
  pgpassContent = builtins.readFile "${builtins.getEnv "HOME"}/.pgpass";
  # ... extract password ...
in
```

**Problem**: Nix flakes run in pure evaluation mode and cannot access files outside the repository. This contradicts Nix's reproducibility philosophy.

**Resolution**: Decided to create users without passwords initially and use a separate utility script (change-password.sh) for post-deployment password management.

### Critical Failure: Extension Loading

**The Error**:
```
ERROR:  extension "vector" is not available
DETAIL:  Could not open extension control file
"/nix/store/qby9r9i1m21l7pjwl02wsrh797q10vrx-postgresql-16.11/share/postgresql/extension/vector.control"
```

**Investigation Path** (All Wrong):
1. Tried mounting .pgpass into container - REJECTED (unnecessary hack)
2. Tried environment variables for password - REJECTED (wrong problem)
3. Tried buildEnv/symlinkJoin - REJECTED (hack)
4. Tried modifying dynamic_library_path in postgresql.conf - REJECTED (completely wrong)
5. Tried manual symlink creation - REJECTED (hack)

**Root Cause Discovery**:
The entrypoint script was using relative paths (`initdb`, `postgres`, `psql`) which resolved to the base PostgreSQL package instead of postgresql-and-plugins. This happened because `buildLayeredImage` created symlinks from both the base package and the with-plugins package in `/bin`, and PATH resolution was picking the wrong one.

**The Breakthrough**:
User question: "Do you install postgres package separately?"
User insight: "Then, you should run postgres from postgresWithPackages, not from postgres."
User clarification: "It is about how the fuck you are running binaries. Specify explicitly from which package you take it."

**The Fix**:
1. Added `@POSTGRESQL_BIN@` placeholder to docker-entrypoint.sh
2. Used `substitute` in docker-image.nix to replace with `${postgresql}/bin`
3. Set `PATH=${postgresql}/bin:/bin` in container config

This ensures all PostgreSQL commands explicitly use the postgresql-and-plugins binaries.

### Configuration Simplification

**pg_hba.conf Redundancy**:
Initial version had redundant network rules:
```
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             172.16.0.0/12           scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
```

**Simplified**: Since `0.0.0.0/0` covers all IPv4 addresses and `::/0` covers all IPv6 addresses, the specific subnet rules were removed.

### Build Optimization

**Layer Caching Problem**: Initial implementation put all configs in a single derivation, causing unnecessary rebuilds.

**Solution**: Separated into distinct derivations based on change frequency:
- `postgresConfigs` - changes rarely
- `initScripts` - may change during development
- `entrypoint` - rarely changes

Docker layer caching now reuses unchanged layers effectively.

**Image Cleanup**: Added `docker rmi postgres-ai:latest 2>/dev/null || true` before loading new image to prevent accumulation of dangling `<none>` images.

## Key Lessons and Conclusions

### 1. Don't Use nixos/nix Docker as Base Image

**The Mistake**: Attempting to use `nixos/nix` as a base image and then installing packages on top of it, Dockerfile-style.

**Why It Fails**:
- The nixos/nix image is designed for running Nix commands, not as an application runtime base
- Minimal environment with limited system tools (user management, permissions, etc.)
- User account creation with proper UID/GID is problematic
- Extension paths and dependencies become difficult to manage
- Defeats Nix's reproducibility guarantees
- Inefficient layer caching

**The Right Way**: Use `dockerTools.buildLayeredImage` from the start. This is Nix's native, declarative way to build Docker images:
- Handles user creation through `fakeRootCommands`
- Manages dependencies correctly through Nix derivations
- Optimizes layer caching automatically
- Fully declarative and reproducible
- No need to trial different base images - Nix builds the image from scratch

Don't think of Nix Docker images as "FROM something" - think of them as pure Nix derivations that output Docker-compatible tar files.

### 2. Respect Nix Purity
Nix flakes run in pure evaluation mode for good reason - it ensures reproducibility. Don't try to access files outside the repository (like ~/.pgpass or environment variables) during the Nix build phase. Instead, handle runtime configuration separately.

### 3. Explicit Binary Paths Matter
When multiple packages provide the same binary names (like base PostgreSQL and postgresql-with-plugins), you cannot rely on PATH resolution. Explicitly specify which package's binaries you're using, either through:
- Full paths in scripts
- Template substitution during build
- Careful PATH ordering in environment config

### 4. No Hacks, Use Proper Patterns
Throughout development, the temptation was to use workarounds:
- Mounting files into containers
- Environment variable tricks
- Manual symlink manipulation
- Configuration hacks like `dynamic_library_path`

The proper solution was always simpler: use the right package's binaries explicitly. When stuck, consult documentation rather than inventing clever workarounds.

### 5. Layer Optimization Requires Deliberate Structure
Docker layer caching in Nix isn't automatic. Separate frequently-changing content from stable content into distinct derivations. This allows Docker to cache the stable layers and only rebuild what changed.

### 6. Read the Error Messages Carefully
The error message showed the path to base PostgreSQL, not postgresql-and-plugins. The clue was in the path all along - we were using the wrong package's binaries.

## Usage

### Building the Image

For your current platform:
```bash
./build.sh
```

For specific platform:
```bash
./build.sh x86_64    # or aarch64
```

The script automatically handles macOS by running Nix in a Docker container.

### Running the Container

```bash
docker-compose up -d
```

On first run, the container will:
1. Initialize the PostgreSQL database
2. Create the chiron user and database
3. Enable vector and age extensions in the chiron database

### Setting User Passwords

Initial setup creates users without passwords (peer authentication only). To set a password:

```bash
./change-password.sh chiron
```

If you have multiple entries in ~/.pgpass for the chiron user, specify the host:
```bash
./change-password.sh chiron chiron.ai.home
```

The script will:
1. Search for matching entries in ~/.pgpass
2. Extract the password
3. Change the PostgreSQL user password via docker exec

### .pgpass Format

The ~/.pgpass file should contain entries in this format:
```
hostname:port:database:username:password
```

Example:
```
chiron.ai.home:5432:chiron:chiron:your_secure_password
```

### Accessing the Database

**From host machine** (requires password):
```bash
psql -h localhost -U chiron -d chiron
```

**From within container** (peer authentication, no password):
```bash
docker exec -it postgres-ai psql -U chiron -d chiron
```

**As postgres superuser**:
```bash
docker exec -it postgres-ai psql -U postgres -d postgres
```

## Project Structure

```
.
├── flake.nix                  # Nix flake definition
├── flake.lock                 # Locked dependency versions
├── docker-image.nix           # Docker image build config
├── docker-entrypoint.sh       # Container startup script
├── docker-compose.yml         # Docker Compose configuration
├── build.sh                   # Cross-platform build script
├── change-password.sh         # Password management utility
├── init.sql                   # Database initialization script
├── pg_hba.conf               # PostgreSQL authentication config
├── pg_ident.conf             # PostgreSQL ident mapping
└── postgresql.conf           # PostgreSQL server config
```

## Technical Details

### Extensions

**pgvector (0.8.1)**
- Vector similarity search for AI/ML applications
- Supports exact and approximate nearest neighbor search
- Custom vector data type and operators

**Apache AGE (1.6.0)**
- Graph database capabilities
- Cypher query language support
- Compatible with PostgreSQL's ACID guarantees

### Cross-Platform Support

The build system supports both architectures:
- **x86_64-linux** (amd64): Standard server architecture
- **aarch64-linux** (arm64): Apple Silicon, AWS Graviton, etc.

On macOS, the build script automatically uses Docker to run Nix in a Linux container, ensuring the resulting image is Linux-compatible.

### Security Considerations

- postgres superuser cannot connect over network (peer authentication only)
- All network connections require password authentication (scram-sha-256)
- Configuration files have restrictive permissions (600)
- Passwords stored in ~/.pgpass should have mode 0600