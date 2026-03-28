"""
Shared helpers for gym scoping, date conversion, member response building, and pricing.
"""

from datetime import date, datetime

from bson import ObjectId
from bson.errors import InvalidId

from app.core.config import MONTHLY_FEE_REGULAR, MONTHLY_FEE_PT
from app.db.database import (
    gyms_collection,
    member_documents_collection,
    members_collection,
)
from app.models import schemas
from app.utils.time_utils import today_ist


def gym_filter(gym_id: str) -> dict:
    """Return a query dict to filter by gym_id (matches both string and ObjectId in DB)."""
    try:
        oid = ObjectId(gym_id)
        return {"gym_id": {"$in": [gym_id, oid]}}
    except InvalidId:
        return {"gym_id": gym_id}


def to_date(v) -> date | None:
    """Convert datetime to date for API; handle datetime, date, or YYYY-MM-DD string."""
    if v is None:
        return None
    if hasattr(v, "date") and callable(getattr(v, "date")):
        return v.date()
    if isinstance(v, str) and len(v) >= 10:
        try:
            return datetime.strptime(v[:10], "%Y-%m-%d").date()
        except ValueError:
            pass
    return v


async def doc_to_member_response(
    doc: dict,
    include_photos: bool = True,
    include_avatar_only: bool = False,
    attendance_map: dict | None = None,
) -> schemas.MemberResponse:
    """Build MemberResponse from a member doc, optionally loading photo/id_doc from member_documents."""
    today_status = None
    if attendance_map:
        mid = str(doc["_id"])
        if mid in attendance_map:
            rec = attendance_map[mid]
            today_status = schemas.TodayAttendance(
                checked_in=True,
                checked_out=bool(rec.get("check_out_at_ist")),
                check_in_time=rec.get("check_in_at_ist"),
                check_out_time=rec.get("check_out_at_ist"),
            )

    include_photo = include_photos or include_avatar_only
    include_id_doc = include_photos and not include_avatar_only

    photo_base64 = None
    id_document_base64 = None
    id_document_type = None

    if include_photo or include_id_doc:
        mid = str(doc["_id"])
        gid = str(doc.get("gym_id") or "")
        media_doc = await member_documents_collection.find_one({"member_id": mid, "gym_id": gid})
        if media_doc:
            photo_base64 = media_doc.get("photo_base64")
            id_document_base64 = media_doc.get("id_document_base64")
            id_document_type = media_doc.get("id_document_type")
        else:
            photo_base64 = doc.get("photo_base64")
            id_document_base64 = doc.get("id_document_base64")
            id_document_type = doc.get("id_document_type")
    else:
        photo_base64 = None
        id_document_base64 = None
        id_document_type = None

    return schemas.MemberResponse(
        id=str(doc["_id"]),
        name=doc["name"],
        phone=doc["phone"],
        email=doc["email"],
        membership_type=doc["membership_type"] if isinstance(doc["membership_type"], str) else getattr(doc["membership_type"], "value", doc["membership_type"]),
        batch=doc["batch"] if isinstance(doc.get("batch"), str) else getattr(doc.get("batch"), "value", doc.get("batch", "")),
        status=doc.get("status", "Active"),
        created_at=doc["created_at"],
        last_attendance_date=to_date(doc.get("last_attendance_date")),
        address=doc.get("address"),
        date_of_birth=to_date(doc.get("date_of_birth")),
        gender=doc.get("gender"),
        workout_schedule=doc.get("workout_schedule"),
        diet_chart=doc.get("diet_chart"),
        photo_base64=photo_base64 if include_photo else None,
        id_document_base64=id_document_base64 if include_id_doc else None,
        id_document_type=id_document_type if include_id_doc else None,
        plan_id=doc.get("plan_id"),
        today_status=today_status,
    )


async def resolve_monthly_fee(gym_id: str, membership_type: str) -> int:
    """
    Resolve the monthly fee for a member based on the gym's active membership
    plans. Falls back to the legacy fixed fees when no suitable plan exists.
    """
    try:
        oid = ObjectId(gym_id)
    except InvalidId:
        return MONTHLY_FEE_PT if membership_type == "PT" else MONTHLY_FEE_REGULAR

    gym = await gyms_collection.find_one({"_id": oid})
    plans = (gym or {}).get("plans") or []
    mt = str(membership_type)

    for p in plans:
        if not isinstance(p, dict):
            continue
        if not p.get("is_active", True):
            continue
        if str(p.get("duration_type")) != "1m":
            continue
        return int(p.get("price", 0) or 0) or (MONTHLY_FEE_PT if mt == "PT" else MONTHLY_FEE_REGULAR)

    return MONTHLY_FEE_PT if mt == "PT" else MONTHLY_FEE_REGULAR


__all__ = ["gym_filter", "to_date", "doc_to_member_response", "resolve_monthly_fee"]
