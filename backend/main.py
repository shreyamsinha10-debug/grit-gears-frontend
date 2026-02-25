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

from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, EmailStr, Field, field_serializer
import jwt
from passlib.context import CryptContext

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
COLLECTION_GYMS = "gyms"
COLLECTION_GYM_ADMINS = "gym_admins"
COLLECTION_APP_CONFIG = "app_config"

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
gyms_collection = db[COLLECTION_GYMS]
gym_admins_collection = db[COLLECTION_GYM_ADMINS]
app_config_collection = db[COLLECTION_APP_CONFIG]

# Super admin auth
SUPER_ADMIN_LOGIN_ID = os.environ.get("SUPER_ADMIN_LOGIN_ID", "Dertz@info987656")
SUPER_ADMIN_PASSWORD = os.environ.get("SUPER_ADMIN_PASSWORD", "#include<376494")
# Legacy default gym admin (phone 9999999999) – shown in Super Admin list if not in DB
DEFAULT_GYM_ADMIN_LOGIN_ID = os.environ.get("DEFAULT_GYM_ADMIN_LOGIN_ID", "9999999999")
DEFAULT_GYM_ADMIN_PASSWORD = os.environ.get("DEFAULT_GYM_ADMIN_PASSWORD", "999999")
JWT_SECRET = os.environ.get("JWT_SECRET", "gym-saas-jwt-secret-change-in-production")
JWT_ALGORITHM = "HS256"
pwd_context = CryptContext(schemes=["bcrypt", "pbkdf2_sha256"], deprecated="auto")
# Fallback when bcrypt not installed (e.g. Windows without C++ build tools)
_pwd_fallback = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")


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


def normalize_phone(s: str) -> str:
    """Digits only, max 10 characters (gym member phone)."""
    digits = "".join(c for c in (s or "").strip() if c.isdigit())
    return digits[:10]


# ---------------------------------------------------------------------------
# App lifecycle: auto-mark inactive members who haven't visited in 90 days
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """On startup: ensure default gym for legacy; backfill gym_id; mark inactive 90d."""
    from datetime import timezone
    from bson import ObjectId

    # Ensure default gym exists for legacy admin (9999999999)
    default_gym = await gyms_collection.find_one({"name": "Default (Legacy)"})
    if not default_gym:
        default_gym_doc = {"name": "Default (Legacy)", "created_at": datetime.now(timezone.utc)}
        r = await gyms_collection.insert_one(default_gym_doc)
        default_gym_id = r.inserted_id
    else:
        default_gym_id = default_gym["_id"]
    await app_config_collection.update_one(
        {"_id": "default_gym_id"},
        {"$set": {"value": str(default_gym_id)}},
        upsert=True,
    )

    # Backfill gym_id for existing documents that don't have it (legacy data). Store as string to match JWT.
    default_gym_id_str = str(default_gym_id)
    await members_collection.update_many(
        {"gym_id": {"$exists": False}},
        {"$set": {"gym_id": default_gym_id_str}},
    )
    await attendance_collection.update_many(
        {"gym_id": {"$exists": False}},
        {"$set": {"gym_id": default_gym_id_str}},
    )
    await payments_collection.update_many(
        {"gym_id": {"$exists": False}},
        {"$set": {"gym_id": default_gym_id_str}},
    )
    await invoices_collection.update_many(
        {"gym_id": {"$exists": False}},
        {"$set": {"gym_id": default_gym_id_str}},
    )

    today = today_ist()
    cutoff = today - timedelta(days=90)
    cutoff_dt = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc)
    await members_collection.update_many(
        {"last_attendance_date": {"$exists": True, "$lt": cutoff_dt}},
        {"$set": {"status": "Inactive"}},
    )
    yield
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
    phone: str = Field(..., min_length=1, max_length=10)
    email: EmailStr
    membership_type: MembershipType
    batch: Batch
    status: str = Field(default="Active", max_length=50)
    address: str | None = None
    date_of_birth: date | None = None  # YYYY-MM-DD
    gender: str | None = None  # e.g. Male, Female, Other, Prefer not to say
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
    address: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
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
    address: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
    workout_schedule: str | None = None
    diet_chart: str | None = None


class MemberResetPasswordBody(BaseModel):
    """Gym Admin: reset a member's password."""
    new_password: str = Field(..., min_length=6)


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


# ---------- Auth & Super Admin ----------
class LoginRequest(BaseModel):
    login_id: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)


class LoginResponse(BaseModel):
    token: str
    role: str
    login_id: str
    member: MemberResponse | None = None


class SuperAdminAdminListItem(BaseModel):
    id: str
    gym_id: str
    gym_name: str
    login_id: str
    is_active: bool
    created_at: datetime


class SuperAdminCreateAdminBody(BaseModel):
    gym_name: str = Field(..., min_length=1)
    admin_login_id: str = Field(..., min_length=1)
    admin_password: str = Field(..., min_length=6)


