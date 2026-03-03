from typing import Iterable, Sequence
import asyncio
import smtplib
from email.message import EmailMessage

from app.core.config import settings


async def send_email_async(to_addresses: Iterable[str], subject: str, body: str) -> None:
    """
    Send an email asynchronously using standard SMTP.

    When SMTP settings are not configured, this function is a no-op so that
    application behaviour remains stable in environments without email.
    """
    recipients: Sequence[str] = [addr for addr in to_addresses if addr]
    if not recipients:
        return
    if not settings.smtp_server or not settings.smtp_port or not settings.from_email:
        return

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
    except Exception:
        # Swallow email errors to avoid impacting API responses.
        return


__all__ = ["send_email_async"]

