"""
Domain models that represent how data is stored in MongoDB.

Phase 1 keeps using the existing untyped dictionaries in `backend.main`. This
module will be populated with rich domain representations once persistence is
fully decoupled from the monolith.
"""

from typing import Any, TypedDict


class MemberDocument(TypedDict, total=False):
    _id: Any
    gym_id: str
    name: str
    phone: str
    email: str
    membership_type: str
    batch: str
    status: str
    address: str | None
    date_of_birth: Any | None
    gender: str | None
    workout_schedule: str | None
    diet_chart: str | None
    last_attendance_date: Any | None


__all__ = ["MemberDocument"]

