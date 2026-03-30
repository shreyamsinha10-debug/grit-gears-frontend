"""
Authentication and authorization dependencies for FastAPI.

These helpers centralise JWT validation and multi-tenant context handling so
routers can remain thin and consistent.
"""

from typing import Tuple

import jwt
from fastapi import Depends, Header, HTTPException, Query

from app.core.config import settings


def get_current_user_payload(authorization: str | None = Header(None)) -> dict:
    """
    Base dependency that validates the Authorization bearer token and returns
    the decoded JWT payload.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization required")
    token = authorization[7:].strip()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_super_admin(payload: dict = Depends(get_current_user_payload)) -> dict:
    """Require super_admin role and return the decoded payload."""
    if payload.get("role") != "super_admin":
        raise HTTPException(status_code=403, detail="Super admin only")
    return payload


def get_gym_admin(payload: dict = Depends(get_current_user_payload)) -> str:
    """Require gym_admin role and return the scoped gym_id."""
    if payload.get("role") != "gym_admin":
        raise HTTPException(status_code=403, detail="Gym admin access required")
    gym_id = str(payload.get("gym_id") or "")
    if not gym_id:
        raise HTTPException(status_code=403, detail="Gym context missing")
    return gym_id


def get_current_member(payload: dict = Depends(get_current_user_payload)) -> Tuple[str, str]:
    """Require member role and return (member_id, gym_id)."""
    if payload.get("role") != "member":
        raise HTTPException(status_code=403, detail="Member access required")
    member_id = str(payload.get("sub") or "")
    gym_id = str(payload.get("gym_id") or "")
    if not member_id or not gym_id:
        raise HTTPException(status_code=403, detail="Member or gym context missing")
    return member_id, gym_id


def get_gym_context(
    authorization: str | None = Header(None),
    member_id: str | None = Query(None, alias="member_id"),
) -> str:
    """
    Allow both gym_admin and member, returning the scoped gym_id.

    When called with a member_id query parameter, members are restricted to
    their own member_id.
    """
    payload = get_current_user_payload(authorization=authorization)
    role = payload.get("role")
    gym_id = str(payload.get("gym_id") or "")

    if role == "gym_admin":
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id

    if role == "member":
        sub = str(payload.get("sub") or "")
        if member_id is not None and str(member_id) != sub:
            raise HTTPException(status_code=403, detail="Members can only access their own data")
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id

    raise HTTPException(status_code=403, detail="Gym admin or member access required")


def get_gym_id_for_attendance_or_member_get(
    member_id: str,
    authorization: str | None = Header(None),
) -> str:
    """Allow gym_admin (any member) or member (only own member_id). Returns gym_id for scoping."""
    payload = get_current_user_payload(authorization=authorization)
    role = payload.get("role")
    gym_id = str(payload.get("gym_id") or "")
    if role == "gym_admin":
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id
    if role == "member":
        if str(payload.get("sub") or "") != str(member_id):
            raise HTTPException(status_code=403, detail="Not authorized for this member")
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id
    raise HTTPException(status_code=403, detail="Gym admin or member access required")


def get_gym_id_for_payments(
    authorization: str | None = Header(None),
    member_id: str | None = Query(None, alias="member_id"),
) -> str:
    """Allow gym_admin (any) or member (only own payments when member_id=sub)."""
    payload = get_current_user_payload(authorization=authorization)
    role = payload.get("role")
    gym_id = str(payload.get("gym_id") or "")
    if role == "gym_admin":
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id
    if role == "member":
        sub = str(payload.get("sub") or "")
        if not member_id or str(member_id) != sub:
            raise HTTPException(status_code=403, detail="Members can only list their own payments")
        if not gym_id:
            raise HTTPException(status_code=403, detail="Gym context missing")
        return gym_id
    raise HTTPException(status_code=403, detail="Gym admin or member access required")


def get_gym_id_and_member_for_messages(
    authorization: str | None = Header(None),
) -> Tuple[str, str | None]:
    """Allow gym_admin or member. Returns (gym_id, member_id). member_id is set only when role is member (for inbox)."""
    payload = get_current_user_payload(authorization=authorization)
    role = payload.get("role")
    gym_id = str(payload.get("gym_id") or "")
    if not gym_id and role in ("gym_admin", "member"):
        raise HTTPException(status_code=403, detail="Gym context missing")
    member_id = str(payload.get("sub")) if role == "member" else None
    return (gym_id, member_id)


__all__ = [
    "get_current_user_payload",
    "get_super_admin",
    "get_gym_admin",
    "get_current_member",
    "get_gym_context",
    "get_gym_id_for_attendance_or_member_get",
    "get_gym_id_for_payments",
    "get_gym_id_and_member_for_messages",
]

