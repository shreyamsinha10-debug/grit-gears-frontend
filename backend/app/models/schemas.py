"""
Pydantic request/response schemas for the GymSaaS API.

All models are defined here so the app has no dependency on backend.main.
"""

from datetime import date, datetime
from enum import Enum

from pydantic import BaseModel, EmailStr, Field, field_serializer


class MembershipType(str, Enum):
    regular = "Regular"
    pt = "PT"


class Batch(str, Enum):
    morning = "Morning"
    evening = "Evening"
    ladies = "Ladies"


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


class LoginRequest(BaseModel):
    login_id: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)


class LoginResponse(BaseModel):
    token: str
    role: str
    login_id: str
    member: MemberResponse | None = None


# --- Member CRUD / documents ---

class MemberCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    phone: str = Field(..., min_length=1, max_length=10)
    email: EmailStr
    membership_type: MembershipType
    batch: str = Field(..., min_length=1, max_length=120)
    status: str = Field(default="Active", max_length=50)
    address: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
    photo_base64: str | None = None
    id_document_base64: str | None = None
    id_document_type: str | None = None
    plan_id: str | None = None


class MemberPTUpdate(BaseModel):
    workout_schedule: str | None = None
    diet_chart: str | None = None


class MemberUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    membership_type: MembershipType | None = None
    batch: str | None = None
    status: str | None = None
    address: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
    workout_schedule: str | None = None
    diet_chart: str | None = None


class MemberResetPasswordBody(BaseModel):
    new_password: str = Field(..., min_length=6)


class PhotoUpdate(BaseModel):
    photo_base64: str | None = None


class IdDocumentUpdate(BaseModel):
    id_document_base64: str | None = None
    id_document_type: str | None = None


# --- Messages ---

class MessageCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    body: str = Field(..., min_length=1, max_length=5000)
    recipient_type: str = Field(..., pattern="^(all_active|members)$")
    recipient_member_ids: list[str] | None = None


class MessageUpdate(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=200)
    body: str | None = Field(None, min_length=1, max_length=5000)


class MessageResponse(BaseModel):
    id: str
    gym_id: str
    recipient_type: str
    recipient_member_ids: list[str]
    title: str
    body: str
    created_at: datetime
    updated_at: datetime | None
    deleted_at: datetime | None


# --- Payments ---

class PaymentResponse(BaseModel):
    id: str
    member_id: str
    member_name: str
    amount: int
    fee_type: str
    period: str | None = None
    status: str
    due_date: date | None = None
    paid_at: datetime | None = None
    created_at: datetime


class PaymentStatusUpdate(BaseModel):
    status: str = Field(..., pattern="^(Paid|Due|Overdue)$")


class LogMonthlyPaymentBody(BaseModel):
    member_id: str
    period: str
    amount: int
    payment_date: str | None = None


# --- Invoices / Billing ---

class InvoiceItem(BaseModel):
    description: str
    amount: int


class InvoiceCreate(BaseModel):
    member_id: str
    items: list[InvoiceItem]


class InvoiceResponse(BaseModel):
    id: str
    member_id: str
    member_name: str
    items: list[dict]
    total: int
    status: str
    issued_at: datetime
    paid_at: datetime | None = None
    bill_number: str | None = None
    payment_method: str | None = None
    notes: str | None = None
    end_date: datetime | None = None
    member_phone: str | None = None
    member_email: str | None = None
    batch: str | None = None


class CreateBillItem(BaseModel):
    description: str = Field(..., min_length=1)
    amount: int = Field(..., ge=0)


class CreateBillRequest(BaseModel):
    member_id: str = Field(..., min_length=1)
    items: list[CreateBillItem] = Field(..., min_length=1)
    total: int = Field(..., ge=0)
    payment_method: str = Field(default="Cash")
    payment_date: str = Field(...)
    end_date: str | None = None
    member_phone: str | None = None
    member_email: str | None = None
    batch: str | None = None
    reference: str | None = None
    notes: str | None = None


class InvoiceUpdate(BaseModel):
    items: list[CreateBillItem] | None = None
    total: int | None = None
    payment_date: str | None = None
    end_date: str | None = None
    member_phone: str | None = None
    member_email: str | None = None
    batch: str | None = None
    notes: str | None = None


class BillingIssueWalkIn(BaseModel):
    name: str = Field(..., min_length=1)
    phone: str = Field(..., min_length=1)
    email: EmailStr
    membership_type: MembershipType
    batch: str = Field(..., min_length=1, max_length=120)


# --- Attendance ---

class AttendanceRecord(BaseModel):
    id: str
    member_id: str
    member_name: str
    member_phone: str | None = None
    check_in_at: datetime
    date_ist: str
    batch: str
    check_out_at: datetime | None = None

    @field_serializer("check_in_at")
    def serialize_check_in_at(self, dt: datetime) -> str:
        return dt.isoformat()

    @field_serializer("check_out_at")
    def serialize_check_out_at(self, dt: datetime | None) -> str | None:
        return dt.isoformat() if dt else None


# --- Gym profile / Super Admin ---

class GymProfileResponse(BaseModel):
    id: str
    name: str
    logo_base64: str | None = None
    invoice_name: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    pin_code: str | None = None
    phone: str | None = None
    terms_and_conditions: str | None = None
    batches: list[dict] | None = None
    plans: list[dict] | None = None


class GymBatchItem(BaseModel):
    id: str | None = None
    name: str = Field(..., min_length=1, max_length=120)
    description: str | None = Field(None, max_length=500)
    start_time: str | None = Field(None, max_length=10)
    end_time: str | None = Field(None, max_length=10)


class GymMembershipPlanItem(BaseModel):
    id: str | None = None
    name: str = Field(..., min_length=1, max_length=50)
    description: str | None = Field(None, max_length=200)
    price: int = Field(..., ge=0)
    duration_type: str = Field(..., pattern="^(1m|2m|3m|6m|1yr|one_time)$")
    is_active: bool = True
    registration_fee: int | None = Field(None, ge=0)
    waive_registration_fee: bool = False


class GymProfileUpdate(BaseModel):
    name: str | None = None
    logo_base64: str | None = None
    invoice_name: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    pin_code: str | None = None
    phone: str | None = None
    terms_and_conditions: str | None = None
    batches: list[GymBatchItem] | None = None
    plans: list[GymMembershipPlanItem] | None = None


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
    new_password: str = Field(..., min_length=6)


# --- Import ---

class MemberImportResult(BaseModel):
    created: int = 0
    updated: int = 0
    errors: list[dict] = []


__all__ = [
    "MembershipType",
    "Batch",
    "TodayAttendance",
    "MemberResponse",
    "LoginRequest",
    "LoginResponse",
    "MemberCreate",
    "MemberPTUpdate",
    "MemberUpdate",
    "MemberResetPasswordBody",
    "PhotoUpdate",
    "IdDocumentUpdate",
    "MessageCreate",
    "MessageUpdate",
    "MessageResponse",
    "PaymentResponse",
    "PaymentStatusUpdate",
    "LogMonthlyPaymentBody",
    "InvoiceItem",
    "InvoiceCreate",
    "InvoiceResponse",
    "CreateBillItem",
    "CreateBillRequest",
    "InvoiceUpdate",
    "BillingIssueWalkIn",
    "AttendanceRecord",
    "GymProfileResponse",
    "GymProfileUpdate",
    "GymBatchItem",
    "GymMembershipPlanItem",
    "SuperAdminAdminListItem",
    "SuperAdminCreateAdminBody",
    "SuperAdminPatchAdminBody",
    "SuperAdminResetPasswordBody",
    "MemberImportResult",
]
