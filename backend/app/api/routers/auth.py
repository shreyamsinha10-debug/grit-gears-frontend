"""
Auth router – login (super_admin, gym_admin, member), owner-claim, forgot-password.
"""

import json
import logging
import os
import re
import secrets
import time
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Iterable

import jwt
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, model_validator

from app.core.config import settings
from app.core.security import _pwd_fallback, pwd_context, verify_password
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

logger = logging.getLogger(__name__)
router = APIRouter()

# #region agent log
def _debug_log(location: str, message: str, data: dict, hypothesis_id: str):
    payload = json.dumps({"sessionId": "1cf765", "location": location, "message": message, "data": data, "timestamp": int(time.time() * 1000), "hypothesisId": hypothesis_id}) + "\n"
    for log_path in [
        Path("/home/animesh/Documents/GymSaaS/.cursor/debug-1cf765.log"),
        Path(__file__).resolve().parent.parent.parent / "debug-1cf765.log",
    ]:
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with open(log_path, "a") as f:
                f.write(payload)
            break
        except Exception:
            continue
# #endregion


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
    if not admin_doc and "@" in login_id:
        pattern = re.escape(login_id)
        admin_doc = await gym_admins_collection.find_one(
            {"login_id": {"$regex": f"^{pattern}$", "$options": "i"}}
        )
    # #region agent log
    _debug_log("auth.py:login:admin_check", "admin login check", {"admin_found": admin_doc is not None, "has_password_hash": bool(admin_doc.get("password_hash") if admin_doc else False), "verify_ok": bool(admin_doc and verify_password(password, admin_doc.get("password_hash") or ""))}, "L")
    # #endregion
    if admin_doc and verify_password(password, admin_doc.get("password_hash") or ""):
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
    if not admin_doc and "@" in login_id:
        pattern = re.escape(login_id)
        admin_doc = await gym_admins_collection.find_one(
            {"login_id": {"$regex": f"^{pattern}$", "$options": "i"}}
        )
    if not admin_doc or not verify_password(
        password, admin_doc.get("password_hash") or ""
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
    """Accept either email_or_phone (new UI) or email (legacy UI) for compatibility."""
    email_or_phone: str | None = Field(None, min_length=3)
    email: str | None = Field(None, min_length=3)

    @model_validator(mode="after")
    def require_identifier(self):
        a = (self.email_or_phone or "").strip()
        b = (self.email or "").strip()
        if len(a) >= 3 or len(b) >= 3:
            return self
        raise ValueError("Provide email_or_phone or email (at least 3 characters)")


class ForgotPasswordResponse(BaseModel):
    message: str


class ResetPasswordRequest(BaseModel):
    token: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=6)


RESET_TOKEN_EXPIRY_HOURS = 1


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


async def _set_admin_temporary_password(
    admin_doc: dict, recipients: Iterable[str]
) -> None:
    """Set a temporary password for a gym admin and email it. Admins use login_id (often email)."""
    temp_password = _generate_temp_password()
    try:
        password_hash = pwd_context.hash(temp_password)
    except Exception:
        password_hash = _pwd_fallback.hash(temp_password)

    await gym_admins_collection.update_one(
        {"_id": admin_doc["_id"]},
        {"$set": {"password_hash": password_hash}},
    )

    body_text = (
        "You requested a password reset for your gym admin account.\n\n"
        f"Temporary password: {temp_password}\n\n"
        "Use this password to log in and change it from your profile or settings.\n"
        "If you did not request this, please contact support or your super admin."
    )
    await send_email_async(recipients, "Your temporary gym admin password", body_text)


def _build_reset_link(token: str) -> str:
    base = (settings.frontend_url or "").strip().rstrip("/")
    if not base:
        return ""
    return f"{base}/?token={token}"


async def _send_member_reset_link(
    member_doc: dict, recipients: Iterable[str], token: str
) -> None:
    link = _build_reset_link(token)
    body_text = (
        "You requested a password reset for your gym account.\n\n"
        "Click the link below to set a new password (link expires in 1 hour):\n\n"
        f"{link}\n\n"
        "If you did not request this, please ignore this email or contact your gym administrator."
    )
    await send_email_async(recipients, "Reset your gym password", body_text)


