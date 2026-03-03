"""
Database client and collections for the GymSaaS backend.

Single place for Motor client and collection references. Used by all routers and services.
"""

from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import (
    settings,
    COLLECTION_MEMBERS,
    COLLECTION_ATTENDANCE,
    COLLECTION_PAYMENTS,
    COLLECTION_INVOICES,
    COLLECTION_GYMS,
    COLLECTION_GYM_ADMINS,
    COLLECTION_APP_CONFIG,
    COLLECTION_MESSAGES,
)

client = AsyncIOMotorClient(settings.mongodb_url)
db = client[settings.database_name]

members_collection = db[COLLECTION_MEMBERS]
attendance_collection = db[COLLECTION_ATTENDANCE]
payments_collection = db[COLLECTION_PAYMENTS]
invoices_collection = db[COLLECTION_INVOICES]
gyms_collection = db[COLLECTION_GYMS]
gym_admins_collection = db[COLLECTION_GYM_ADMINS]
app_config_collection = db[COLLECTION_APP_CONFIG]
messages_collection = db[COLLECTION_MESSAGES]
member_documents_collection = db["member_documents"]

__all__ = [
    "client",
    "db",
    "members_collection",
    "attendance_collection",
    "payments_collection",
    "invoices_collection",
    "gyms_collection",
    "gym_admins_collection",
    "app_config_collection",
    "messages_collection",
    "member_documents_collection",
]
