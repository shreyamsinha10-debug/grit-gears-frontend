"""
Jupiter Arena Gym API – Backend for GymSaaS.

This FastAPI application provides REST endpoints for:
- Member CRUD and lookup (by id or phone for member login)
- Attendance: check-in/check-out (IST), daily and date-range reports
- Payments: registration + monthly fees (₹500 Regular / ₹2000 PT), log monthly with date
- Billing: walk-in (new member + first invoice), invoice history, mark paid
- Analytics: dashboard counts (active/inactive, today's check-ins, etc.)
- Export: members, payments, billing to Excel

All timestamps and "today" are in Asia/Kolkata (IST). MongoDB collections:
gym_members, attendance_logs, payments, invoices.
"""

import os
from contextlib import asynccontextmanager
from datetime import datetime, date, timedelta
from enum import Enum
from io import BytesIO
from zoneinfo import ZoneInfo

from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, EmailStr, Field, field_serializer

# ---------------------------------------------------------------------------
# Configuration & database
# ---------------------------------------------------------------------------
# MongoDB: use MONGODB_URL env in production to avoid credentials in source
MONGODB_URL = os.environ.get("MONGODB_URL", "mongodb+srv://gym_admin:8qxXOYKp1El0bw0B@clustergymadmin.zkcgd9b.mongodb.net/?appName=Clustergymadmin")
DATABASE_NAME = os.environ.get("DATABASE_NAME", "gym_db")
COLLECTION_MEMBERS = "gym_members"
COLLECTION_ATTENDANCE = "attendance_logs"
COLLECTION_PAYMENTS = "payments"
COLLECTION_INVOICES = "invoices"

# Fee constants (used for registration, monthly dues, walk-in first bill)
REGISTRATION_FEE = 1000
MONTHLY_FEE_REGULAR = 500
MONTHLY_FEE_PT = 2000

IST = ZoneInfo("Asia/Kolkata")

client = AsyncIOMotorClient(MONGODB_URL)
db = client[DATABASE_NAME]
members_collection = db[COLLECTION_MEMBERS]
attendance_collection = db[COLLECTION_ATTENDANCE]
payments_collection = db[COLLECTION_PAYMENTS]
invoices_collection = db[COLLECTION_INVOICES]


# ---------------------------------------------------------------------------
# Time helpers (all business logic uses IST)
# ---------------------------------------------------------------------------

# ---------- Time helpers (all business logic uses IST) ----------

def now_ist() -> datetime:
    """Current datetime in IST."""
    return datetime.now(IST)


def today_ist() -> date:
    """Current date in IST."""
    return now_ist().date()


def batch_from_ist(dt: datetime) -> str:
    """Return Morning, Evening, or Ladies based on IST hour. Morning 4-11, Evening 12-16, Ladies 17-23, else Evening."""
    h = dt.hour
    if 4 <= h <= 11:
        return "Morning"
    if 17 <= h <= 23:
        return "Ladies"
    return "Evening"  # 0-3, 12-16


# ---------------------------------------------------------------------------
# App lifecycle: auto-mark inactive members who haven't visited in 90 days
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """On startup: mark members as Inactive if last_attendance_date is older than 90 days (IST)."""
    from datetime import timezone
    today = today_ist()
    cutoff = today - timedelta(days=90)
    cutoff_dt = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc)
    await members_collection.update_many(
        {"last_attendance_date": {"$exists": True, "$lt": cutoff_dt}},
        {"$set": {"status": "Inactive"}},
    )
    yield
    # shutdown if needed
    pass


app = FastAPI(title="Gym API", lifespan=lifespan)

# CORS: allow Flutter web (varying ports) and mobile to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for local dev (Flutter web uses varying ports)
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Pydantic models (request/response shapes for API)
# ---------------------------------------------------------------------------

class MembershipType(str, Enum):
    regular = "Regular"
    pt = "PT"


class Batch(str, Enum):
    morning = "Morning"
    evening = "Evening"
    ladies = "Ladies"


class MemberCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    phone: str = Field(..., min_length=1, max_length=20)
    email: EmailStr
    membership_type: MembershipType
    batch: Batch
    status: str = Field(default="Active", max_length=50)
    photo_base64: str | None = None  # optional member photo (JPEG/PNG base64)
    id_document_base64: str | None = None  # optional ID document (PDF/image base64)
    id_document_type: str | None = None  # e.g. Aadhar, Driving Licence, Voter ID, Passport


class TodayAttendance(BaseModel):
    checked_in: bool = False
    checked_out: bool = False
    check_in_time: str | None = None
    check_out_time: str | None = None


class MemberResponse(BaseModel):
    id: str
    name: str
    phone: str
    email: str
    membership_type: str
    batch: str
    status: str
    created_at: datetime
    last_attendance_date: date | None = None
    workout_schedule: str | None = None
    diet_chart: str | None = None
    photo_base64: str | None = None
    id_document_base64: str | None = None
    id_document_type: str | None = None
    today_status: TodayAttendance | None = None


class MemberPTUpdate(BaseModel):
    workout_schedule: str | None = None
    diet_chart: str | None = None


class MemberUpdate(BaseModel):
    """Admin: full member edit for corrections."""
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    membership_type: MembershipType | None = None
    batch: Batch | None = None
    status: str | None = None
    workout_schedule: str | None = None
    diet_chart: str | None = None


class PhotoUpdate(BaseModel):
    """Set or clear member profile photo. Send photo_base64: null to delete."""
    photo_base64: str | None = None


class IdDocumentUpdate(BaseModel):
    """Set or clear identity document. Send id_document_base64: null to delete."""
    id_document_base64: str | None = None
    id_document_type: str | None = None  # Aadhar, Driving Licence, Voter ID, Passport


