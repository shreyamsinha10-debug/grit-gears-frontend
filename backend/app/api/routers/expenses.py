"""
Expenses router: create expense, list by month, balance sheet (collections vs expenses).
"""

from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.auth import get_gym_context
from app.db.database import expenses_collection, payments_collection
from app.models.schemas import (
    BalanceSheetResponse,
    ExpenseCategory,
    ExpenseCreate,
    ExpenseResponse,
    ExpenseUpdate,
)
from app.utils.helpers import gym_filter

router = APIRouter()

_VALID_CATEGORIES = {e.value for e in ExpenseCategory}


def _validate_category(category: str) -> None:
    if category not in _VALID_CATEGORIES:
        raise HTTPException(
            status_code=400,
            detail=f"category must be one of: {sorted(_VALID_CATEGORIES)}",
        )


@router.post("", response_model=ExpenseResponse)
async def create_expense(
    body: ExpenseCreate,
    gym_id: str = Depends(get_gym_context),
):
    _validate_category(body.category)
    doc = {
        "gym_id": gym_id,
        "amount": body.amount,
        "category": body.category,
        "description": body.description,
        "expense_date": body.expense_date,
        "receipt_ref": body.receipt_ref,
        "created_at": datetime.now(timezone.utc),
    }
    result = await expenses_collection.insert_one(doc)
    return ExpenseResponse(
        id=str(result.inserted_id),
        gym_id=gym_id,
        amount=doc["amount"],
        category=doc["category"],
        description=doc.get("description"),
        expense_date=doc["expense_date"],
        receipt_ref=doc.get("receipt_ref"),
        created_at=doc["created_at"],
    )


@router.get("", response_model=list[ExpenseResponse])
async def list_expenses(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    gym_id: str = Depends(get_gym_context),
):
    q = {**gym_filter(gym_id), "expense_date": {"$regex": f"^{month}"}}
    cursor = expenses_collection.find(q).sort("expense_date", -1)
    out = []
    async for doc in cursor:
        out.append(
            ExpenseResponse(
                id=str(doc["_id"]),
                gym_id=doc["gym_id"],
                amount=doc["amount"],
                category=doc["category"],
                description=doc.get("description"),
                expense_date=doc["expense_date"],
                receipt_ref=doc.get("receipt_ref"),
                created_at=doc["created_at"],
            )
        )
    return out


@router.get("/balance-sheet", response_model=BalanceSheetResponse)
async def get_balance_sheet(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    gym_id: str = Depends(get_gym_context),
):
    year, month_num = int(month[:4]), int(month[5:7])
    start_dt = datetime(year, month_num, 1, 0, 0, 0, tzinfo=timezone.utc)
    if month_num == 12:
        end_dt = datetime(year + 1, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
    else:
        end_dt = datetime(year, month_num + 1, 1, 0, 0, 0, tzinfo=timezone.utc)

    # Collections: payments for this gym, status Paid, paid_at in [start_dt, end_dt)
    pay_q = {
        **gym_filter(gym_id),
        "status": "Paid",
        "paid_at": {"$gte": start_dt, "$lt": end_dt},
    }
    total_collections = 0
    async for doc in payments_collection.find(pay_q, {"amount": 1}):
        total_collections += doc.get("amount") or 0

    # Expenses: this gym, expense_date in month; sum total and group by category
    exp_q = {**gym_filter(gym_id), "expense_date": {"$regex": f"^{month}"}}
    total_expenses = 0
    category_breakdown = {}
    async for doc in expenses_collection.find(exp_q):
        amt = doc.get("amount") or 0
        total_expenses += amt
        cat = doc.get("category") or "Other"
        category_breakdown[cat] = category_breakdown.get(cat, 0) + amt

    return BalanceSheetResponse(
        month=month,
        total_collections=total_collections,
        total_expenses=total_expenses,
        net_balance=total_collections - total_expenses,
        category_breakdown=category_breakdown,
    )


@router.get("/{expense_id}", response_model=ExpenseResponse)
async def get_expense(
    expense_id: str,
    gym_id: str = Depends(get_gym_context),
):
    try:
        oid = ObjectId(expense_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid expense ID")
    q = {**gym_filter(gym_id), "_id": oid}
    doc = await expenses_collection.find_one(q)
    if not doc:
        raise HTTPException(status_code=404, detail="Expense not found")
    return ExpenseResponse(
        id=str(doc["_id"]),
        gym_id=doc["gym_id"],
        amount=doc["amount"],
        category=doc["category"],
        description=doc.get("description"),
        expense_date=doc["expense_date"],
        receipt_ref=doc.get("receipt_ref"),
        created_at=doc["created_at"],
    )


@router.patch("/{expense_id}", response_model=ExpenseResponse)
async def update_expense(
    expense_id: str,
    body: ExpenseUpdate,
    gym_id: str = Depends(get_gym_context),
):
    try:
        oid = ObjectId(expense_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid expense ID")
    q = {**gym_filter(gym_id), "_id": oid}
    doc = await expenses_collection.find_one(q)
    if not doc:
        raise HTTPException(status_code=404, detail="Expense not found")
    update = {}
    if body.amount is not None:
        update["amount"] = body.amount
    if body.category is not None:
        _validate_category(body.category)
        update["category"] = body.category
    if body.description is not None:
        update["description"] = body.description
    if body.expense_date is not None:
        update["expense_date"] = body.expense_date
    if body.receipt_ref is not None:
        update["receipt_ref"] = body.receipt_ref
    if not update:
        return ExpenseResponse(
            id=str(doc["_id"]),
            gym_id=doc["gym_id"],
            amount=doc["amount"],
            category=doc["category"],
            description=doc.get("description"),
            expense_date=doc["expense_date"],
            receipt_ref=doc.get("receipt_ref"),
            created_at=doc["created_at"],
        )
    await expenses_collection.update_one(q, {"$set": update})
    doc = await expenses_collection.find_one(q)
    return ExpenseResponse(
        id=str(doc["_id"]),
        gym_id=doc["gym_id"],
        amount=doc["amount"],
        category=doc["category"],
        description=doc.get("description"),
        expense_date=doc["expense_date"],
        receipt_ref=doc.get("receipt_ref"),
        created_at=doc["created_at"],
    )


__all__ = ["router"]
