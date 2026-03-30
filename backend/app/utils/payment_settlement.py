"""
Apply collected amounts to member Due/Overdue rows without double-counting collections.

Paid totals come from explicit Paid payment rows (invoice lines, log-monthly, etc.).
This module reduces or removes Due rows so pending dues match reality, including
partial payments (e.g. pay 500 of 1500 → Due becomes 1000).
"""

from app.db.database import payments_collection
from app.utils.helpers import gym_filter


async def apply_collection_to_due_payments(member_id: str, gym_id: str, amount_budget: int) -> int:
    """
    FIFO: apply ``amount_budget`` rupees against Due/Overdue rows for this member.

    - If a row's amount <= remaining budget: delete the row and subtract from budget.
    - If a row's amount > remaining budget: decrease the row's amount by remaining and stop.

    Returns the number of payment documents updated or deleted.
    """
    if amount_budget <= 0:
        return 0
    pay_q = {"member_id": member_id, "status": {"$in": ["Due", "Overdue"]}}
    pay_q.update(gym_filter(gym_id))
    cursor = payments_collection.find(pay_q).sort("created_at", 1)
    remaining = int(amount_budget)
    touched = 0
    async for p in cursor:
        if remaining <= 0:
            break
        pid = p["_id"]
        amt = int(p.get("amount") or 0)
        base_q = {"_id": pid, **gym_filter(gym_id)}
        if amt <= 0:
            await payments_collection.delete_one(base_q)
            touched += 1
            continue
        if amt <= remaining:
            await payments_collection.delete_one(base_q)
            remaining -= amt
            touched += 1
        else:
            await payments_collection.update_one(base_q, {"$set": {"amount": amt - remaining}})
            touched += 1
            remaining = 0
            break
    return touched


__all__ = ["apply_collection_to_due_payments"]
