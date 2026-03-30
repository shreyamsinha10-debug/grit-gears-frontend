"""
Simulated notifications (registration, payment received, status change, fees due).

In production replace with real WhatsApp/email/SMS. For now prints to console.
"""

from typing import Any, Mapping


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


async def send_gym_notification(target: str, payload: Mapping[str, Any]) -> None:
    """Optional async hook; no-op by default."""
    return None


__all__ = ["send_notification", "send_gym_notification"]

