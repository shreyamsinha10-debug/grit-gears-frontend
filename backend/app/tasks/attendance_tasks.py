"""
Auto check-out: close attendance records where member checked in >2 hours ago and never checked out.
Runs once at startup and then periodically from app lifespan.
All stored times follow existing convention: *_at_ist in IST (Asia/Kolkata) as isoformat string,
*_at_utc as UTC datetime.
"""

from datetime import datetime, timedelta, timezone

from app.db.database import attendance_collection
from app.utils.time_utils import IST, today_ist


AUTO_CHECKOUT_HOURS = 2
"""After this many hours from check-in, open attendance is auto-checked out."""


def _get_check_in_utc(doc: dict) -> datetime | None:
    """Return check-in time as UTC datetime from an attendance doc."""
    ci = doc.get("check_in_at_utc")
    if ci is not None:
        if hasattr(ci, "tzinfo") and ci.tzinfo is None:
            return ci.replace(tzinfo=timezone.utc)
        return ci.astimezone(timezone.utc) if hasattr(ci, "astimezone") else ci
    raw = doc.get("check_in_at_ist")
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=IST)
        return dt.astimezone(timezone.utc)
    except (ValueError, TypeError):
        return None


async def run_auto_checkout() -> int:
    """
    Find today's attendance records that have check-in but no check-out and are older than 2 hours.
    Set check_out to check_in + 2 hours (so session duration is exactly 2 hours).
    Returns the number of records updated.
    """
    now_utc = datetime.now(timezone.utc)
    cutoff_utc = now_utc - timedelta(hours=AUTO_CHECKOUT_HOURS)

    # Open check-ins: no check-out set, check-in before cutoff, and today's date (IST)
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    has_no_checkout = {
        "$or": [
            {"check_out_at_ist": {"$exists": False}},
            {"check_out_at_ist": None},
            {"check_out_at_ist": ""},
        ]
    }
    query = {
        **has_no_checkout,
        "date_ist": date_ist_str,
        "check_in_at_utc": {"$lt": cutoff_utc},
    }

    updated = 0
    cursor = attendance_collection.find(query)
    async for doc in cursor:
        check_in_utc = _get_check_in_utc(doc)
        if check_in_utc is None:
            continue
        check_out_utc = check_in_utc + timedelta(hours=AUTO_CHECKOUT_HOURS)
        check_out_ist_dt = check_out_utc.astimezone(IST)  # IST for storage, same as check-in/check-out endpoints

        await attendance_collection.update_one(
            {"_id": doc["_id"]},
            {
                "$set": {
                    "check_out_at_ist": check_out_ist_dt.isoformat(),  # IST (Asia/Kolkata)
                    "check_out_at_utc": check_out_utc,
                }
            },
        )
        updated += 1

    return updated
