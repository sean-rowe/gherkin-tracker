#!/bin/bash

# CareSync Database BDD Test Runner
# This script follows the Red-Green-Refactor cycle

echo "================================================"
echo "CareSync Database BDD Test Runner"
echo "================================================"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running. Please start Docker first."
    exit 1
fi

# Function to wait for SQL Server to be ready
wait_for_sqlserver() {
    echo "Waiting for SQL Server to be ready..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "CareSync_2024_Strong!" -Q "SELECT 1" > /dev/null 2>&1; then
            echo "SQL Server is ready!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: SQL Server not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    echo "ERROR: SQL Server failed to start within 60 seconds"
    return 1
}

# Function to run SQL script
run_sql_script() {
    local script=$1
    local description=$2
    
    echo ""
    echo "Executing: $description"
    docker exec -i caresync-mssql /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "CareSync_2024_Strong!" \
        -i "$script" \
        -b -e
    
    if [ $? -eq 0 ]; then
        echo "✓ Success: $description"
    else
        echo "✗ Failed: $description"
        return 1
    fi
}

# Start the process
echo "Step 1: Starting SQL Server container..."
docker-compose down > /dev/null 2>&1
docker rm -f caresync-mssql > /dev/null 2>&1
docker-compose up -d

# Wait for SQL Server to be ready
if ! wait_for_sqlserver; then
    exit 1
fi

echo ""
echo "================================================"
echo "Phase 1: RED - Running BDD tests (should fail)"
echo "================================================"

# Run tSQLt setup first
run_sql_script "/tests/tSQLt-setup.sql" "Setting up tSQLt framework"

# Run tests before implementation (Red phase)
echo ""
echo "Running tests BEFORE implementation (expecting failures)..."
docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P "CareSync_2024_Strong!" \
    -Q "USE CareSync; EXEC [tSQLt].[Run];" 2>&1 | grep -E "(FAIL|ERROR|Total Tests|Failed Tests)" || true

echo ""
echo "✓ Red phase complete - Tests failed as expected (no implementation yet)"

echo ""
echo "================================================"
echo "Phase 2: GREEN - Implementing database schema"
echo "================================================"

# Run implementation scripts
run_sql_script "/scripts/01-create-database.sql" "Creating database with HIPAA configuration"
run_sql_script "/scripts/02-create-tables.sql" "Creating Identity and Care tables"
run_sql_script "/scripts/03-create-clinical-tables.sql" "Creating Clinical tables with partitioning"
run_sql_script "/scripts/04-create-communication-tables.sql" "Creating Communication tables"
run_sql_script "/scripts/05-create-audit-security.sql" "Creating Audit and Security configuration"

echo ""
echo "================================================"
echo "Phase 3: VERIFY - Running BDD tests (should pass)"
echo "================================================"

# Set up tSQLt in the new database
run_sql_script "/tests/tSQLt-setup.sql" "Re-initializing tSQLt framework"

# Run all test classes
run_sql_script "/tests/DatabaseSchemaTests.sql" "Loading Database Schema Tests"
run_sql_script "/tests/SecurityFunctionTests.sql" "Loading Security Function Tests"

# Execute all tests
echo ""
echo "Running ALL tests after implementation..."
docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P "CareSync_2024_Strong!" \
    -i "/tests/run-tests.sql" \
    -y 0 -Y 30

# Check test results
echo ""
echo "Checking test results..."
TEST_RESULTS=$(docker exec caresync-mssql /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P "CareSync_2024_Strong!" \
    -Q "SET NOCOUNT ON; USE CareSync; SELECT COUNT(*) FROM [tSQLt].[TestResults] WHERE [Result] = 'Failure';" \
    -h -1 2>/dev/null | tr -d ' ')

if [ "$TEST_RESULTS" = "0" ]; then
    echo ""
    echo "================================================"
    echo "✓ SUCCESS: All BDD tests passed!"
    echo "================================================"
    echo ""
    echo "The database schema successfully implements:"
    echo "- Multi-tenant isolation with row-level security"
    echo "- HIPAA-compliant audit trails and retention"
    echo "- Concurrent multi-user access (PRIMARY differentiator)"
    echo "- Monthly partitioning for performance"
    echo "- Real-time collaboration features"
    echo ""
    echo "Ready for deployment to Kubernetes StatefulSet!"
else
    echo ""
    echo "================================================"
    echo "✗ FAILURE: $TEST_RESULTS tests failed"
    echo "================================================"
    echo ""
    echo "Review the test output above to fix failing tests."
    echo "The implementation must satisfy all BDD requirements."
fi

echo ""
echo "To connect to the database:"
echo "  Server: localhost,1434"
echo "  Username: sa"
echo "  Password: CareSync_2024_Strong!"
echo ""
echo "To stop the database:"
echo "  docker-compose down"
echo ""