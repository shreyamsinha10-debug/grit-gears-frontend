# GymSaaS

A commercial-grade Gym Management System built with **FastAPI** (Backend) and **Flutter** (Frontend).

## Features

- **Member Management**: Register members, assign batches (Morning/Evening/Ladies), and track status (Active/Inactive).
- **Attendance Tracking**:
  - Daily check-ins via dashboard.
  - Prevents double check-ins within 4 hours.
  - **Automated Inactivity**: Members who haven't checked in for 90 days are automatically marked 'Inactive'.
- **Financial Engine**:
  - Track payments (Registration + Monthly fees).
  - Dashboard overview of Paid, Due, and Overdue fees.
  - Simulated payment gateway integration.
- **Personal Training (PT)**:
  - Admin can assign custom Workout Schedules and Diet Charts.
  - PT members see their personalized plans in the app.
- **Reporting**:
  - Export Member and Payment data to Excel.
  - Daily Attendance Reports.

## Tech Stack

- **Backend**: Python, FastAPI, MongoDB (Motor), Pandas
- **Frontend**: Flutter (Web/Mobile), Google Fonts, Provider pattern
- **Database**: MongoDB Atlas

## How to Run

### 1. Backend

1.  Navigate to the backend folder:
    ```bash
    cd backend
    ```
2.  Install dependencies:
    ```bash
    pip install -r requirements.txt
    ```
3.  Run the server:
    ```bash
    python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
    ```
    *API will be available at http://localhost:8000*

### 2. Frontend

1.  Navigate to the frontend folder:
    ```bash
    cd frontend
    ```
2.  Install packages:
    ```bash
    flutter pub get
    ```
3.  Run the app (Web):
    ```bash
    flutter run -d chrome
    ```
    *App opens in Chrome; API is expected at http://localhost:8000.*

## Build APK for sharing (Android)

To generate an APK you can share with friends for testing:

1.  Open a terminal in the project and run:
    ```bash
    cd frontend
    flutter build apk --release
    ```
2.  When the build finishes, the APK is at:
    ```
    frontend/build/app/outputs/flutter-apk/app-release.apk
    ```
3.  Share that file (e.g. via Google Drive, WhatsApp, or email). Testers install it on their Android phone (they may need to allow “Install from unknown sources” for your file source).

**Important when sharing with others:** The app is configured to call `http://localhost:8000`. On your friends’ phones, “localhost” is their device, so the app will not reach your backend unless you either:
- **Option A:** Deploy your backend to a public URL (e.g. a VPS or cloud), then in `frontend/lib/core/api_client.dart` set `baseUrl` to that URL (e.g. `https://your-api.example.com`) and rebuild the APK, or  
- **Option B:** Use the app only for **UI/review** (screens, navigation, layout). Buttons that call the API will fail unless the phone can reach the server.

For a quick **UI-only** build to show the look and flow, the default APK is fine; testers will see the interface even if API calls fail.

---

## Share APK for full end-to-end testing (friends can use all features)

To let friends test the full app (login, members, billing, attendance, etc.) on their phones, the app must call **your backend** on the internet, not localhost. Follow these steps.

### Step 1: Deploy the backend to a public URL

Your backend must be reachable at a URL like `https://your-app.railway.app` or `https://gymsaas.onrender.com`. The app already uses **MongoDB Atlas**, so the backend can run on any cloud host.

