"""
Simulated notifications for Jupiter Arena (utils).

In production you would replace this with real WhatsApp Business API, email (SendGrid, etc.),
or SMS. For now, all notifications are printed to the backend console so you can verify
the flow when testing registration, payment received, fee reminders, or status change.

Usage: from utils import send_notification
  send_notification("registration", {"name": "John", "phone": "9876543210", "email": "j@x.com"})
  send_notification("payment_received", user, {"amount": 500})
"""


def send_notification(notification_type: str, user: dict, extra: dict | None = None):
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
