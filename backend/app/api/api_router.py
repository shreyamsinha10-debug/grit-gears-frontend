"""
Central API router that aggregates all feature routers.

All routers use no prefix so route paths match main.py (e.g. /members, /gym/profile, /super-admin/admins).
Auth routes are under prefix /auth (so /auth/login, /auth/owner-claim, /auth/forgot-password).
"""

from fastapi import APIRouter

from .routers import admin, attendance, auth, billing, documents, export, members, messages, payments

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(admin.router, tags=["admin", "gym", "super-admin", "analytics"])
api_router.include_router(members.router, tags=["members"])
api_router.include_router(documents.router, tags=["documents"])
api_router.include_router(attendance.router, tags=["attendance"])
api_router.include_router(payments.router, tags=["payments"])
api_router.include_router(billing.router, tags=["billing"])
api_router.include_router(messages.router, tags=["messages"])
api_router.include_router(export.router, tags=["export"])

__all__ = ["api_router"]
