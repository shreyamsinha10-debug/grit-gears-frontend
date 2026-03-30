"""
Billing router: create, next-bill-number, issue, history, pay, PATCH/DELETE invoices.
"""

from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from bson.regex import Regex
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from app.core.auth import get_gym_admin
from app.db.database import invoices_collection, members_collection, payments_collection
from app.models.schemas import (
    BillingIssueWalkIn,
    CreateBillRequest,
    InvoiceResponse,
    InvoiceUpdate,
)
from app.utils.helpers import gym_filter, resolve_monthly_fee
from app.utils.notifications import send_notification
from app.utils.payment_settlement import apply_collection_to_due_payments
from app.utils.time_utils import today_ist

router = APIRouter()


def _invoice_period_dates(doc: dict):
    start = doc.get("paid_at") or doc.get("issued_at")
    if not start:
        return None, None
    start_date = start.date() if hasattr(start, "date") else start
    end = doc.get("end_date")
    end_date = (end.date() if hasattr(end, "date") else end) if end else start_date
    return start_date, end_date


def _notify_payment_received(name: str, amount: int, email: str, phone: str):
    send_notification("payment_received", {"name": name, "phone": phone, "email": email}, {"amount": amount})


def _invoice_doc_to_response(doc) -> InvoiceResponse:
    return InvoiceResponse(
        id=str(doc["_id"]),
        member_id=doc["member_id"],
        member_name=doc.get("member_name", ""),
        items=doc.get("items", []),
        total=doc["total"],
        status=doc.get("status", "Unpaid"),
        issued_at=doc["issued_at"],
        paid_at=doc.get("paid_at"),
        bill_number=doc.get("bill_number"),
        payment_method=doc.get("payment_method"),
        notes=doc.get("notes"),
        end_date=doc.get("end_date"),
        member_phone=doc.get("member_phone"),
        member_email=doc.get("member_email"),
        batch=doc.get("batch"),
    )


