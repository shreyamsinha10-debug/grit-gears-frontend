"""
Index management utilities for MongoDB collections.

The concrete index definitions will be added in Phase 4. For now this module
provides an async entrypoint that can be called from the FastAPI lifespan
without altering existing behaviour.
"""

import logging

from pymongo.errors import OperationFailure

from motor.motor_asyncio import AsyncIOMotorDatabase

logger = logging.getLogger(__name__)

from app.core.config import (
    COLLECTION_MEMBERS,
    COLLECTION_ATTENDANCE,
    COLLECTION_PAYMENTS,
    COLLECTION_INVOICES,
    COLLECTION_EXPENSES,
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
    expenses = db[COLLECTION_EXPENSES]

    # Members: filter by gym_id + status, and login by phone + gym_id
    await members.create_index([("gym_id", 1), ("status", 1)], name="members_gym_status")
    # Phone unique per gym: no duplicate members with same phone in one gym
    try:
        await members.create_index(
            [("phone", 1), ("gym_id", 1)], name="members_phone_gym", unique=True, sparse=True
        )
    except OperationFailure as e:
        if e.code == 86:  # IndexKeySpecsConflict: same name, different options (e.g. old non-unique)
            await members.drop_index("members_phone_gym")
            try:
                await members.create_index(
                    [("phone", 1), ("gym_id", 1)], name="members_phone_gym", unique=True, sparse=True
                )
            except OperationFailure as e2:
                if e2.code == 11000:  # DuplicateKey: collection has duplicate (phone, gym_id)
                    logger.warning(
                        "members_phone_gym: cannot create unique index due to duplicate phone numbers. "
                        "Recreating non-unique index so app can start. Fix duplicates then restart."
                    )
                    await members.create_index(
                        [("phone", 1), ("gym_id", 1)], name="members_phone_gym", unique=False, sparse=True
                    )
                else:
                    raise
        elif e.code == 11000:  # DuplicateKey on first create (e.g. after manual drop)
            logger.warning(
                "members_phone_gym: duplicate phone numbers exist. Using non-unique index."
            )
            await members.create_index(
                [("phone", 1), ("gym_id", 1)], name="members_phone_gym", unique=False, sparse=True
            )
        else:
            raise

    # Attendance: queries by member_id + date_ist (+ gym_id)
    await attendance.create_index(
        [("member_id", 1), ("date_ist", 1), ("gym_id", 1)],
        name="attendance_member_date_gym",
    )
    # Auto check-out: find today's open check-ins older than 2h
    await attendance.create_index(
        [("date_ist", 1), ("check_in_at_utc", 1)],
        name="attendance_date_checkin_autocheckout",
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

    # Expenses: list by gym_id and expense_date (for balance-sheet and list by month)
    await expenses.create_index(
        [("gym_id", 1), ("expense_date", -1)],
        name="expenses_gym_date",
    )


__all__ = ["ensure_indexes"]

