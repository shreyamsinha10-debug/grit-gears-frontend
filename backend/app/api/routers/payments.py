"""
Payments router: list, members-with-due, fees-summary, log-monthly, PATCH, pay.
"""

from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException
import jwt

from app.core.auth import get_gym_admin, get_gym_id_for_payments
from app.core.config import settings
from app.core.security import _pwd_fallback, pwd_context
from app.db.database import members_collection, payments_collection
from app.models.schemas import LogMonthlyPaymentBody, PaymentResponse, PaymentStatusUpdate
from app.utils.helpers import gym_filter, to_date
from app.utils.notifications import send_notification
from app.utils.time_utils import today_ist

router = APIRouter()


def _notify_payment_received(name: str, amount: int, email: str, phone: str):
    send_notification("payment_received", {"name": name, "phone": phone, "email": email}, {"amount": amount})


@router.get("/payments", response_model=list[PaymentResponse])
async def list_payments(
    member_id: str | None = None,
    status: str | None = None,
    skip: int = 0,
    limit: int = 100,
    gym_id: str = Depends(get_gym_id_for_payments),
    authorization: str | None = Header(None),
):
    if member_id and authorization and authorization.startswith("Bearer "):
        token = authorization[7:].strip()
        try:
            payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
            if payload.get("role") == "member" and payload.get("sub") == member_id:
                mid_oid = ObjectId(member_id)
                member_doc = await members_collection.find_one({"_id": mid_oid})
                if member_doc and (member_doc.get("status") or "Active") != "Active":
                    raise HTTPException(status_code=403, detail="Portal access is blocked. Your membership is not active.")
        except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
            pass

    q = gym_filter(gym_id)
    if member_id:
        q["member_id"] = member_id
    if status:
        q["status"] = status
    skip = max(0, skip)
    limit = min(max(1, limit), 1000)
    cursor = payments_collection.find(q).sort("created_at", -1).skip(skip).limit(limit)
    out = []
    async for doc in cursor:
        out.append(PaymentResponse(
            id=str(doc["_id"]),
            member_id=doc["member_id"],
            member_name=doc.get("member_name", ""),
            amount=doc["amount"],
            fee_type=doc["fee_type"],
            period=doc.get("period"),
            status=doc["status"],
            due_date=to_date(doc.get("due_date")),
            paid_at=doc.get("paid_at"),
            created_at=doc["created_at"],
        ))
    return out


@router.get("/payments/members-with-due")
async def list_members_with_due(gym_id: str = Depends(get_gym_admin)):
    today = today_ist()
    today_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    q = gym_filter(gym_id)
    q["status"] = {"$in": ["Due", "Overdue"]}
    pipeline = [
        {"$match": q},
        {"$group": {"_id": "$member_id", "member_name": {"$first": "$member_name"}}},
        {"$project": {"member_id": "$_id", "member_name": 1, "_id": 0}},
    ]
    out = []
    async for doc in payments_collection.aggregate(pipeline):
        mid = doc.get("member_id")
        if mid:
            out.append({"member_id": mid, "member_name": doc.get("member_name") or ""})
    return out


@router.get("/payments/fees-summary")
async def fees_summary(gym_id: str = Depends(get_gym_admin)):
    today = today_ist()
    today_dt = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    q = gym_filter(gym_id)
    pipeline = [
        {"$match": q},
        {"$group": {"_id": "$status", "count": {"$sum": 1}, "total_amount": {"$sum": "$amount"}}}
    ]
    cursor = payments_collection.aggregate(pipeline)
    paid = due = overdue = 0
    paid_amt = due_amt = overdue_amt = 0
    async for row in cursor:
        s = row["_id"]
        c, a = row["count"], row["total_amount"]
        if s == "Paid":
            paid, paid_amt = c, a
        elif s == "Due":
            due, due_amt = c, a
        elif s == "Overdue":
            overdue, overdue_amt = c, a
    await payments_collection.update_many(
        {**q, "status": "Due", "due_date": {"$lt": today_dt}},
        {"$set": {"status": "Overdue"}},
    )
    cursor2 = payments_collection.aggregate(pipeline)
    paid = due = overdue = 0
    paid_amt = due_amt = overdue_amt = 0
    async for row in cursor2:
        s = row["_id"]
        c, a = row["count"], row["total_amount"]
        if s == "Paid":
            paid, paid_amt = c, a
        elif s == "Due":
            due, due_amt = c, a
        elif s == "Overdue":
            overdue, overdue_amt = c, a
    return {
        "paid": {"count": paid, "total_amount": paid_amt},
        "due": {"count": due, "total_amount": due_amt},
        "overdue": {"count": overdue, "total_amount": overdue_amt},
    }


