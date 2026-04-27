"""
Members router: CRUD, by-phone, attendance-stats, import.
"""

import re
from datetime import datetime, time, timezone
from io import BytesIO

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from pymongo.errors import DuplicateKeyError
import jwt

from app.core.auth import get_gym_admin, get_gym_id_for_attendance_or_member_get
from app.core.config import settings
from app.core.security import _pwd_fallback, pwd_context
from app.db.database import (
    gyms_collection,
    invoices_collection,
    member_documents_collection,
    members_collection,
    payments_collection,
    attendance_collection,
)
from app.models.schemas import (
    MemberCreate,
    MemberDeviceTokenUpsert,
    MemberImportResult,
    MemberResponse,
    MemberUpdate,
    MemberResetPasswordBody,
    MembershipType,
)
from app.utils.helpers import doc_to_member_response, gym_filter, resolve_monthly_fee, to_date
from app.utils.notifications import send_notification
from app.utils.time_utils import normalize_phone, today_ist

router = APIRouter()


@router.post("/members", response_model=MemberResponse)
async def create_member(member: MemberCreate, gym_id: str = Depends(get_gym_admin)):
    doc = member.model_dump()
    photo_base64 = doc.pop("photo_base64", None)
    id_document_base64 = doc.pop("id_document_base64", None)
    doc["gym_id"] = gym_id
    if doc.get("date_of_birth") is not None:
        doc["date_of_birth"] = datetime.combine(doc["date_of_birth"], datetime.min.time())
    doc["phone"] = normalize_phone(doc.get("phone") or "")
    if not doc["phone"]:
        raise HTTPException(status_code=400, detail="Phone must contain at least one digit")
    existing = await members_collection.find_one({**gym_filter(gym_id), "phone": doc["phone"]})
    if existing:
        raise HTTPException(
            status_code=400,
            detail="A member with this phone number already exists. Phone number must be unique.",
        )
    doc["created_at"] = datetime.now(timezone.utc)
    mt = doc["membership_type"].value if isinstance(doc["membership_type"], MembershipType) else doc["membership_type"]
    pid = str(member.plan_id).strip()
    if not pid:
        raise HTTPException(
            status_code=400,
            detail="Membership plan is required. Create at least one plan under Gym settings, then select it when registering a member.",
        )
    gym = await gyms_collection.find_one({"_id": ObjectId(gym_id)})
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    plans_list = gym.get("plans") or []
    plan = None
    for p in plans_list:
        if isinstance(p, dict) and str(p.get("id", "")) == pid:
            if not p.get("is_active", True):
                raise HTTPException(status_code=400, detail="Selected plan is deactivated")
            plan = p
            break
    if not plan:
        raise HTTPException(
            status_code=400,
            detail="Membership plan not found. Create or restore the plan in Gym settings, or pick an active plan from the list.",
        )
    doc["plan_id"] = pid
    doc["workout_schedule"] = doc.get("workout_schedule")
    doc["diet_chart"] = doc.get("diet_chart")
    try:
        result = await members_collection.insert_one(doc)
    except DuplicateKeyError:
        raise HTTPException(
            status_code=400,
            detail="A member with this phone number already exists in this gym. Phone number must be unique.",
        )
    mid = str(result.inserted_id)
    doc["_id"] = result.inserted_id

    if photo_base64 is not None or id_document_base64 is not None:
        await member_documents_collection.update_one(
            {"member_id": mid, "gym_id": gym_id},
            {
                "$set": {
                    "member_id": mid,
                    "gym_id": gym_id,
                    "photo_base64": photo_base64,
                    "id_document_base64": id_document_base64,
                    "id_document_type": doc.get("id_document_type"),
                }
            },
            upsert=True,
        )

    today = today_ist()
    due_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    period = today.strftime("%Y-%m")
    plan_price = int(plan.get("price", 0))
    payments_to_insert = []
    if plan.get("duration_type") == "one_time":
        if plan_price > 0:
            payments_to_insert.append({"member_id": mid, "member_name": doc["name"], "amount": plan_price, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id})
    else:
        if plan_price > 0:
            payments_to_insert.append({"member_id": mid, "member_name": doc["name"], "amount": plan_price, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id})
    if payments_to_insert:
        await payments_collection.insert_many(payments_to_insert)
    send_notification("registration", {"name": doc["name"], "phone": doc["phone"], "email": doc["email"]})

    return MemberResponse(
        id=mid,
        name=doc["name"],
        phone=doc["phone"],
        email=doc["email"],
        membership_type=mt,
        batch=str(doc.get("batch", "")),
        status=doc["status"],
        created_at=doc["created_at"],
        last_attendance_date=doc.get("last_attendance_date"),
        address=doc.get("address"),
        date_of_birth=to_date(doc.get("date_of_birth")),
        gender=doc.get("gender"),
        workout_schedule=doc.get("workout_schedule"),
        diet_chart=doc.get("diet_chart"),
        photo_base64=photo_base64,
        id_document_base64=id_document_base64,
        id_document_type=doc.get("id_document_type"),
        plan_id=doc.get("plan_id"),
    )


