"""
Notification helpers.

- Keep simulated WhatsApp/email print messages for local/dev visibility.
- Optionally send real mobile push notifications through Firebase Cloud Messaging
  when FCM_SERVER_KEY and member push tokens are available.
"""

import asyncio
from typing import Any, Mapping

import httpx

from app.core.config import settings


def send_notification(notification_type: str, user: dict, extra: dict | None = None) -> None:
    """
    Simulated WhatsApp/Email: prints to console.
    user: dict with at least 'phone', 'name'; optionally 'email'.
    notification_type: 'registration' | 'payment_received' | 'fees_due' | 'status_change'
    extra: e.g. {'amount': 500} for payment, {'new_status': 'Inactive'} for status.
    """
    phone = user.get("phone", "")
    name = user.get("name", "")
    extra = extra or {}
    if notification_type == "registration":
        message = f"Welcome to Jupiter Arena, {name}! Your registration is complete."
    elif notification_type == "payment_received":
        amount = extra.get("amount", 0)
        message = f"Hi {name}, we received your payment of ₹{amount}. Thank you!"
    elif notification_type == "fees_due":
        amount = extra.get("pending_amount", 0)
        message = f"Hi {name}, your pending fee of ₹{amount} is due. Please pay at the gym."
    elif notification_type == "status_change":
        new_status = extra.get("new_status", "")
        message = f"Hi {name}, your membership status is now: {new_status}."
    else:
        message = f"Hi {name}, you have a notification from Jupiter Arena."
    print(f"[WHATSAPP SENT to {phone}]: {message}")
    # Fire-and-forget push when we are inside an async request context and
    # the caller supplied member device tokens.
    device_tokens = user.get("device_tokens") or []
    if isinstance(device_tokens, list) and device_tokens:
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(
                send_push_notification(
                    tokens=[str(t) for t in device_tokens if str(t).strip()],
                    title="Jupiter Arena",
                    body=message,
                    data={"type": notification_type},
                )
            )
        except RuntimeError:
            # No running event loop (e.g., sync script): skip async push.
            pass


async def send_push_notification(
    *,
    tokens: list[str],
    title: str,
    body: str,
    data: Mapping[str, Any] | None = None,
) -> int:
    """
    Send push notifications via FCM legacy HTTP API.
    Returns number of successful deliveries.
    """
    server_key = (settings.fcm_server_key or "").strip()
    if not server_key:
        return 0
    cleaned_tokens = [t.strip() for t in tokens if isinstance(t, str) and t.strip()]
    if not cleaned_tokens:
        return 0

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"key={server_key}",
    }
    success = 0
    async with httpx.AsyncClient(timeout=10.0) as client:
        for token in cleaned_tokens:
            payload: dict[str, Any] = {
                "to": token,
                "notification": {"title": title, "body": body},
                "data": dict(data or {}),
                "priority": "high",
            }
            try:
                r = await client.post("https://fcm.googleapis.com/fcm/send", headers=headers, json=payload)
                if 200 <= r.status_code < 300:
                    body_json = r.json() if r.content else {}
                    if body_json.get("success", 0) == 1:
                        success += 1
            except Exception:
                continue
    return success


async def send_gym_notification(target: str, payload: Mapping[str, Any]) -> None:
    """
    Optional async hook used by routers for custom push dispatch.
    payload keys:
    - tokens: list[str]
    - title: str
    - body: str
    - data: dict (optional)
    """
    tokens = payload.get("tokens") if isinstance(payload, Mapping) else None
    if not isinstance(tokens, list) or not tokens:
        return None
    title = str(payload.get("title") or "Jupiter Arena")
    body = str(payload.get("body") or "")
    data = payload.get("data") if isinstance(payload.get("data"), Mapping) else None
    await send_push_notification(tokens=[str(t) for t in tokens], title=title, body=body, data=data)
    return None


__all__ = ["send_notification", "send_gym_notification", "send_push_notification"]

