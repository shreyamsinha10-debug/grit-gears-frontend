"""
Index management utilities for MongoDB collections.

The concrete index definitions will be added in Phase 4. For now this module
provides an async entrypoint that can be called from the FastAPI lifespan
without altering existing behaviour.
"""

from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.config import (
    COLLECTION_MEMBERS,
    COLLECTION_ATTENDANCE,
    COLLECTION_PAYMENTS,
    COLLECTION_INVOICES,
)


async def ensure_indexes(db: AsyncIOMotorDatabase) -> None:
    """
    Create the key indexes required for common query patterns. This function is
    idempotent and safe to call on every startup.
    """
    members = db[COLLECTION_MEMBERS]
    attendance = db[COLLECTION_ATTENDANCE]
    payments = db[COLLECTION_PAYMENTS]
    invoices = db[COLLECTION_INVOICES]
    member_documents = db["member_documents"]

    # Members: filter by gym_id + status, and login by phone + gym_id
    await members.create_index([("gym_id", 1), ("status", 1)], name="members_gym_status")
    await members.create_index(
        [("phone", 1), ("gym_id", 1)], name="members_phone_gym", unique=False, sparse=True
    )

    # Attendance: queries by member_id + date_ist (+ gym_id)
    await attendance.create_index(
        [("member_id", 1), ("date_ist", 1), ("gym_id", 1)],
        name="attendance_member_date_gym",
    )

    # Payments: common filters by gym_id + status, and member_id + period
    await payments.create_index(
        [("gym_id", 1), ("status", 1)], name="payments_gym_status"
    )
    await payments.create_index(
        [("member_id", 1), ("period", 1), ("gym_id", 1)],
        name="payments_member_period_gym",
    )

    # Invoices: history and overlap queries by member_id + date range
    await invoices.create_index(
        [("member_id", 1), ("issued_at", -1)], name="invoices_member_issued_at"
    )
    await invoices.create_index(
        [("member_id", 1), ("end_date", -1)], name="invoices_member_end_date"
    )

    # Member documents: lookup by member_id + gym_id
    await member_documents.create_index(
        [("member_id", 1), ("gym_id", 1)],
        name="member_documents_member_gym",
        unique=True,
    )


__all__ = ["ensure_indexes"]