@router.post("/payments/log-monthly", response_model=PaymentResponse)
async def log_monthly_payment(body: LogMonthlyPaymentBody, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(body.member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")
    pay_date_str = body.payment_date or today_ist().strftime("%Y-%m-%d")
    try:
        pay_date = datetime.strptime(pay_date_str + " 12:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        raise HTTPException(status_code=400, detail="payment_date must be YYYY-MM-DD")
    doc = {
        "member_id": body.member_id,
        "member_name": member.get("name", ""),
        "amount": body.amount,
        "fee_type": "monthly",
        "period": body.period,
        "status": "Paid",
        "due_date": pay_date,
        "paid_at": pay_date,
        "created_at": datetime.now(timezone.utc),
        "gym_id": gym_id,
    }
    result = await payments_collection.insert_one(doc)
    doc["_id"] = result.inserted_id

    inv_items = [{"description": f"Monthly Fee ({body.period})", "amount": body.amount}]
    from app.db.database import invoices_collection
    inv_doc = {
        "member_id": body.member_id,
        "member_name": member.get("name", ""),
        "items": inv_items,
        "total": body.amount,
        "status": "Paid",
        "issued_at": datetime.now(timezone.utc),
        "paid_at": pay_date,
        "gym_id": gym_id,
    }
    await invoices_collection.insert_one(inv_doc)

    return PaymentResponse(
        id=str(doc["_id"]),
        member_id=doc["member_id"],
        member_name=doc["member_name"],
        amount=doc["amount"],
        fee_type=doc["fee_type"],
        period=doc["period"],
        status=doc["status"],
        due_date=to_date(doc.get("due_date")),
        paid_at=doc.get("paid_at"),
        created_at=doc["created_at"],
    )


@router.patch("/payments/{payment_id}", response_model=PaymentResponse)
async def update_payment_status(payment_id: str, body: PaymentStatusUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(payment_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid payment ID")
    pay_q = {"_id": oid}
    pay_q.update(gym_filter(gym_id))
    doc = await payments_collection.find_one(pay_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Payment not found")
    update = {"status": body.status}
    if body.status != "Paid":
        update["paid_at"] = None
    await payments_collection.update_one(pay_q, {"$set": update})
    updated = await payments_collection.find_one(pay_q)
    return PaymentResponse(
        id=str(updated["_id"]),
        member_id=updated["member_id"],
        member_name=updated.get("member_name", ""),
        amount=updated["amount"],
        fee_type=updated["fee_type"],
        period=updated.get("period"),
        status=updated["status"],
        due_date=to_date(updated.get("due_date")),
        paid_at=updated.get("paid_at"),
        created_at=updated["created_at"],
    )


@router.post("/payments/pay", response_model=PaymentResponse)
async def record_payment(member_id: str, payment_id: str, background_tasks: BackgroundTasks, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(payment_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid payment ID")
    pay_q = {"_id": oid, "member_id": member_id}
    pay_q.update(gym_filter(gym_id))
    doc = await payments_collection.find_one(pay_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Payment not found")
    if doc["status"] == "Paid":
        raise HTTPException(status_code=400, detail="Already paid")
    now = datetime.now(timezone.utc)
    await payments_collection.update_one(pay_q, {"$set": {"status": "Paid", "paid_at": now}})
    member_q = {"_id": ObjectId(member_id)}
    member_q.update(gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if member:
        background_tasks.add_task(_notify_payment_received, member.get("name", ""), doc["amount"], member.get("email", ""), member.get("phone", ""))
    updated = await payments_collection.find_one(pay_q)
    return PaymentResponse(
        id=str(updated["_id"]),
        member_id=updated["member_id"],
        member_name=updated.get("member_name", ""),
        amount=updated["amount"],
        fee_type=updated["fee_type"],
        period=updated.get("period"),
        status=updated["status"],
        due_date=to_date(updated.get("due_date")),
        paid_at=updated.get("paid_at"),
        created_at=updated["created_at"],
    )


__all__ = ["router"]
