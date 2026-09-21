import psycopg
from app.config import DATABASE_URL
with psycopg.connect(DATABASE_URL, connect_timeout=5) as conn:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS job_audit "
        "(id SERIAL PRIMARY KEY, job_name TEXT NOT NULL, "
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
    )
print("Migration completed successfully")