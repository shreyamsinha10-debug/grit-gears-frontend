# GymSaaS Backend

FastAPI backend for the GymSaaS app (members, attendance, payments, billing, messages).

## Architecture (post–monolith refactor)

All route handlers live under **`app/`**:

- **`app/main.py`** – FastAPI app, lifespan, CORS, health routes (`/`, `/version`), and the aggregated API router
- **`app/api/routers/`** – auth, admin, members, documents, attendance, payments, billing, messages, export
- **`app/core/`** – config, security, auth dependencies
- **`app/db/`** – database client, collections, indexes
- **`app/models/`** – Pydantic schemas
- **`app/utils/`** – time, helpers, notifications, email

**`backend/main.py`** is a thin entrypoint: it re-exports `app` from `app.main` so `uvicorn main:app` (from the backend directory) and `uvicorn backend.main:app` (from repo root) both serve the same app.

## Local development

```bash
# From backend directory (recommended)
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Or from **repo root** (same app):

```bash
cd c:\src\GymSaaS
python -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

**Local backend URL:** `http://localhost:8000`

- API docs: http://localhost:8000/docs  
- OpenAPI JSON: http://localhost:8000/openapi.json  

**Checking logs:** When you run the backend in a terminal, all logs appear there. For email (forgot-password, test): look for `INFO:app.utils.email:Email sent to ...` (success), `WARNING:app.utils.email:Email skipped: ...` (SMTP not configured), or `ERROR:... Email failed to ...` (SMTP error). Run from the `backend` directory so `backend/.env` is loaded.

In the Flutter app, set the server URL to `http://localhost:8000` (e.g. via "Set server URL" or `API_BASE_URL` when building).

1. **In the app (easiest):** Run the Flutter app, then use **Set server URL** (or the URL field on login/home) and set it to `http://localhost:8000` (no trailing slash). The app persists this for next runs.

2. **At build time (web):**
   ```bash
   cd frontend
   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
   ```

3. **At build time (APK):**
   ```bash
   cd frontend
   flutter build apk --release --dart-define=API_BASE_URL=http://localhost:8000
   ```

### Quick checks

| Step | Action |
|------|--------|
| 1 | Start backend (see above). Ensure MongoDB is running and `.env` has `MONGODB_URL`, `JWT_SECRET`, `SUPER_ADMIN_LOGIN_ID`, `SUPER_ADMIN_PASSWORD`, `ALLOWED_ORIGINS`. |
| 2 | Open http://localhost:8000 → should return a JSON status. |
| 3 | Open http://localhost:8000/docs → try `GET /`, `POST /auth/login` with super-admin credentials. |
| 4 | Start frontend: `cd frontend && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000`. Set server URL in app to `http://localhost:8000` if you didn’t use the dart-define. |
| 5 | In the app: Admin login → create gym/admin if needed → Members, Billing, Attendance, Export. Member login with a registered phone and OTP `123456`. |

If you use **Option B**, you can also test `POST /auth/forgot-password` in Swagger (http://localhost:8000/docs) with a body like `{"email": "member@example.com"}` (use an email that exists for a member).

## Environment

Copy `.env.example` to `.env` and set `MONGODB_URL`, `JWT_SECRET`, and optional super-admin credentials. See `.env.example` for details. For the refactor, `ALLOWED_ORIGINS` is required (comma-separated list, e.g. `http://localhost:3000,http://localhost:8080`).

## Deploying to Railway (or similar)

The **refactored backend has no default values** for required settings. If any required env var is missing, the app **fails on startup** (before it can serve requests). That often shows as "unable to reach" or 502/503 from the public URL.

**Required variables** (set these in Railway → your service → Variables):

| Variable | Example | Notes |
|----------|---------|--------|
| `MONGODB_URL` | `mongodb+srv://user:pass@cluster.mongodb.net/` | MongoDB Atlas or other connection string |
| `DATABASE_NAME` | `gym_db` | Database name |
| `SUPER_ADMIN_LOGIN_ID` | `admin@gymsaas.com` | Super-admin login (e.g. for app) |
| `SUPER_ADMIN_PASSWORD` | `YourSecurePassword` | Super-admin password |
| `JWT_SECRET` | Long random string | Use a strong secret in production |
| `ALLOWED_ORIGINS` | `https://your-app.web.app,http://localhost:8080` | Comma-separated; include your frontend and any app origins |

Optional: `BACKEND_LABEL` (e.g. `Railway`) so `GET /` returns it for health checks.

**Optional – Password reset and email:**

| Variable | Example | Notes |
|----------|---------|--------|
| `SMTP_SERVER` | `smtpout.secureserver.net` | GoDaddy: [SMTP settings](https://www.godaddy.com/help/set-up-third-party-plugins-or-websites-using-smtp-settings-42788) (port 465, SSL) |
| `SMTP_PORT` | `465` | |
| `SMTP_USERNAME` | `contact@yourdomain.com` | Usually same as FROM_EMAIL |
| `SMTP_PASSWORD` | Your email password | |
| `FROM_EMAIL` | `contact@yourdomain.com` | Sender address for reset emails |
| `FRONTEND_URL` | `https://your-app.web.app` | Base URL where the app is hosted (no trailing slash). Forgot-password emails send a link like `FRONTEND_URL/?token=xxx`. Set this for reset-link flow; if unset, a temporary password is emailed instead. |

**Start command** (from repo root or from `backend`):

- From repo root: `uvicorn backend.main:app --host 0.0.0.0 --port $PORT`  
- Or from `backend` directory: `uvicorn main:app --host 0.0.0.0 --port $PORT`

Railway sets `PORT` automatically. The app is the same in both cases (`backend/main.py` re-exports `app` from `app.main`).

**If the URL is unreachable:**

1. In Railway dashboard, open your service → **Deployments** → latest deploy → **View logs**.  
2. Look for startup errors (e.g. `ValidationError` from pydantic-settings = missing or invalid env var).  
3. Ensure all required variables above are set in **Variables** and redeploy.
