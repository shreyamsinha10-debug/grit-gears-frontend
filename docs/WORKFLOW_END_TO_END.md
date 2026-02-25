# GymSaaS – End-to-End Workflow

This document describes how the app works from app open to each user role, so you can answer follow-up questions confidently.

---

## 1. App entry and configuration

- **First screen**: Landing page (home) showing app name, **current backend URL**, "Set server URL" (optional), **Sign In** button, and "Ping server".
- **Server URL**: Stored in SharedPreferences; default is the production URL (`https://gymsaas-production-b4a0.up.railway.app`). Users can change it (e.g. for local testing).
- **Version check**: On load, app calls `GET /version`; if `min_app_version` is higher than the app version, an "Update required" dialog is shown.
- **Theme**: Light/dark is persisted in secure storage and applied globally.
- **No auto-login**: The app does not restore a previous session on startup. User always goes Landing → Sign In → Login screen, then routing depends on credentials.

---

## 2. User roles and login

**Single login screen**: Email or mobile number + password. Backend decides the role.

### Backend auth (`POST /auth/login`)

- **Super admin**: Fixed credentials (env `SUPER_ADMIN_LOGIN_ID` / `SUPER_ADMIN_PASSWORD`). Returns `role: "super_admin"`, JWT token.
- **Gym admin**: Lookup in `gym_admins` by `login_id`; password verified with bcrypt. Returns `role: "gym_admin"`, JWT with `gym_id`. If admin is inactive, returns 403.
- **Member**: `login_id` treated as phone; lookup in `gym_members` by `phone`; password verified. Member must be Active and have `gym_id`. Returns `role: "member"`, JWT, and **member** object (including `today_status`: checked_in / checked_out for today).

### Fallbacks (when auth API does not return a role)

- **Default admin**: Phone `9999999999` + password `999999` → app still calls `/auth/login`; if that returns a token, it's stored and user goes to Admin Dashboard.
- **Saved admin phone**: If the credential matches the last-used admin phone (from SecureStorage), user is sent to Admin Dashboard (no backend token in this path; used for legacy flow).
- **Member by phone**: `GET /members/by-phone/{phone}` (no password). If a member exists, user is sent to Member Home with that member payload.
- **First-time owner**: If no admin phone is saved and the credential is not a member, app saves the phone as admin and opens Admin Dashboard (with a "Welcome, you have full admin access" message).

### Where each role goes after login

| Role          | Screen / destination   |
|---------------|------------------------|
| `super_admin` | **Super Admin** screen (manage gym admins) |
| `gym_admin`   | **Admin Dashboard** (Overview, Members, Fees, Billing) |
| `member`      | **Member Home** (member object passed to screen) |

---

## 3. Admin workflow

### Admin Dashboard (bottom nav)

