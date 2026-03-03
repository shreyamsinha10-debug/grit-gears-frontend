"""
Configuration utilities for the GymSaaS backend.

All configuration is sourced from environment variables via `pydantic-settings`.
There are **no hardcoded fallbacks** for secrets or required settings – the
application will fail fast on startup if they are missing.
"""

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# Load .env from backend directory so it works regardless of current working directory
_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
_ENV_FILE = _BACKEND_DIR / ".env"


class Settings(BaseSettings):
    """
    Central application settings.

    Environment variables:
    - MONGODB_URL
    - DATABASE_NAME
    - SUPER_ADMIN_LOGIN_ID
    - SUPER_ADMIN_PASSWORD
    - JWT_SECRET
    - ALLOWED_ORIGINS  (comma-separated list)
    - SMTP_SERVER      (optional, Phase 6)
    - SMTP_PORT        (optional, Phase 6)
    - SMTP_USERNAME    (optional, Phase 6)
    - SMTP_PASSWORD    (optional, Phase 6)
    - FROM_EMAIL       (optional, Phase 6)
    """

    model_config = SettingsConfigDict(
        env_prefix="",
        case_sensitive=False,
        env_file=_ENV_FILE if _ENV_FILE.exists() else None,
        env_file_encoding="utf-8",
    )

    mongodb_url: str = Field(..., alias="MONGODB_URL")
    database_name: str = Field(..., alias="DATABASE_NAME")

    super_admin_login_id: str = Field(..., alias="SUPER_ADMIN_LOGIN_ID")
    super_admin_password: str = Field(..., alias="SUPER_ADMIN_PASSWORD")

    jwt_secret: str = Field(..., alias="JWT_SECRET")
    jwt_algorithm: str = "HS256"

    allowed_origins: str = Field(..., alias="ALLOWED_ORIGINS")

    smtp_server: str | None = Field(default=None, alias="SMTP_SERVER")
    smtp_port: int | None = Field(default=None, alias="SMTP_PORT")
    smtp_username: str | None = Field(default=None, alias="SMTP_USERNAME")
    smtp_password: str | None = Field(default=None, alias="SMTP_PASSWORD")
    from_email: str | None = Field(default=None, alias="FROM_EMAIL")

    backend_label: str | None = Field(default=None, alias="BACKEND_LABEL")


settings = Settings()

COLLECTION_MEMBERS = "gym_members"
COLLECTION_ATTENDANCE = "attendance_logs"
COLLECTION_PAYMENTS = "payments"
COLLECTION_INVOICES = "invoices"
COLLECTION_GYMS = "gyms"
COLLECTION_GYM_ADMINS = "gym_admins"
COLLECTION_APP_CONFIG = "app_config"
COLLECTION_MESSAGES = "messages"

REGISTRATION_FEE = 1000
MONTHLY_FEE_REGULAR = 500
MONTHLY_FEE_PT = 2000

__all__ = [
    "settings",
    "COLLECTION_MEMBERS",
    "COLLECTION_ATTENDANCE",
    "COLLECTION_PAYMENTS",
    "COLLECTION_INVOICES",
    "COLLECTION_GYMS",
    "COLLECTION_GYM_ADMINS",
    "COLLECTION_APP_CONFIG",
    "COLLECTION_MESSAGES",
    "REGISTRATION_FEE",
    "MONTHLY_FEE_REGULAR",
    "MONTHLY_FEE_PT",
]