class SuperAdminPatchAdminBody(BaseModel):
    is_active: bool | None = None


class SuperAdminResetPasswordBody(BaseModel):
    """Super admin: set a new password for a gym admin. Cannot recover existing password (stored hashed)."""
    new_password: str = Field(..., min_length=6)


class GymProfileResponse(BaseModel):
    """Current gym's profile for gym_admin (name, logo, name on invoices)."""
    id: str
    name: str
    logo_base64: str | None = None
    invoice_name: str | None = None  # Name shown on invoices; defaults to name if not set


class GymProfileUpdate(BaseModel):
    """Gym admin can update their gym's display name, logo, and invoice name."""
    name: str | None = None
    logo_base64: str | None = None
    invoice_name: str | None = None


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


# ---------- Auth: login (super_admin / gym_admin) ----------
def _encode_super_admin_jwt() -> str:
    from datetime import timezone
    payload = {"sub": SUPER_ADMIN_LOGIN_ID, "role": "super_admin", "exp": datetime.now(timezone.utc) + timedelta(days=7)}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _require_super_admin(authorization: str | None = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization[7:].strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        if payload.get("role") != "super_admin":
            raise HTTPException(status_code=403, detail="Super admin only")
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_gym_id(authorization: str | None = Header(None)) -> str:
    """Require gym_admin JWT; return gym_id for multi-tenant scoping. Use on all gym-scoped endpoints."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization required")
    token = authorization[7:].strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        if payload.get("role") != "gym_admin":
            raise HTTPException(status_code=403, detail="Gym admin access required")
        gym_id = payload.get("gym_id") or ""
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_gym_id_for_attendance_or_member_get(member_id: str, authorization: str | None = Header(None)) -> str:
    """Allow gym_admin (any member) or member (only own member_id). Returns gym_id for scoping."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization required")
    token = authorization[7:].strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        role = payload.get("role")
        gym_id = payload.get("gym_id") or ""
        if role == "gym_admin":
            if not gym_id:
                raise HTTPException(status_code=403, detail="Gym context missing")
            return gym_id
        if role == "member":
            if payload.get("sub") != member_id:
                raise HTTPException(status_code=403, detail="Not authorized for this member")
            if not gym_id:
                raise HTTPException(status_code=403, detail="Gym context missing")
            return gym_id
        raise HTTPException(status_code=403, detail="Gym admin or member access required")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_gym_id_for_payments(
    authorization: str | None = Header(None),
    member_id: str | None = Query(None, alias="member_id"),
) -> str:
    """Allow gym_admin (any) or member (only own payments when member_id=sub)."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization required")
    token = authorization[7:].strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        role = payload.get("role")
        gym_id = payload.get("gym_id") or ""
        if role == "gym_admin":
            if not gym_id:
                raise HTTPException(status_code=403, detail="Gym context missing")
            return gym_id
        if role == "member":
            if not member_id or payload.get("sub") != member_id:
                raise HTTPException(status_code=403, detail="Members can only list their own payments")
            if not gym_id:
                raise HTTPException(status_code=403, detail="Gym context missing")
            return gym_id
        raise HTTPException(status_code=403, detail="Gym admin or member access required")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def _gym_filter(gym_id: str):
    """Return a query dict to filter by gym_id (matches both string and ObjectId in DB)."""
    from bson import ObjectId
    try:
        oid = ObjectId(gym_id)
        return {"gym_id": {"$in": [gym_id, oid]}}
    except Exception:
        return {"gym_id": gym_id}


@app.post("/auth/login", response_model=LoginResponse)
async def auth_login(body: LoginRequest):
    login_id = (body.login_id or "").strip()
    password = body.password or ""

    if login_id == SUPER_ADMIN_LOGIN_ID and password == SUPER_ADMIN_PASSWORD:
        return LoginResponse(token=_encode_super_admin_jwt(), role="super_admin", login_id=login_id)

    from datetime import timezone
    admin_doc = await gym_admins_collection.find_one({"login_id": login_id})
    if admin_doc and pwd_context.verify(password, admin_doc.get("password_hash", "")):
        if not admin_doc.get("is_active", True):
            raise HTTPException(status_code=403, detail="Account disabled")
        gym = await gyms_collection.find_one({"_id": admin_doc["gym_id"]}) if admin_doc.get("gym_id") else None
        gym_name = gym.get("name", "") if gym else ""
        payload = {"sub": login_id, "role": "gym_admin", "gym_id": str(admin_doc["gym_id"]), "gym_name": gym_name, "exp": datetime.now(timezone.utc) + timedelta(days=7)}
        token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
        return LoginResponse(token=token, role="gym_admin", login_id=login_id)

    # Member login: by phone (login_id) + password
    phone_norm = normalize_phone(login_id)
    if phone_norm:
        member_doc = await members_collection.find_one({"phone": phone_norm})
        if member_doc:
            password_hash = member_doc.get("password_hash") or ""
            if password_hash and pwd_context.verify(password, password_hash):
                if (member_doc.get("status") or "Active") != "Active":
                    raise HTTPException(status_code=403, detail="Membership is not active")
                member_id = str(member_doc["_id"])
                gym_id = str(member_doc.get("gym_id") or "")
                if not gym_id:
                    raise HTTPException(status_code=403, detail="Member gym not set")
                payload = {"sub": member_id, "role": "member", "gym_id": gym_id, "exp": datetime.now(timezone.utc) + timedelta(days=7)}
                token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
                date_ist_str = today_ist().strftime("%Y-%m-%d")
                att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
                attendance_map = {member_id: att_doc} if att_doc else None
                member_resp = _doc_to_member_response(member_doc, attendance_map=attendance_map)
                return LoginResponse(token=token, role="member", login_id=login_id, member=member_resp)

    raise HTTPException(status_code=401, detail="Invalid login or password")


# ---------- Gym profile (gym_admin: get/update own gym name, logo, invoice name) ----------
async def _gym_doc_from_gym_id(gym_id: str):
    """Resolve gym document by gym_id (string). Returns None if not found."""
    from bson import ObjectId
    try:
        oid = ObjectId(gym_id)
    except Exception:
        return None
    return await gyms_collection.find_one({"_id": oid})


@app.get("/gym/profile", response_model=GymProfileResponse)
async def get_gym_profile(gym_id: str = Depends(get_gym_id)):
    """Get current gym's profile (name, logo, invoice name). For gym_admin only."""
    gym = await _gym_doc_from_gym_id(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    return GymProfileResponse(
        id=str(gym["_id"]),
        name=gym.get("name", ""),
        logo_base64=gym.get("logo_base64"),
        invoice_name=gym.get("invoice_name"),
    )


@app.patch("/gym/profile", response_model=GymProfileResponse)
async def update_gym_profile(body: GymProfileUpdate, gym_id: str = Depends(get_gym_id)):
    """Update current gym's name, logo, and/or invoice name. For gym_admin only."""
    from bson import ObjectId
    try:
        oid = ObjectId(gym_id)
    except Exception:
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
    if set_fields or unset_fields:
        update_op = {}
        if set_fields:
            update_op["$set"] = set_fields
        if unset_fields:
            update_op["$unset"] = unset_fields
        await gyms_collection.update_one({"_id": oid}, update_op)
    updated = await gyms_collection.find_one({"_id": oid})
    return GymProfileResponse(
        id=str(updated["_id"]),
        name=updated.get("name", ""),
        logo_base64=updated.get("logo_base64"),
        invoice_name=updated.get("invoice_name"),
    )


# ---------- Super Admin: list/create/patch gym admins ----------
@app.get("/super-admin/admins", response_model=list[SuperAdminAdminListItem])
async def super_admin_list_admins(_: dict = Depends(_require_super_admin)):
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
            created_at=doc.get("created_at", datetime.now(IST)),
        ))
    return out


