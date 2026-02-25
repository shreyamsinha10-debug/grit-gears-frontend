"""
One-time script: fix member phones that exceed 10 digits.
- Updates any member with phone "111111111111" to "1111111111"
- Updates any member with phone length > 10 to first 10 digits only (digits only)

Run from backend dir: python fix_phone_once.py
"""
import asyncio
import os

from motor.motor_asyncio import AsyncIOMotorClient

MONGODB_URL = os.environ.get(
    "MONGODB_URL",
    "mongodb+srv://gym_admin:8qxXOYKp1El0bw0B@clustergymadmin.zkcgd9b.mongodb.net/?appName=Clustergymadmin",
)
DATABASE_NAME = os.environ.get("DATABASE_NAME", "gym_db")
COLLECTION_MEMBERS = "gym_members"


def normalize_phone(s: str) -> str:
    digits = "".join(c for c in (s or "").strip() if c.isdigit())
    return digits[:10]


async def main():
    client = AsyncIOMotorClient(MONGODB_URL)
    coll = client[DATABASE_NAME][COLLECTION_MEMBERS]
    updated = 0
    async for doc in coll.find({}):
        phone = doc.get("phone") or ""
        if len(phone) > 10 or (phone and normalize_phone(phone) != phone):
            new_phone = normalize_phone(phone)
            if not new_phone:
                print(f"  Skip member {doc.get('_id')} (name={doc.get('name')}): phone has no digits")
                continue
            await coll.update_one(
                {"_id": doc["_id"]},
                {"$set": {"phone": new_phone}},
            )
            print(f"  Updated {doc.get('name')} ({doc.get('_id')}): {phone!r} -> {new_phone!r}")
            updated += 1
    print(f"Done. Updated {updated} member(s).")


if __name__ == "__main__":
    asyncio.run(main())