class PaymentResponse(BaseModel):
    id: str
    member_id: str
    member_name: str
    amount: int
    fee_type: str  # registration | monthly
    period: str | None = None  # e.g. "2025-02" for monthly
    status: str  # Paid | Due | Overdue
    due_date: date | None = None
    paid_at: datetime | None = None
    created_at: datetime


class InvoiceItem(BaseModel):
    description: str
    amount: int


class InvoiceCreate(BaseModel):
    member_id: str
    items: list[InvoiceItem]  # e.g. [{"description": "Registration", "amount": 1000}, {"description": "First Month", "amount": 500}]


class InvoiceResponse(BaseModel):
    id: str
    member_id: str
    member_name: str
    items: list[dict]
    total: int
    status: str  # Paid | Unpaid
    issued_at: datetime
    paid_at: datetime | None = None


class AttendanceRecord(BaseModel):
    id: str
    member_id: str
    member_name: str
    member_phone: str | None = None
    check_in_at: datetime  # IST, for display
    date_ist: str
    batch: str
    check_out_at: datetime | None = None  # IST, when member checked out

    @field_serializer("check_in_at")
    def serialize_check_in_at(self, dt: datetime) -> str:
        return dt.isoformat()

    @field_serializer("check_out_at")
    def serialize_check_out_at(self, dt: datetime | None) -> str | None:
        return dt.isoformat() if dt else None


# ---------- Notifications (utils.send_notification) ----------
def _notify_registration(name: str, email: str, phone: str):
    from utils import send_notification
    send_notification("registration", {"name": name, "phone": phone, "email": email})

def _notify_payment_received(name: str, amount: int, email: str, phone: str):
    from utils import send_notification
    send_notification("payment_received", {"name": name, "phone": phone, "email": email}, {"amount": amount})

def _notify_status_change(name: str, new_status: str, email: str, phone: str):
    from utils import send_notification
    send_notification("status_change", {"name": name, "phone": phone, "email": email}, {"new_status": new_status})


# Minimum app version the backend supports (app should prompt update if below this).
MIN_APP_VERSION = "1.0.0"

# Optional: max check-ins per batch per day (None = no limit). Set e.g. {"Morning": 30, "Evening": 30, "Ladies": 20}.
BATCH_CAPACITY = None  # or {"Morning": 30, "Evening": 30, "Ladies": 20}


@app.get("/")
def root():
    return {"status": "success", "message": "Gym API is Live!"}


@app.get("/version")
def version():
    """App can check this to prompt user to update if current version < min_app_version."""
    return {"min_app_version": MIN_APP_VERSION, "api_version": "1"}


# ---------- Members: CRUD, lookup, attendance stats ----------

@app.post("/members", response_model=MemberResponse)
async def create_member(member: MemberCreate):
    from datetime import timezone
    doc = member.model_dump()
    # Normalize phone for consistent lookup (member login uses by-phone)
    doc["phone"] = (doc.get("phone") or "").strip()
    doc["created_at"] = datetime.now(timezone.utc)
    mt = doc["membership_type"].value if isinstance(doc["membership_type"], MembershipType) else doc["membership_type"]
    doc["workout_schedule"] = doc.get("workout_schedule")
    doc["diet_chart"] = doc.get("diet_chart")
    result = await members_collection.insert_one(doc)
    mid = str(result.inserted_id)
    doc["_id"] = result.inserted_id

    # Create registration fee (Due) and first monthly fee (Due)
    today = today_ist()
    due_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    monthly_amount = MONTHLY_FEE_PT if mt == "PT" else MONTHLY_FEE_REGULAR
    period = today.strftime("%Y-%m")
    await payments_collection.insert_many([
        {"member_id": mid, "member_name": doc["name"], "amount": REGISTRATION_FEE, "fee_type": "registration", "period": None, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc)},
        {"member_id": mid, "member_name": doc["name"], "amount": monthly_amount, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc)},
    ])
    _notify_registration(doc["name"], doc["email"], doc["phone"])

    return MemberResponse(
        id=mid,
        name=doc["name"],
        phone=doc["phone"],
        email=doc["email"],
        membership_type=mt,
        batch=doc["batch"].value if isinstance(doc["batch"], Batch) else doc["batch"],
        status=doc["status"],
        created_at=doc["created_at"],
        last_attendance_date=doc.get("last_attendance_date"),
        workout_schedule=doc.get("workout_schedule"),
        diet_chart=doc.get("diet_chart"),
        photo_base64=doc.get("photo_base64"),
        id_document_base64=doc.get("id_document_base64"),
        id_document_type=doc.get("id_document_type"),
    )


@app.get("/members/{member_id}", response_model=MemberResponse)
async def get_member_by_id(member_id: str):
    """Get a single member by ID."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    doc = await members_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
        
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None
    
    return _doc_to_member_response(doc, attendance_map=attendance_map)


@app.get("/members/{member_id}/attendance-stats")
async def member_attendance_stats(member_id: str):
    """Total visits, visits this month, and avg workout duration (minutes) for a member."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    if await members_collection.find_one({"_id": oid}) is None:
        raise HTTPException(status_code=404, detail="Member not found")
    total_visits = await attendance_collection.count_documents({"member_id": member_id})
    today = today_ist()
    month_start = today.replace(day=1).strftime("%Y-%m-%d")
    month_end = today.strftime("%Y-%m-%d")
    visits_this_month = await attendance_collection.count_documents({
        "member_id": member_id,
        "date_ist": {"$gte": month_start, "$lte": month_end},
    })
    cursor = attendance_collection.find(
        {"member_id": member_id, "check_out_at_utc": {"$exists": True, "$ne": None}}
    )
    durations_min = []
    async for doc in cursor:
        try:
            ci = doc.get("check_in_at_utc") or datetime.fromisoformat(doc.get("check_in_at_ist", ""))
            co = doc.get("check_out_at_utc") or datetime.fromisoformat(doc.get("check_out_at_ist", ""))
            if hasattr(ci, "timestamp") and hasattr(co, "timestamp"):
                durations_min.append((co - ci).total_seconds() / 60)
        except Exception:
            pass
    avg_duration_minutes = round(sum(durations_min) / len(durations_min), 1) if durations_min else None
    return {
        "total_visits": total_visits,
        "visits_this_month": visits_this_month,
        "avg_duration_minutes": avg_duration_minutes,
    }