@app.post("/super-admin/admins", response_model=SuperAdminAdminListItem)
async def super_admin_create_admin(body: SuperAdminCreateAdminBody, _: dict = Depends(_require_super_admin)):
    from bson import ObjectId
    from datetime import timezone
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


@app.patch("/super-admin/admins/{admin_id}", response_model=SuperAdminAdminListItem)
async def super_admin_patch_admin(admin_id: str, body: SuperAdminPatchAdminBody, _: dict = Depends(_require_super_admin)):
    from bson import ObjectId
    from datetime import timezone

    try:
        oid = ObjectId(admin_id)
    except Exception:
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
    return SuperAdminAdminListItem(
        id=str(doc["_id"]),
        gym_id=str(gym_id) if gym_id else "",
        gym_name=gym_name,
        login_id=doc.get("login_id", ""),
        is_active=bool(doc.get("is_active", True)),
        created_at=doc.get("created_at", datetime.now(IST)),
    )


@app.patch("/super-admin/admins/{admin_id}/password", response_model=dict)
async def super_admin_reset_admin_password(admin_id: str, body: SuperAdminResetPasswordBody, _: dict = Depends(_require_super_admin)):
    """Super admin: set a new password for a gym admin. Existing password cannot be viewed (stored hashed)."""
    from bson import ObjectId
    from datetime import timezone

    if admin_id == "legacy-default":
        raise HTTPException(
            status_code=400,
            detail="Legacy default admin (9999999999) password is set by server config. Cannot reset from here.",
        )

    try:
        oid = ObjectId(admin_id)
    except Exception:
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


# ---------- Members: CRUD, lookup, attendance stats ----------

