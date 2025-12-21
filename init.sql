-- PostgreSQL Initialization Script
-- Create chiron user and database with vector and age extensions

-- Create chiron user without password (use peer authentication via Unix socket)
-- To set password: docker exec -it postgres-ai psql -U chiron -d chiron
-- Then run: ALTER USER chiron PASSWORD 'your_secure_password';
CREATE USER chiron;

-- Create chiron database with chiron as owner
CREATE DATABASE chiron OWNER chiron;

-- Enable vector and age extensions in chiron database
\c chiron
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