async def _send_admin_reset_link(
    admin_doc: dict, recipients: Iterable[str], token: str
) -> None:
    """Send password reset link email for gym admin when FRONTEND_URL is set."""
    link = _build_reset_link(token)
    body_text = (
        "You requested a password reset for your gym admin account.\n\n"
        "Click the link below to set a new password (link expires in 1 hour):\n\n"
        f"{link}\n\n"
        "If you did not request this, please ignore this email or contact support."
    )
    await send_email_async(recipients, "Reset your gym admin password", body_text)


@router.post("/forgot-password", response_model=ForgotPasswordResponse)
async def forgot_password(body: ForgotPasswordRequest) -> ForgotPasswordResponse:
    # #region agent log
    _debug_log("auth.py:forgot_password:entry", "forgot_password called", {"email_or_phone": getattr(body, "email_or_phone", None), "email": getattr(body, "email", None), "body_keys": list(body.model_dump().keys())}, "A")
    # #endregion
    identifier = (body.email_or_phone or body.email or "").strip()
    if not identifier:
        raise HTTPException(
            status_code=422,
            detail="Provide email_or_phone or email in the request body.",
        )

    member_doc = None
    admin_doc = None
    recipients: list[str] = []

    if "@" in identifier:
        # Gym admin: lookup by login_id (often email, e.g. contact@dertzinfotech.com)
        email_clean = identifier.strip()
        pattern = r"^\s*" + re.escape(email_clean) + r"\s*$"
        admin_doc = await gym_admins_collection.find_one(
            {"login_id": {"$regex": pattern, "$options": "i"}}
        )
        if admin_doc and "@" in (admin_doc.get("login_id") or ""):
            recipients.append((admin_doc.get("login_id") or "").strip())
        if not admin_doc or not recipients:
            # Member: lookup by email (case-insensitive)
            member_doc = await members_collection.find_one(
                {"email": {"$regex": pattern, "$options": "i"}}
            )
            if member_doc and member_doc.get("email"):
                recipients = [(member_doc.get("email") or "").strip()]
    else:
        # Phone: only members have phone; gym admins use login_id (email)
        phone_norm = normalize_phone(identifier)
        member_doc = await members_collection.find_one(
            {"phone": phone_norm}
        ) or await members_collection.find_one({"phone": identifier})
        if member_doc and member_doc.get("email"):
            recipients.append((member_doc.get("email") or "").strip())

    # #region agent log
    _debug_log("auth.py:forgot_password:after_lookup", "lookup result", {"member_found": member_doc is not None, "admin_found": admin_doc is not None, "has_recipients": bool(recipients), "identifier": identifier}, "B")
    # #endregion

    # So you can see in the terminal why email was or wasn't sent
    logger.info(
        "Forgot-password: identifier=%s, admin_found=%s, member_found=%s, recipients=%s",
        identifier,
        admin_doc is not None,
        member_doc is not None,
        recipients,
    )
    if not recipients and not (admin_doc or member_doc):
        logger.info("Forgot-password: no account found for %r, email not sent (add as gym admin login_id or member email)", identifier)

    base_url = (settings.frontend_url or os.environ.get("FRONTEND_URL") or "").strip()

    # Gym admin path: reset link if FRONTEND_URL set, else temporary password
    if admin_doc and recipients:
        # #region agent log
        _debug_log("auth.py:forgot_password:admin_branch", "admin path choice", {"base_url": base_url, "base_url_len": len(base_url), "using_reset_link": bool(base_url)}, "A")
        # #endregion
        if base_url:
            token = secrets.token_urlsafe(32)
            expires_at = datetime.now(timezone.utc) + timedelta(hours=RESET_TOKEN_EXPIRY_HOURS)
            await gym_admins_collection.update_one(
                {"_id": admin_doc["_id"]},
                {
                    "$set": {
                        "password_reset_token": token,
                        "password_reset_expires_at": expires_at,
                    }
                },
            )
            await _send_admin_reset_link(admin_doc, recipients, token)
            return ForgotPasswordResponse(
                message="If an account exists for that email or phone, you will receive a reset link shortly."
            )
        await _set_admin_temporary_password(admin_doc, recipients)
        return ForgotPasswordResponse(
            message="If an account exists for that email or phone, you will receive a temporary password shortly."
        )

    if not member_doc:
        logger.info("Forgot-password: no member or admin found for %r, returning generic message (no email sent)", identifier)
        return ForgotPasswordResponse(
            message="If an account exists for that email or phone, you will receive instructions shortly."
        )
    if not recipients:
        logger.info("Forgot-password: member found for %r but no email on file, no email sent", identifier)
        return ForgotPasswordResponse(
            message="If an account exists for that email or phone, you will receive instructions shortly."
        )

    # Member path: reset link if FRONTEND_URL set, else temporary password
    # #region agent log
    _debug_log("auth.py:forgot_password:branch", "which path", {"base_url": base_url, "using_reset_link": bool(base_url)}, "C")
    # #endregion
    if base_url:
        token = secrets.token_urlsafe(32)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=RESET_TOKEN_EXPIRY_HOURS)
        await members_collection.update_one(
            {"_id": member_doc["_id"]},
            {
                "$set": {
                    "password_reset_token": token,
                    "password_reset_expires_at": expires_at,
                }
            },
        )
        # #region agent log
        _debug_log("auth.py:forgot_password:before_send", "calling _send_member_reset_link", {"recipients": recipients}, "D")
        # #endregion
        await _send_member_reset_link(member_doc, recipients, token)
        return ForgotPasswordResponse(
            message="If an account exists for that email or phone, you will receive a reset link shortly."
        )

    # #region agent log
    _debug_log("auth.py:forgot_password:before_send", "calling _set_member_temporary_password", {"recipients": recipients}, "D")
    # #endregion
    await _set_member_temporary_password(member_doc, recipients)
    return ForgotPasswordResponse(
        message="If an account exists for that email or phone, you will receive a temporary password shortly."
    )


