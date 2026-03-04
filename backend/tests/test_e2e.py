"""
Backend E2E tests: hit real FastAPI app and MongoDB (test DB).
Uses async client so Motor runs in the same event loop (avoids "Event loop is closed").
Run from repo root: pytest backend/tests/ -v
Or from backend: pytest tests/ -v

Requires: MongoDB running (MONGODB_URL); env DATABASE_NAME, SUPER_ADMIN_LOGIN_ID,
SUPER_ADMIN_PASSWORD, JWT_SECRET, ALLOWED_ORIGINS. The client fixture logs in as
super_admin, creates a gym+admin (or reuses if "e2e_admin" exists), then uses the
gym_admin token for all requests.
"""
import os
import sys
from pathlib import Path

_backend = Path(__file__).resolve().parent.parent
if str(_backend) not in sys.path:
    sys.path.insert(0, str(_backend))

import pytest
from httpx import ASGITransport, AsyncClient

try:
    from pymongo.errors import ServerSelectionTimeoutError
except ImportError:
    ServerSelectionTimeoutError = Exception  # motor may expose it differently

from main import app

# Run all tests in this module as async; session-scoped client shares one event loop with Motor
pytestmark = pytest.mark.asyncio


@pytest.fixture(scope="session")
async def client():
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            # Obtain gym_admin token: login as super_admin -> create gym+admin -> login as gym_admin
            super_id = os.environ.get("SUPER_ADMIN_LOGIN_ID", "")
            super_pass = os.environ.get("SUPER_ADMIN_PASSWORD", "")
            r = await ac.post("/auth/login", json={"login_id": super_id, "password": super_pass})
            assert r.status_code == 200, f"Super admin login failed: {r.text}"
            super_token = r.json()["token"]
            r2 = await ac.post(
                "/super-admin/admins",
                json={"gym_name": "E2E Gym", "admin_login_id": "e2e_admin", "admin_password": "e2epass123"},
                headers={"Authorization": f"Bearer {super_token}"},
            )
            # 200 = created; 400 with "already in use" = reuse existing admin from prior run
            if r2.status_code not in (200, 400):
                pytest.fail(f"Create gym admin failed: {r2.status_code} {r2.text}")
            if r2.status_code == 400 and "already in use" not in (r2.json().get("detail") or ""):
                pytest.fail(f"Create gym admin failed: {r2.text}")
            r3 = await ac.post("/auth/login", json={"login_id": "e2e_admin", "password": "e2epass123"})
            assert r3.status_code == 200, f"Gym admin login failed: {r3.text}"
            gym_token = r3.json()["token"]
    except ServerSelectionTimeoutError as e:
        pytest.skip(
            f"MongoDB not running at MONGODB_URL. Start MongoDB (e.g. local or Docker) to run E2E tests. {e!r}"
        )
    # Client that sends gym_admin token on every request
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {gym_token}"},
    ) as ac:
        yield ac


async def test_root(client: AsyncClient):
    r = await client.get("/")
    assert r.status_code == 200
    data = r.json()
    assert data.get("status") == "success"
    assert "Gym API" in (data.get("message") or "")


async def test_version(client: AsyncClient):
    r = await client.get("/version")
    assert r.status_code == 200
    data = r.json()
    assert "min_app_version" in data
    assert "api_version" in data


async def test_member_crud_and_by_phone(client: AsyncClient):
    payload = {
        "name": "E2E Test User",
        "phone": "9876543210",
        "email": "e2e@example.com",
        "membership_type": "Regular",
        "batch": "Morning",
    }
    r = await client.post("/members", json=payload)
    assert r.status_code == 200, r.text
    created = r.json()
    member_id = created["id"]
    assert created["name"] == payload["name"]
    assert created["phone"] == payload["phone"]
    assert created["email"] == payload["email"]
    assert created["membership_type"] == "Regular"
    assert created["batch"] == "Morning"
    assert created["status"] == "Active"

    r2 = await client.get(f"/members/{member_id}")
    assert r2.status_code == 200
    assert r2.json()["id"] == member_id

    r3 = await client.get("/members/by-phone/9876543210")
    assert r3.status_code == 200
    assert r3.json()["phone"] == "9876543210"

    r4 = await client.get("/members")
    assert r4.status_code == 200
    members = r4.json()
    assert isinstance(members, list)
    assert member_id in [m["id"] for m in members]


async def test_attendance_check_in_check_out(client: AsyncClient):
    payload = {
        "name": "Attendance Test",
        "phone": "9876543211",
        "email": "att@example.com",
        "membership_type": "Regular",
        "batch": "Evening",
    }
    r = await client.post("/members", json=payload)
    assert r.status_code == 200, r.text
    member_id = r.json()["id"]

    r_in = await client.post(f"/attendance/check-in/{member_id}")
    assert r_in.status_code == 200, r_in.text
    check_in_data = r_in.json()
    assert check_in_data["member_id"] == member_id
    assert check_in_data["date_ist"]
    assert check_in_data["batch"]
    assert check_in_data["check_in_at"]
    assert check_in_data["check_out_at"] is None

    r_dup = await client.post(f"/attendance/check-in/{member_id}")
    assert r_dup.status_code == 400

    r_today = await client.get("/attendance/today")
    assert r_today.status_code == 200
    today_list = r_today.json()
    assert isinstance(today_list, list)
    assert any(e["member_id"] == member_id for e in today_list)

    r_out = await client.post(f"/attendance/check-out/{member_id}")
    assert r_out.status_code == 200, r_out.text
    assert r_out.json()["check_out_at"] is not None


