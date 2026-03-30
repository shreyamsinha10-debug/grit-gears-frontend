from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pytest


@dataclass
class _DeleteResult:
    deleted_count: int


@dataclass
class _UpdateResult:
    modified_count: int


class _AsyncCursor:
    def __init__(self, docs: list[dict[str, Any]]):
        self._docs = docs
        self._i = 0

    def sort(self, *args, **kwargs):
        return self

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._i >= len(self._docs):
            raise StopAsyncIteration
        d = self._docs[self._i]
        self._i += 1
        return d


class _FakePaymentsCollection:
    def __init__(self, docs: list[dict[str, Any]]):
        self.docs = docs

    def find(self, query: dict[str, Any]):
        mid = query.get("member_id")
        st = query.get("status", {}).get("$in", [])
        gid = query.get("gym_id")
        matched = [
            d
            for d in self.docs
            if d.get("member_id") == mid and d.get("status") in st and d.get("gym_id") == gid
        ]
        matched.sort(key=lambda x: x.get("created_at", 0))
        return _AsyncCursor(matched)

    async def delete_one(self, query: dict[str, Any]) -> _DeleteResult:
        target = query.get("_id")
        before = len(self.docs)
        self.docs[:] = [d for d in self.docs if d.get("_id") != target]
        return _DeleteResult(deleted_count=before - len(self.docs))

    async def update_one(self, query: dict[str, Any], update: dict[str, Any]) -> _UpdateResult:
        target = query.get("_id")
        sets = (update or {}).get("$set") or {}
        for d in self.docs:
            if d.get("_id") == target:
                d.update(sets)
                return _UpdateResult(modified_count=1)
        return _UpdateResult(modified_count=0)


pytestmark = pytest.mark.asyncio


async def test_apply_collection_full_delete_fifo(monkeypatch):
    from app.utils import payment_settlement

    docs = [
        {"_id": 1, "member_id": "m1", "gym_id": "g1", "status": "Due", "amount": 500, "created_at": 1},
        {"_id": 2, "member_id": "m1", "gym_id": "g1", "status": "Due", "amount": 1000, "created_at": 2},
    ]
    fake = _FakePaymentsCollection(docs)
    monkeypatch.setattr(payment_settlement, "payments_collection", fake)
    monkeypatch.setattr(payment_settlement, "gym_filter", lambda gid: {"gym_id": gid})

    n = await payment_settlement.apply_collection_to_due_payments("m1", "g1", 1500)
    assert n == 2
    assert docs == []


async def test_apply_collection_partial_reduces_amount(monkeypatch):
    from app.utils import payment_settlement

    docs = [
        {"_id": 1, "member_id": "m1", "gym_id": "g1", "status": "Due", "amount": 1500, "created_at": 1},
    ]
    fake = _FakePaymentsCollection(docs)
    monkeypatch.setattr(payment_settlement, "payments_collection", fake)
    monkeypatch.setattr(payment_settlement, "gym_filter", lambda gid: {"gym_id": gid})

    n = await payment_settlement.apply_collection_to_due_payments("m1", "g1", 500)
    assert n == 1
    assert len(docs) == 1
    assert docs[0]["amount"] == 1000


async def test_apply_collection_multi_row_partial(monkeypatch):
    from app.utils import payment_settlement

    docs = [
        {"_id": 1, "member_id": "m1", "gym_id": "g1", "status": "Due", "amount": 200, "created_at": 1},
        {"_id": 2, "member_id": "m1", "gym_id": "g1", "status": "Due", "amount": 500, "created_at": 2},
    ]
    fake = _FakePaymentsCollection(docs)
    monkeypatch.setattr(payment_settlement, "payments_collection", fake)
    monkeypatch.setattr(payment_settlement, "gym_filter", lambda gid: {"gym_id": gid})

    n = await payment_settlement.apply_collection_to_due_payments("m1", "g1", 500)
    assert n == 2
    assert len(docs) == 1
    assert docs[0]["_id"] == 2
    assert docs[0]["amount"] == 200
