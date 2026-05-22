-- Agent OS: PostgreSQL initialization
-- Executed once on first container start (docker-entrypoint-initdb.d)

-- pgvector extension for embedding search
CREATE EXTENSION IF NOT EXISTS vector;

-- Dashboard metrics snapshot table (write from day 1 to preserve history)
CREATE TABLE IF NOT EXISTS dashboard_metrics (
    id SERIAL PRIMARY KEY,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    service TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    metric_value NUMERIC NOT NULL
);

CREATE INDEX idx_dashboard_metrics_time ON dashboard_metrics (recorded_at DESC);
CREATE INDEX idx_dashboard_metrics_service ON dashboard_metrics (service, metric_name);

-- Honcho schema: managed by Alembic migrations (auto on first start)
-- After Alembic creates tables with default 1536-dim vectors,
-- a post-migration step resizes to 768 for nomic-embed-text.
-- See config/honcho/fix-embedding-dims.sql

-- GBRAIN schema: uses PGLite by default (MVP), shared Postgres is optional
