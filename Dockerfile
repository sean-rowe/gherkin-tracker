# Dockerfile for Gherkin Tracker PostgreSQL Database
FROM postgres:17-alpine

# Install additional tools
RUN apk add --no-cache \
    bash \
    curl

# Set environment variables
ENV POSTGRES_DB=gherkin_tracker
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres

# Create directory for initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy database schema and migration scripts
COPY database/schema.sql /docker-entrypoint-initdb.d/01-schema.sql
COPY database/scripts/01-create-project-database.sql /docker-entrypoint-initdb.d/02-project-database.sql
COPY database/scripts/02-create-project-schema.sql /docker-entrypoint-initdb.d/03-project-schema.sql
COPY database/scripts/03-add-task-dependencies.sql /docker-entrypoint-initdb.d/04-task-dependencies.sql
COPY database/scripts/04-add-pr-management.sql /docker-entrypoint-initdb.d/05-pr-management.sql

# Expose PostgreSQL port
EXPOSE 5432

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U postgres -d gherkin_tracker || exit 1

# The postgres image already has a default CMD that runs postgres
# /docker-entrypoint-initdb.d scripts will run automatically on first start
