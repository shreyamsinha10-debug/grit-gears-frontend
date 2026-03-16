from typing import Iterable, Sequence
import asyncio
import json
import logging
import smtplib
import time
from pathlib import Path
from email.message import EmailMessage

import httpx
from app.core.config import settings

logger = logging.getLogger(__name__)

SENDGRID_API_URL = "https://api.sendgrid.com/v3/mail/send"

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
    logger.info("Sending email to %s (subject: %s)", ", ".join(recipients), subject)
    # #region agent log
    _debug_log("email.py:send_email_async:entry", "send_email_async called", {"recipients_count": len(recipients), "recipients": list(recipients)[:3], "subject": subject}, "D")
    # #endregion
    if not recipients:
        logger.warning("Email skipped: no recipients")
        return
    if not settings.from_email:
        logger.warning(
            "Email skipped: FROM_EMAIL not set. Set FROM_EMAIL and either SENDGRID_API_KEY or SMTP_* in backend/.env."
        )
        return

    # Prefer SendGrid HTTP API when API key is set (avoids SMTP port blocks in containers e.g. Railway).
    if settings.sendgrid_api_key:
        # #region agent log
        _debug_log("email.py:send_email_async:attempt", "attempting SendGrid API send", {"to": list(recipients)}, "D")
        # #endregion
        payload = {
            "personalizations": [{"to": [{"email": email} for email in recipients], "subject": subject}],
            "from": {"email": settings.from_email},
            "content": [{"type": "text/plain", "value": body}],
        }
        try:
            async with httpx.AsyncClient(timeout=25.0) as client:
                r = await client.post(
                    SENDGRID_API_URL,
                    headers={
                        "Authorization": f"Bearer {settings.sendgrid_api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
            if r.is_success:
                logger.info("Email sent to %s (subject: %s) via SendGrid API", ", ".join(recipients), subject)
            else:
                logger.error("SendGrid API failed to %s: %s %s", ", ".join(recipients), r.status_code, r.text)
        except Exception as e:
            logger.exception("Email failed to %s: %s", ", ".join(recipients), e)
        return
    if not settings.smtp_server or not settings.smtp_port:
        # #region agent log
        _debug_log("email.py:send_email_async:skip", "SMTP not configured", {"smtp_server": bool(settings.smtp_server), "smtp_port": bool(settings.smtp_port)}, "D")
        # #endregion
        logger.warning(
            "Email skipped: neither SENDGRID_API_KEY nor SMTP configured. Set SENDGRID_API_KEY or SMTP_SERVER/SMTP_PORT and FROM_EMAIL."
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

    timeout_sec = 25

    def _send():
        if int(settings.smtp_port) == 465:
            server_cls = smtplib.SMTP_SSL
        else:
            server_cls = smtplib.SMTP
        with server_cls(settings.smtp_server, int(settings.smtp_port), timeout=timeout_sec) as server:
            server.ehlo()
            if settings.smtp_username and settings.smtp_password:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(msg)

    try:
        await asyncio.to_thread(_send)
        logger.info("Email sent to %s (subject: %s)", ", ".join(recipients), subject)
    except Exception as e:
        logger.exception("Email failed to %s: %s", ", ".join(recipients), e)


__all__ = ["send_email_async"]

