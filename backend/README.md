# GymSaaS Backend

FastAPI backend for the GymSaaS app (members, attendance, payments, billing, messages).

## Local development

```bash
# From backend directory
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

**Local backend URL:** `http://localhost:8000` (or `http://127.0.0.1:8000`)

- API docs: http://localhost:8000/docs  
- OpenAPI JSON: http://localhost:8000/openapi.json  

In the Flutter app, set the server URL to this (e.g. via "Set server URL" on the login/home screen or `API_BASE_URL` when building).

## Environment

Copy `.env.example` to `.env` and set `MONGODB_URL`, `JWT_SECRET`, and optional super-admin credentials. See `.env.example` for details.
