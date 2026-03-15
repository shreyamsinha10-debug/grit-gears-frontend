from typing import Iterable, Sequence
import asyncio
import json
import logging
import smtplib
import time
from pathlib import Path
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger(__name__)

# #region agent log
def _debug_log(location: str, message: str, data: dict, hypothesis_id: str):
    payload = json.dumps({"sessionId": "1cf765", "location": location, "message": message, "data": data, "timestamp": int(time.time() * 1000), "hypothesisId": hypothesis_id}) + "\n"
    for log_path in [
        Path("/home/animesh/Documents/GymSaaS/.cursor/debug-1cf765.log"),
        Path(__file__).resolve().parent.parent.parent / "debug-1cf765.log",
    ]:
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with open(log_path, "a") as f:
                f.write(payload)
            break
        except Exception:
            continue
# #endregion


async def send_email_async(to_addresses: Iterable[str], subject: str, body: str) -> None:
    """
    Send an email asynchronously using standard SMTP.

    When SMTP settings are not configured, this function is a no-op so that
    application behaviour remains stable in environments without email.
    """
    recipients: Sequence[str] = [addr for addr in to_addresses if addr]
    # #region agent log
    _debug_log("email.py:send_email_async:entry", "send_email_async called", {"recipients_count": len(recipients), "recipients": list(recipients)[:3], "subject": subject}, "D")
    # #endregion
    if not recipients:
        logger.warning("Email skipped: no recipients")
        return
    if not settings.smtp_server or not settings.smtp_port or not settings.from_email:
        # #region agent log
        _debug_log("email.py:send_email_async:skip", "SMTP not configured", {"smtp_server": bool(settings.smtp_server), "smtp_port": bool(settings.smtp_port), "from_email": bool(settings.from_email)}, "D")
        # #endregion
        logger.warning(
            "Email skipped: SMTP not configured. Forgot-password and other emails will not be sent. "
            "Set SMTP_SERVER, SMTP_PORT, and FROM_EMAIL in backend/.env (see .env.example)."
        )
        return

    # #region agent log
    _debug_log("email.py:send_email_async:attempt", "attempting SMTP send", {"to": list(recipients)}, "D")
    # #endregion
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = settings.from_email
    msg["To"] = ", ".join(recipients)
    msg.set_content(body)

    def _send():
        if int(settings.smtp_port) == 465:
            server_cls = smtplib.SMTP_SSL
        else:
            server_cls = smtplib.SMTP
        with server_cls(settings.smtp_server, int(settings.smtp_port)) as server:
            server.ehlo()
            if settings.smtp_username and settings.smtp_password:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(msg)

    try:
        await asyncio.to_thread(_send)
        logger.info("Email sent to %s (subject: %s)", ", ".join(recipients), subject)
    except Exception as e:
        logger.exception("Email failed to %s: %s", ", ".join(recipients), e)
        # Swallow so API still returns success (don't reveal to client whether email exists)


__all__ = ["send_email_async"]

