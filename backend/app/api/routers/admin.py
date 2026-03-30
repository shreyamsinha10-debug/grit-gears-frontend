"""
Admin router: gym profile, super-admin admins, admin helpers, analytics dashboard.
"""

from datetime import datetime, timedelta, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, HTTPException
from app.core.auth import get_current_user_payload, get_gym_admin, get_super_admin
from app.core.security import _pwd_fallback, pwd_context
from app.db.database import (
    attendance_collection,
    gym_admins_collection,
    gyms_collection,
    members_collection,
    payments_collection,
)
from app.models.schemas import (
    GymProfileResponse,
    GymProfileUpdate,
    SuperAdminAdminListItem,
    SuperAdminCreateAdminBody,
    SuperAdminPatchAdminBody,
    SuperAdminResetPasswordBody,
)
from app.utils.helpers import gym_filter
from app.utils.notifications import send_notification
from app.utils.time_utils import today_ist

router = APIRouter()


def _require_super_admin(payload: dict = Depends(get_current_user_payload)):
    return get_super_admin(payload=payload)


async def _gym_doc_from_gym_id(gym_id: str):
    try:
        oid = ObjectId(gym_id)
    except InvalidId:
        return None
    return await gyms_collection.find_one({"_id": oid})


def _serialize_batches(batches):
    out = []
    for b in batches or []:
        if isinstance(b, dict):
            out.append({
                "id": str(b.get("id", "")),
                "name": str(b.get("name", "")),
                "description": b.get("description") if b.get("description") is None else str(b.get("description", "")),
                "start_time": b.get("start_time") if b.get("start_time") is None else str(b.get("start_time", "")),
                "end_time": b.get("end_time") if b.get("end_time") is None else str(b.get("end_time", "")),
            })
        else:
            out.append({"id": "", "name": "", "description": None, "start_time": None, "end_time": None})
    return out


def _serialize_plans(plans):
    out = []
    for p in plans or []:
        if isinstance(p, dict):
            out.append({
                "id": str(p.get("id", "")),
                "name": str(p.get("name", "")),
                "description": p.get("description") if p.get("description") is None else str(p.get("description", "")),
                "price": int(p.get("price", 0)),
                "duration_type": str(p.get("duration_type", "1m")),
                "is_active": bool(p.get("is_active", True)),
                "registration_fee": int(p["registration_fee"]) if p.get("registration_fee") is not None else None,
                "waive_registration_fee": bool(p.get("waive_registration_fee", False)),
            })
        else:
            out.append({"id": "", "name": "", "description": None, "price": 0, "duration_type": "1m", "is_active": True, "registration_fee": None, "waive_registration_fee": False})
    return out


# ---------- Gym profile ----------

