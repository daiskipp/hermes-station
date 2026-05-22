#!/bin/sh
set -e

echo "Running database migrations..."
/app/.venv/bin/python scripts/provision_db.py

# Fix embedding dimensions for Ollama nomic-embed-text (768d)
# Honcho's Alembic creates vector(1536) by default (OpenAI).
# This idempotent fix resizes to match EMBEDDING_VECTOR_DIMENSIONS.
DIMS="${EMBEDDING_VECTOR_DIMENSIONS:-768}"
echo "Fixing embedding dimensions to ${DIMS}..."
/app/.venv/bin/python -c "
import os, sqlalchemy
uri = os.environ['DB_CONNECTION_URI']
engine = sqlalchemy.create_engine(uri)
with engine.connect() as conn:
    for table, col in [('documents', 'embedding'), ('message_embeddings', 'embedding')]:
        try:
            result = conn.execute(sqlalchemy.text(
                f\"SELECT atttypmod FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid WHERE c.relname = '{table}' AND a.attname = '{col}'\"
            ))
            row = result.fetchone()
            if row and row[0] != int('${DIMS}') + 4:  # typmod = dims + 4 for vector
                conn.execute(sqlalchemy.text(f'ALTER TABLE {table} DROP COLUMN IF EXISTS {col}'))
                conn.execute(sqlalchemy.text(f'ALTER TABLE {table} ADD COLUMN {col} vector(${DIMS})'))
                conn.commit()
                print(f'  Fixed {table}.{col} to vector(${DIMS})')
            else:
                print(f'  {table}.{col} already correct')
        except Exception as e:
            print(f'  Warning: {table}.{col} fix skipped: {e}')
            conn.rollback()
"

echo "Starting API server..."
exec /app/.venv/bin/fastapi run --host 0.0.0.0 src/main.py