@app.get("/members/by-phone/{phone}", response_model=MemberResponse)
async def get_member_by_phone(phone: str):
    """For member login: lookup by phone. Phone is normalized (stripped) for lookup."""
    phone_normalized = phone.strip() if phone else ""
    if not phone_normalized:
        raise HTTPException(status_code=400, detail="Phone required")
    doc = await members_collection.find_one({"phone": phone_normalized})
    if not doc:
        # Try with original in case DB has different formatting
        doc = await members_collection.find_one({"phone": phone})
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
        
    mid = str(doc["_id"])
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": mid, "date_ist": date_ist_str})
    attendance_map = {mid: att_doc} if att_doc else None
    
    return _doc_to_member_response(doc, attendance_map=attendance_map)


@app.get("/members", response_model=list[MemberResponse])
async def list_members(skip: int = 0, limit: int = 100, brief: bool = False):
    """List members. brief=True omits photo_base64 and id_document_base64 for faster list load. Use skip/limit for pagination."""
    skip = max(0, skip)
    limit = min(max(1, limit), 500)  # Cap at 500 for performance/security
    cursor = members_collection.find().sort("created_at", -1).skip(skip).limit(limit)
    
    # Fetch today's attendance for these members
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_cursor = attendance_collection.find({"date_ist": date_ist_str})
    attendance_map = {}
    async for doc in att_cursor:
        attendance_map[doc["member_id"]] = doc

    members = []
    async for doc in cursor:
        members.append(
            _doc_to_member_response(doc, include_photos=not brief, attendance_map=attendance_map)
        )
    return members


@app.patch("/members/{member_id}", response_model=MemberResponse)
async def update_member(member_id: str, body: MemberUpdate):
    """Admin: edit member details (name, phone, email, batch, status, PT fields, etc.) for corrections."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    update = {}
    if body.name is not None:
        update["name"] = body.name
    if body.phone is not None:
        update["phone"] = body.phone
    if body.email is not None:
        update["email"] = body.email
    if body.membership_type is not None:
        update["membership_type"] = body.membership_type.value if hasattr(body.membership_type, "value") else body.membership_type
    if body.batch is not None:
        update["batch"] = body.batch.value if hasattr(body.batch, "value") else body.batch
    if body.status is not None:
        update["status"] = body.status
    if body.workout_schedule is not None:
        update["workout_schedule"] = body.workout_schedule
    if body.diet_chart is not None:
        update["diet_chart"] = body.diet_chart
    if not update:
        result = await members_collection.find_one({"_id": oid})
        if not result:
            raise HTTPException(status_code=404, detail="Member not found")
        return _doc_to_member_response(result)
    result = await members_collection.find_one_and_update(
        {"_id": oid},
        {"$set": update},
        return_document=True,
    )
    if not result:
        raise HTTPException(status_code=404, detail="Member not found")
        
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None
    
    return _doc_to_member_response(result, attendance_map=attendance_map)


@app.patch("/members/{member_id}/photo", response_model=MemberResponse)
async def update_member_photo(member_id: str, body: PhotoUpdate):
    """Upload or remove member profile picture. Both member and admin can call this. Send photo_base64: null to delete."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    if body.photo_base64 is None:
        await members_collection.update_one({"_id": oid}, {"$unset": {"photo_base64": ""}})
    else:
        await members_collection.update_one({"_id": oid}, {"$set": {"photo_base64": body.photo_base64}})
    doc = await members_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
        
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None
    
    return _doc_to_member_response(doc, attendance_map=attendance_map)


