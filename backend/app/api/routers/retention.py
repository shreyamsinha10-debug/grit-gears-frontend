"""
Retention Alerts: identify active members with declining attendance (7+ days since last visit).
Read-only; does not modify any collections.
"""

from datetime import date, datetime

from app.core.auth import get_gym_admin
from app.db.database import members_collection
from app.models.schemas import RetentionAlertResponse
from app.utils.helpers import gym_filter, to_date
from app.utils.time_utils import today_ist
from fastapi import APIRouter, Depends

router = APIRouter()


def _reference_date(doc: dict) -> date:
    """Last attendance date if present, else created_at as date."""
    lad = doc.get("last_attendance_date")
    if lad is not None:
        d = to_date(lad)
        if d is not None:
            return d
    created = doc.get("created_at")
    if isinstance(created, datetime):
        return created.date()
    if isinstance(created, date):
        return created
    return today_ist()


def _risk_level(days: int) -> str:
    if days <= 14:
        return "Slipping"
    if days <= 30:
        return "High Risk"
    return "Critical"


@router.get("/retention-alerts", response_model=list[RetentionAlertResponse])
async def get_retention_alerts(gym_id: str = Depends(get_gym_admin)):
    """
    Return active members who have not visited for 7+ days, sorted by days since last visit (desc).
    Risk levels: 7–14 days Slipping, 15–30 High Risk, >30 Critical.
    """
    today = today_ist()
    q = {**gym_filter(gym_id), "status": "Active"}
    cursor = members_collection.find(q, {"_id": 1, "name": 1, "phone": 1, "last_attendance_date": 1, "created_at": 1})
    out: list[RetentionAlertResponse] = []
    async for doc in cursor:
        ref = _reference_date(doc)
        days = (today - ref).days
        if days < 7:
            continue
        out.append(
            RetentionAlertResponse(
                member_id=str(doc["_id"]),
                name=doc.get("name") or "",
                phone=doc.get("phone") or "",
                last_attendance_date=to_date(doc.get("last_attendance_date")),
                days_since_last_visit=days,
                risk_level=_risk_level(days),
            )
        )
    out.sort(key=lambda x: x.days_since_last_visit, reverse=True)
    return out
