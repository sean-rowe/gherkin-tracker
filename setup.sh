#!/bin/bash

# Gherkin Tracker Database Setup Script (PostgreSQL)
# Generic project-agnostic Gherkin feature tracking system

set -e

echo "=================================================="
echo "Gherkin Tracker Database Setup (PostgreSQL)"
echo "=================================================="
echo ""

# Navigate to script directory
cd "$(dirname "$0")"

# Check if PostgreSQL is running
echo "Checking PostgreSQL status..."
if ! /usr/local/opt/postgresql@17/bin/pg_isready > /dev/null 2>&1; then
    echo "PostgreSQL is not running. Starting PostgreSQL..."
    brew services start postgresql@17
    sleep 3
fi

echo "✓ PostgreSQL is running"
echo ""

# Create database
echo "Creating gherkin_tracker database..."
/usr/local/opt/postgresql@17/bin/psql -U "$USER" -d postgres -f scripts/01-create-database.sql

echo ""
echo "Creating database schema..."
/usr/local/opt/postgresql@17/bin/psql -U "$USER" -d gherkin_tracker -f scripts/02-create-schema.sql

echo ""
echo "=================================================="
echo "✓ Database setup completed successfully!"
echo "=================================================="
echo ""
echo "Connection details:"
echo "  Database: gherkin_tracker"
echo "  Username: $USER"
echo "  Host: localhost"
echo "  Port: 5432"
echo ""
echo "To connect using psql:"
echo "  psql -d gherkin_tracker"
echo ""
echo "To stop PostgreSQL:"
echo "  brew services stop postgresql@17"
echo ""