@app.patch("/members/{member_id}/id-document", response_model=MemberResponse)
async def update_member_id_document(member_id: str, body: IdDocumentUpdate):
    """Upload or remove identity document (Aadhar, Driving Licence, Voter ID, Passport). Send id_document_base64: null to delete."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    if body.id_document_base64 is None:
        await members_collection.update_one({"_id": oid}, {"$unset": {"id_document_base64": "", "id_document_type": ""}})
    else:
        update = {"id_document_base64": body.id_document_base64}
        if body.id_document_type is not None:
            update["id_document_type"] = body.id_document_type
        await members_collection.update_one({"_id": oid}, {"$set": update})
    doc = await members_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
        
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None
    
    return _doc_to_member_response(doc, attendance_map=attendance_map)


def _doc_to_member_response(doc, include_photos: bool = True, attendance_map: dict | None = None) -> MemberResponse:
    today_status = None
    if attendance_map:
        mid = str(doc["_id"])
        if mid in attendance_map:
            rec = attendance_map[mid]
            today_status = TodayAttendance(
                checked_in=True,
                checked_out=bool(rec.get("check_out_at_ist")),
                check_in_time=rec.get("check_in_at_ist"),
                check_out_time=rec.get("check_out_at_ist"),
            )
    
    return MemberResponse(
                id=str(doc["_id"]),
                name=doc["name"],
                phone=doc["phone"],
                email=doc["email"],
                membership_type=doc["membership_type"] if isinstance(doc["membership_type"], str) else doc["membership_type"].value,
                batch=doc["batch"] if isinstance(doc["batch"], str) else doc["batch"].value,
                status=doc.get("status", "Active"),
                created_at=doc["created_at"],
        last_attendance_date=_to_date(doc.get("last_attendance_date")),
        workout_schedule=doc.get("workout_schedule"),
        diet_chart=doc.get("diet_chart"),
        photo_base64=doc.get("photo_base64") if include_photos else None,
        id_document_base64=doc.get("id_document_base64") if include_photos else None,
        id_document_type=doc.get("id_document_type") if include_photos else None,
        today_status=today_status,
    )


def _to_date(v):
    """Convert datetime to date for API; leave date as is."""
    if v is None:
        return None
    return v.date() if hasattr(v, "date") else v


# ---------- Attendance ----------


# ---------- Attendance: check-in/check-out (IST), by date, summary ----------

@app.post("/attendance/check-in/{member_id}", response_model=AttendanceRecord)
async def check_in(member_id: str):
    """Record check-in in IST. One check-in per member per calendar day (IST)."""
    from bson import ObjectId
    from datetime import timezone

    try:
        try:
            oid = ObjectId(member_id)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid member ID")

        member = await members_collection.find_one({"_id": oid})
        if not member:
            raise HTTPException(status_code=404, detail="Member not found")

        now = now_ist()
        date_ist_str = now.strftime("%Y-%m-%d")
        batch = batch_from_ist(now)

        already_today = await attendance_collection.find_one(
            {"member_id": member_id, "date_ist": date_ist_str},
        )
        if already_today:
            raise HTTPException(
                status_code=400,
                detail="Already checked in today. One check-in per day allowed.",
            )

        if BATCH_CAPACITY and batch in BATCH_CAPACITY:
            cap = BATCH_CAPACITY[batch]
            count_today_batch = await attendance_collection.count_documents(
                {"date_ist": date_ist_str, "batch": batch}
            )
            if count_today_batch >= cap:
                raise HTTPException(
                    status_code=400,
                    detail=f"Batch full. {batch} batch has reached capacity ({cap}). Try another batch.",
                )

        check_in_at_utc = now.astimezone(timezone.utc)
        doc = {
            "member_id": member_id,
            "check_in_at_utc": check_in_at_utc,
            "check_in_at_ist": now.isoformat(),
            "date_ist": date_ist_str,
            "batch": batch,
            "member_name": member.get("name", ""),
            "member_phone": member.get("phone"),
        }
        result = await attendance_collection.insert_one(doc)
        # Store as datetime at midnight UTC so MongoDB (BSON) can encode it
        today_date = now.date()
        last_attendance_dt = datetime(today_date.year, today_date.month, today_date.day, tzinfo=timezone.utc)
        await members_collection.update_one(
            {"_id": oid},
            {"$set": {"last_attendance_date": last_attendance_dt}},
        )

        return AttendanceRecord(
            id=str(result.inserted_id),
            member_id=member_id,
            member_name=doc["member_name"],
            member_phone=doc.get("member_phone"),
            check_in_at=now,
            date_ist=date_ist_str,
            batch=batch,
            check_out_at=None,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Server error during check-in: {e!s}")


async def _attendance_docs_to_records(cursor) -> list:
    out = []
    async for doc in cursor:
        # Prefer the IST string if available (it was stored as now_ist().isoformat())
        # Otherwise fallback to utc field.
        check_in_at_ist = None
        if doc.get("check_in_at_ist"):
            try:
                check_in_at_ist = datetime.fromisoformat(doc["check_in_at_ist"])
            except ValueError:
                pass
        
        if not check_in_at_ist:
            check_in_at_ist = doc["check_in_at_utc"]
            # If naive, it's UTC from Mongo. Convert to IST.
            if hasattr(check_in_at_ist, "tzinfo") and check_in_at_ist.tzinfo is None:
                from datetime import timezone
                check_in_at_ist = check_in_at_ist.replace(tzinfo=timezone.utc).astimezone(IST)
            elif hasattr(check_in_at_ist, "astimezone"):
                check_in_at_ist = check_in_at_ist.astimezone(IST)

        check_out_at = None
        if doc.get("check_out_at_ist"):
            try:
                check_out_at = datetime.fromisoformat(doc["check_out_at_ist"])
            except ValueError:
                pass
        
        if not check_out_at and doc.get("check_out_at_utc"):
            check_out_at = doc["check_out_at_utc"]
            # If naive, it's UTC. Convert to IST.
            if hasattr(check_out_at, "tzinfo") and check_out_at.tzinfo is None:
                from datetime import timezone
                check_out_at = check_out_at.replace(tzinfo=timezone.utc).astimezone(IST)
            elif hasattr(check_out_at, "astimezone"):
                check_out_at = check_out_at.astimezone(IST)

        out.append(
            AttendanceRecord(
                id=str(doc["_id"]),
                member_id=doc["member_id"],
                member_name=doc.get("member_name", ""),
                member_phone=doc.get("member_phone"),
                check_in_at=check_in_at_ist,
                date_ist=doc["date_ist"],
                batch=doc["batch"],
                check_out_at=check_out_at,
            )
        )
    return out


@app.get("/attendance/summary")
async def attendance_summary():
    """Today's check-ins, currently in gym, this week count, average daily (for dashboard cards)."""
    from datetime import timedelta
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    today_count = await attendance_collection.count_documents({"date_ist": date_ist_str})
    today_check_outs = await attendance_collection.count_documents({
        "date_ist": date_ist_str,
        "check_out_at_ist": {"$exists": True, "$ne": None, "$ne": ""},
    })
    currently_in = today_count - today_check_outs
    week_start = (today_ist() - timedelta(days=6)).strftime("%Y-%m-%d")
    this_week = await attendance_collection.count_documents({
        "date_ist": {"$gte": week_start, "$lte": date_ist_str},
    })
    average_daily = round(this_week / 7.0, 1) if this_week else 0
    return {
        "today_check_ins": today_count,
        "currently_in_gym": currently_in,
        "this_week": this_week,
        "average_daily": average_daily,
    }


