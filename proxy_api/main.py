from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field
import httpx


TARGET_URL = "https://www.dertzinfotech.com/api/contact-user"

app = FastAPI(title="Signup Proxy API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class SignUpPayload(BaseModel):
    name: str = Field(min_length=2)
    email: EmailStr
    contact: str = Field(min_length=6, max_length=20)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/api/contact-user-proxy")
async def contact_user_proxy(payload: SignUpPayload) -> dict:
    proxy_payload = {
        "name": payload.name.strip(),
        "email": payload.email,
        "contact": payload.contact.strip(),
        "company": "NA",
        "message": "GymOpsHQ",
    }
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(TARGET_URL, json=proxy_payload)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Proxy request failed: {exc}") from exc

    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    try:
        return response.json()
    except ValueError:
        return {"status": 1, "message": "Forwarded", "raw_response": response.text}
