"""
FastAPI application entrypoint for the GymSaaS backend.
"""

import asyncio
import json
import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path
from datetime import datetime, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.api.api_router import api_router
from app.core.config import settings
from app.db.database import (
    app_config_collection,
    attendance_collection,
    db,
    invoices_collection,
    members_collection,
    payments_collection,
)
from app.db.indexes import ensure_indexes
from app.tasks.attendance_tasks import run_auto_checkout
from app.utils.time_utils import today_ist

MIN_APP_VERSION = "1.0.0"

# #region agent log
def _debug_log(location: str, message: str, data: dict, hypothesis_id: str):
    payload = json.dumps({"sessionId": "1cf765", "location": location, "message": message, "data": data, "timestamp": int(time.time() * 1000), "hypothesisId": hypothesis_id}) + "\n"
    for log_path in [
        Path("/home/animesh/Documents/GymSaaS/.cursor/debug-1cf765.log"),
        Path(__file__).resolve().parent.parent / "debug-1cf765.log",
    ]:
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with open(log_path, "a") as f:
                f.write(payload)
            break
        except Exception:
            continue
# #endregion

# So email send/skip/fail is visible in the terminal when testing forgot-password
logging.basicConfig(level=logging.INFO)
logging.getLogger("app.utils.email").setLevel(logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """On startup: ensure indexes, optional backfill gym_id, mark 90-day inactive members."""
    from bson import ObjectId

    await ensure_indexes(db)

    cfg = await app_config_collection.find_one({"_id": "default_gym_id"})
    if cfg and cfg.get("value"):
        try:
            default_gym_id = ObjectId(cfg["value"])
            default_gym_id_str = str(default_gym_id)
            await members_collection.update_many(
                {"gym_id": {"$exists": False}},
                {"$set": {"gym_id": default_gym_id_str}},
            )
            await attendance_collection.update_many(
                {"gym_id": {"$exists": False}},
                {"$set": {"gym_id": default_gym_id_str}},
            )
            await payments_collection.update_many(
                {"gym_id": {"$exists": False}},
                {"$set": {"gym_id": default_gym_id_str}},
            )
            await invoices_collection.update_many(
                {"gym_id": {"$exists": False}},
                {"$set": {"gym_id": default_gym_id_str}},
            )
        except Exception:
            pass

    today = today_ist()
    cutoff = today - timedelta(days=90)
    from datetime import timezone

    cutoff_dt = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc)
    await members_collection.update_many(
        {"last_attendance_date": {"$exists": True, "$lt": cutoff_dt}},
        {"$set": {"status": "Inactive"}},
    )

    # Run auto check-out once at startup (then every interval)
    await run_auto_checkout()

    interval = settings.auto_checkout_interval_seconds

    async def auto_checkout_loop() -> None:
        while True:
            await asyncio.sleep(interval)
            try:
                await run_auto_checkout()
            except asyncio.CancelledError:
                break
            except Exception:
                pass  # Log and continue next interval

    auto_checkout_task = asyncio.create_task(auto_checkout_loop())
    try:
        yield
    finally:
        auto_checkout_task.cancel()
        try:
            await auto_checkout_task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Gym API", lifespan=lifespan)

raw_origins = (settings.allowed_origins or "").split(",")
allow_origins = [o.strip() for o in raw_origins if o.strip()]

# Allow any localhost / 127.0.0.1 origin (e.g. Flutter web on random port) so preflight succeeds
allow_origin_regex = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_origin_regex=allow_origin_regex,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class LocalhostCORSMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # #region agent log
        if request.url.path == "/auth/forgot-password" and request.method == "POST":
            _debug_log("main.py:middleware", "POST /auth/forgot-password received", {"path": request.url.path}, "E")
        # #endregion
        response = await call_next(request)
        origin = request.headers.get("origin")
        if origin and (
            origin.startswith("http://localhost:") or origin.startswith("http://127.0.0.1:")
        ):
            response.headers.setdefault("access-control-allow-origin", origin)
            response.headers.setdefault(
                "access-control-allow-methods", "GET, POST, PATCH, DELETE, OPTIONS"
            )
            response.headers.setdefault(
                "access-control-allow-headers", "Authorization, Content-Type"
            )
        return response


app.add_middleware(LocalhostCORSMiddleware)


@app.get("/")
def root():
    out = {"status": "success", "message": "Gym API is Live!"}
    if getattr(settings, "backend_label", None):
        out["backend"] = settings.backend_label
    return out


@app.get("/version")
def version():
    return {"min_app_version": MIN_APP_VERSION, "api_version": "1"}


app.include_router(api_router)

__all__ = ["app"]
