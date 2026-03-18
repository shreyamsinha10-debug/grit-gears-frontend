# Railway: Set the 6 Required Variables (Step-by-Step)

## Where to find Variables in Railway

1. **Open Railway**  
   Go to [railway.app](https://railway.app) and log in.

2. **Open your project**  
   Click the project that hosts your GymSaaS backend (the one that deploys from GitHub).

3. **Open the backend service**  
   Click the **service** that runs the API (the one that runs `uvicorn`). It might be named "backend", "api", or after your repo.

4. **Open the Variables tab**  
   - In the **top tabs** for that service you should see: **Deployments**, **Settings**, **Variables**, **Metrics**, etc.  
   - Click **Variables**.  
   - If you don’t see "Variables", try **Settings** and look for a section like **Environment** or **Variables**.

5. **Add variables**  
   - Click **"+ New Variable"** (or **"Add Variable"** / **"RAW Editor"**).  
   - If there is a **RAW Editor**, you can paste all 6 at once (one per line, `NAME=value`).  
   - Otherwise add each variable one by one: **Variable name** = left side, **Value** = right side.

6. **Redeploy**  
   After saving, trigger a new deploy (e.g. **Deployments** → **Redeploy**, or push a small commit so Railway redeploys).

---

## Values from your old code (main_old)

These were the **defaults** in the old backend. Use them so the refactored app can start on Railway. **Change the secrets (passwords, JWT) in production** after it’s working.

| Variable | Value to set in Railway |
|----------|-------------------------|
| `MONGODB_URL` | `mongodb+srv://gym_admin:8qxXOYKp1El0bw0B@clustergymadmin.zkcgd9b.mongodb.net/?appName=Clustergymadmin` |
| `DATABASE_NAME` | `gym_db` |
| `SUPER_ADMIN_LOGIN_ID` | `admin@gymsaas.com` |
| `SUPER_ADMIN_PASSWORD` | `Admin@Gym123` |
| `JWT_SECRET` | `gym-saas-jwt-secret-change-in-production` |
| `ALLOWED_ORIGINS` | `*` |

**Copy-paste for RAW Editor** (if Railway has it):

```
MONGODB_URL=mongodb+srv://gym_admin:8qxXOYKp1El0bw0B@clustergymadmin.zkcgd9b.mongodb.net/?appName=Clustergymadmin
DATABASE_NAME=gym_db
SUPER_ADMIN_LOGIN_ID=admin@gymsaas.com
SUPER_ADMIN_PASSWORD=Admin@Gym123
JWT_SECRET=gym-saas-jwt-secret-change-in-production
ALLOWED_ORIGINS=*
```

**Note:** The old backend used `allow_origins=["*"]`, so `ALLOWED_ORIGINS=*` keeps the same behavior. If you later want to restrict origins, set a comma-separated list, e.g.  
`ALLOWED_ORIGINS=https://your-frontend.vercel.app,https://gymsaas-production-87a0.up.railway.app`

---

## If you still don’t see "Variables"

- Try **Service** → **Settings** → scroll for **Environment** or **Variables**.  
- Or click the **three dots (⋮)** or **gear** on the service card and look for **Variables** or **Environment**.  
- Railway’s docs: [Using Variables](https://docs.railway.app/guides/variables) (they say: service → **Variables** tab → New Variable or RAW Editor).

After these 6 are set and you redeploy, the server should start and the Railway URL should respond.