@router.get("/members/{member_id}", response_model=MemberResponse)
async def get_member_by_id(
    member_id: str,
    gym_id: str = Depends(get_gym_id_for_attendance_or_member_get),
    authorization: str | None = Header(None),
):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    doc = await members_collection.find_one(q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")

    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:].strip()
        try:
            payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
            if payload.get("role") == "member" and payload.get("sub") == member_id:
                if (doc.get("status") or "Active") != "Active":
                    raise HTTPException(status_code=403, detail="Portal access is blocked. Your membership is not active.")
        except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
            pass

    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None

    return await doc_to_member_response(doc, attendance_map=attendance_map)


@router.post("/members/{member_id}/device-token", response_model=dict)
async def upsert_member_device_token(
    member_id: str,
    body: MemberDeviceTokenUpsert,
    gym_id: str = Depends(get_gym_id_for_attendance_or_member_get),
):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")

    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    member = await members_collection.find_one(q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")

    update_doc = {
        "$addToSet": {"push_tokens": body.token.strip()},
        "$set": {"push_token_updated_at": datetime.now(timezone.utc)},
    }
    if body.platform and body.platform.strip():
        update_doc["$set"]["push_platform"] = body.platform.strip()

    await members_collection.update_one(q, update_doc)
    return {"message": "Device token saved"}


@router.delete("/members/{member_id}/device-token", response_model=dict)
async def delete_member_device_token(
    member_id: str,
    token: str,
    gym_id: str = Depends(get_gym_id_for_attendance_or_member_get),
):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    member = await members_collection.find_one(q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    await members_collection.update_one(q, {"$pull": {"push_tokens": token}})
    return {"message": "Device token removed"}


@router.get("/members/{member_id}/attendance-stats")
async def member_attendance_stats(
    member_id: str,
    gym_id: str = Depends(get_gym_id_for_attendance_or_member_get),
    authorization: str | None = Header(None),
):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    member_doc = await members_collection.find_one(member_q)
    if member_doc is None:
        raise HTTPException(status_code=404, detail="Member not found")

    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:].strip()
        try:
            payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
            if payload.get("role") == "member" and payload.get("sub") == member_id:
                if (member_doc.get("status") or "Active") != "Active":
                    raise HTTPException(status_code=403, detail="Portal access is blocked. Your membership is not active.")
        except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
            pass

    att_q = {"member_id": member_id}
    att_q.update(gym_filter(gym_id))
    total_visits = await attendance_collection.count_documents(att_q)
    today = today_ist()
    month_start = today.replace(day=1).strftime("%Y-%m-%d")
    month_end = today.strftime("%Y-%m-%d")
    visits_this_month = await attendance_collection.count_documents({
        "member_id": member_id,
        "date_ist": {"$gte": month_start, "$lte": month_end},
        **gym_filter(gym_id),
    })
    cursor = attendance_collection.find(
        {"member_id": member_id, "check_out_at_utc": {"$exists": True, "$ne": None}, **gym_filter(gym_id)}
    )
    durations_min = []
    async for d in cursor:
        try:
            ci_raw = d.get("check_in_at_ist", "")
            co_raw = d.get("check_out_at_ist", "")
            ci = d.get("check_in_at_utc") or (datetime.fromisoformat(ci_raw) if ci_raw else None)
            co = d.get("check_out_at_utc") or (datetime.fromisoformat(co_raw) if co_raw else None)
            if hasattr(ci, "timestamp") and hasattr(co, "timestamp"):
                durations_min.append((co - ci).total_seconds() / 60)
        except ValueError:
            pass
    avg_duration_minutes = round(sum(durations_min) / len(durations_min), 1) if durations_min else None
    return {
        "total_visits": total_visits,
        "visits_this_month": visits_this_month,
        "avg_duration_minutes": avg_duration_minutes,
    }


@router.get("/members/by-phone/{phone}", response_model=MemberResponse)
async def get_member_by_phone(phone: str):
    phone_normalized = phone.strip() if phone else ""
    if not phone_normalized:
        raise HTTPException(status_code=400, detail="Phone required")
    doc = await members_collection.find_one({"phone": phone_normalized})
    if not doc:
        doc = await members_collection.find_one({"phone": phone})
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
    mid = str(doc["_id"])
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": mid, "date_ist": date_ist_str})
    attendance_map = {mid: att_doc} if att_doc else None
    return await doc_to_member_response(doc, attendance_map=attendance_map)


@router.get("/members", response_model=list[MemberResponse])
async def list_members(
    skip: int = 0,
    limit: int = 100,
    brief: bool = False,
    include_avatar: bool = False,
    search: str | None = None,
    gym_id: str = Depends(get_gym_admin),
):
    skip = max(0, skip)
    limit = min(max(1, limit), 500)
    q = gym_filter(gym_id)
    if search and search.strip():
        term = re.escape(search.strip())
        q["$or"] = [
            {"name": {"$regex": term, "$options": "i"}},
            {"phone": {"$regex": term, "$options": "i"}},
        ]
    cursor = members_collection.find(q).sort("created_at", -1).skip(skip).limit(limit)

    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_q = {"date_ist": date_ist_str}
    att_q.update(gym_filter(gym_id))
    att_cursor = attendance_collection.find(att_q)
    attendance_map = {}
    async for d in att_cursor:
        attendance_map[d["member_id"]] = d

    include_photos = not brief
    include_avatar_only = include_avatar and brief
    members = []
    async for doc in cursor:
        members.append(
            await doc_to_member_response(
                doc,
                include_photos=include_photos,
                include_avatar_only=include_avatar_only,
                attendance_map=attendance_map,
            )
        )
    return members


@router.patch("/members/{member_id}", response_model=MemberResponse)
async def update_member(member_id: str, body: MemberUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    update = {}
    if body.name is not None:
        update["name"] = body.name
    if body.phone is not None:
        update["phone"] = normalize_phone(body.phone)
        if not update["phone"]:
            raise HTTPException(status_code=400, detail="Phone must contain at least one digit")
        # Prevent changing to a phone that another member in this gym already has
        other = await members_collection.find_one({
            **gym_filter(gym_id),
            "phone": update["phone"],
            "_id": {"$ne": oid},
        })
        if other:
            raise HTTPException(
                status_code=400,
                detail="A member with this phone number already exists. Phone number must be unique.",
            )
    if body.email is not None:
        update["email"] = body.email
    if body.membership_type is not None:
        update["membership_type"] = body.membership_type.value if hasattr(body.membership_type, "value") else body.membership_type
    if body.batch is not None:
        update["batch"] = body.batch
    if body.status is not None:
        update["status"] = body.status
    if body.workout_schedule is not None:
        update["workout_schedule"] = body.workout_schedule
    if body.diet_chart is not None:
        update["diet_chart"] = body.diet_chart
    if body.address is not None:
        update["address"] = body.address.strip() if body.address else None
    if body.date_of_birth is not None:
        update["date_of_birth"] = datetime.combine(body.date_of_birth, time.min)
    if body.gender is not None:
        update["gender"] = body.gender.strip() if body.gender else None
    if not update:
        result = await members_collection.find_one(member_q)
        if not result:
            raise HTTPException(status_code=404, detail="Member not found")
        return await doc_to_member_response(result)
    result = await members_collection.find_one_and_update(
        member_q,
        {"$set": update},
        return_document=True,
    )
    if not result:
        raise HTTPException(status_code=404, detail="Member not found")

    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None

    return await doc_to_member_response(result, attendance_map=attendance_map)


@router.patch("/members/{member_id}/password", response_model=dict)
async def reset_member_password(member_id: str, body: MemberResetPasswordBody, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid ID")
    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    doc = await members_collection.find_one(q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
    try:
        password_hash = pwd_context.hash(body.new_password)
    except Exception:
        password_hash = _pwd_fallback.hash(body.new_password)
    await members_collection.update_one(
        q,
        {"$set": {"password_hash": password_hash, "updated_at": datetime.now(timezone.utc)}}
    )
    return {"message": "Password reset successfully"}


@router.delete("/members/{member_id}", status_code=204)
async def delete_member(member_id: str, gym_id: str = Depends(get_gym_admin)):
    """Permanently delete a member and all their related data. Cannot be undone."""
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    doc = await members_collection.find_one(member_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")

    gfilter = gym_filter(gym_id)
    await attendance_collection.delete_many({**gfilter, "member_id": member_id})
    await payments_collection.delete_many({**gfilter, "member_id": member_id})
    await invoices_collection.delete_many({**gfilter, "member_id": member_id})
    await member_documents_collection.delete_many({"member_id": member_id, **gfilter})
    await members_collection.delete_one(member_q)


def _parse_import_date(s: str):
    if not s or not str(s).strip():
        return None
    s = str(s).strip()
    for fmt in ("%m/%d/%Y", "%m-%d-%Y", "%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def _cell_str(v):
    if v is None:
        return ""
    if isinstance(v, float) and (v != v):
        return ""
    return str(v).strip()


@router.post("/members/import", response_model=MemberImportResult)
async def import_members_excel(file: UploadFile = File(...), gym_id: str = Depends(get_gym_admin)):
    import pandas as pd
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    fn = file.filename.lower()
    if not (fn.endswith(".csv") or fn.endswith(".xlsx")):
        raise HTTPException(status_code=400, detail="File must be CSV or Excel (.csv, .xlsx)")

    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="File is empty")

    try:
        if fn.endswith(".csv"):
            df = pd.read_csv(BytesIO(contents), encoding="utf-8-sig")
            if len(df.columns) == 1:
                df = pd.read_csv(BytesIO(contents), encoding="utf-8-sig", sep=";")
        else:
            df = pd.read_excel(BytesIO(contents), engine="openpyxl")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read file: {e!s}")

    if df.empty or len(df) == 0:
        return MemberImportResult(created=0, updated=0, errors=[{"row": 0, "message": "No rows in file"}])

    def _norm_col(c):
        s = str(c).strip().lower().replace(" ", "_")
        if s.startswith("\ufeff"):
            s = s[1:].strip()
        return s

    df.columns = [_norm_col(c) for c in df.columns]
    df.columns = [c.split("(")[0].strip("_") if "(" in c else c for c in df.columns]
    col_map = {
        "full_name": "name", "fullname": "name", "member_name": "name", "name_": "name",
        "email_address": "email", "e-mail_id": "email", "email_id": "email",
        "mobile": "phone", "phone_number": "phone", "phone_no": "phone", "contact": "phone",
        "type": "membership_type", "member_type": "membership_type",
    }
    for src, dst in col_map.items():
        if src not in df.columns:
            continue
        if dst not in df.columns:
            df[dst] = df[src]
        else:
            def _str(v):
                if v is None or (isinstance(v, float) and (v != v)):
                    return ""
                return str(v).strip()
            combined = df[dst].apply(_str).replace("", None).fillna(df[src].apply(_str).replace("", None))
            df[dst] = combined
        if src != dst:
            df.drop(columns=[src], inplace=True, errors="ignore")
    if "email" not in df.columns and "e-mail_id" in df.columns:
        df["email"] = df["e-mail_id"]

    created = 0
    updated = 0
    errors = []

    today = today_ist()
    due_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    period = today.strftime("%Y-%m")
    gfilter = gym_filter(gym_id)

    for idx, row in df.iterrows():
        row_num = int(idx) + 2
        try:
            name = _cell_str(row.get("name"))
            phone = normalize_phone(_cell_str(row.get("phone")) or "")
            email = (_cell_str(row.get("email")) or "").strip()
            if not name:
                errors.append({"row": row_num, "message": "Name is required"})
                continue
            if not phone:
                errors.append({"row": row_num, "message": "Phone is required"})
                continue
            if not email or "@" not in email:
                errors.append({"row": row_num, "message": "Valid email is required"})
                continue
            membership_type_raw = _cell_str(row.get("membership_type")) or "Regular"
            membership_type = "PT" if membership_type_raw.lower().strip() == "pt" else "Regular"
            batch = _cell_str(row.get("batch")) or "Morning"
            status = _cell_str(row.get("status")) or "Active"
            if status not in ("Active", "Inactive", "Disabled"):
                status = "Active"
            address = _cell_str(row.get("address")) or None
            if address == "":
                address = None
            gender = _cell_str(row.get("gender")) or None
            if gender == "":
                gender = None
            date_of_birth = _parse_import_date(_cell_str(row.get("date_of_birth")))

            existing = await members_collection.find_one({**gfilter, "phone": phone})
            set_fields = {
                "name": name[:200],
                "email": email,
                "membership_type": membership_type,
                "batch": batch[:120],
                "status": status,
            }
            if address is not None:
                set_fields["address"] = address[:500]
            if gender is not None:
                set_fields["gender"] = gender.strip()[:50]
            if date_of_birth is not None:
                set_fields["date_of_birth"] = datetime.combine(date_of_birth, time.min)

            if existing:
                await members_collection.update_one(
                    {"_id": existing["_id"]},
                    {"$set": set_fields},
                )
                updated += 1
            else:
                doc = {
                    "name": name[:200],
                    "phone": phone,
                    "email": email,
                    "membership_type": membership_type,
                    "batch": batch[:120],
                    "status": status,
                    "gym_id": gym_id,
                    "created_at": datetime.now(timezone.utc),
                    "address": set_fields.get("address"),
                    "gender": set_fields.get("gender"),
                    "date_of_birth": datetime.combine(date_of_birth, time.min) if date_of_birth is not None else None,
                }
                try:
                    result = await members_collection.insert_one(doc)
                except DuplicateKeyError:
                    errors.append({"row": row_num, "message": "Duplicate phone number in this gym; member already exists."})
                    continue
                mid = str(result.inserted_id)
                mt = doc["membership_type"]
                monthly_amount = await resolve_monthly_fee(gym_id, mt)
                await payments_collection.insert_many([
                    {
                        "member_id": mid,
                        "member_name": doc["name"],
                        "amount": monthly_amount,
                        "fee_type": "monthly",
                        "period": period,
                        "status": "Due",
                        "due_date": due_dt,
                        "paid_at": None,
                        "created_at": datetime.now(timezone.utc),
                        "gym_id": gym_id,
                    },
                ])
                created += 1
        except Exception as e:
            errors.append({"row": row_num, "message": str(e)[:200]})

    return MemberImportResult(created=created, updated=updated, errors=errors)


__all__ = ["router"]