@app.get("/attendance/today", response_model=list[AttendanceRecord])
async def attendance_today():
    """All check-ins for current date in IST."""
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    return await attendance_by_date(date_ist_str)


@app.get("/attendance/by-date", response_model=list[AttendanceRecord])
async def attendance_by_date_endpoint(date: str):
    """All check-ins for a given date (YYYY-MM-DD). Use for date picker."""
    if len(date) != 10 or date[4] != "-" or date[7] != "-":
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")
    return await attendance_by_date(date)


@app.get("/attendance/by-date-range", response_model=list[AttendanceRecord])
async def attendance_by_date_range(date_from: str, date_to: str):
    """All check-ins in date range (YYYY-MM-DD). For daily/monthly/historical view."""
    if len(date_from) != 10 or date_from[4] != "-" or date_from[7] != "-" or len(date_to) != 10 or date_to[4] != "-" or date_to[7] != "-":
        raise HTTPException(status_code=400, detail="date_from and date_to must be YYYY-MM-DD")
    if date_from > date_to:
        raise HTTPException(status_code=400, detail="date_from must be <= date_to")
    cursor = attendance_collection.find(
        {"date_ist": {"$gte": date_from, "$lte": date_to}}
    ).sort([("date_ist", 1), ("batch", 1), ("check_in_at_utc", 1)])
    return await _attendance_docs_to_records(cursor)


