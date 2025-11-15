#!/bin/bash

# CareSync Project Database Setup Script
# This script starts the Docker container and initializes the project management database

set -e

echo "=================================================="
echo "CareSync Project Database Setup"
echo "=================================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running."
    echo "Please start Docker Desktop and try again."
    exit 1
fi

echo "✓ Docker is running"
echo ""

# Navigate to database directory
cd "$(dirname "$0")"

# Start the database container
echo "Starting MSSQL container..."
docker-compose up -d

# Wait for SQL Server to be ready
echo "Waiting for SQL Server to be ready..."
sleep 10

# Check if container is healthy
echo "Checking container health..."
for i in {1..30}; do
    if docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "CareSync_2024_Strong!" -Q "SELECT 1" > /dev/null 2>&1; then
        echo "✓ SQL Server is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: SQL Server failed to start within 5 minutes"
        docker logs caresync-mssql
        exit 1
    fi
    echo "  Waiting... ($i/30)"
    sleep 10
done

echo ""
echo "Creating CareSyncProject database..."
docker exec -i caresync-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "CareSync_2024_Strong!" < scripts/01-create-project-database.sql

echo ""
echo "Creating database schema..."
docker exec -i caresync-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "CareSync_2024_Strong!" < scripts/02-create-project-schema.sql

echo ""
echo "=================================================="
echo "✓ Database setup completed successfully!"
echo "=================================================="
echo ""
echo "Connection details:"
echo "  Server: localhost,1434"
echo "  Database: CareSyncProject"
echo "  Username: sa"
echo "  Password: CareSync_2024_Strong!"
echo ""
echo "To connect using sqlcmd:"
echo "  docker exec -it caresync-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P 'CareSync_2024_Strong!' -d CareSyncProject"
echo ""
echo "To stop the database:"
echo "  docker-compose down"
echo ""
echo "To stop and remove all data:"
echo "  docker-compose down -v"
echo ""
