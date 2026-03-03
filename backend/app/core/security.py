"""
Password hashing and JWT encoding/decoding for the GymSaaS backend.

Used by auth flows (login, forgot-password) and by main.py for backward compatibility.
"""

from datetime import datetime, timedelta, timezone

import jwt
from passlib.context import CryptContext

from app.core.config import settings

# Primary: bcrypt when available; fallback for environments without C++ build tools
pwd_context = CryptContext(schemes=["bcrypt", "pbkdf2_sha256"], deprecated="auto")
_pwd_fallback = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")


def hash_password(plain: str) -> str:
    """Hash a plaintext password. Uses bcrypt when available."""
    try:
        return pwd_context.hash(plain)
    except Exception:
        return _pwd_fallback.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    """Verify a plaintext password against a hash."""
    if not hashed:
        return False
    try:
        return pwd_context.verify(plain, hashed)
    except Exception:
        return _pwd_fallback.verify(plain, hashed)


def encode_jwt(payload: dict) -> str:
    """Encode a payload into a JWT using app secret and algorithm."""
    return jwt.encode(
        payload,
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def decode_jwt(token: str) -> dict:
    """Decode and validate a JWT. Raises jwt.ExpiredSignatureError or jwt.InvalidTokenError."""
    return jwt.decode(
        token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
    )


__all__ = [
    "pwd_context",
    "_pwd_fallback",
    "hash_password",
    "verify_password",
    "encode_jwt",
    "decode_jwt",
]