@app.post("/attendance/check-out/{member_id}", response_model=AttendanceRecord)
async def check_out(member_id: str):
    """Record check-out for today's check-in (IST)."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member = await members_collection.find_one({"_id": oid})
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    if not doc:
        raise HTTPException(status_code=400, detail="No check-in found for today. Check in first.")
    if doc.get("check_out_at_ist"):
        raise HTTPException(status_code=400, detail="Already checked out today.")
    now = now_ist()
    check_out_utc = now.astimezone(timezone.utc)
    await attendance_collection.update_one(
        {"_id": doc["_id"]},
        {"$set": {"check_out_at_ist": now.isoformat(), "check_out_at_utc": check_out_utc}},
    )
    updated = await attendance_collection.find_one({"_id": doc["_id"]})
    # Build record from single doc (cursor helper expects async iterable)
    records = await _attendance_docs_to_records(
        _async_iter([updated])
    )
    return records[0]


async def _async_iter(items):
    for x in items:
        yield x


async def attendance_by_date(date_ist_str: str) -> list:
    cursor = attendance_collection.find({"date_ist": date_ist_str}).sort([("batch", 1), ("check_in_at_utc", 1)])
    return await _attendance_docs_to_records(cursor)


@app.delete("/attendance/{attendance_id}")
async def delete_attendance(attendance_id: str):
    """Admin: remove a check-in record (e.g. wrong person or duplicate)."""
    from bson import ObjectId
    try:
        oid = ObjectId(attendance_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid attendance ID")
    result = await attendance_collection.delete_one({"_id": oid})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Attendance record not found")
    return {"message": "Attendance record deleted"}


INACTIVE_DAYS_THRESHOLD = 90


@app.post("/admin/mark-inactive-by-attendance")
async def mark_inactive_by_attendance():
    """
    Only mark Inactive when last_attendance_date exists and is older than 90 days (IST).
    Members who have never checked in (no last_attendance_date) are left unchanged.
    """
    from datetime import timezone

    today = today_ist()
    cutoff = today - timedelta(days=INACTIVE_DAYS_THRESHOLD)
    cutoff_dt = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc)
    result = await members_collection.update_many(
        {"last_attendance_date": {"$exists": True, "$lt": cutoff_dt}},
        {"$set": {"status": "Inactive"}},
    )
    return {"updated_count": result.modified_count, "cutoff_date_ist": cutoff.isoformat()}


# ---------- Payments & Fees ----------

# ---------- Payments: list, fees summary, log monthly, mark paid ----------

@app.get("/payments", response_model=list[PaymentResponse])
async def list_payments(member_id: str | None = None, status: str | None = None, limit: int = 1000):
    """List payments. Filter by member_id and/or status (Paid/Due/Overdue). Capped at 1000 for performance."""
    from datetime import timezone
    q = {}
    if member_id:
        q["member_id"] = member_id
    if status:
        q["status"] = status
    limit = min(max(1, limit), 1000)
    cursor = payments_collection.find(q).sort("created_at", -1).limit(limit)
    out = []
    async for doc in cursor:
        out.append(PaymentResponse(
            id=str(doc["_id"]),
            member_id=doc["member_id"],
            member_name=doc.get("member_name", ""),
            amount=doc["amount"],
            fee_type=doc["fee_type"],
            period=doc.get("period"),
            status=doc["status"],
            due_date=_to_date(doc.get("due_date")),
            paid_at=doc.get("paid_at"),
            created_at=doc["created_at"],
        ))
    return out


@app.get("/payments/fees-summary")
async def fees_summary():
    """Paid/Due/Overdue counts and total amounts for Fees Management tab."""
    from datetime import timezone
    today = today_ist()
    today_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    pipeline = [
        {"$group": {"_id": "$status", "count": {"$sum": 1}, "total_amount": {"$sum": "$amount"}}}
    ]
    cursor = payments_collection.aggregate(pipeline)
    paid = due = overdue = 0
    paid_amt = due_amt = overdue_amt = 0
    async for row in cursor:
        s = row["_id"]
        c, a = row["count"], row["total_amount"]
        if s == "Paid":
            paid, paid_amt = c, a
        elif s == "Due":
            due, due_amt = c, a
        elif s == "Overdue":
            overdue, overdue_amt = c, a
    # Mark Due -> Overdue where due_date < today
    await payments_collection.update_many(
        {"status": "Due", "due_date": {"$lt": today_dt}},
        {"$set": {"status": "Overdue"}},
    )
    # Re-run summary after update
    cursor2 = payments_collection.aggregate(pipeline)
    paid = due = overdue = 0
    paid_amt = due_amt = overdue_amt = 0
    async for row in cursor2:
        s = row["_id"]
        c, a = row["count"], row["total_amount"]
        if s == "Paid":
            paid, paid_amt = c, a
        elif s == "Due":
            due, due_amt = c, a
        elif s == "Overdue":
            overdue, overdue_amt = c, a
    return {
        "paid": {"count": paid, "total_amount": paid_amt},
        "due": {"count": due, "total_amount": due_amt},
        "overdue": {"count": overdue, "total_amount": overdue_amt},
    }


class PaymentStatusUpdate(BaseModel):
    """Admin: correct payment status (e.g. revert to unpaid)."""
    status: str = Field(..., pattern="^(Paid|Due|Overdue)$")


class LogMonthlyPaymentBody(BaseModel):
    """Log a monthly payment for an existing member (Rs 500 Regular / Rs 2000 PT)."""
    member_id: str
    period: str  # YYYY-MM
    amount: int  # 500 or 2000
    payment_date: str | None = None  # YYYY-MM-DD, default today IST


@app.post("/payments/log-monthly", response_model=PaymentResponse)
async def log_monthly_payment(body: LogMonthlyPaymentBody):
    """Create a monthly payment record marked as Paid (for existing member payment logging)."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(body.member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member = await members_collection.find_one({"_id": oid})
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    if body.amount not in (500, 2000):
        raise HTTPException(status_code=400, detail="Amount must be 500 (Regular) or 2000 (PT)")
    pay_date_str = body.payment_date or today_ist().strftime("%Y-%m-%d")
    try:
        pay_date = datetime.strptime(pay_date_str + " 12:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except Exception:
        raise HTTPException(status_code=400, detail="payment_date must be YYYY-MM-DD")
    doc = {
        "member_id": body.member_id,
        "member_name": member.get("name", ""),
        "amount": body.amount,
        "fee_type": "monthly",
        "period": body.period,
        "status": "Paid",
        "due_date": pay_date,
        "paid_at": pay_date,
        "created_at": datetime.now(timezone.utc),
    }
    result = await payments_collection.insert_one(doc)
    doc["_id"] = result.inserted_id

    # Create Invoice for this payment
    inv_items = [{"description": f"Monthly Fee ({body.period})", "amount": body.amount}]
    inv_doc = {
        "member_id": body.member_id,
        "member_name": member.get("name", ""),
        "items": inv_items,
        "total": body.amount,
        "status": "Paid",
        "issued_at": datetime.now(timezone.utc),
        "paid_at": pay_date,
    }
    await invoices_collection.insert_one(inv_doc)

    return PaymentResponse(
        id=str(doc["_id"]),
        member_id=doc["member_id"],
        member_name=doc["member_name"],
        amount=doc["amount"],
        fee_type=doc["fee_type"],
        period=doc["period"],
        status=doc["status"],
        due_date=_to_date(doc.get("due_date")),
        paid_at=doc.get("paid_at"),
        created_at=doc["created_at"],
    )


@app.patch("/payments/{payment_id}", response_model=PaymentResponse)
async def update_payment_status(payment_id: str, body: PaymentStatusUpdate):
    """Admin: edit payment status for corrections (e.g. revert Paid to Due)."""
    from bson import ObjectId
    try:
        oid = ObjectId(payment_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid payment ID")
    doc = await payments_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Payment not found")
    update = {"status": body.status}
    if body.status != "Paid":
        update["paid_at"] = None
    await payments_collection.update_one({"_id": oid}, {"$set": update})
    updated = await payments_collection.find_one({"_id": oid})
    return PaymentResponse(
        id=str(updated["_id"]),
        member_id=updated["member_id"],
        member_name=updated.get("member_name", ""),
        amount=updated["amount"],
        fee_type=updated["fee_type"],
        period=updated.get("period"),
        status=updated["status"],
        due_date=_to_date(updated.get("due_date")),
        paid_at=updated.get("paid_at"),
        created_at=updated["created_at"],
    )


@app.post("/payments/pay", response_model=PaymentResponse)
async def record_payment(member_id: str, payment_id: str, background_tasks: BackgroundTasks):
    """Record a payment (simulated). Sends payment-received notification."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(payment_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid payment ID")
    doc = await payments_collection.find_one({"_id": oid, "member_id": member_id})
    if not doc:
        raise HTTPException(status_code=404, detail="Payment not found")
    if doc["status"] == "Paid":
        raise HTTPException(status_code=400, detail="Already paid")
    now = datetime.now(timezone.utc)
    await payments_collection.update_one(
        {"_id": oid},
        {"$set": {"status": "Paid", "paid_at": now}},
    )
    member = await members_collection.find_one({"_id": ObjectId(member_id)})
    if member:
        background_tasks.add_task(_notify_payment_received, member.get("name", ""), doc["amount"], member.get("email", ""), member.get("phone", ""))
    updated = await payments_collection.find_one({"_id": oid})
    return PaymentResponse(
        id=str(updated["_id"]),
        member_id=updated["member_id"],
        member_name=updated.get("member_name", ""),
        amount=updated["amount"],
        fee_type=updated["fee_type"],
        period=updated.get("period"),
        status=updated["status"],
        due_date=_to_date(updated.get("due_date")),
        paid_at=updated.get("paid_at"),
        created_at=updated["created_at"],
    )


# ---------- Analytics: dashboard counts, fee reminders, admin helpers ----------

@app.get("/analytics/dashboard")
async def analytics_dashboard(date_from: str | None = None, date_to: str | None = None):
    """
    Total Active/Inactive, Total Collections (₹), Pending Dues, Regular vs PT split.
    Optional date_from, date_to (YYYY-MM-DD): add attendance_count_in_range and payments_received_in_range for that period.
    """
    from datetime import timezone
    active = await members_collection.count_documents({"status": "Active"})
    inactive = await members_collection.count_documents({"status": "Inactive"})
    regular = await members_collection.count_documents({"membership_type": "Regular"})
    pt = await members_collection.count_documents({"membership_type": "PT"})
    pipeline_pending = [{"$match": {"status": {"$in": ["Due", "Overdue"]}}}, {"$group": {"_id": None, "total": {"$sum": "$amount"}}}]
    cur = payments_collection.aggregate(pipeline_pending)
    pending_fees = 0
    async for row in cur:
        pending_fees = row["total"]
        break
    pipeline_paid = [{"$match": {"status": "Paid"}}, {"$group": {"_id": None, "total": {"$sum": "$amount"}}}]
    cur2 = payments_collection.aggregate(pipeline_paid)
    total_collections = 0
    async for row in cur2:
        total_collections = row["total"]
        break
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    today_attendance_count = await attendance_collection.count_documents({"date_ist": date_ist_str})
    today_check_outs = await attendance_collection.count_documents({
        "date_ist": date_ist_str,
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
        from datetime import datetime as dt_parse
        start = dt_parse.strptime(date_from + " 00:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=IST)
        end = dt_parse.strptime(date_to + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=IST)
        start_utc = start.astimezone(timezone.utc)
        end_utc = end.astimezone(timezone.utc)
        attendance_in_range = await attendance_collection.count_documents({
            "check_in_at_utc": {"$gte": start_utc, "$lte": end_utc},
        })
        pipeline_paid_range = [
            {"$match": {"status": "Paid", "paid_at": {"$gte": start_utc, "$lte": end_utc}}},
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


@app.post("/admin/run-fee-reminders")
async def run_fee_reminders(background_tasks: BackgroundTasks):
    """Send Payment Reminders: simulated WhatsApp to all members with unpaid fees."""
    from utils import send_notification
    from bson import ObjectId
    cursor = payments_collection.find({"status": {"$in": ["Due", "Overdue"]}})
    member_pending = {}
    async for doc in cursor:
        mid = doc["member_id"]
        if mid not in member_pending:
            member_pending[mid] = 0
        member_pending[mid] += doc["amount"]
    sent = 0
    for mid, pending_amount in member_pending.items():
        member = await members_collection.find_one({"_id": ObjectId(mid)})
        if member:
            background_tasks.add_task(
                send_notification,
                "fees_due",
                {"name": member.get("name", ""), "phone": member.get("phone", ""), "email": member.get("email", "")},
                {"pending_amount": pending_amount},
            )
            sent += 1
    return {"message": f"Month-end reminders queued for {sent} member(s)."}


@app.post("/admin/seed-inactive-test")
async def seed_inactive_test():
    """
    Creates 2 dummy members with last_attendance_date set to 91 days ago (IST).
    Use this to test the 90-day automation: run this, then run Mark inactive (90d) to see them turn Inactive.
    """
    from datetime import timezone

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
        },
    ]
    inserted = []
    for doc in dummy_members:
        result = await members_collection.insert_one(doc)
        inserted.append({"id": str(result.inserted_id), "name": doc["name"]})
    return {"message": "Created 2 test members with last check-in 91 days ago.", "members": inserted}


# ---------- Billing / Invoices ----------

class BillingIssueWalkIn(BaseModel):
    """Walk-in: new member + first bill (Registration + 1st Month)."""
    name: str = Field(..., min_length=1)
    phone: str = Field(..., min_length=1)
    email: EmailStr
    membership_type: MembershipType
    batch: Batch


# ---------- Billing: walk-in (new member + first bill), history, mark paid ----------

@app.post("/billing/issue", response_model=InvoiceResponse)
async def billing_issue(body: BillingIssueWalkIn):
    """Walk-in flow: create member and issue first bill (Registration + 1st Month)."""
    from datetime import timezone
    from bson import ObjectId
    doc = {
        "name": body.name,
        "phone": body.phone,
        "email": body.email,
        "membership_type": body.membership_type.value,
        "batch": body.batch.value,
        "status": "Active",
        "created_at": datetime.now(timezone.utc),
    }
    result = await members_collection.insert_one(doc)
    mid = str(result.inserted_id)
    reg_amount = REGISTRATION_FEE
    monthly_amount = MONTHLY_FEE_PT if body.membership_type == MembershipType.pt else MONTHLY_FEE_REGULAR
    total = reg_amount + monthly_amount
    items = [
        {"description": "Registration", "amount": reg_amount},
        {"description": "First Month", "amount": monthly_amount},
    ]
    inv_doc = {
        "member_id": mid,
        "member_name": body.name,
        "items": items,
        "total": total,
        "status": "Unpaid",
        "issued_at": datetime.now(timezone.utc),
        "paid_at": None,
    }
    inv_result = await invoices_collection.insert_one(inv_doc)
    due_dt = datetime(today_ist().year, today_ist().month, today_ist().day, tzinfo=timezone.utc)
    period = today_ist().strftime("%Y-%m")
    await payments_collection.insert_many([
        {"member_id": mid, "member_name": body.name, "amount": reg_amount, "fee_type": "registration", "period": None, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc)},
        {"member_id": mid, "member_name": body.name, "amount": monthly_amount, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc)},
    ])
    _notify_registration(body.name, body.email, body.phone)
    return InvoiceResponse(
        id=str(inv_result.inserted_id),
        member_id=mid,
        member_name=body.name,
        items=items,
        total=total,
        status="Unpaid",
        issued_at=inv_doc["issued_at"],
        paid_at=None,
    )


@app.get("/billing/history", response_model=list[InvoiceResponse])
async def billing_history(
    member_id: str | None = None,
    search: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
):
    """List invoices. Optional: member_id, search (invoice id or member name), date_from, date_to (YYYY-MM-DD)."""
    q = {}
    if member_id:
        q["member_id"] = member_id
    if search and search.strip():
        from bson.regex import Regex
        from bson import ObjectId
        s = search.strip()
        or_clauses = [{"member_name": Regex(s, "i")}]
        try:
            or_clauses.append({"_id": ObjectId(s)})
        except Exception:
            pass
        q["$or"] = or_clauses
    if date_from and len(date_from) == 10 and date_from[4] == "-" and date_from[7] == "-":
        from datetime import timezone
        start = datetime.strptime(date_from + " 00:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        q.setdefault("issued_at", {})
        if isinstance(q["issued_at"], dict):
            q["issued_at"]["$gte"] = start
        else:
            q["issued_at"] = {"$gte": start}
    if date_to and len(date_to) == 10 and date_to[4] == "-" and date_to[7] == "-":
        from datetime import timezone
        end = datetime.strptime(date_to + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        if "issued_at" not in q:
            q["issued_at"] = {}
        if isinstance(q["issued_at"], dict):
            q["issued_at"]["$lte"] = end
        else:
            q["issued_at"] = {"$lte": end}
    cursor = invoices_collection.find(q).sort("issued_at", -1)
    out = []
    async for doc in cursor:
        out.append(InvoiceResponse(
            id=str(doc["_id"]),
            member_id=doc["member_id"],
            member_name=doc.get("member_name", ""),
            items=doc.get("items", []),
            total=doc["total"],
            status=doc.get("status", "Unpaid"),
            issued_at=doc["issued_at"],
            paid_at=doc.get("paid_at"),
        ))
    return out


@app.post("/billing/pay", response_model=InvoiceResponse)
async def billing_pay(invoice_id: str, background_tasks: BackgroundTasks):
    """Mark invoice as paid. Simulated UPI/cash. Sends payment notification."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(invoice_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid invoice ID")
    doc = await invoices_collection.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if doc.get("status") == "Paid":
        raise HTTPException(status_code=400, detail="Already paid")
    now = datetime.now(timezone.utc)
    await invoices_collection.update_one({"_id": oid}, {"$set": {"status": "Paid", "paid_at": now}})
    member = await members_collection.find_one({"_id": ObjectId(doc["member_id"])})
    if member:
        background_tasks.add_task(_notify_payment_received, member.get("name", ""), doc["total"], member.get("email", ""), member.get("phone", ""))
    updated = await invoices_collection.find_one({"_id": oid})
    return InvoiceResponse(
        id=str(updated["_id"]),
        member_id=updated["member_id"],
        member_name=updated.get("member_name", ""),
        items=updated.get("items", []),
        total=updated["total"],
        status=updated["status"],
        issued_at=updated["issued_at"],
        paid_at=updated.get("paid_at"),
    )


# ---------- Export to Excel (billing, members, payments) ----------

@app.get("/export/billing")
async def export_billing_excel():
    """Export billing/invoices to Excel."""
    import pandas as pd
    cursor = invoices_collection.find().sort("issued_at", -1)
    rows = []
    async for doc in cursor:
        rows.append({
            "id": str(doc["_id"]),
            "member_id": doc.get("member_id", ""),
            "member_name": doc.get("member_name", ""),
            "total": doc.get("total", 0),
            "status": doc.get("status", ""),
            "issued_at": str(doc.get("issued_at", "")),
            "paid_at": str(doc.get("paid_at", "")) if doc.get("paid_at") else "",
        })
    df = pd.DataFrame(rows)
    buf = BytesIO()
    df.to_excel(buf, index=False, engine="openpyxl")
    buf.seek(0)
    return StreamingResponse(buf, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", headers={"Content-Disposition": "attachment; filename=billing_history.xlsx"}    )


@app.get("/export/members")
async def export_members_excel():
    """Export members list to Excel."""
    import pandas as pd
    cursor = members_collection.find().sort("created_at", -1)
    rows = []
    async for doc in cursor:
        rows.append({
            "id": str(doc["_id"]),
            "name": doc.get("name", ""),
            "phone": doc.get("phone", ""),
            "email": doc.get("email", ""),
            "membership_type": doc.get("membership_type", ""),
            "batch": doc.get("batch", ""),
            "status": doc.get("status", ""),
            "last_attendance_date": str(_to_date(doc.get("last_attendance_date")) or ""),
        })
    df = pd.DataFrame(rows)
    buf = BytesIO()
    df.to_excel(buf, index=False, engine="openpyxl")
    buf.seek(0)
    return StreamingResponse(buf, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", headers={"Content-Disposition": "attachment; filename=members.xlsx"})


@app.get("/export/payments")
async def export_payments_excel():
    """Export payments list to Excel."""
    import pandas as pd
    cursor = payments_collection.find().sort("created_at", -1)
    rows = []
    async for doc in cursor:
        rows.append({
            "id": str(doc["_id"]),
            "member_id": doc.get("member_id", ""),
            "member_name": doc.get("member_name", ""),
            "amount": doc.get("amount", 0),
            "fee_type": doc.get("fee_type", ""),
            "period": doc.get("period", ""),
            "status": doc.get("status", ""),
            "due_date": str(_to_date(doc.get("due_date")) or ""),
            "paid_at": str(doc.get("paid_at")) if doc.get("paid_at") else "",
        })
    df = pd.DataFrame(rows)
    buf = BytesIO()
    df.to_excel(buf, index=False, engine="openpyxl")
    buf.seek(0)
    return StreamingResponse(buf, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", headers={"Content-Disposition": "attachment; filename=payments.xlsx"})
