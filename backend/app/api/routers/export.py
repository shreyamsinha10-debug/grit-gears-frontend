"""
Export router: billing, members, payments to Excel.
"""

from io import BytesIO

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.core.auth import get_gym_admin
from app.db.database import invoices_collection, members_collection, payments_collection
from app.utils.helpers import gym_filter, to_date

router = APIRouter()


@router.get("/export/billing")
async def export_billing_excel(gym_id: str = Depends(get_gym_admin)):
    from openpyxl import Workbook
    async def iterfile():
        q = gym_filter(gym_id)
        cursor = invoices_collection.find(q).sort("issued_at", -1)
        wb = Workbook()
        ws = wb.active
        ws.title = "Billing"
        ws.append(["id", "member_id", "member_name", "total", "status", "issued_at", "paid_at"])
        async for doc in cursor:
            ws.append([
                str(doc.get("_id", "")),
                doc.get("member_id", ""),
                doc.get("member_name", ""),
                doc.get("total", 0),
                doc.get("status", ""),
                str(doc.get("issued_at", "")),
                str(doc.get("paid_at", "")) if doc.get("paid_at") else "",
            ])
        buf = BytesIO()
        wb.save(buf)
        buf.seek(0)
        chunk = buf.read(8192)
        while chunk:
            yield chunk
            chunk = buf.read(8192)
    return StreamingResponse(
        iterfile(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=billing_history.xlsx"},
    )


@router.get("/export/members")
async def export_members_excel(gym_id: str = Depends(get_gym_admin)):
    from openpyxl import Workbook
    async def iterfile():
        q = gym_filter(gym_id)
        cursor = members_collection.find(q).sort("created_at", -1)
        wb = Workbook()
        ws = wb.active
        ws.title = "Members"
        ws.append(["Full Name", "Phone", "E-mail ID", "Address", "Date of Birth (MM/DD/YYYY)", "Gender", "Membership Type", "Batch", "Status"])
        async for doc in cursor:
            dob = to_date(doc.get("date_of_birth"))
            dob_str = dob.strftime("%d-%m-%Y") if dob else ""
            ws.append([
                doc.get("name", ""),
                doc.get("phone", ""),
                doc.get("email", ""),
                doc.get("address", ""),
                dob_str,
                doc.get("gender", ""),
                doc.get("membership_type", ""),
                doc.get("batch", ""),
                doc.get("status", ""),
            ])
        buf = BytesIO()
        wb.save(buf)
        buf.seek(0)
        chunk = buf.read(8192)
        while chunk:
            yield chunk
            chunk = buf.read(8192)
    return StreamingResponse(
        iterfile(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=members.xlsx"},
    )


@router.get("/export/payments")
async def export_payments_excel(gym_id: str = Depends(get_gym_admin)):
    import pandas as pd
    q = gym_filter(gym_id)
    cursor = payments_collection.find(q).sort("created_at", -1)
    rows = []
    async for doc in cursor:
        rows.append({
            "id": str(doc["_id"]),
            "member_id": doc.get("member_id", ""),
            "member_name": doc.get("member_name", ""),
            "amount": doc.get("amount", 0),
            "fee_type": doc.get("fee_type", ""),
            "period": doc.get("period", ""),
            "status": doc.get("status", ""),
            "due_date": str(to_date(doc.get("due_date")) or ""),
            "paid_at": str(doc.get("paid_at")) if doc.get("paid_at") else "",
        })
    df = pd.DataFrame(rows)
    buf = BytesIO()
    df.to_excel(buf, index=False, engine="openpyxl")
    buf.seek(0)
    return StreamingResponse(buf, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", headers={"Content-Disposition": "attachment; filename=payments.xlsx"})


__all__ = ["router"]
