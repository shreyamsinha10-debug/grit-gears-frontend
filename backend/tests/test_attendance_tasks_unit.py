from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import pytest


@dataclass
class _UpdateResult:
    modified_count: int


class _AsyncCursor:
    def __init__(self, docs: list[dict[str, Any]]):
        self._docs = docs
        self._i = 0

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._i >= len(self._docs):
            raise StopAsyncIteration
        d = self._docs[self._i]
        self._i += 1
        return d


class _FakeAttendanceCollection:
    def __init__(self, docs: list[dict[str, Any]]):
        self.docs = docs

    def _matches(self, doc: dict[str, Any], query: dict[str, Any]) -> bool:
        def matches_clause(d: dict[str, Any], q: dict[str, Any]) -> bool:
            for k, v in q.items():
                if k == "$and":
                    if not all(matches_clause(d, sub) for sub in v):
                        return False
                    continue
                if k == "$or":
                    if not any(matches_clause(d, sub) for sub in v):
                        return False
                    continue

                if isinstance(v, dict):
                    if "$exists" in v:
                        exists = k in d
                        if bool(v["$exists"]) != exists:
                            return False
                    if "$ne" in v:
                        if d.get(k) == v["$ne"]:
                            return False
                    if "$lt" in v:
                        dv = d.get(k)
                        if dv is None or not (dv < v["$lt"]):
                            return False
                    continue

                if d.get(k) != v:
                    return False
            return True

        return matches_clause(doc, query)

    def find(self, query: dict[str, Any]):
        matched = [d for d in self.docs if self._matches(d, query)]
        return _AsyncCursor(matched)

    async def update_one(self, q: dict[str, Any], u: dict[str, Any]) -> _UpdateResult:
        target_id = q.get("_id")
        for d in self.docs:
            if d.get("_id") == target_id:
                sets = (u or {}).get("$set") or {}
                d.update(sets)
                return _UpdateResult(modified_count=1)
        return _UpdateResult(modified_count=0)


pytestmark = pytest.mark.asyncio


async def test_auto_checkout_updates_open_checkin_older_than_2h(monkeypatch):
    from app.tasks import attendance_tasks

    ci = datetime.now(timezone.utc) - timedelta(hours=3)
    docs = [{"_id": "a", "check_in_at_utc": ci, "check_out_at_ist": ""}]
    fake = _FakeAttendanceCollection(docs)
    monkeypatch.setattr(attendance_tasks, "attendance_collection", fake)

    n = await attendance_tasks.run_auto_checkout()
    assert n == 1
    assert docs[0].get("check_out_at_utc") == ci + timedelta(hours=2)
    assert isinstance(docs[0].get("check_out_at_ist"), str) and docs[0]["check_out_at_ist"]


async def test_auto_checkout_handles_midnight_rollover_date_ist(monkeypatch):
    from app.tasks import attendance_tasks

    ci = datetime.now(timezone.utc) - timedelta(hours=3)
    docs = [
        {
            "_id": "b",
            "date_ist": "1999-12-31",  # intentionally wrong/old
            "check_in_at_utc": ci,
            "check_out_at_ist": None,
        }
    ]
    fake = _FakeAttendanceCollection(docs)
    monkeypatch.setattr(attendance_tasks, "attendance_collection", fake)

    n = await attendance_tasks.run_auto_checkout()
    assert n == 1
    assert docs[0].get("check_out_at_utc") == ci + timedelta(hours=2)


async def test_auto_checkout_legacy_records_without_check_in_at_utc(monkeypatch):
    from app.tasks import attendance_tasks

    # Stored as IST string; 3h ago in UTC is also safely >2h for the test regardless of IST offset.
    ci_utc = datetime.now(timezone.utc) - timedelta(hours=3)
    ci_ist = ci_utc.astimezone(attendance_tasks.IST).isoformat()
    docs = [{"_id": "c", "check_in_at_ist": ci_ist, "check_out_at_ist": ""}]
    fake = _FakeAttendanceCollection(docs)
    monkeypatch.setattr(attendance_tasks, "attendance_collection", fake)

    n = await attendance_tasks.run_auto_checkout()
    assert n == 1
    assert docs[0].get("check_out_at_utc") == ci_utc + timedelta(hours=2)


async def test_auto_checkout_does_not_touch_already_checked_out(monkeypatch):
    from app.tasks import attendance_tasks

    ci = datetime.now(timezone.utc) - timedelta(hours=3)
    docs = [
        {
            "_id": "d",
            "check_in_at_utc": ci,
            "check_out_at_ist": "2026-01-01T10:00:00+05:30",
            "check_out_at_utc": ci + timedelta(hours=1),
        }
    ]
    fake = _FakeAttendanceCollection(docs)
    monkeypatch.setattr(attendance_tasks, "attendance_collection", fake)

    n = await attendance_tasks.run_auto_checkout()
    assert n == 0
    assert docs[0]["check_out_at_utc"] == ci + timedelta(hours=1)

