"""
FastAPI application entrypoint for the GymSaaS backend.

This is the canonical app: lifespan, CORS, health routes, and the aggregated API router.
All feature routes live under app.api.routers and are mounted via api_router.
"""

from contextlib import asynccontextmanager
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
from app.utils.time_utils import today_ist

MIN_APP_VERSION = "1.0.0"


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
    yield


app = FastAPI(title="Gym API", lifespan=lifespan)

raw_origins = (settings.allowed_origins or "").split(",")
allow_origins = [o.strip() for o in raw_origins if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class LocalhostCORSMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
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
