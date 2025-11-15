# Docker Setup for Gherkin Tracker

This guide explains how to set up the Gherkin Tracker database using Docker.

## Quick Start

### 1. Start Database Only

```bash
# Copy environment file
cp .env.example .env

# Edit if needed
nano .env

# Start database
docker-compose up -d database

# Check status
docker-compose ps

# View logs
docker-compose logs -f database
```

The database will be available at `localhost:5432` with:
- **Database**: `gherkin_tracker`
- **User**: `postgres`
- **Password**: `postgres` (or value from `.env`)

### 2. Start with PgAdmin (Development Mode)

```bash
# Start database + PgAdmin
docker-compose --profile dev up -d

# Access PgAdmin at http://localhost:5050
# Email: admin@gherkin-tracker.local (or from .env)
# Password: admin (or from .env)
```

## Database Initialization

The database is automatically initialized with all required tables, functions, and views on first start.

**Initialization scripts** (run in order):
1. `01-schema.sql` - Base schema
2. `02-project-database.sql` - Project tables
3. `03-project-schema.sql` - Project schema
4. `04-task-dependencies.sql` - Task dependencies
5. `05-pr-management.sql` - PR management tables

## Connecting from Python

Update your connection parameters:

```python
DB_PARAMS = {
    'dbname': 'gherkin_tracker',
    'user': 'postgres',
    'password': 'postgres',  # or from .env
    'host': 'localhost',
    'port': 5432
}
```

Or use environment variable:

```bash
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/gherkin_tracker"
```

## Management Commands

### View Logs

```bash
# All logs
docker-compose logs -f

# Database only
docker-compose logs -f database

# Last 100 lines
docker-compose logs --tail=100 database
```

### Execute SQL

```bash
# Using docker exec
docker-compose exec database psql -U postgres -d gherkin_tracker

# Run SQL file
docker-compose exec -T database psql -U postgres -d gherkin_tracker < my_script.sql

# Quick query
docker-compose exec database psql -U postgres -d gherkin_tracker -c "SELECT COUNT(*) FROM task;"
```

### Backup and Restore

```bash
# Backup
docker-compose exec database pg_dump -U postgres gherkin_tracker > backup.sql

# Restore
docker-compose exec -T database psql -U postgres gherkin_tracker < backup.sql
```

### Reset Database

```bash
# Stop and remove containers + volumes
docker-compose down -v

# Start fresh
docker-compose up -d database
```

## Environment Variables

Create `.env` file in the project root:

```bash
# Database
DB_PASSWORD=your_secure_password
DB_PORT=5432

# PgAdmin (optional)
PGADMIN_EMAIL=your@email.com
PGADMIN_PASSWORD=your_admin_password
PGADMIN_PORT=5050
```

## PgAdmin Configuration

After starting PgAdmin:

1. Navigate to http://localhost:5050
2. Login with credentials from `.env`
3. Add server:
   - **Name**: Gherkin Tracker
   - **Host**: database (container name)
   - **Port**: 5432
   - **Username**: postgres
   - **Password**: (from .env)

## Docker Compose Profiles

```bash
# Database only (default)
docker-compose up -d

# Database + PgAdmin (development)
docker-compose --profile dev up -d

# All services (if we add more in future)
docker-compose --profile full up -d
```

## Health Checks

The database container includes a health check:

```bash
# Check health status
docker-compose ps

# database should show "healthy" status
```

Health check runs every 10 seconds and verifies PostgreSQL is accepting connections.

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 5432
lsof -i :5432

# Change port in .env
echo "DB_PORT=5433" >> .env

# Restart
docker-compose up -d
```

### Database Won't Start

```bash
# View logs
docker-compose logs database

# Reset everything
docker-compose down -v
docker-compose up -d database
```

### Can't Connect from Python

```bash
# Verify container is running
docker-compose ps

# Check container can accept connections
docker-compose exec database pg_isready -U postgres

# Test connection
docker-compose exec database psql -U postgres -d gherkin_tracker -c "SELECT 1;"
```

### Initialization Scripts Failed

```bash
# View initialization logs
docker-compose logs database | grep "init"

# Manual re-run (if needed)
docker-compose exec database psql -U postgres -d gherkin_tracker -f /database/schema.sql
```

## Production Deployment

For production use:

1. **Change default passwords** in `.env`
2. **Use Docker secrets** instead of environment variables
3. **Enable SSL/TLS** for PostgreSQL
4. **Set up regular backups** (automated pg_dump cron jobs)
5. **Monitor disk usage** for database volume
6. **Configure resource limits** in docker-compose.yml:

```yaml
services:
  database:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          memory: 2G
```

## Volume Management

```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect gherkin_tracker_db_data

# Backup volume
docker run --rm -v gherkin_tracker_db_data:/data -v $(pwd):/backup alpine tar czf /backup/db_backup.tar.gz /data

# Restore volume
docker run --rm -v gherkin_tracker_db_data:/data -v $(pwd):/backup alpine tar xzf /backup/db_backup.tar.gz -C /
```

## Network

The database runs on an isolated Docker network `gherkin_tracker_network`.

To connect other containers:

```yaml
services:
  my_app:
    networks:
      - gherkin_tracker_network
```

## Performance Tuning

Adjust PostgreSQL settings in `.env`:

```bash
POSTGRES_SHARED_BUFFERS=512MB
POSTGRES_EFFECTIVE_CACHE_SIZE=2GB
POSTGRES_WORK_MEM=32MB
POSTGRES_MAINTENANCE_WORK_MEM=256MB
POSTGRES_MAX_CONNECTIONS=200
```

Or mount custom `postgresql.conf`:

```yaml
volumes:
  - ./postgresql.conf:/etc/postgresql/postgresql.conf:ro
```

## Monitoring

View database statistics:

```bash
# Connection count
docker-compose exec database psql -U postgres -d gherkin_tracker -c "SELECT count(*) FROM pg_stat_activity;"

# Database size
docker-compose exec database psql -U postgres -d gherkin_tracker -c "SELECT pg_size_pretty(pg_database_size('gherkin_tracker'));"

# Table sizes
docker-compose exec database psql -U postgres -d gherkin_tracker -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```
