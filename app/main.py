import psycopg
from fastapi import FastAPI, HTTPException
from app.config import DATABASE_URL, get_redis
app = FastAPI()
@app.get("/health")
def health():
    return {"status": "ok"}
@app.get("/ready")
def ready():
    try:
        get_redis(2).ping()
        with psycopg.connect(DATABASE_URL, connect_timeout=2) as conn:
            conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Dependency unavailable") from exc