async def test_payments_and_log_monthly(client: AsyncClient):
    payload = {
        "name": "Payment Test",
        "phone": "9876543212",
        "email": "pay@example.com",
        "membership_type": "Regular",
        "batch": "Morning",
    }
    r = await client.post("/members", json=payload)
    assert r.status_code == 200, r.text
    member_id = r.json()["id"]

    r_list = await client.get("/payments", params={"member_id": member_id})
    assert r_list.status_code == 200
    payments = r_list.json()
    assert isinstance(payments, list)
    assert len(payments) >= 1

    from datetime import date
    period = date.today().strftime("%Y-%m")
    r_log = await client.post(
        "/payments/log-monthly",
        json={"member_id": member_id, "period": period, "amount": 500},
    )
    assert r_log.status_code == 200, r_log.text
    log_data = r_log.json()
    assert log_data["status"] == "Paid"
    assert log_data["amount"] == 500
    assert log_data["period"] == period

    r_sum = await client.get("/payments/fees-summary")
    assert r_sum.status_code == 200


async def test_billing_issue_and_history_and_pay(client: AsyncClient):
    payload = {
        "name": "Billing Walk-in",
        "phone": "9876543213",
        "email": "bill@example.com",
        "membership_type": "Regular",
        "batch": "Ladies",
    }
    r_issue = await client.post("/billing/issue", json=payload)
    assert r_issue.status_code == 200, r_issue.text
    inv = r_issue.json()
    invoice_id = inv["id"]
    member_id = inv["member_id"]
    assert inv["status"] == "Unpaid"
    assert inv["total"] > 0
    assert len(inv["items"]) >= 1

    r_hist = await client.get("/billing/history", params={"member_id": member_id})
    assert r_hist.status_code == 200
    history = r_hist.json()
    assert isinstance(history, list)
    assert any(h["id"] == invoice_id for h in history)

    r_pay = await client.post("/billing/pay", params={"invoice_id": invoice_id})
    assert r_pay.status_code == 200, r_pay.text
    paid_inv = r_pay.json()
    assert paid_inv["status"] == "Paid"
    assert paid_inv["paid_at"] is not None


async def test_analytics_dashboard(client: AsyncClient):
    r = await client.get("/analytics/dashboard")
    assert r.status_code == 200, r.text
    data = r.json()
    assert "active_members" in data
    assert "inactive_members" in data
    assert "total_collections" in data
    assert "pending_fees_amount" in data
    assert "today_attendance_count" in data


async def test_export_endpoints(client: AsyncClient):
    r_billing = await client.get("/export/billing")
    assert r_billing.status_code == 200
    assert "application" in r_billing.headers.get("content-type", "")

    r_members = await client.get("/export/members")
    assert r_members.status_code == 200

    r_payments = await client.get("/export/payments")
    assert r_payments.status_code == 200


async def test_expenses_create_list_balance_sheet(client: AsyncClient):
    """Expense management: create expense, list by month, get balance sheet."""
    from datetime import date
    month = date.today().strftime("%Y-%m")
    day = date.today().strftime("%Y-%m-%d")

    # POST /expenses
    r_create = await client.post(
        "/expenses",
        json={
            "amount": 1500,
            "category": "Electricity",
            "description": "E2E test bill",
            "expense_date": day,
            "receipt_ref": "REF-E2E-001",
        },
    )
    assert r_create.status_code == 200, r_create.text
    created = r_create.json()
    assert created["amount"] == 1500
    assert created["category"] == "Electricity"
    assert created["expense_date"] == day
    assert created["gym_id"]
    assert created["id"]

    # GET /expenses?month=YYYY-MM
    r_list = await client.get("/expenses", params={"month": month})
    assert r_list.status_code == 200, r_list.text
    expenses = r_list.json()
    assert isinstance(expenses, list)
    assert any(e["id"] == created["id"] and e["amount"] == 1500 for e in expenses)

    # GET /expenses/balance-sheet?month=YYYY-MM
    r_sheet = await client.get("/expenses/balance-sheet", params={"month": month})
    assert r_sheet.status_code == 200, r_sheet.text
    sheet = r_sheet.json()
    assert sheet["month"] == month
    assert "total_collections" in sheet
    assert "total_expenses" in sheet
    assert "net_balance" in sheet
    assert "category_breakdown" in sheet
    assert sheet["total_expenses"] >= 1500
    assert sheet["category_breakdown"].get("Electricity", 0) >= 1500


async def test_get_member_404(client: AsyncClient):
    r = await client.get("/members/000000000000000000000000")
    assert r.status_code == 404


async def test_get_member_invalid_id(client: AsyncClient):
    r = await client.get("/members/not-an-object-id")
    assert r.status_code == 400