**Option A – Railway (recommended, free tier)**  
1. Go to [railway.app](https://railway.app), sign in with GitHub.  
2. **New Project** → **Deploy from GitHub repo** → select your GymSaaS repo (or upload the `backend` folder).  
3. Set **Root Directory** to `backend` (if you deployed the whole repo).  
4. Set **Start Command** to: `uvicorn main:app --host 0.0.0.0 --port $PORT`.  
5. Add **Variables**: `MONGODB_URL` = your existing MongoDB Atlas connection string (same as in `backend/main.py`; you can keep it in code for now or move to env).  
6. Deploy; Railway will give you a URL like `https://your-app.railway.app`. Use this as your API URL (no trailing slash).

**Option B – Render (free tier)**  
1. Go to [render.com](https://render.com), sign in.  
2. **New** → **Web Service** → connect repo or upload.  
3. **Root Directory**: `backend`. **Build**: `pip install -r requirements.txt`. **Start**: `uvicorn main:app --host 0.0.0.0 --port $PORT`.  
4. Add **Environment Variable**: `MONGODB_URL` (your Atlas URL).  
5. Deploy and copy the service URL (e.g. `https://gymsaas.onrender.com`).

**Option C – Quick test with ngrok (your PC as server)**  
1. Run your backend locally: `cd backend && uvicorn main:app --host 0.0.0.0 --port 8000`.  
2. Install [ngrok](https://ngrok.com), then run: `ngrok http 8000`.  
3. Use the HTTPS URL ngrok shows (e.g. `https://abc123.ngrok.io`) as your API URL.  
Note: The URL changes each time you restart ngrok (free); good for a quick test, not for long-term sharing.

### Step 2: Point the app to your backend and build the APK

Open a terminal in the project and run (replace with **your** backend URL, no trailing slash):

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-BACKEND-URL
```

Examples:

- Railway: `flutter build apk --release --dart-define=API_BASE_URL=https://gymsaas-production-87a0.up.railway.app`
- Render: `flutter build apk --release --dart-define=API_BASE_URL=https://gymsaas.onrender.com`
- ngrok: `flutter build apk --release --dart-define=API_BASE_URL=https://abc123.ngrok.io`

The built APK will use this URL for all API calls.

---

## Host the web app on Vercel

You can host the **Flutter web app** on Vercel and keep using your **existing backend on Railway** (e.g. `https://gymsaas-production-87a0.up.railway.app`). The app is already configured to use that URL by default; no backend code change is needed. The backend allows all origins (`allow_origins=["*"]`), so the Vercel domain can call the API.

### Option A – Vercel builds the app (simplest, but slow first build)

1. Go to [vercel.com](https://vercel.com) and sign in with GitHub.
2. **Add New** → **Project** → import your **GymSaaS** repo.
3. Configure the project:
   - **Root Directory**: click **Edit** → set to **`frontend`** (so Vercel uses the Flutter app).
   - **Build Command**, **Install Command**, **Output Directory**: leave as in `frontend/vercel.json` (Vercel will use it). The install step downloads the Flutter SDK (~1 GB), so the first build can take 10–15 minutes.
   - **Output Directory**: `build/web` (from vercel.json).
4. Click **Deploy**. When it finishes, you get a URL like `https://gymsaas-xxx.vercel.app`. The web app will call your Railway backend automatically.

### Option B – GitHub Actions builds and deploys to Vercel (faster, more reliable)

This avoids installing Flutter on Vercel by building in GitHub Actions and deploying the built files.

1. **Create a Vercel project** (to get IDs):
   - Vercel → **Add New** → **Project** → import your repo.
   - Set **Root Directory** to **`frontend`**.
   - Deploy once (can cancel after it starts, or let it run). Go to **Project Settings** → note the **Project ID**. Under **General** or your team, note the **Org ID** (Team ID or your user id from the URL).

2. **Create a Vercel token**: [vercel.com/account/tokens](https://vercel.com/account/tokens) → **Create** → copy the token.

3. **Add GitHub secrets** (repo → Settings → Secrets and variables → Actions):
   - `VERCEL_TOKEN` = the token from step 2.
   - `VERCEL_ORG_ID` = your Org/Team ID.
   - `VERCEL_PROJECT_ID` = the Project ID from step 1.

4. **Workflow file**: A workflow is provided at `.github/workflows/deploy-web-vercel.yml`. Push it to your repo (e.g. with your next commit). On every push to `main`, the workflow builds the Flutter web app and deploys it to Vercel.

After deployment, the web app URL (e.g. `https://gymsaas-xxx.vercel.app`) uses the same Railway backend; no extra configuration needed.

### Step 3: Get the APK and share it

After the build finishes, the APK is at:

```
frontend/build/app/outputs/flutter-apk/app-release.apk
```

Share this file (Google Drive, WhatsApp, email, etc.). Testers install it on their Android phone (they may need to allow “Install from unknown sources” for the app or browser used to open the file).

### Step 4: Tell testers how to use it

- **Admin:** Open app → **Admin Dashboard** → use Overview, Members, Fees, Billing, Attendance.  
- **Member login:** They need a **phone number** that exists in your database. Create at least one member from Admin (or Billing → Walk-in), then share that phone number with friends. They tap **Member Login** → enter that phone → OTP **123456** (simulated) → then they see their dashboard, attendance, and (if PT) diet/workout.  
- Backend must be **running** and **reachable** (Railway/Render stay up; ngrok only while your PC and ngrok are running).

### Checklist

| Step | What to do |
|------|------------|
| 1 | Deploy backend (Railway / Render / ngrok) and get HTTPS URL |
| 2 | `cd frontend` then `flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-URL` |
| 3 | Share `frontend/build/app/outputs/flutter-apk/app-release.apk` |
| 4 | Share a test phone number (and that OTP is 123456) so they can try Member Login |

## How to Test

### Quick run (two terminals)

**Terminal 1 – Backend**
```bash
cd backend
pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
Wait until you see `Uvicorn running on http://0.0.0.0:8000`.

**Terminal 2 – Frontend**
```bash
cd frontend
flutter pub get
flutter run -d chrome
```

### Verify backend

- Open http://localhost:8000 in a browser → should return JSON like `{"message":"Gym API is Live!"}`.
- Docs: http://localhost:8000/docs (Swagger UI).

### Test in the app

1. **Home screen**  
   - Tap **Admin** → opens Admin Dashboard (Overview, Members, Fees, Billing).  
   - Tap **Member Login** → opens Member login (phone + OTP).

2. **Admin**
   - **Overview:** Total Active/Inactive, Total Collections, Pending Dues, Regular vs PT; tap **Send Month-End Reminders** (simulated WhatsApp in backend console).
   - **Members:** Register a member (name, phone, email, batch, type Regular/PT). Open a member → for PT, edit Diet chart / Workout schedule.
   - **Fees:** See Paid/Due/Overdue summary and list of payments.
   - **Billing:**  
     - **Walk-in:** New member + first bill (Registration + 1st month) → member appears in Members.  
     - **Existing Member:** Select member → Log payment (cash/UPI).  
     - **Invoice / History:** View invoice, simulated UPI QR, Mark as Paid; **Export CSV/Excel** downloads billing history.
   - **AppBar:** Calendar → Attendance report; Export → Members / Payments / Billing Excel.

3. **Member portal**
   - On home, tap **Member Login**. Enter a **registered phone number** (e.g. one you created in Admin).
   - Request OTP → use **123456** (simulated).
   - After login: see **Attendance** (last check-in), **Status**, **Batch**.  
   - **PT members:** Diet chart and Workout schedule (if set by admin).  
   - **Regular members:** Preset weekly workouts (Chest Day, Leg Day, etc.).  
   - **Pay Fees:** List of Due/Overdue payments; Pay → simulated payment (backend marks as Paid and prints `[WHATSAPP SENT to ...]` in backend console).

### Optional: seed test data

- From **Admin → Members** (embedded dashboard), use **Seed 90-day test members** and **Mark inactive (90d)** to test the 90-day auto-inactive flow.
- Backend console shows simulated notifications when you register, pay, or run fee reminders.

## Performance (Enterprise / Gym Management)

The Flutter app uses several best practices for faster load and smoother UX:

- **Shared API client** (`lib/core/api_client.dart`): Single HTTP client (connection reuse), configurable timeouts, and in-memory GET cache (45s TTL). List/dashboard endpoints use cache so tab switches and repeat views are instant; pull-to-refresh invalidates cache for fresh data.
- **Lazy tab loading**: Admin dashboard builds only the selected tab when first visited (Overview, Members, Fees, Billing), reducing initial work and memory.
- **Asset precache**: Logo is precached after the first frame so it appears quickly when opening Admin or Member screens.
- **RepaintBoundary**: Member list cards are wrapped in `RepaintBoundary` for smoother scrolling.
- **Explicit binding**: `WidgetsFlutterBinding.ensureInitialized()` in `main()` for correct startup on Android/iOS.

To change cache duration or base URL, edit `lib/core/api_client.dart`.

## Project Structure

- `backend/`: FastAPI application, database logic, and automation scripts.
- `frontend/`: Flutter application code (Screens, Widgets, Models). `lib/core/api_client.dart` for shared HTTP and cache.

## Code structure (for developers)

The codebase is commented so that **junior developers** can follow the flow and understand where to change things. Start with the entry points below, then follow the section comments and docstrings in each file.

### Backend (`backend/`)

| File / area | Purpose |
|-------------|---------|
| **`main.py`** | Single FastAPI app: config, DB (MongoDB collections), time helpers (IST), CORS, Pydantic models, and all routes. Section comments inside mark: **Members** (CRUD, by-phone, attendance stats), **Attendance** (check-in/out, by date, summary), **Payments** (list, fees summary, log monthly, mark paid), **Billing** (walk-in, history, mark paid), **Analytics** (dashboard, fee reminders), **Export** (Excel). |
| **`utils.py`** | Simulated notifications (WhatsApp/email). `send_notification(notification_type, user, extra)` — in production you would replace with real SMS/email/WhatsApp. |

**MongoDB collections** used in `main.py`: `members`, `attendance`, `payments`, `invoices`. All dates in business logic use **IST** (see time helpers at top of `main.py`).

### Frontend (`frontend/lib/`)

| Folder / file | Purpose |
|---------------|---------|
| **`main.dart`** | App entry: theme (light/dark), initial route (Login vs Admin Dashboard vs Member Home). Theme and server URL are persisted. |
| **`core/`** | Shared logic: **api_client.dart** (single HTTP client, base URL, cache, DNS fallback), **date_utils.dart** (display + API date format), **export_helper.dart** (download Excel to device), **secure_storage.dart** (admin phone/PIN, theme), **app_constants.dart** (app version for update check). |
| **`theme/app_theme.dart`** | Light and dark theme (colors, Poppins, Material 3). |
| **`screens/`** | **login_screen.dart** (unified login → Admin or Member), **admin_dashboard_screen.dart** (tabs: Members, Attendance, Billing, More), **dashboard_screen.dart** (member list, search, check-in), **member_detail_screen.dart** (profile, edit, payments, attendance), **member_home_screen.dart** (member portal: check-in/out, fees), **attendance_report_screen.dart**, **billing_screen.dart**, **registration_screen.dart**, **admin_login_screen.dart**, **member_login_screen.dart**. |
| **`widgets/`** | **animated_fade.dart** (FadeInSlide for list items), **skeleton_loading.dart** (skeleton placeholders + haptics). |

To trace a feature (e.g. “mark payment paid”): start from the screen (e.g. `member_detail_screen.dart` or billing), find the button handler, then follow the `ApiClient` call to the backend route in `main.py` (e.g. `POST /payments/pay`).
