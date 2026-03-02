"""
One-time script: CLEAR ALL GYM DATA (use with extreme caution).

Deletes ALL documents from:
- gyms
- gym_admins
- gym_members
- attendance_logs
- payments
- invoices
- messages
- app_config

Super admin is NOT stored in the database (it is env-based), so it will remain.

Usage:
1. Ensure MONGODB_URL and DATABASE_NAME point to the target database
   (e.g. production Railway DB for https://gymsaas-production-b4a0.up.railway.app).
2. From the backend folder, run:

       python clear_legacy_gym_data.py

3. Type YES when prompted to actually perform the deletion.
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
COLLECTION_ATTENDANCE = "attendance_logs"
COLLECTION_PAYMENTS = "payments"
COLLECTION_INVOICES = "invoices"
COLLECTION_GYMS = "gyms"
COLLECTION_GYM_ADMINS = "gym_admins"
COLLECTION_APP_CONFIG = "app_config"
COLLECTION_MESSAGES = "messages"


async def main():
    print("WARNING: This will DELETE ALL gym data from the database:")
    print(f"  MONGODB_URL = {MONGODB_URL}")
    print(f"  DATABASE_NAME = {DATABASE_NAME}")
    print("Collections affected: gyms, gym_admins, gym_members, attendance_logs, payments, invoices, messages, app_config")
    confirm = input("Type YES to continue: ").strip()
    if confirm != "YES":
        print("Aborted. No data was deleted.")
        return

    client = AsyncIOMotorClient(MONGODB_URL)
    db = client[DATABASE_NAME]

    members_collection = db[COLLECTION_MEMBERS]
    attendance_collection = db[COLLECTION_ATTENDANCE]
    payments_collection = db[COLLECTION_PAYMENTS]
    invoices_collection = db[COLLECTION_INVOICES]
    gyms_collection = db[COLLECTION_GYMS]
    gym_admins_collection = db[COLLECTION_GYM_ADMINS]
    app_config_collection = db[COLLECTION_APP_CONFIG]
    messages_collection = db[COLLECTION_MESSAGES]

    r_members = await members_collection.delete_many({})
    r_attendance = await attendance_collection.delete_many({})
    r_payments = await payments_collection.delete_many({})
    r_invoices = await invoices_collection.delete_many({})
    r_messages = await messages_collection.delete_many({})
    r_gym_admins = await gym_admins_collection.delete_many({})
    r_gyms = await gyms_collection.delete_many({})
    r_app_config = await app_config_collection.delete_many({})

    print("All gym data cleared.")
    print(f"  Members deleted:    {r_members.deleted_count}")
    print(f"  Attendance deleted: {r_attendance.deleted_count}")
    print(f"  Payments deleted:   {r_payments.deleted_count}")
    print(f"  Invoices deleted:   {r_invoices.deleted_count}")
    print(f"  Messages deleted:   {r_messages.deleted_count}")
    print(f"  Gym admins deleted: {r_gym_admins.deleted_count}")
    print(f"  Gyms deleted:       {r_gyms.deleted_count}")
    print(f"  App config deleted: {r_app_config.deleted_count}")

    client.close()


if __name__ == "__main__":
    asyncio.run(main())

