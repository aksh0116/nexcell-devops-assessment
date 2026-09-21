import signal
from app.config import get_redis
redis_client = get_redis()
stopping = False
def stop(*_):
    global stopping
    stopping = True
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
while not stopping:
    item = redis_client.brpop("jobs", timeout=5)
    if item:
        _, job = item
        print(f"Processed job: {job}", flush=True)
        redis_client.set("worker:last_job", job)