from datetime import date, datetime
from zoneinfo import ZoneInfo


IST = ZoneInfo("Asia/Kolkata")


def now_ist() -> datetime:
    return datetime.now(IST)


def today_ist() -> date:
    return now_ist().date()


def batch_from_ist(dt: datetime) -> str:
    """Return Morning, Evening, or Ladies based on IST hour. Morning 4-11, Evening 12-16, Ladies 17-23, else Evening."""
    h = dt.hour
    if 4 <= h <= 11:
        return "Morning"
    if 17 <= h <= 23:
        return "Ladies"
    return "Evening"


def normalize_phone(s: str) -> str:
    """Digits only, max 10 characters (gym member phone)."""
    digits = "".join(c for c in (s or "").strip() if c.isdigit())
    return digits[:10]


__all__ = ["IST", "now_ist", "today_ist", "batch_from_ist", "normalize_phone"]