@app.post("/members", response_model=MemberResponse)
async def create_member(member: MemberCreate, gym_id: str = Depends(get_gym_id)):
    from datetime import timezone
    doc = member.model_dump()
    doc["gym_id"] = gym_id
    if doc.get("date_of_birth") is not None:
        doc["date_of_birth"] = datetime.combine(doc["date_of_birth"], datetime.min.time())
    # Normalize phone: digits only, max 10 chars (member login uses by-phone)
    doc["phone"] = normalize_phone(doc.get("phone") or "")
    if not doc["phone"]:
        raise HTTPException(status_code=400, detail="Phone must contain at least one digit")
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
        {"member_id": mid, "member_name": doc["name"], "amount": REGISTRATION_FEE, "fee_type": "registration", "period": None, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id},
        {"member_id": mid, "member_name": doc["name"], "amount": monthly_amount, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id},
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
        address=doc.get("address"),
        date_of_birth=_to_date(doc.get("date_of_birth")),
        gender=doc.get("gender"),
        workout_schedule=doc.get("workout_schedule"),
        diet_chart=doc.get("diet_chart"),
        photo_base64=doc.get("photo_base64"),
        id_document_base64=doc.get("id_document_base64"),
        id_document_type=doc.get("id_document_type"),
    )


@app.get("/members/{member_id}", response_model=MemberResponse)
async def get_member_by_id(member_id: str, gym_id: str = Depends(get_gym_id_for_attendance_or_member_get)):
    """Get a single member by ID. Member must belong to current gym."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    q = {"_id": oid}
    q.update(_gym_filter(gym_id))
    doc = await members_collection.find_one(q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
        
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None
    
    return _doc_to_member_response(doc, attendance_map=attendance_map)


@app.get("/members/{member_id}/attendance-stats")
async def member_attendance_stats(member_id: str, gym_id: str = Depends(get_gym_id_for_attendance_or_member_get)):
    """Total visits, visits this month, and avg workout duration (minutes) for a member."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(_gym_filter(gym_id))
    if await members_collection.find_one(member_q) is None:
        raise HTTPException(status_code=404, detail="Member not found")
    att_q = {"member_id": member_id}
    att_q.update(_gym_filter(gym_id))
    total_visits = await attendance_collection.count_documents(att_q)
    today = today_ist()
    month_start = today.replace(day=1).strftime("%Y-%m-%d")
    month_end = today.strftime("%Y-%m-%d")
    visits_this_month = await attendance_collection.count_documents({
        "member_id": member_id,
        "date_ist": {"$gte": month_start, "$lte": month_end},
        **(_gym_filter(gym_id)),
    })
    cursor = attendance_collection.find(
        {"member_id": member_id, "check_out_at_utc": {"$exists": True, "$ne": None}, **_gym_filter(gym_id)}
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
async def list_members(skip: int = 0, limit: int = 100, brief: bool = False, gym_id: str = Depends(get_gym_id)):
    """List members. brief=True omits photo_base64 and id_document_base64 for faster list load. Use skip/limit for pagination."""
    skip = max(0, skip)
    limit = min(max(1, limit), 500)  # Cap at 500 for performance/security
    q = _gym_filter(gym_id)
    cursor = members_collection.find(q).sort("created_at", -1).skip(skip).limit(limit)
    
    # Fetch today's attendance for these members (same gym)
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_q = {"date_ist": date_ist_str}
    att_q.update(_gym_filter(gym_id))
    att_cursor = attendance_collection.find(att_q)
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
async def update_member(member_id: str, body: MemberUpdate, gym_id: str = Depends(get_gym_id)):
    """Admin: edit member details (name, phone, email, batch, status, PT fields, etc.) for corrections."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(_gym_filter(gym_id))
    update = {}
    if body.name is not None:
        update["name"] = body.name
    if body.phone is not None:
        update["phone"] = normalize_phone(body.phone)
        if not update["phone"]:
            raise HTTPException(status_code=400, detail="Phone must contain at least one digit")
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
    if body.address is not None:
        update["address"] = body.address.strip() if body.address else None
    if body.date_of_birth is not None:
        from datetime import time
        update["date_of_birth"] = datetime.combine(body.date_of_birth, time.min)
    if body.gender is not None:
        update["gender"] = body.gender.strip() if body.gender else None
    if not update:
        result = await members_collection.find_one(member_q)
        if not result:
            raise HTTPException(status_code=404, detail="Member not found")
        return _doc_to_member_response(result)
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
    
    return _doc_to_member_response(result, attendance_map=attendance_map)


@app.patch("/members/{member_id}/password", response_model=dict)
async def reset_member_password(member_id: str, body: MemberResetPasswordBody, gym_id: str = Depends(get_gym_id)):
    """Gym Admin: reset a member's password."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid ID")
    q = {"_id": oid}
    q.update(_gym_filter(gym_id))
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


@app.patch("/members/{member_id}/photo", response_model=MemberResponse)
async def update_member_photo(member_id: str, body: PhotoUpdate, gym_id: str = Depends(get_gym_id)):
    """Upload or remove member profile picture. Both member and admin can call this. Send photo_base64: null to delete."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(_gym_filter(gym_id))
    if body.photo_base64 is None:
        await members_collection.update_one(member_q, {"$unset": {"photo_base64": ""}})
    else:
        await members_collection.update_one(member_q, {"$set": {"photo_base64": body.photo_base64}})
    doc = await members_collection.find_one(member_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")
        
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None
    
    return _doc_to_member_response(doc, attendance_map=attendance_map)


@app.patch("/members/{member_id}/id-document", response_model=MemberResponse)
async def update_member_id_document(member_id: str, body: IdDocumentUpdate, gym_id: str = Depends(get_gym_id)):
    """Upload or remove identity document (Aadhar, Driving Licence, Voter ID, Passport). Send id_document_base64: null to delete."""
    from bson import ObjectId
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(_gym_filter(gym_id))
    if body.id_document_base64 is None:
        await members_collection.update_one(member_q, {"$unset": {"id_document_base64": "", "id_document_type": ""}})
    else:
        update = {"id_document_base64": body.id_document_base64}
        if body.id_document_type is not None:
            update["id_document_type"] = body.id_document_type
        await members_collection.update_one(member_q, {"$set": update})
    doc = await members_collection.find_one(member_q)
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
        address=doc.get("address"),
        date_of_birth=_to_date(doc.get("date_of_birth")),
        gender=doc.get("gender"),
        workout_schedule=doc.get("workout_schedule"),
        diet_chart=doc.get("diet_chart"),
        photo_base64=doc.get("photo_base64") if include_photos else None,
        id_document_base64=doc.get("id_document_base64") if include_photos else None,
        id_document_type=doc.get("id_document_type") if include_photos else None,
        today_status=today_status,
    )


def _to_date(v):
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


# ---------- Attendance ----------


# ---------- Attendance: check-in/check-out (IST), by date, summary ----------

@app.post("/attendance/check-in/{member_id}", response_model=AttendanceRecord)
async def check_in(member_id: str, gym_id: str = Depends(get_gym_id_for_attendance_or_member_get)):
    """Record check-in in IST. One check-in per member per calendar day (IST)."""
    from bson import ObjectId
    from datetime import timezone

    try:
        try:
            oid = ObjectId(member_id)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid member ID")

        member_q = {"_id": oid}
        member_q.update(_gym_filter(gym_id))
        member = await members_collection.find_one(member_q)
        if not member:
            raise HTTPException(status_code=404, detail="Member not found")

        now = now_ist()
        date_ist_str = now.strftime("%Y-%m-%d")
        batch = batch_from_ist(now)

        already_today = await attendance_collection.find_one(
            {"member_id": member_id, "date_ist": date_ist_str, **_gym_filter(gym_id)},
        )
        if already_today:
            raise HTTPException(
                status_code=400,
                detail="Already checked in today. One check-in per day allowed.",
            )

        if BATCH_CAPACITY and batch in BATCH_CAPACITY:
            cap = BATCH_CAPACITY[batch]
            batch_q = {"date_ist": date_ist_str, "batch": batch}
            batch_q.update(_gym_filter(gym_id))
            count_today_batch = await attendance_collection.count_documents(batch_q)
            if count_today_batch >= cap:
                raise HTTPException(
                    status_code=400,
                    detail=f"Batch full. {batch} batch has reached capacity ({cap}). Try another batch.",
                )

        check_in_at_utc = now.astimezone(timezone.utc)
        doc = {
            "member_id": member_id,
            "gym_id": gym_id,
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
            member_q,
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
async def attendance_summary(gym_id: str = Depends(get_gym_id)):
    """Today's check-ins, currently in gym, this week count, average daily (for dashboard cards)."""
    from datetime import timedelta
    q = _gym_filter(gym_id)
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    today_count = await attendance_collection.count_documents({**q, "date_ist": date_ist_str})
    today_check_outs = await attendance_collection.count_documents({
        **q,
        "date_ist": date_ist_str,
        "check_out_at_ist": {"$exists": True, "$ne": None, "$ne": ""},
    })
    currently_in = today_count - today_check_outs
    week_start = (today_ist() - timedelta(days=6)).strftime("%Y-%m-%d")
    this_week = await attendance_collection.count_documents({
        **q,
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
async def attendance_today(gym_id: str = Depends(get_gym_id)):
    """All check-ins for current date in IST."""
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    return await attendance_by_date(date_ist_str, gym_id)


@app.get("/attendance/by-date", response_model=list[AttendanceRecord])
async def attendance_by_date_endpoint(date: str, gym_id: str = Depends(get_gym_id)):
    """All check-ins for a given date (YYYY-MM-DD). Use for date picker."""
    if len(date) != 10 or date[4] != "-" or date[7] != "-":
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")
    return await attendance_by_date(date, gym_id)


@app.get("/attendance/by-date-range", response_model=list[AttendanceRecord])
async def attendance_by_date_range(date_from: str, date_to: str, gym_id: str = Depends(get_gym_id)):
    """All check-ins in date range (YYYY-MM-DD). For daily/monthly/historical view."""
    if len(date_from) != 10 or date_from[4] != "-" or date_from[7] != "-" or len(date_to) != 10 or date_to[4] != "-" or date_to[7] != "-":
        raise HTTPException(status_code=400, detail="date_from and date_to must be YYYY-MM-DD")
    if date_from > date_to:
        raise HTTPException(status_code=400, detail="date_from must be <= date_to")
    q = {"date_ist": {"$gte": date_from, "$lte": date_to}}
    q.update(_gym_filter(gym_id))
    cursor = attendance_collection.find(q).sort([("date_ist", 1), ("batch", 1), ("check_in_at_utc", 1)])
    return await _attendance_docs_to_records(cursor)


@app.get("/attendance/heatmap")
async def attendance_heatmap(
    date_from: str | None = Query(None, description="Start date YYYY-MM-DD (default: 14 days ago)"),
    date_to: str | None = Query(None, description="End date YYYY-MM-DD (default: today)"),
    gym_id: str = Depends(get_gym_id),
):
    """
    Occupancy heatmap for gym admin: per (date, hour) how many people were in the gym.
    Returns today summary, heatmap grid (date_ist, hour, count), avg session duration, quietest slots.
    """
    from collections import defaultdict

    today_str = today_ist().strftime("%Y-%m-%d")
    if date_from is None or date_to is None:
        start = today_ist() - timedelta(days=14)
        end = today_ist()
        date_from = start.strftime("%Y-%m-%d")
        date_to = end.strftime("%Y-%m-%d")
    else:
        if len(date_from) != 10 or date_from[4] != "-" or len(date_to) != 10 or date_to[4] != "-":
            raise HTTPException(status_code=400, detail="date_from and date_to must be YYYY-MM-DD")
        if date_from > date_to:
            raise HTTPException(status_code=400, detail="date_from must be <= date_to")

    q = {"date_ist": {"$gte": date_from, "$lte": date_to}}
    q.update(_gym_filter(gym_id))
    cursor = attendance_collection.find(q)

    grid = defaultdict(int)
    durations_minutes = []

    async for doc in cursor:
        date_ist = doc.get("date_ist") or ""
        if not date_ist:
            continue
        try:
            ci_str = doc.get("check_in_at_ist")
            if not ci_str:
                continue
            if hasattr(ci_str, "isoformat"):
                check_in = ci_str.astimezone(IST) if getattr(ci_str, "tzinfo", None) else datetime.fromisoformat(str(ci_str).replace("Z", "+00:00")).astimezone(IST)
            else:
                s = str(ci_str).strip()
                if s and "+" not in s and "Z" not in s:
                    s = s + "+05:30"
                check_in = datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(IST)
        except Exception:
            continue
        co_str = doc.get("check_out_at_ist") or doc.get("check_out_at_utc")
        if co_str:
            try:
                if hasattr(co_str, "isoformat"):
                    check_out = co_str.astimezone(IST) if getattr(co_str, "tzinfo", None) else datetime.fromisoformat(str(co_str).replace("Z", "+00:00")).astimezone(IST)
                else:
                    s = str(co_str).strip()
                    if s and "+" not in s and "Z" not in s:
                        s = s + "+05:30"
                    check_out = datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(IST)
            except Exception:
                check_out = check_in.replace(hour=23, minute=59)
        else:
            check_out = check_in.replace(hour=23, minute=59)
        if check_out.date() != check_in.date():
            check_out = check_in.replace(hour=23, minute=59)
        h_start = check_in.hour
        h_end = check_out.hour
        for h in range(h_start, min(h_end + 1, 24)):
            grid[(date_ist, h)] += 1
        if co_str:
            durations_minutes.append((check_out - check_in).total_seconds() / 60)

    today_count = await attendance_collection.count_documents({**_gym_filter(gym_id), "date_ist": today_str})
    today_check_outs = await attendance_collection.count_documents({
        **_gym_filter(gym_id),
        "date_ist": today_str,
        "check_out_at_ist": {"$exists": True, "$ne": None, "$ne": ""},
    })
    currently_in_gym = today_count - today_check_outs

    heatmap_list = [{"date_ist": d, "hour": h, "count": c} for (d, h), c in sorted(grid.items())]
    avg_duration = round(sum(durations_minutes) / len(durations_minutes), 1) if durations_minutes else None

    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    dow_hour_agg = defaultdict(list)
    for (d, h), c in grid.items():
        try:
            dt = datetime.strptime(d, "%Y-%m-%d")
            dow = day_names[dt.weekday()]
            dow_hour_agg[(dow, h)].append(c)
        except Exception:
            pass
    quietest = []
    for (dow, h), counts in dow_hour_agg.items():
        avg = sum(counts) / len(counts) if counts else 0
        quietest.append({"day_of_week": dow, "hour": h, "avg_count": round(avg, 1), "sample_days": len(counts)})
    quietest.sort(key=lambda x: (x["avg_count"], -x["sample_days"]))
    quietest_slots = quietest[:15]
    quietest_keys = {(s["day_of_week"], s["hour"]) for s in quietest_slots}
    busiest = sorted(quietest, key=lambda x: (-x["avg_count"], -x["sample_days"]))
    busiest_slots = [s for s in busiest[:15] if (s["day_of_week"], s["hour"]) not in quietest_keys]

    return {
        "today_summary": {
            "check_ins": today_count,
            "currently_in_gym": currently_in_gym,
            "avg_duration_minutes": avg_duration,
        },
        "date_from": date_from,
        "date_to": date_to,
        "heatmap": heatmap_list,
        "avg_duration_minutes": avg_duration,
        "quietest_slots": quietest_slots,
        "busiest_slots": busiest_slots,
    }


@app.post("/attendance/check-out/{member_id}", response_model=AttendanceRecord)
async def check_out(member_id: str, gym_id: str = Depends(get_gym_id_for_attendance_or_member_get)):
    """Record check-out for today's check-in (IST)."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(_gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_q = {"member_id": member_id, "date_ist": date_ist_str}
    att_q.update(_gym_filter(gym_id))
    doc = await attendance_collection.find_one(att_q)
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


async def attendance_by_date(date_ist_str: str, gym_id: str) -> list:
    q = {"date_ist": date_ist_str}
    q.update(_gym_filter(gym_id))
    cursor = attendance_collection.find(q).sort([("batch", 1), ("check_in_at_utc", 1)])
    return await _attendance_docs_to_records(cursor)


@app.delete("/attendance/{attendance_id}")
async def delete_attendance(attendance_id: str, gym_id: str = Depends(get_gym_id)):
    """Admin: remove a check-in record (e.g. wrong person or duplicate)."""
    from bson import ObjectId
    try:
        oid = ObjectId(attendance_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid attendance ID")
    q = {"_id": oid}
    q.update(_gym_filter(gym_id))
    result = await attendance_collection.delete_one(q)
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Attendance record not found")
    return {"message": "Attendance record deleted"}


INACTIVE_DAYS_THRESHOLD = 90


@app.post("/admin/mark-inactive-by-attendance")
async def mark_inactive_by_attendance(gym_id: str = Depends(get_gym_id)):
    """
    Only mark Inactive when last_attendance_date exists and is older than 90 days (IST).
    Members who have never checked in (no last_attendance_date) are left unchanged.
    """
    from datetime import timezone

    today = today_ist()
    cutoff = today - timedelta(days=INACTIVE_DAYS_THRESHOLD)
    cutoff_dt = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc)
    q = {"last_attendance_date": {"$exists": True, "$lt": cutoff_dt}}
    q.update(_gym_filter(gym_id))
    result = await members_collection.update_many(
        q,
        {"$set": {"status": "Inactive"}},
    )
    return {"updated_count": result.modified_count, "cutoff_date_ist": cutoff.isoformat()}


# ---------- Payments & Fees ----------

# ---------- Payments: list, fees summary, log monthly, mark paid ----------

@app.get("/payments", response_model=list[PaymentResponse])
async def list_payments(member_id: str | None = None, status: str | None = None, limit: int = 1000, gym_id: str = Depends(get_gym_id_for_payments)):
    """List payments. Filter by member_id and/or status (Paid/Due/Overdue). Capped at 1000 for performance."""
    from datetime import timezone
    q = _gym_filter(gym_id)
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
async def fees_summary(gym_id: str = Depends(get_gym_id)):
    """Paid/Due/Overdue counts and total amounts for Fees Management tab."""
    from datetime import timezone
    today = today_ist()
    today_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    q = _gym_filter(gym_id)
    pipeline = [
        {"$match": q},
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
        {**q, "status": "Due", "due_date": {"$lt": today_dt}},
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
async def log_monthly_payment(body: LogMonthlyPaymentBody, gym_id: str = Depends(get_gym_id)):
    """Create a monthly payment record marked as Paid (for existing member payment logging)."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(body.member_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(_gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
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
        "gym_id": gym_id,
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
        "gym_id": gym_id,
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
async def update_payment_status(payment_id: str, body: PaymentStatusUpdate, gym_id: str = Depends(get_gym_id)):
    """Admin: edit payment status for corrections (e.g. revert Paid to Due)."""
    from bson import ObjectId
    try:
        oid = ObjectId(payment_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid payment ID")
    pay_q = {"_id": oid}
    pay_q.update(_gym_filter(gym_id))
    doc = await payments_collection.find_one(pay_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Payment not found")
    update = {"status": body.status}
    if body.status != "Paid":
        update["paid_at"] = None
    await payments_collection.update_one(pay_q, {"$set": update})
    updated = await payments_collection.find_one(pay_q)
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
async def record_payment(member_id: str, payment_id: str, background_tasks: BackgroundTasks, gym_id: str = Depends(get_gym_id)):
    """Record a payment (simulated). Sends payment-received notification."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(payment_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid payment ID")
    pay_q = {"_id": oid, "member_id": member_id}
    pay_q.update(_gym_filter(gym_id))
    doc = await payments_collection.find_one(pay_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Payment not found")
    if doc["status"] == "Paid":
        raise HTTPException(status_code=400, detail="Already paid")
    now = datetime.now(timezone.utc)
    await payments_collection.update_one(
        pay_q,
        {"$set": {"status": "Paid", "paid_at": now}},
    )
    member_q = {"_id": ObjectId(member_id)}
    member_q.update(_gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if member:
        background_tasks.add_task(_notify_payment_received, member.get("name", ""), doc["amount"], member.get("email", ""), member.get("phone", ""))
    updated = await payments_collection.find_one(pay_q)
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
async def analytics_dashboard(date_from: str | None = None, date_to: str | None = None, gym_id: str = Depends(get_gym_id)):
    """
    Total Active/Inactive, Total Collections (₹), Pending Dues, Regular vs PT split.
    Optional date_from, date_to (YYYY-MM-DD): add attendance_count_in_range and payments_received_in_range for that period.
    """
    from datetime import timezone
    q = _gym_filter(gym_id)
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
        from datetime import datetime as dt_parse
        start = dt_parse.strptime(date_from + " 00:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=IST)
        end = dt_parse.strptime(date_to + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=IST)
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


@app.post("/admin/run-fee-reminders")
async def run_fee_reminders(background_tasks: BackgroundTasks, gym_id: str = Depends(get_gym_id)):
    """Send Payment Reminders: simulated WhatsApp to all members with unpaid fees."""
    from utils import send_notification
    from bson import ObjectId
    q = _gym_filter(gym_id)
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
        member_q.update(_gym_filter(gym_id))
        member = await members_collection.find_one(member_q)
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
async def seed_inactive_test(gym_id: str = Depends(get_gym_id)):
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
async def billing_issue(body: BillingIssueWalkIn, gym_id: str = Depends(get_gym_id)):
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
        "gym_id": gym_id,
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
        "gym_id": gym_id,
    }
    inv_result = await invoices_collection.insert_one(inv_doc)
    due_dt = datetime(today_ist().year, today_ist().month, today_ist().day, tzinfo=timezone.utc)
    period = today_ist().strftime("%Y-%m")
    await payments_collection.insert_many([
        {"member_id": mid, "member_name": body.name, "amount": reg_amount, "fee_type": "registration", "period": None, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id},
        {"member_id": mid, "member_name": body.name, "amount": monthly_amount, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id},
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
    gym_id: str = Depends(get_gym_id),
):
    """List invoices. Optional: member_id, search (invoice id or member name), date_from, date_to (YYYY-MM-DD)."""
    q = _gym_filter(gym_id)
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
async def billing_pay(invoice_id: str, background_tasks: BackgroundTasks, gym_id: str = Depends(get_gym_id)):
    """Mark invoice as paid. Simulated UPI/cash. Sends payment notification."""
    from bson import ObjectId
    from datetime import timezone
    try:
        oid = ObjectId(invoice_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid invoice ID")
    inv_q = {"_id": oid}
    inv_q.update(_gym_filter(gym_id))
    doc = await invoices_collection.find_one(inv_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if doc.get("status") == "Paid":
        raise HTTPException(status_code=400, detail="Already paid")
    now = datetime.now(timezone.utc)
    await invoices_collection.update_one(inv_q, {"$set": {"status": "Paid", "paid_at": now}})
    member_q = {"_id": ObjectId(doc["member_id"])}
    member_q.update(_gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if member:
        background_tasks.add_task(_notify_payment_received, member.get("name", ""), doc["total"], member.get("email", ""), member.get("phone", ""))
    updated = await invoices_collection.find_one(inv_q)
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
async def export_billing_excel(gym_id: str = Depends(get_gym_id)):
    """Export billing/invoices to Excel."""
    import pandas as pd
    q = _gym_filter(gym_id)
    cursor = invoices_collection.find(q).sort("issued_at", -1)
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
async def export_members_excel(gym_id: str = Depends(get_gym_id)):
    """Export members list to Excel."""
    import pandas as pd
    q = _gym_filter(gym_id)
    cursor = members_collection.find(q).sort("created_at", -1)
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
async def export_payments_excel(gym_id: str = Depends(get_gym_id)):
    """Export payments list to Excel."""
    import pandas as pd
    q = _gym_filter(gym_id)
    cursor = payments_collection.find(q).sort("created_at", -1)
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
