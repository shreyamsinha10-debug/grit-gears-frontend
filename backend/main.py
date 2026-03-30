"""
Backend entry point: expose the canonical FastAPI app from app.main.

The monolith (route handlers) has been moved to app.api.routers; this module
only re-exports the app so that "uvicorn backend.main:app" and imports of
backend.main.app continue to work.
"""

from app.main import app

__all__ = ["app"]
