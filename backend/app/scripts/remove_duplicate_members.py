"""
One-off script: remove duplicate members (same phone + gym_id), keeping the oldest per group.
Cascade-deletes attendance, payments, invoices, member_documents for each duplicate, then deletes the member.

Run from repo root: python -m app.scripts.remove_duplicate_members
Or from backend: python -m app.scripts.remove_duplicate_members
"""
import asyncio
import logging
import sys

from bson import ObjectId

from app.db.database import (
    attendance_collection,
    invoices_collection,
    members_collection,
    member_documents_collection,
    payments_collection,
)
from app.utils.helpers import gym_filter

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


async def delete_member_and_related(member_id: str, gym_id: str) -> None:
    """Cascade delete then remove member (same logic as DELETE /members/{id})."""
    gfilter = gym_filter(gym_id)
    await attendance_collection.delete_many({**gfilter, "member_id": member_id})
    await payments_collection.delete_many({**gfilter, "member_id": member_id})
    await invoices_collection.delete_many({**gfilter, "member_id": member_id})
    await member_documents_collection.delete_many({"member_id": member_id, **gfilter})
    await members_collection.delete_one({"_id": ObjectId(member_id)})


async def run() -> None:
    # Find (phone, gym_id) groups with more than one member
    pipeline = [
        {"$match": {"phone": {"$exists": True, "$ne": None, "$ne": ""}}},
        {"$group": {"_id": {"phone": "$phone", "gym_id": "$gym_id"}, "count": {"$sum": 1}, "docs": {"$push": {"_id": "$_id", "created_at": "$created_at"}}}},
        {"$match": {"count": {"$gt": 1}}},
    ]
    cursor = members_collection.aggregate(pipeline)
    duplicates = []
    async for row in cursor:
        duplicates.append(row)

    if not duplicates:
        logger.info("No duplicate (phone, gym_id) members found.")
        return

    logger.info("Found %d duplicate group(s). Keeping oldest member per group, removing the rest.", len(duplicates))
    removed = 0
    for row in duplicates:
        key = row["_id"]
        phone, gym_id = key["phone"], str(key["gym_id"])
        docs = sorted(row["docs"], key=lambda d: (d.get("created_at") or 0))
        # Keep first (oldest), remove the rest
        to_remove = docs[1:]
        for d in to_remove:
            mid = str(d["_id"])
            logger.info("  Removing duplicate member id=%s (phone=%s, gym_id=%s)", mid, phone, gym_id)
            await delete_member_and_related(mid, gym_id)
            removed += 1
    logger.info("Done. Removed %d duplicate member(s).", removed)


def main() -> None:
    try:
        asyncio.run(run())
    except Exception as e:
        logger.exception("%s", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