@router.get("/gym/profile", response_model=GymProfileResponse)
async def get_gym_profile(gym_id: str = Depends(get_gym_admin)):
    gym = await _gym_doc_from_gym_id(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    return GymProfileResponse(
        id=str(gym["_id"]),
        name=gym.get("name", ""),
        logo_base64=gym.get("logo_base64"),
        invoice_name=gym.get("invoice_name"),
        address_line1=gym.get("address_line1"),
        address_line2=gym.get("address_line2"),
        city=gym.get("city"),
        state=gym.get("state"),
        pin_code=gym.get("pin_code"),
        phone=gym.get("phone"),
        terms_and_conditions=gym.get("terms_and_conditions"),
        batches=_serialize_batches(gym.get("batches")),
        plans=_serialize_plans(gym.get("plans")),
    )


@router.patch("/gym/profile", response_model=GymProfileResponse)
async def update_gym_profile(body: GymProfileUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(gym_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid gym ID")
    gym = await gyms_collection.find_one({"_id": oid})
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    set_fields = {}
    unset_fields = {}
    if body.name is not None and body.name.strip():
        set_fields["name"] = body.name.strip()
    if body.logo_base64 is not None:
        if body.logo_base64:
            set_fields["logo_base64"] = body.logo_base64
        else:
            unset_fields["logo_base64"] = ""
    if body.invoice_name is not None:
        if body.invoice_name and body.invoice_name.strip():
            set_fields["invoice_name"] = body.invoice_name.strip()
        else:
            unset_fields["invoice_name"] = ""
    if body.address_line1 is not None:
        set_fields["address_line1"] = (body.address_line1 or "").strip() or None
    if body.address_line2 is not None:
        set_fields["address_line2"] = (body.address_line2 or "").strip() or None
    if body.city is not None:
        set_fields["city"] = (body.city or "").strip() or None
    if body.state is not None:
        set_fields["state"] = (body.state or "").strip() or None
    if body.pin_code is not None:
        set_fields["pin_code"] = (body.pin_code or "").strip() or None
    if body.phone is not None:
        set_fields["phone"] = (body.phone or "").strip() or None
    if body.terms_and_conditions is not None:
        set_fields["terms_and_conditions"] = (body.terms_and_conditions or "").strip() or None
    if body.batches is not None:
        batches_out = []
        for b in body.batches:
            bid = (b.id or "").strip() or str(ObjectId())
            batches_out.append({
                "id": bid,
                "name": (b.name or "").strip(),
                "description": (b.description or "").strip() or None,
                "start_time": (b.start_time or "").strip() or None,
                "end_time": (b.end_time or "").strip() or None,
            })
        set_fields["batches"] = batches_out
    if body.plans is not None:
        plans_out = []
        for p in body.plans:
            pid = (p.id or "").strip() or str(ObjectId())
            plans_out.append({
                "id": pid,
                "name": (p.name or "").strip(),
                "description": (p.description or "").strip() or None,
                "price": p.price,
                "duration_type": p.duration_type,
                "is_active": p.is_active,
                "registration_fee": p.registration_fee,
                "waive_registration_fee": p.waive_registration_fee,
            })
        set_fields["plans"] = plans_out
    if set_fields or unset_fields:
        update_op = {}
        if set_fields:
            update_op["$set"] = set_fields
        if unset_fields:
            update_op["$unset"] = unset_fields
        await gyms_collection.update_one({"_id": oid}, update_op)
    updated = await gyms_collection.find_one({"_id": oid})
    batches = updated.get("batches") or []
    plans = updated.get("plans") or []
    plans_ser = []
    for p in plans:
        if isinstance(p, dict):
            plans_ser.append({
                "id": str(p.get("id", "")),
                "name": str(p.get("name", "")),
                "description": p.get("description"),
                "price": int(p.get("price", 0)),
                "duration_type": str(p.get("duration_type", "1m")),
                "is_active": bool(p.get("is_active", True)),
                "registration_fee": int(p["registration_fee"]) if p.get("registration_fee") is not None else None,
                "waive_registration_fee": bool(p.get("waive_registration_fee", False)),
            })
        else:
            plans_ser.append({"id": "", "name": "", "description": None, "price": 0, "duration_type": "1m", "is_active": True, "registration_fee": None, "waive_registration_fee": False})
    return GymProfileResponse(
        id=str(updated["_id"]),
        name=updated.get("name", ""),
        logo_base64=updated.get("logo_base64"),
        invoice_name=updated.get("invoice_name"),
        address_line1=updated.get("address_line1"),
        address_line2=updated.get("address_line2"),
        city=updated.get("city"),
        state=updated.get("state"),
        pin_code=updated.get("pin_code"),
        phone=updated.get("phone"),
        terms_and_conditions=updated.get("terms_and_conditions"),
        batches=[{"id": b.get("id", ""), "name": b.get("name", ""), "description": b.get("description"), "start_time": b.get("start_time"), "end_time": b.get("end_time")} for b in batches],
        plans=plans_ser,
    )


# ---------- Super Admin ----------

@router.get("/super-admin/admins", response_model=list[SuperAdminAdminListItem])
async def super_admin_list_admins(_: dict = Depends(_require_super_admin)):
    from app.utils.time_utils import now_ist
    cursor = gym_admins_collection.find().sort("created_at", -1)
    out = []
    async for doc in cursor:
        gym_id = doc.get("gym_id")
        gym_name = ""
        if gym_id:
            g = await gyms_collection.find_one({"_id": gym_id})
            if g:
                gym_name = g.get("name", "")
        out.append(SuperAdminAdminListItem(
            id=str(doc["_id"]),
            gym_id=str(gym_id) if gym_id else "",
            gym_name=gym_name,
            login_id=doc.get("login_id", ""),
            is_active=bool(doc.get("is_active", True)),
            created_at=doc.get("created_at", now_ist()),
        ))
    return out


@router.post("/super-admin/admins", response_model=SuperAdminAdminListItem)
async def super_admin_create_admin(body: SuperAdminCreateAdminBody, _: dict = Depends(_require_super_admin)):
    existing = await gym_admins_collection.find_one({"login_id": body.admin_login_id.strip()})
    if existing:
        raise HTTPException(status_code=400, detail="Login ID already in use")
    gym_doc = {"name": body.gym_name.strip(), "created_at": datetime.now(timezone.utc)}
    gym_result = await gyms_collection.insert_one(gym_doc)
    gym_id = gym_result.inserted_id
    try:
        password_hash = pwd_context.hash(body.admin_password)
    except Exception:
        password_hash = _pwd_fallback.hash(body.admin_password)
    admin_doc = {
        "gym_id": gym_id,
        "login_id": body.admin_login_id.strip(),
        "password_hash": password_hash,
        "is_active": True,
        "created_at": datetime.now(timezone.utc),
    }
    admin_result = await gym_admins_collection.insert_one(admin_doc)
    return SuperAdminAdminListItem(
        id=str(admin_result.inserted_id),
        gym_id=str(gym_id),
        gym_name=body.gym_name.strip(),
        login_id=body.admin_login_id.strip(),
        is_active=True,
        created_at=admin_doc["created_at"],
    )


@router.patch("/super-admin/admins/{admin_id}", response_model=SuperAdminAdminListItem)
async def super_admin_patch_admin(admin_id: str, body: SuperAdminPatchAdminBody, _: dict = Depends(_require_super_admin)):
    try:
        oid = ObjectId(admin_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid admin ID")
    doc = await gym_admins_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Admin not found")
    if body.is_active is not None:
        await gym_admins_collection.update_one({"_id": oid}, {"$set": {"is_active": body.is_active}})
        doc = await gym_admins_collection.find_one({"_id": oid})
    gym_id = doc.get("gym_id")
    gym_name = ""
    if gym_id:
        g = await gyms_collection.find_one({"_id": gym_id})
        if g:
            gym_name = g.get("name", "")
    from app.utils.time_utils import now_ist
    return SuperAdminAdminListItem(
        id=str(doc["_id"]),
        gym_id=str(gym_id) if gym_id else "",
        gym_name=gym_name,
        login_id=doc.get("login_id", ""),
        is_active=bool(doc.get("is_active", True)),
        created_at=doc.get("created_at", now_ist()),
    )


@router.patch("/super-admin/admins/{admin_id}/password", response_model=dict)
async def super_admin_reset_admin_password(admin_id: str, body: SuperAdminResetPasswordBody, _: dict = Depends(_require_super_admin)):
    try:
        oid = ObjectId(admin_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid admin ID")
    doc = await gym_admins_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Admin not found")
    try:
        password_hash = pwd_context.hash(body.new_password)
    except Exception:
        password_hash = _pwd_fallback.hash(body.new_password)
    await gym_admins_collection.update_one(
        {"_id": oid},
        {"$set": {"password_hash": password_hash, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"message": "Password reset successfully"}


# ---------- Admin helpers ----------

INACTIVE_DAYS_THRESHOLD = 90


@router.post("/admin/mark-inactive-by-attendance")
async def mark_inactive_by_attendance(gym_id: str = Depends(get_gym_admin)):
    today = today_ist()
    cutoff = today - timedelta(days=INACTIVE_DAYS_THRESHOLD)
    cutoff_dt = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc)
    q = {"last_attendance_date": {"$exists": True, "$lt": cutoff_dt}}
    q.update(gym_filter(gym_id))
    result = await members_collection.update_many(q, {"$set": {"status": "Inactive"}})
    return {"updated_count": result.modified_count, "cutoff_date_ist": cutoff.isoformat()}


@router.post("/admin/run-fee-reminders")
async def run_fee_reminders(gym_id: str = Depends(get_gym_admin)):
    q = gym_filter(gym_id)
    q["status"] = {"$in": ["Due", "Overdue"]}
    cursor = payments_collection.find(q)
    member_pending = {}
    async for doc in cursor:
        mid = doc["member_id"]
        if mid not in member_pending:
            member_pending[mid] = 0
        member_pending[mid] += doc["amount"]
    sent = 0
    for mid, pending_amount in member_pending.items():
        member_q = {"_id": ObjectId(mid)}
        member_q.update(gym_filter(gym_id))
        member = await members_collection.find_one(member_q)
        if member:
            send_notification(
                "fees_due",
                {"name": member.get("name", ""), "phone": member.get("phone", ""), "email": member.get("email", "")},
                {"pending_amount": pending_amount},
            )
            sent += 1
    return {"message": f"Month-end reminders queued for {sent} member(s)."}


@router.post("/admin/seed-inactive-test")
async def seed_inactive_test(gym_id: str = Depends(get_gym_admin)):
    today = today_ist()
    old_date = today - timedelta(days=91)
    old_dt = datetime(old_date.year, old_date.month, old_date.day, tzinfo=timezone.utc)
    dummy_members = [
        {
            "name": "Test User (90d ago)",
            "phone": "9999900001",
            "email": "test90d1@example.com",
            "membership_type": "Regular",
            "batch": "Morning",
            "status": "Active",
            "created_at": datetime.now(timezone.utc),
            "last_attendance_date": old_dt,
            "gym_id": gym_id,
        },
        {
            "name": "Another Test (90d ago)",
            "phone": "9999900002",
            "email": "test90d2@example.com",
            "membership_type": "PT",
            "batch": "Evening",
            "status": "Active",
            "created_at": datetime.now(timezone.utc),
            "last_attendance_date": old_dt,
            "gym_id": gym_id,
        },
    ]
    inserted = []
    for doc in dummy_members:
        result = await members_collection.insert_one(doc)
        inserted.append({"id": str(result.inserted_id), "name": doc["name"]})
    return {"message": "Created 2 test members with last check-in 91 days ago.", "members": inserted}


# ---------- Analytics ----------

@router.get("/analytics/dashboard")
async def analytics_dashboard(
    date_from: str | None = None,
    date_to: str | None = None,
    gym_id: str = Depends(get_gym_admin),
):
    from app.utils.time_utils import IST
    q = gym_filter(gym_id)
    active = await members_collection.count_documents({**q, "status": "Active"})
    inactive = await members_collection.count_documents({**q, "status": "Inactive"})
    regular = await members_collection.count_documents({**q, "membership_type": "Regular"})
    pt = await members_collection.count_documents({**q, "membership_type": "PT"})
    pipeline_pending = [{"$match": {**q, "status": {"$in": ["Due", "Overdue"]}}}, {"$group": {"_id": None, "total": {"$sum": "$amount"}}}]
    cur = payments_collection.aggregate(pipeline_pending)
    pending_fees = 0
    async for row in cur:
        pending_fees = row["total"]
        break
    pipeline_paid = [{"$match": {**q, "status": "Paid"}}, {"$group": {"_id": None, "total": {"$sum": "$amount"}}}]
    cur2 = payments_collection.aggregate(pipeline_paid)
    total_collections = 0
    async for row in cur2:
        total_collections = row["total"]
        break
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_q = {**q, "date_ist": date_ist_str}
    today_attendance_count = await attendance_collection.count_documents(att_q)
    today_check_outs = await attendance_collection.count_documents({
        **att_q,
        "check_out_at_ist": {"$exists": True, "$ne": None, "$ne": ""},
    })
    today_currently_in = today_attendance_count - today_check_outs
    out = {
        "active_members": active,
        "inactive_members": inactive,
        "regular_count": regular,
        "pt_count": pt,
        "pending_fees_amount": pending_fees,
        "total_collections": total_collections,
        "today_attendance_count": today_attendance_count,
        "today_check_ins": today_attendance_count,
        "today_check_outs": today_check_outs,
        "today_currently_in": today_currently_in,
    }
    if date_from and date_to:
        if len(date_from) != 10 or date_from[4] != "-" or date_from[7] != "-" or len(date_to) != 10 or date_to[4] != "-" or date_to[7] != "-":
            raise HTTPException(status_code=400, detail="date_from and date_to must be YYYY-MM-DD")
        start = datetime.strptime(date_from + " 00:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=IST)
        end = datetime.strptime(date_to + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=IST)
        start_utc = start.astimezone(timezone.utc)
        end_utc = end.astimezone(timezone.utc)
        attendance_in_range = await attendance_collection.count_documents({
            **q,
            "check_in_at_utc": {"$gte": start_utc, "$lte": end_utc},
        })
        pipeline_paid_range = [
            {"$match": {**q, "status": "Paid", "paid_at": {"$gte": start_utc, "$lte": end_utc}}},
            {"$group": {"_id": None, "total": {"$sum": "$amount"}, "count": {"$sum": 1}}},
        ]
        cur3 = payments_collection.aggregate(pipeline_paid_range)
        payments_in_range_amt = 0
        payments_in_range_count = 0
        async for row in cur3:
            payments_in_range_amt = row.get("total", 0)
            payments_in_range_count = row.get("count", 0)
            break
        out["attendance_count_in_range"] = attendance_in_range
        out["payments_received_in_range"] = payments_in_range_amt
        out["payments_count_in_range"] = payments_in_range_count
        out["date_from"] = date_from
        out["date_to"] = date_to
    return out


__all__ = ["router"]
