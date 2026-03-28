"""
Create new monthly Due rows when a member's last paid invoice period has ended (by end_date)
and today is no longer covered by any Paid invoice — without duplicating current-month dues.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId

from app.db.database import gyms_collection, invoices_collection, members_collection, payments_collection
from app.utils.helpers import gym_filter, resolve_monthly_fee
from app.utils.time_utils import IST, today_ist

logger = logging.getLogger(__name__)


def _as_utc_aware(dt: datetime | None) -> datetime | None:
    """MongoDB often returns naive datetimes (stored as UTC); make them comparable to aware UTC."""
    if dt is None:
        return None
    if getattr(dt, "tzinfo", None) is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _utc_range_for_ist_calendar_day(d) -> tuple[datetime, datetime]:
    start = datetime(d.year, d.month, d.day, 0, 0, 0, tzinfo=IST)
    end = datetime(d.year, d.month, d.day, 23, 59, 59, 999999, tzinfo=IST)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


async def _invoice_covers_today_ist(member_id: str, gym_id: str, today_d) -> bool:
    start_utc, end_utc = _utc_range_for_ist_calendar_day(today_d)
    q = {
        "member_id": member_id,
        "status": "Paid",
        **gym_filter(gym_id),
        "$or": [
            {
                "$and": [
                    {"end_date": {"$exists": True, "$ne": None}},
                    {"paid_at": {"$lte": end_utc}},
                    {"end_date": {"$gte": start_utc}},
                ]
            },
            {
                "$and": [
                    {"$or": [{"end_date": {"$exists": False}}, {"end_date": None}]},
                    {"paid_at": {"$gte": start_utc, "$lte": end_utc}},
                ]
            },
        ],
    }
    return bool(await invoices_collection.find_one(q))


async def _recurring_monthly_fee_amount(member: dict, gym_id: str) -> int | None:
    """Monthly fee for a new Due, or None if member is on a one-time / non-recurring plan."""
    pid = member.get("plan_id")
    if pid and str(pid).strip():
        try:
            oid = ObjectId(gym_id)
        except InvalidId:
            oid = None
        gym = await gyms_collection.find_one({"_id": oid}) if oid else None
        if gym:
            for p in gym.get("plans") or []:
                if not isinstance(p, dict):
                    continue
                if str(p.get("id", "")) != str(pid).strip():
                    continue
                if str(p.get("duration_type", "")) == "one_time":
                    return None
                price = int(p.get("price", 0) or 0)
                return price if price > 0 else None
    mt = member.get("membership_type")
    if not isinstance(mt, str):
        mt = getattr(mt, "value", None) or "Regular"
    amt = await resolve_monthly_fee(gym_id, str(mt))
    return int(amt) if amt and amt > 0 else None


async def run_monthly_due_renewal() -> int:
    """
    For each member with a Paid invoice that has end_date before today (IST), if they are Active,
    not covered by any Paid invoice for today, and have no Due/Overdue for the current calendar
    month (period YYYY-MM), insert one new Due for the recurring monthly amount.
    """
    today_d = today_ist()
    period = today_d.strftime("%Y-%m")
    start_today_utc = datetime(today_d.year, today_d.month, today_d.day, tzinfo=IST).astimezone(timezone.utc)

    pipeline = [
        {"$match": {"status": "Paid", "end_date": {"$exists": True, "$ne": None}}},
        {"$group": {"_id": "$member_id", "max_end": {"$max": "$end_date"}, "gym_id": {"$first": "$gym_id"}}},
    ]

    inserted = 0
    async for row in invoices_collection.aggregate(pipeline):
        mid = row.get("_id")
        gym_id = row.get("gym_id")
        max_end = row.get("max_end")
        if not mid or not gym_id or max_end is None:
            continue
        max_end_utc = _as_utc_aware(max_end) if isinstance(max_end, datetime) else None
        if max_end_utc is None:
            continue
        if max_end_utc >= start_today_utc:
            continue

        try:
            moid = ObjectId(mid)
        except InvalidId:
            continue

        member = await members_collection.find_one({"_id": moid, **gym_filter(str(gym_id))})
        if not member:
            continue
        if (member.get("status") or "Active") != "Active":
            continue

        if await _invoice_covers_today_ist(str(mid), str(gym_id), today_d):
            continue

        existing = await payments_collection.find_one(
            {
                "member_id": str(mid),
                "period": period,
                "status": {"$in": ["Due", "Overdue"]},
                **gym_filter(str(gym_id)),
            }
        )
        if existing:
            continue

        fee = await _recurring_monthly_fee_amount(member, str(gym_id))
        if fee is None or fee <= 0:
            continue

        due_dt = start_today_utc
        await payments_collection.insert_one(
            {
                "member_id": str(mid),
                "member_name": member.get("name", ""),
                "amount": fee,
                "fee_type": "monthly",
                "period": period,
                "status": "Due",
                "due_date": due_dt,
                "paid_at": None,
                "created_at": datetime.now(timezone.utc),
                "gym_id": str(gym_id),
            }
        )
        inserted += 1

    if inserted:
        logger.info("Monthly due renewal: inserted %s new Due row(s) for period %s", inserted, period)
    return inserted


__all__ = ["run_monthly_due_renewal"]
