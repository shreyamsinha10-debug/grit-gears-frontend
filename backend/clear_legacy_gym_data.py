"""
One-time script: remove all data for the legacy admin (9999999999) / Default (Legacy) gym.
Run from backend folder: python clear_legacy_gym_data.py
Uses same MONGODB_URL and DATABASE_NAME as main.py. Keeps the default gym document
so 9999999999 can still log in with an empty slate.
"""

import asyncio
import os

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient

MONGODB_URL = os.environ.get(
    "MONGODB_URL",
    "mongodb+srv://gym_admin:8qxXOYKp1El0bw0B@clustergymadmin.zkcgd9b.mongodb.net/?appName=Clustergymadmin",
)
DATABASE_NAME = os.environ.get("DATABASE_NAME", "gym_db")

COLLECTION_MEMBERS = "gym_members"
COLLECTION_ATTENDANCE = "attendance_logs"
COLLECTION_PAYMENTS = "payments"
COLLECTION_INVOICES = "invoices"
COLLECTION_GYMS = "gyms"
COLLECTION_APP_CONFIG = "app_config"


async def main():
    client = AsyncIOMotorClient(MONGODB_URL)
    db = client[DATABASE_NAME]
    app_config = db[COLLECTION_APP_CONFIG]
    members_collection = db[COLLECTION_MEMBERS]
    attendance_collection = db[COLLECTION_ATTENDANCE]
    payments_collection = db[COLLECTION_PAYMENTS]
    invoices_collection = db[COLLECTION_INVOICES]
    gyms_collection = db[COLLECTION_GYMS]

    # Resolve default (legacy) gym id
    cfg = await app_config.find_one({"_id": "default_gym_id"})
    if not cfg or not cfg.get("value"):
        default_gym = await gyms_collection.find_one({"name": "Default (Legacy)"})
        if not default_gym:
            print("No Default (Legacy) gym found. Nothing to clear.")
            client.close()
            return
        default_gym_id = default_gym["_id"]
    else:
        try:
            default_gym_id = ObjectId(cfg["value"])
        except Exception:
            print("default_gym_id in app_config is not a valid ObjectId. Exiting.")
            client.close()
            return

    default_gym_id_str = str(default_gym_id)
    # Match both string and ObjectId gym_id (legacy data may have either)
    gym_filter = {"gym_id": {"$in": [default_gym_id_str, default_gym_id]}}

    r_members = await members_collection.delete_many(gym_filter)
    r_attendance = await attendance_collection.delete_many(gym_filter)
    r_payments = await payments_collection.delete_many(gym_filter)
    r_invoices = await invoices_collection.delete_many(gym_filter)

    print("Legacy gym data cleared (Default (Legacy) / 9999999999):")
    print(f"  Members deleted:    {r_members.deleted_count}")
    print(f"  Attendance deleted:  {r_attendance.deleted_count}")
    print(f"  Payments deleted:   {r_payments.deleted_count}")
    print(f"  Invoices deleted:   {r_invoices.deleted_count}")
    print("Legacy admin 9999999999 can log in with an empty slate.")
    client.close()


if __name__ == "__main__":
    asyncio.run(main())
