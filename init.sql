-- PostgreSQL Initialization Script
-- Enable extensions in template1 so they are available in every new database.
-- Consuming projects create their own users and databases (see create-db-user.sh).

\c template1
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