@router.post("/reset-password", response_model=dict)
async def reset_password(body: ResetPasswordRequest) -> dict:
    """Set a new password using the token from the reset link. Supports member and gym admin tokens."""
    token = (body.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token is required")

    # Try member first, then gym admin
    member_doc = await members_collection.find_one({"password_reset_token": token})
    admin_doc = await gym_admins_collection.find_one({"password_reset_token": token}) if not member_doc else None

    if member_doc:
        expires_at = member_doc.get("password_reset_expires_at")
        if expires_at and expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if not expires_at or expires_at < datetime.now(timezone.utc):
            await members_collection.update_one(
                {"_id": member_doc["_id"]},
                {"$unset": {"password_reset_token": "", "password_reset_expires_at": ""}},
            )
            raise HTTPException(status_code=400, detail="Reset link has expired")
        try:
            password_hash = pwd_context.hash(body.new_password)
        except Exception:
            password_hash = _pwd_fallback.hash(body.new_password)
        await members_collection.update_one(
            {"_id": member_doc["_id"]},
            {
                "$set": {"password_hash": password_hash},
                "$unset": {"password_reset_token": "", "password_reset_expires_at": ""},
            },
        )
        return {"message": "Password updated successfully. You can now sign in."}

    if admin_doc:
        expires_at = admin_doc.get("password_reset_expires_at")
        if expires_at and expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if not expires_at or expires_at < datetime.now(timezone.utc):
            await gym_admins_collection.update_one(
                {"_id": admin_doc["_id"]},
                {"$unset": {"password_reset_token": "", "password_reset_expires_at": ""}},
            )
            raise HTTPException(status_code=400, detail="Reset link has expired")
        try:
            password_hash = pwd_context.hash(body.new_password)
        except Exception:
            password_hash = _pwd_fallback.hash(body.new_password)
        await gym_admins_collection.update_one(
            {"_id": admin_doc["_id"]},
            {
                "$set": {"password_hash": password_hash},
                "$unset": {"password_reset_token": "", "password_reset_expires_at": ""},
            },
        )
        # #region agent log
        _debug_log("auth.py:reset_password:admin_done", "admin password reset update", {"admin_id": str(admin_doc["_id"])}, "R")
        # #endregion
        return {"message": "Password updated successfully. You can now sign in."}

    raise HTTPException(status_code=400, detail="Invalid or expired reset link")


__all__ = ["router"]
