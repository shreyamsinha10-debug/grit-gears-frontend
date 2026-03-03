"""
Documents router: member photo (get, patch), id-document (patch).
"""

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import get_gym_admin
from app.db.database import attendance_collection, member_documents_collection, members_collection
from app.models.schemas import IdDocumentUpdate, MemberResponse, PhotoUpdate
from app.utils.helpers import doc_to_member_response, gym_filter
from app.utils.time_utils import today_ist

router = APIRouter()


@router.get("/members/{member_id}/photo")
async def get_member_photo(member_id: str, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_doc = await members_collection.find_one({"_id": oid, **gym_filter(gym_id)}, {"_id": 1})
    if not member_doc:
        raise HTTPException(status_code=404, detail="Member not found")

    media_doc = await member_documents_collection.find_one({"member_id": member_id, "gym_id": gym_id})
    if media_doc is not None and "photo_base64" in media_doc:
        return {"photo_base64": media_doc.get("photo_base64")}

    doc = await members_collection.find_one({"_id": oid, **gym_filter(gym_id)}, {"photo_base64": 1})
    return {"photo_base64": doc.get("photo_base64") if doc else None}


@router.patch("/members/{member_id}/photo", response_model=MemberResponse)
async def update_member_photo(member_id: str, body: PhotoUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    doc = await members_collection.find_one(member_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")

    if body.photo_base64 is None:
        await member_documents_collection.update_one(
            {"member_id": member_id, "gym_id": gym_id},
            {"$unset": {"photo_base64": ""}},
        )
        await members_collection.update_one(member_q, {"$unset": {"photo_base64": ""}})
    else:
        await member_documents_collection.update_one(
            {"member_id": member_id, "gym_id": gym_id},
            {
                "$set": {
                    "member_id": member_id,
                    "gym_id": gym_id,
                    "photo_base64": body.photo_base64,
                }
            },
            upsert=True,
        )
        await members_collection.update_one(member_q, {"$unset": {"photo_base64": ""}})

    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None

    return await doc_to_member_response(doc, attendance_map=attendance_map)


@router.patch("/members/{member_id}/id-document", response_model=MemberResponse)
async def update_member_id_document(member_id: str, body: IdDocumentUpdate, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    doc = await members_collection.find_one(member_q)
    if not doc:
        raise HTTPException(status_code=404, detail="Member not found")

    if body.id_document_base64 is None:
        await member_documents_collection.update_one(
            {"member_id": member_id, "gym_id": gym_id},
            {"$unset": {"id_document_base64": "", "id_document_type": ""}},
        )
        await members_collection.update_one(member_q, {"$unset": {"id_document_base64": "", "id_document_type": ""}})
    else:
        update = {"id_document_base64": body.id_document_base64}
        if body.id_document_type is not None:
            update["id_document_type"] = body.id_document_type
        await member_documents_collection.update_one(
            {"member_id": member_id, "gym_id": gym_id},
            {
                "$set": {
                    "member_id": member_id,
                    "gym_id": gym_id,
                    **update,
                    "id_document_type": body.id_document_type if body.id_document_type is not None else doc.get("id_document_type"),
                }
            },
            upsert=True,
        )
        await members_collection.update_one(member_q, {"$unset": {"id_document_base64": ""}})

    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_doc = await attendance_collection.find_one({"member_id": member_id, "date_ist": date_ist_str})
    attendance_map = {member_id: att_doc} if att_doc else None

    return await doc_to_member_response(doc, attendance_map=attendance_map)


__all__ = ["router"]