@router.post("/billing/create", response_model=InvoiceResponse)
async def billing_create(body: CreateBillRequest, gym_id: str = Depends(get_gym_admin)):
    try:
        mid_oid = ObjectId(body.member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": mid_oid}
    member_q.update(gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    if body.total != sum(i.amount for i in body.items):
        raise HTTPException(status_code=400, detail="Total must match sum of item amounts")
    try:
        pay_dt = datetime.strptime(body.payment_date + " 12:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        raise HTTPException(status_code=400, detail="payment_date must be YYYY-MM-DD")
    year = pay_dt.year
    count = await invoices_collection.count_documents({
        **gym_filter(gym_id),
        "issued_at": {"$gte": datetime(year, 1, 1, tzinfo=timezone.utc), "$lt": datetime(year + 1, 1, 1, tzinfo=timezone.utc)},
    })
    bill_number = f"BILL-{year}-{count + 1:05d}"
    items = [{"description": i.description, "amount": i.amount} for i in body.items]
    inv_doc = {
        "member_id": body.member_id,
        "member_name": member.get("name", ""),
        "member_phone": body.member_phone or member.get("phone"),
        "member_email": body.member_email or member.get("email"),
        "batch": body.batch or member.get("batch"),
        "items": items,
        "total": body.total,
        "status": "Paid",
        "issued_at": datetime.now(timezone.utc),
        "paid_at": pay_dt,
        "gym_id": gym_id,
        "bill_number": bill_number,
        "payment_method": body.payment_method,
        "payment_reference": body.reference,
        "notes": body.notes,
    }
    end_dt = None
    if body.end_date:
        try:
            end_dt = datetime.strptime(body.end_date + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            inv_doc["end_date"] = end_dt
        except ValueError:
            pass
    start_new_dt = pay_dt
    end_new_dt = end_dt or pay_dt
    overlap_q = {
        "member_id": body.member_id,
        **gym_filter(gym_id),
        "$or": [
            {"$and": [{"end_date": {"$exists": True}}, {"paid_at": {"$lte": end_new_dt}}, {"end_date": {"$gte": start_new_dt}}]},
            {"end_date": {"$exists": False}, "paid_at": {"$gte": start_new_dt, "$lte": end_new_dt}},
        ],
    }
    other = await invoices_collection.find_one(overlap_q)
    if other:
        o_start, o_end = _invoice_period_dates(other)
        raise HTTPException(status_code=400, detail=f"Another invoice for this member already covers this period (e.g. {o_start} to {o_end}). Use different dates or edit the existing invoice.")
    inv_result = await invoices_collection.insert_one(inv_doc)
    inv_id_str = str(inv_result.inserted_id)
    member_name = member.get("name", "")
    for it in items:
        await payments_collection.insert_one({
            "member_id": body.member_id, "member_name": member_name, "amount": it["amount"], "fee_type": it["description"],
            "period": None, "status": "Paid", "due_date": pay_dt, "paid_at": pay_dt, "created_at": datetime.now(timezone.utc),
            "gym_id": gym_id, "invoice_id": inv_id_str,
        })
    await apply_collection_to_due_payments(body.member_id, gym_id, body.total)
    return _invoice_doc_to_response({**inv_doc, "_id": inv_result.inserted_id})


@router.get("/billing/next-bill-number")
async def billing_next_bill_number(gym_id: str = Depends(get_gym_admin)):
    year = datetime.now(timezone.utc).year
    count = await invoices_collection.count_documents({
        **gym_filter(gym_id),
        "issued_at": {"$gte": datetime(year, 1, 1, tzinfo=timezone.utc), "$lt": datetime(year + 1, 1, 1, tzinfo=timezone.utc)},
    })
    return {"bill_number": f"BILL-{year}-{count + 1:05d}"}


@router.post("/billing/issue", response_model=InvoiceResponse)
async def billing_issue(body: BillingIssueWalkIn, gym_id: str = Depends(get_gym_admin)):
    doc = {"name": body.name, "phone": body.phone, "email": body.email, "membership_type": body.membership_type.value, "batch": body.batch, "status": "Active", "created_at": datetime.now(timezone.utc), "gym_id": gym_id}
    result = await members_collection.insert_one(doc)
    mid = str(result.inserted_id)
    mt = body.membership_type.value if hasattr(body.membership_type, "value") else str(body.membership_type)
    monthly_amount = await resolve_monthly_fee(gym_id, mt)
    items = [{"description": "First Month", "amount": monthly_amount}]
    inv_doc = {"member_id": mid, "member_name": body.name, "items": items, "total": monthly_amount, "status": "Unpaid", "issued_at": datetime.now(timezone.utc), "paid_at": None, "gym_id": gym_id}
    inv_result = await invoices_collection.insert_one(inv_doc)
    t = today_ist()
    due_dt = datetime(t.year, t.month, t.day, tzinfo=timezone.utc)
    period = t.strftime("%Y-%m")
    await payments_collection.insert_many([{"member_id": mid, "member_name": body.name, "amount": monthly_amount, "fee_type": "monthly", "period": period, "status": "Due", "due_date": due_dt, "paid_at": None, "created_at": datetime.now(timezone.utc), "gym_id": gym_id}])
    send_notification("registration", {"name": body.name, "phone": body.phone, "email": body.email})
    return InvoiceResponse(id=str(inv_result.inserted_id), member_id=mid, member_name=body.name, items=items, total=monthly_amount, status="Unpaid", issued_at=inv_doc["issued_at"], paid_at=None, bill_number=None)


@router.get("/billing/history", response_model=list[InvoiceResponse])
async def billing_history(member_id: str | None = None, search: str | None = None, date_from: str | None = None, date_to: str | None = None, gym_id: str = Depends(get_gym_admin), skip: int = 0, limit: int = 100):
    q = gym_filter(gym_id)
    if member_id:
        q["member_id"] = member_id
    if search and search.strip():
        s = search.strip()
        q["$or"] = [{"member_name": Regex(s, "i")}] + ([{"_id": ObjectId(s)}] if _oid_ok(s) else [])
    if date_from and len(date_from) == 10 and date_from[4] == "-" and date_from[7] == "-":
        q.setdefault("issued_at", {})
        if isinstance(q["issued_at"], dict):
            q["issued_at"]["$gte"] = datetime.strptime(date_from + " 00:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        else:
            q["issued_at"] = {"$gte": datetime.strptime(date_from + " 00:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)}
    if date_to and len(date_to) == 10 and date_to[4] == "-" and date_to[7] == "-":
        if "issued_at" not in q:
            q["issued_at"] = {}
        if isinstance(q["issued_at"], dict):
            q["issued_at"]["$lte"] = datetime.strptime(date_to + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        else:
            q["issued_at"] = {"$lte": datetime.strptime(date_to + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)}
    skip, limit = max(0, skip), min(max(1, limit), 500)
    cursor = invoices_collection.find(q).sort("issued_at", -1).skip(skip).limit(limit)
    return [_invoice_doc_to_response(d) async for d in cursor]


def _oid_ok(s):
    try:
        ObjectId(s)
        return True
    except InvalidId:
        return False


@router.post("/billing/pay", response_model=InvoiceResponse)
async def billing_pay(invoice_id: str, background_tasks: BackgroundTasks, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(invoice_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid invoice ID")
    inv_q = {"_id": oid}
    inv_q.update(gym_filter(gym_id))
    doc = await invoices_collection.find_one(inv_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if doc.get("status") == "Paid":
        raise HTTPException(status_code=400, detail="Already paid")
    now = datetime.now(timezone.utc)
    await invoices_collection.update_one(inv_q, {"$set": {"status": "Paid", "paid_at": now}})
    member_id = doc["member_id"]
    member_name = doc.get("member_name", "")
    for it in doc.get("items", []):
        await payments_collection.insert_one({"member_id": member_id, "member_name": member_name, "amount": it.get("amount", 0), "fee_type": it.get("description", "Payment"), "period": None, "status": "Paid", "due_date": now, "paid_at": now, "created_at": now, "gym_id": gym_id, "invoice_id": str(doc["_id"])})
    inv_total = int(doc.get("total") or 0)
    await apply_collection_to_due_payments(member_id, gym_id, inv_total)
    member_q = {"_id": ObjectId(member_id)}
    member_q.update(gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if member:
        background_tasks.add_task(_notify_payment_received, member.get("name", ""), doc["total"], member.get("email", ""), member.get("phone", ""))
    updated = await invoices_collection.find_one(inv_q)
    return _invoice_doc_to_response(updated)


@router.patch("/billing/invoices/{invoice_id}", response_model=InvoiceResponse)
async def billing_update_invoice(invoice_id: str, body: InvoiceUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(invoice_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid invoice ID")
    inv_q = {"_id": oid}
    inv_q.update(gym_filter(gym_id))
    doc = await invoices_collection.find_one(inv_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Invoice not found")
    member_id = doc["member_id"]
    update = {}
    if body.items is not None and body.total is not None:
        if body.total != sum(i.amount for i in body.items):
            raise HTTPException(status_code=400, detail="Total must match sum of item amounts")
        update["items"] = [{"description": i.description, "amount": i.amount} for i in body.items]
        update["total"] = body.total
    if body.payment_date is not None:
        try:
            update["paid_at"] = datetime.strptime(body.payment_date + " 12:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        except ValueError:
            raise HTTPException(status_code=400, detail="payment_date must be YYYY-MM-DD")
    if body.end_date is not None:
        try:
            update["end_date"] = datetime.strptime(body.end_date + " 23:59:59", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        except ValueError:
            update["end_date"] = None
    if body.member_phone is not None:
        update["member_phone"] = body.member_phone
    if body.member_email is not None:
        update["member_email"] = body.member_email
    if body.batch is not None:
        update["batch"] = body.batch
    if body.notes is not None:
        update["notes"] = body.notes
    if "paid_at" in update or "end_date" in update or body.payment_date is not None or body.end_date is not None:
        start_new_dt = update.get("paid_at") or doc.get("paid_at") or doc.get("issued_at")
        if start_new_dt:
            end_new_dt = update.get("end_date") or doc.get("end_date") or start_new_dt
            other = await invoices_collection.find_one({"member_id": member_id, "_id": {"$ne": oid}, **gym_filter(gym_id), "$or": [{"$and": [{"end_date": {"$exists": True}}, {"paid_at": {"$lte": end_new_dt}}, {"end_date": {"$gte": start_new_dt}}]}, {"end_date": {"$exists": False}, "paid_at": {"$gte": start_new_dt, "$lte": end_new_dt}}]})
            if other:
                raise HTTPException(status_code=400, detail="Another invoice for this member already covers this period. Use different dates.")
    await invoices_collection.update_one(inv_q, {"$set": update})
    if doc.get("status") == "Paid" and "items" in update:
        await payments_collection.delete_many({"invoice_id": invoice_id, **gym_filter(gym_id)})
        pay_dt = update.get("paid_at") or doc.get("paid_at") or datetime.now(timezone.utc)
        member_name = doc.get("member_name", "")
        for it in update["items"]:
            await payments_collection.insert_one({"member_id": member_id, "member_name": member_name, "amount": it["amount"], "fee_type": it["description"], "period": None, "status": "Paid", "due_date": pay_dt, "paid_at": pay_dt, "created_at": datetime.now(timezone.utc), "gym_id": gym_id, "invoice_id": invoice_id})
    updated_doc = await invoices_collection.find_one(inv_q)
    return _invoice_doc_to_response(updated_doc)


@router.delete("/billing/invoices/{invoice_id}", response_model=dict)
async def billing_delete_invoice(invoice_id: str, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(invoice_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid invoice ID")
    inv_q = {"_id": oid}
    inv_q.update(gym_filter(gym_id))
    doc = await invoices_collection.find_one(inv_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Invoice not found")
    r_payments = await payments_collection.delete_many({"invoice_id": invoice_id, **gym_filter(gym_id)})
    await invoices_collection.delete_one(inv_q)
    return {"message": "Invoice deleted", "payments_removed": r_payments.deleted_count}


__all__ = ["router"]
