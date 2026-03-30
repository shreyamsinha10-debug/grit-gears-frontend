"""
Messages router: create, list, inbox, PATCH, DELETE.
"""

from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import get_gym_admin, get_gym_id_and_member_for_messages
from app.db.database import messages_collection
from app.models.schemas import MessageCreate, MessageResponse, MessageUpdate
from app.utils.helpers import gym_filter

router = APIRouter()


@router.post("/messages", response_model=MessageResponse)
async def create_message(body: MessageCreate, gym_id: str = Depends(get_gym_admin)):
    if body.recipient_type == "members" and (not body.recipient_member_ids or len(body.recipient_member_ids) == 0):
        raise HTTPException(status_code=400, detail="recipient_member_ids required when recipient_type is 'members'")
    now = datetime.now(timezone.utc)
    doc = {
        "gym_id": gym_id,
        "recipient_type": body.recipient_type,
        "recipient_member_ids": body.recipient_member_ids or [],
        "title": body.title.strip(),
        "body": body.body.strip(),
        "created_at": now,
        "updated_at": now,
        "deleted_at": None,
    }
    result = await messages_collection.insert_one(doc)
    doc["_id"] = result.inserted_id
    return MessageResponse(
        id=str(doc["_id"]),
        gym_id=doc["gym_id"],
        recipient_type=doc["recipient_type"],
        recipient_member_ids=doc["recipient_member_ids"],
        title=doc["title"],
        body=doc["body"],
        created_at=doc["created_at"],
        updated_at=doc["updated_at"],
        deleted_at=doc["deleted_at"],
    )


@router.get("/messages", response_model=list[MessageResponse])
async def list_messages(
    include_deleted: bool = False,
    skip: int = 0,
    limit: int = 100,
    gym_id: str = Depends(get_gym_admin),
):
    q = gym_filter(gym_id)
    if not include_deleted:
        q["deleted_at"] = None
    skip = max(0, skip)
    limit = min(max(1, limit), 500)
    cursor = messages_collection.find(q).sort("created_at", -1).skip(skip).limit(limit)
    out = []
    async for doc in cursor:
        out.append(MessageResponse(
            id=str(doc["_id"]),
            gym_id=doc["gym_id"],
            recipient_type=doc.get("recipient_type", "all_active"),
            recipient_member_ids=doc.get("recipient_member_ids") or [],
            title=doc.get("title", ""),
            body=doc.get("body", ""),
            created_at=doc["created_at"],
            updated_at=doc.get("updated_at"),
            deleted_at=doc.get("deleted_at"),
        ))
    return out


@router.get("/messages/inbox", response_model=list[MessageResponse])
async def list_inbox(auth: tuple[str, str | None] = Depends(get_gym_id_and_member_for_messages)):
    gym_id, member_id = auth
    if not member_id:
        raise HTTPException(status_code=403, detail="Inbox is for members only")
    q = gym_filter(gym_id)
    q["deleted_at"] = None
    q["$or"] = [
        {"recipient_type": "all_active"},
        {"recipient_type": "members", "recipient_member_ids": member_id},
    ]
    cursor = messages_collection.find(q).sort("created_at", -1).limit(100)
    out = []
    async for doc in cursor:
        out.append(MessageResponse(
            id=str(doc["_id"]),
            gym_id=doc["gym_id"],
            recipient_type=doc.get("recipient_type", "all_active"),
            recipient_member_ids=doc.get("recipient_member_ids") or [],
            title=doc.get("title", ""),
            body=doc.get("body", ""),
            created_at=doc["created_at"],
            updated_at=doc.get("updated_at"),
            deleted_at=doc.get("deleted_at"),
        ))
    return out


@router.patch("/messages/{message_id}", response_model=MessageResponse)
async def update_message(message_id: str, body: MessageUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(message_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid message ID")
    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    doc = await messages_collection.find_one(q)
    if not doc:
        raise HTTPException(status_code=404, detail="Message not found")
    if doc.get("deleted_at"):
        raise HTTPException(status_code=400, detail="Cannot edit deleted message")
    update = {"updated_at": datetime.now(timezone.utc)}
    if body.title is not None:
        update["title"] = body.title.strip()
    if body.body is not None:
        update["body"] = body.body.strip()
    if len(update) <= 1:
        return MessageResponse(
            id=str(doc["_id"]),
            gym_id=doc["gym_id"],
            recipient_type=doc.get("recipient_type", "all_active"),
            recipient_member_ids=doc.get("recipient_member_ids") or [],
            title=doc.get("title", ""),
            body=doc.get("body", ""),
            created_at=doc["created_at"],
            updated_at=doc.get("updated_at"),
            deleted_at=doc.get("deleted_at"),
        )
    await messages_collection.update_one(q, {"$set": update})
    updated = await messages_collection.find_one(q)
    return MessageResponse(
        id=str(updated["_id"]),
        gym_id=updated["gym_id"],
        recipient_type=updated.get("recipient_type", "all_active"),
        recipient_member_ids=updated.get("recipient_member_ids") or [],
        title=updated.get("title", ""),
        body=updated.get("body", ""),
        created_at=updated["created_at"],
        updated_at=updated.get("updated_at"),
        deleted_at=updated.get("deleted_at"),
    )


@router.delete("/messages/{message_id}")
async def delete_message(message_id: str, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(message_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid message ID")
    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    result = await messages_collection.update_one(q, {"$set": {"deleted_at": datetime.now(timezone.utc)}})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Message not found")
    return {"message": "Deleted"}


__all__ = ["router"]
