## Signup Proxy API

This proxy avoids browser CORS issues by forwarding signup requests server-side.

### Run locally

```bash
cd proxy_api
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8010
```

### Endpoint

- `POST /api/contact-user-proxy`
- Input:
  - `name`
  - `email`
  - `contact`
- The proxy always forwards with:
  - `company: "NA"`
  - `message: "NA"`

### Flutter config

Build/run Flutter with:

```bash
flutter run -d chrome --dart-define=SIGNUP_PROXY_URL=http://127.0.0.1:8010/api/contact-user-proxy
```
