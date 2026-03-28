"""
Configuration utilities for the GymSaaS backend.

Configuration is read from environment variables via pydantic-settings.
Fallback defaults are provided so the app can start on hosts (e.g. Railway)
that do not inject env vars into the process; set all variables in the
dashboard for production.
"""

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# Load .env from backend directory so it works regardless of current working directory
_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
_ENV_FILE = _BACKEND_DIR / ".env"

# Fallbacks used when env vars are not set (e.g. Railway not injecting variables).
# Override by setting MONGODB_URL, etc., in the host environment or .env.
_DEFAULT_MONGODB_URL = "mongodb+srv://gym_admin:8qxXOYKp1El0bw0B@clustergymadmin.zkcgd9b.mongodb.net/?appName=Clustergymadmin"
_DEFAULT_DATABASE_NAME = "gym_db"
_DEFAULT_SUPER_ADMIN_LOGIN_ID = "admin@gymsaas.com"
_DEFAULT_SUPER_ADMIN_PASSWORD = "Admin@Gym123"
_DEFAULT_JWT_SECRET = "gym-saas-jwt-secret-change-in-production"
_DEFAULT_ALLOWED_ORIGINS = "*"


class Settings(BaseSettings):
    """
    Central application settings.

    Environment variables (with fallbacks so app starts if host does not inject them):
    - MONGODB_URL
    - DATABASE_NAME
    - SUPER_ADMIN_LOGIN_ID
    - SUPER_ADMIN_PASSWORD
    - JWT_SECRET
    - ALLOWED_ORIGINS  (comma-separated list, or * for all)
    - SMTP_* / FROM_EMAIL (optional)
    """

    model_config = SettingsConfigDict(
        env_prefix="",
        case_sensitive=False,
        env_file=_ENV_FILE if _ENV_FILE.exists() else None,
        env_file_encoding="utf-8",
    )

    mongodb_url: str = Field(default=_DEFAULT_MONGODB_URL, alias="MONGODB_URL")
    database_name: str = Field(default=_DEFAULT_DATABASE_NAME, alias="DATABASE_NAME")

    super_admin_login_id: str = Field(default=_DEFAULT_SUPER_ADMIN_LOGIN_ID, alias="SUPER_ADMIN_LOGIN_ID")
    super_admin_password: str = Field(default=_DEFAULT_SUPER_ADMIN_PASSWORD, alias="SUPER_ADMIN_PASSWORD")

    jwt_secret: str = Field(default=_DEFAULT_JWT_SECRET, alias="JWT_SECRET")
    jwt_algorithm: str = "HS256"

    allowed_origins: str = Field(default=_DEFAULT_ALLOWED_ORIGINS, alias="ALLOWED_ORIGINS")

    smtp_server: str | None = Field(default=None, alias="SMTP_SERVER")
    smtp_port: int | None = Field(default=None, alias="SMTP_PORT")
    smtp_username: str | None = Field(default=None, alias="SMTP_USERNAME")
    smtp_password: str | None = Field(default=None, alias="SMTP_PASSWORD")
    from_email: str | None = Field(default=None, alias="FROM_EMAIL")
    # SendGrid API key (optional). When set, mail is sent via SendGrid HTTP API instead of SMTP (avoids port blocks in containers).
    sendgrid_api_key: str | None = Field(default=None, alias="SENDGRID_API_KEY")

    # Base URL for password-reset and registration links (where app/web is hosted).
    # No trailing slash. Example: https://gymopshq.web.app or https://yourapp.com
    frontend_url: str | None = Field(default=None, alias="FRONTEND_URL")

    backend_label: str | None = Field(default=None, alias="BACKEND_LABEL")

    # Auto check-out: run job every N seconds (default 3600 = 1 hour). Set higher to reduce load.
    auto_checkout_interval_seconds: int = Field(
        default=3600,
        alias="AUTO_CHECKOUT_INTERVAL_SECONDS",
        ge=60,
        description="Interval in seconds for auto check-out job (min 60).",
    )

    monthly_due_renewal_interval_seconds: int = Field(
        default=3600,
        alias="MONTHLY_DUE_RENEWAL_INTERVAL_SECONDS",
        ge=60,
        description="Interval for scanning expired invoice periods and inserting new monthly Due rows.",
    )


settings = Settings()

COLLECTION_MEMBERS = "gym_members"
COLLECTION_ATTENDANCE = "attendance_logs"
COLLECTION_PAYMENTS = "payments"
COLLECTION_INVOICES = "invoices"
COLLECTION_GYMS = "gyms"
COLLECTION_GYM_ADMINS = "gym_admins"
COLLECTION_APP_CONFIG = "app_config"
COLLECTION_MESSAGES = "messages"
COLLECTION_EXPENSES = "expenses"

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
    "COLLECTION_EXPENSES",
    "REGISTRATION_FEE",
    "MONTHLY_FEE_REGULAR",
    "MONTHLY_FEE_PT",
]