- **Overview (tab 0)**: Analytics from `GET /analytics/dashboard` (active/inactive counts, today's check-ins, fees summary, etc.). Optional date range. Links to **Gym Settings** (name, logo, invoice name). "Send fee reminders" calls `POST /admin/run-fee-reminders`.
- **Members (tab 1)**: List from `GET /members`. Search, tap member → **Member Detail**. "Register" → **Registration** screen (new member with photo, ID doc, batch, type, etc.).
- **Fees (tab 2)**: Fee summary and "Log monthly" payments; list of payments; mark as paid.
- **Billing (tab 3)**: **Billing** screen (Issue walk-in invoice, History, Export).

### App bar actions (admin)

- **Occupancy heatmap** → **Heatmap** screen (`GET /attendance/heatmap`): by day and hour (5 AM–11 PM), occupancy levels, "peak hours" and "best times to suggest" (disjoint lists).
- **Calendar** → **Attendance report**: by date or range; list of check-ins/outs.
- **Export** → Menu: Export Members / Payments / Billing to Excel (calls `/export/members`, `/export/payments`, `/export/billing`).

### Session and security

- **Session timeout**: 15 minutes of no interaction; then token and role are cleared and user is sent back to **Login**.
- All admin API calls use **Bearer token** from `ApiClient` (set after login).

### Key admin actions

- **Registration**: `POST /members` (name, phone, email, membership type, batch, optional workout/diet, photo and ID doc as base64).
- **Member detail**: View/edit member, view payments, **check-in / check-out** for that member (`POST /attendance/check-in/{id}`, `POST /attendance/check-out/{id}`), mark payment paid, update photo/ID doc.
- **Fees**: Log monthly fee (`POST /payments/log-monthly`), mark paid (`POST /payments/pay`).
- **Billing**: Issue invoice for walk-in (`POST /billing/issue`), view history (`GET /billing/history`), mark paid (`POST /billing/pay`), export billing Excel.

---

## 4. Member workflow

### Member Home (after member login)

- **Profile card**: Name, batch, status, last check-in date.
- **Profile and ID**: Upload/change/remove **profile photo** (`PATCH /members/{id}/photo`) and **ID document** (`PATCH /members/{id}/id-document`).
- **Inbox**: Due/overdue fees for this member (`GET /payments?member_id=...`). "Pay" opens simulated payment dialog and calls `POST /payments/pay?member_id=...&payment_id=...`.
- **Check In / Check Out**: Buttons call `POST /attendance/check-in/{id}` and `POST /attendance/check-out/{id}`. One check-in and one check-out per calendar day (IST); UI disables after done.
- **Attendance**: Stats from `GET /members/{id}/attendance-stats` (total visits, this month, avg duration, last visit).
- **PT vs Regular**:
  - **PT**: Shows **Workout Schedule** and **Diet Chart** from member profile (admin-assigned).
  - **Regular**: Shows preset weekly workout chips (Chest Day, Leg Day, etc.; UI-only, no backend).

---

## 5. Backend – data and key APIs

### Data (MongoDB, IST for dates/times)

- **Collections**: `gym_members`, `attendance_logs`, `payments`, `invoices`, `gyms`, `gym_admins`.
- **Member**: `gym_id`, phone, name, email, batch (Morning/Evening/Ladies), status (Active/Inactive), membership_type (Regular/PT), optional workout_schedule, diet_chart, photo_base64, id_document_base64, password_hash.
- **Attendance**: One record per member per calendar day (IST); `check_in_at_ist`, `check_out_at_ist`; used for "currently in gym" and heatmap.
- **Payments**: Registration plus monthly fees; status Due/Overdue/Paid; amounts (e.g. Rs 500 Regular, Rs 2000 PT).

### Important business rules

- **Check-in**: One check-in per member per calendar day (IST). Double check-in same day returns 400.
- **Check-out**: Only if already checked in today; one check-out per day.
- **Inactivity**: Admin can run "Mark inactive by attendance" (`POST /admin/mark-inactive-by-attendance`); members with no check-in for 90 days can be marked Inactive.
- **Heatmap**: `GET /attendance/heatmap` returns grid by day-of-week and hour (5 AM–11 PM), plus **quietest_slots** and **busiest_slots** (disjoint: a slot appears either as "best time" or "peak", not both).

### Auth and scoping

- **Gym admin**: JWT contains `gym_id`; all member/attendance/payment/billing APIs filter by this gym.
- **Member**: JWT contains `member_id` (and `gym_id`); member can only access own data (check-in/out, payments, profile).
- **Super admin**: Can manage gym admins (list/create/patch/password); not scoped to a single gym.

---

## 6. End-to-end flows (summary)

| Flow | Steps |
|------|--------|
| **Admin opens app** | Landing → Sign In → Login (admin credentials) → Admin Dashboard → Overview / Members / Fees / Billing. Can register member, check-in/out for member, log fees, issue invoices, export Excel, open Heatmap and Attendance report. |
| **Member opens app** | Landing → Sign In → Login (phone + password, or phone-only member lookup) → Member Home → Check-in/out, view dues, pay (simulated), view attendance stats, update photo/ID, view PT schedule/diet if PT. |
| **Super admin** | Login with super_admin credentials → Super Admin screen → Manage gym admins (create, edit, set password). |
| **Data flow** | Flutter uses `ApiClient` (base URL from env/default or SharedPreferences). All authenticated requests send `Authorization: Bearer <token>`. Backend uses JWT to resolve gym_id or member_id and applies filters. |

Use this as the single source of truth for "how does X work?" and "where is Y handled?" (e.g. login routing, check-in rules, heatmap, exports, session timeout, roles).
