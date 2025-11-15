-- Create Gherkin Tracker Database for PostgreSQL
-- This script creates the database and enables necessary extensions

-- Drop database if exists (for fresh start)
DROP DATABASE IF EXISTS gherkin_tracker;

-- Create database
CREATE DATABASE gherkin_tracker
    WITH
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

-- Connect to the database
\c gherkin_tracker;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Confirmation message
SELECT 'Database gherkin_tracker created successfully' AS status;
