"""
Auth router – login (super_admin, gym_admin, member), owner-claim, forgot-password.
"""

import secrets
from datetime import datetime, timedelta, timezone
from typing import Iterable

import jwt
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.core.config import settings
from app.core.security import _pwd_fallback, pwd_context
from app.db.database import (
    attendance_collection,
    gym_admins_collection,
    gyms_collection,
    members_collection,
)
from app.models.schemas import LoginRequest, LoginResponse
from app.utils.email import send_email_async
from app.utils.helpers import doc_to_member_response
from app.utils.time_utils import normalize_phone, today_ist

router = APIRouter()


def _encode_super_admin_jwt() -> str:
    payload = {
        "sub": settings.super_admin_login_id,
        "role": "super_admin",
        "exp": datetime.now(timezone.utc) + timedelta(days=7),
    }
    return jwt.encode(
        payload, settings.jwt_secret, algorithm=settings.jwt_algorithm
    )


@router.post("/login", response_model=LoginResponse)
async def auth_login(body: LoginRequest):
    login_id = (body.login_id or "").strip()
    password = body.password or ""

    if login_id == settings.super_admin_login_id and password == settings.super_admin_password:
        return LoginResponse(
            token=_encode_super_admin_jwt(),
            role="super_admin",
            login_id=login_id,
        )

    admin_doc = await gym_admins_collection.find_one({"login_id": login_id})
    if admin_doc and pwd_context.verify(password, admin_doc.get("password_hash", "")):
        if not admin_doc.get("is_active", True):
            raise HTTPException(status_code=403, detail="Account disabled")
        gym = (
            await gyms_collection.find_one({"_id": admin_doc["gym_id"]})
            if admin_doc.get("gym_id")
            else None
        )
        gym_name = gym.get("name", "") if gym else ""
        payload = {
            "sub": login_id,
            "role": "gym_admin",
            "gym_id": str(admin_doc["gym_id"]),
            "gym_name": gym_name,
            "exp": datetime.now(timezone.utc) + timedelta(days=7),
        }
        token = jwt.encode(
            payload, settings.jwt_secret, algorithm=settings.jwt_algorithm
        )
        return LoginResponse(token=token, role="gym_admin", login_id=login_id)

    phone_norm = normalize_phone(login_id)
    if phone_norm:
        member_doc = await members_collection.find_one({"phone": phone_norm})
        if member_doc:
            password_hash = member_doc.get("password_hash") or ""
            if password_hash and pwd_context.verify(password, password_hash):
                if (member_doc.get("status") or "Active") != "Active":
                    raise HTTPException(
                        status_code=403,
                        detail="Portal access is blocked. Your membership is not active.",
                    )
                member_id = str(member_doc["_id"])
                gym_id = str(member_doc.get("gym_id") or "")
                if not gym_id:
                    raise HTTPException(status_code=403, detail="Member gym not set")
                payload = {
                    "sub": member_id,
                    "role": "member",
                    "gym_id": gym_id,
                    "exp": datetime.now(timezone.utc) + timedelta(days=7),
                }
                token = jwt.encode(
                    payload, settings.jwt_secret, algorithm=settings.jwt_algorithm
                )
                date_ist_str = today_ist().strftime("%Y-%m-%d")
                att_doc = await attendance_collection.find_one(
                    {"member_id": member_id, "date_ist": date_ist_str}
                )
                attendance_map = {member_id: att_doc} if att_doc else None
                member_resp = await doc_to_member_response(
                    member_doc, attendance_map=attendance_map
                )
                return LoginResponse(
                    token=token, role="member", login_id=login_id, member=member_resp
                )

    raise HTTPException(status_code=401, detail="Invalid login or password")


@router.post("/owner-claim", response_model=LoginResponse)
async def auth_owner_claim(body: LoginRequest):
    """Login as gym_admin only if one already exists for this login_id. Backward compatibility."""
    login_id = (body.login_id or "").strip()
    password = body.password or ""

    admin_doc = await gym_admins_collection.find_one({"login_id": login_id})
    if not admin_doc or not pwd_context.verify(
        password, admin_doc.get("password_hash", "")
    ):
        raise HTTPException(status_code=401, detail="Invalid login or password")
    if not admin_doc.get("is_active", True):
        raise HTTPException(status_code=403, detail="Account disabled")
    gym = (
        await gyms_collection.find_one({"_id": admin_doc["gym_id"]})
        if admin_doc.get("gym_id")
        else None
    )
    gym_name = gym.get("name", "") if gym else ""
    payload = {
        "sub": login_id,
        "role": "gym_admin",
        "gym_id": str(admin_doc["gym_id"]),
        "gym_name": gym_name,
        "exp": datetime.now(timezone.utc) + timedelta(days=7),
    }
    token = jwt.encode(
        payload, settings.jwt_secret, algorithm=settings.jwt_algorithm
    )
    return LoginResponse(token=token, role="gym_admin", login_id=login_id)


class ForgotPasswordRequest(BaseModel):
    email_or_phone: str = Field(..., min_length=3)


class ForgotPasswordResponse(BaseModel):
    message: str


def _generate_temp_password(length: int = 8) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#$%!"
    return "".join(secrets.choice(alphabet) for _ in range(length))


async def _set_member_temporary_password(
    member_doc: dict, recipients: Iterable[str]
) -> None:
    temp_password = _generate_temp_password()
    try:
        password_hash = pwd_context.hash(temp_password)
    except Exception:
        password_hash = _pwd_fallback.hash(temp_password)

    await members_collection.update_one(
        {"_id": member_doc["_id"]},
        {"$set": {"password_hash": password_hash}},
    )

    body_text = (
        "You requested a temporary password for your gym account.\n\n"
        f"Temporary password: {temp_password}\n\n"
        "Use this password to log in and change it immediately from your profile.\n"
        "If you did not request this, please contact your gym administrator."
    )
    await send_email_async(recipients, "Your temporary gym password", body_text)


@router.post("/forgot-password", response_model=ForgotPasswordResponse)
async def forgot_password(body: ForgotPasswordRequest) -> ForgotPasswordResponse:
    identifier = (body.email_or_phone or "").strip()
    if not identifier:
        raise HTTPException(status_code=400, detail="email_or_phone is required")

    member_doc = None
    recipients: list[str] = []

    if "@" in identifier:
        member_doc = await members_collection.find_one({"email": identifier})
        if member_doc:
            recipients.append(identifier)
    else:
        phone_norm = normalize_phone(identifier)
        member_doc = await members_collection.find_one(
            {"phone": phone_norm}
        ) or await members_collection.find_one({"phone": identifier})
        if member_doc and member_doc.get("email"):
            recipients.append(member_doc["email"])

    if not member_doc or not recipients:
        return ForgotPasswordResponse(
            message="If an account exists for the provided contact, a temporary password has been sent."
        )

    await _set_member_temporary_password(member_doc, recipients)
    return ForgotPasswordResponse(
        message="If an account exists for the provided contact, a temporary password has been sent."
    )


__all__ = ["router"]
