"""
Attendance router: check-in/check-out, summary, today, by-date, by-date-range, heatmap, delete.
"""

from collections import defaultdict
from datetime import datetime, timedelta, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.auth import get_gym_admin, get_gym_id_for_attendance_or_member_get
from app.db.database import attendance_collection, members_collection
from app.models.schemas import AttendanceRecord
from app.utils.helpers import gym_filter
from app.utils.time_utils import IST, batch_from_ist, now_ist, today_ist

router = APIRouter()

BATCH_CAPACITY = None  # or {"Morning": 30, "Evening": 30, "Ladies": 20}


async def _attendance_docs_to_records(cursor) -> list:
    out = []
    async for doc in cursor:
        check_in_at_ist = None
        if doc.get("check_in_at_ist"):
            try:
                check_in_at_ist = datetime.fromisoformat(doc["check_in_at_ist"])
            except ValueError:
                pass
        if not check_in_at_ist:
            check_in_at_ist = doc["check_in_at_utc"]
            if hasattr(check_in_at_ist, "tzinfo") and check_in_at_ist.tzinfo is None:
                check_in_at_ist = check_in_at_ist.replace(tzinfo=timezone.utc).astimezone(IST)
            elif hasattr(check_in_at_ist, "astimezone"):
                check_in_at_ist = check_in_at_ist.astimezone(IST)

        check_out_at = None
        if doc.get("check_out_at_ist"):
            try:
                check_out_at = datetime.fromisoformat(doc["check_out_at_ist"])
            except ValueError:
                pass
        if not check_out_at and doc.get("check_out_at_utc"):
            check_out_at = doc["check_out_at_utc"]
            if hasattr(check_out_at, "tzinfo") and check_out_at.tzinfo is None:
                check_out_at = check_out_at.replace(tzinfo=timezone.utc).astimezone(IST)
            elif hasattr(check_out_at, "astimezone"):
                check_out_at = check_out_at.astimezone(IST)

        out.append(
            AttendanceRecord(
                id=str(doc["_id"]),
                member_id=doc["member_id"],
                member_name=doc.get("member_name", ""),
                member_phone=doc.get("member_phone"),
                check_in_at=check_in_at_ist,
                date_ist=doc["date_ist"],
                batch=doc["batch"],
                check_out_at=check_out_at,
            )
        )
    return out


async def _async_iter(items):
    for x in items:
        yield x


async def attendance_by_date(date_ist_str: str, gym_id: str) -> list:
    q = {"date_ist": date_ist_str}
    q.update(gym_filter(gym_id))
    cursor = attendance_collection.find(q).sort([("batch", 1), ("check_in_at_utc", 1)])
    return await _attendance_docs_to_records(cursor)


@router.post("/attendance/check-in/{member_id}", response_model=AttendanceRecord)
async def check_in(member_id: str, gym_id: str = Depends(get_gym_id_for_attendance_or_member_get)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")

    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")

    if (member.get("status") or "Active") != "Active":
        raise HTTPException(status_code=403, detail="Portal access is blocked. Your membership is not active.")

    now = now_ist()
    date_ist_str = now.strftime("%Y-%m-%d")
    batch_time_slot = batch_from_ist(now)
    member_batch = (member.get("batch") or "").strip() or batch_time_slot

    already_today = await attendance_collection.find_one(
        {"member_id": member_id, "date_ist": date_ist_str, **gym_filter(gym_id)},
    )
    if already_today:
        raise HTTPException(
            status_code=400,
            detail="Already checked in today. One check-in per day allowed.",
        )

    if BATCH_CAPACITY and batch_time_slot in BATCH_CAPACITY:
        cap = BATCH_CAPACITY[batch_time_slot]
        batch_q = {"date_ist": date_ist_str, "batch_time_slot": batch_time_slot}
        batch_q.update(gym_filter(gym_id))
        count_today_batch = await attendance_collection.count_documents(batch_q)
        if count_today_batch >= cap:
            raise HTTPException(
                status_code=400,
                detail=f"Batch full. {batch_time_slot} batch has reached capacity ({cap}). Try another batch.",
            )

    check_in_at_utc = now.astimezone(timezone.utc)
    doc = {
        "member_id": member_id,
        "gym_id": gym_id,
        "check_in_at_utc": check_in_at_utc,
        "check_in_at_ist": now.isoformat(),
        "date_ist": date_ist_str,
        "batch": member_batch,
        "batch_time_slot": batch_time_slot,
        "member_name": member.get("name", ""),
        "member_phone": member.get("phone"),
    }
    result = await attendance_collection.insert_one(doc)
    today_date = now.date()
    last_attendance_dt = datetime(today_date.year, today_date.month, today_date.day, tzinfo=timezone.utc)
    await members_collection.update_one(
        member_q,
        {"$set": {"last_attendance_date": last_attendance_dt}},
    )

    return AttendanceRecord(
        id=str(result.inserted_id),
        member_id=member_id,
        member_name=doc["member_name"],
        member_phone=doc.get("member_phone"),
        check_in_at=now,
        date_ist=date_ist_str,
        batch=member_batch,
        check_out_at=None,
    )


@router.post("/attendance/check-out/{member_id}", response_model=AttendanceRecord)
async def check_out(member_id: str, gym_id: str = Depends(get_gym_id_for_attendance_or_member_get)):
    try:
        oid = ObjectId(member_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid member ID")
    member_q = {"_id": oid}
    member_q.update(gym_filter(gym_id))
    member = await members_collection.find_one(member_q)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")

    if (member.get("status") or "Active") != "Active":
        raise HTTPException(status_code=403, detail="Portal access is blocked. Your membership is not active.")

    date_ist_str = today_ist().strftime("%Y-%m-%d")
    att_q = {"member_id": member_id, "date_ist": date_ist_str}
    att_q.update(gym_filter(gym_id))
    doc = await attendance_collection.find_one(att_q)
    if not doc:
        raise HTTPException(status_code=400, detail="No check-in found for today. Check in first.")
    if doc.get("check_out_at_ist"):
        raise HTTPException(status_code=400, detail="Already checked out today.")
    now = now_ist()
    check_out_utc = now.astimezone(timezone.utc)
    await attendance_collection.update_one(
        {"_id": doc["_id"]},
        {"$set": {"check_out_at_ist": now.isoformat(), "check_out_at_utc": check_out_utc}},
    )
    updated = await attendance_collection.find_one({"_id": doc["_id"]})
    records = await _attendance_docs_to_records(_async_iter([updated]))
    return records[0]


@router.get("/attendance/summary")
async def attendance_summary(gym_id: str = Depends(get_gym_admin)):
    q = gym_filter(gym_id)
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    today_count = await attendance_collection.count_documents({**q, "date_ist": date_ist_str})
    today_check_outs = await attendance_collection.count_documents({
        **q,
        "date_ist": date_ist_str,
        "check_out_at_ist": {"$exists": True, "$ne": None, "$ne": ""},
    })
    currently_in = today_count - today_check_outs
    week_start = (today_ist() - timedelta(days=6)).strftime("%Y-%m-%d")
    this_week = await attendance_collection.count_documents({
        **q,
        "date_ist": {"$gte": week_start, "$lte": date_ist_str},
    })
    average_daily = round(this_week / 7.0, 1) if this_week else 0
    return {
        "today_check_ins": today_count,
        "currently_in_gym": currently_in,
        "this_week": this_week,
        "average_daily": average_daily,
    }


@router.get("/attendance/today", response_model=list[AttendanceRecord])
async def attendance_today(gym_id: str = Depends(get_gym_admin)):
    date_ist_str = today_ist().strftime("%Y-%m-%d")
    return await attendance_by_date(date_ist_str, gym_id)


@router.get("/attendance/by-date", response_model=list[AttendanceRecord])
async def attendance_by_date_endpoint(date: str, gym_id: str = Depends(get_gym_admin)):
    if len(date) != 10 or date[4] != "-" or date[7] != "-":
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")
    return await attendance_by_date(date, gym_id)


@router.get("/attendance/by-date-range", response_model=list[AttendanceRecord])
async def attendance_by_date_range(date_from: str, date_to: str, gym_id: str = Depends(get_gym_admin)):
    if len(date_from) != 10 or date_from[4] != "-" or date_from[7] != "-" or len(date_to) != 10 or date_to[4] != "-" or date_to[7] != "-":
        raise HTTPException(status_code=400, detail="date_from and date_to must be YYYY-MM-DD")
    if date_from > date_to:
        raise HTTPException(status_code=400, detail="date_from must be <= date_to")
    q = {"date_ist": {"$gte": date_from, "$lte": date_to}}
    q.update(gym_filter(gym_id))
    cursor = attendance_collection.find(q).sort([("date_ist", 1), ("batch", 1), ("check_in_at_utc", 1)])
    return await _attendance_docs_to_records(cursor)


@router.get("/attendance/heatmap")
async def attendance_heatmap(
    date_from: str | None = Query(None, description="Start date YYYY-MM-DD (default: 14 days ago)"),
    date_to: str | None = Query(None, description="End date YYYY-MM-DD (default: today)"),
    gym_id: str = Depends(get_gym_admin),
):
    today_str = today_ist().strftime("%Y-%m-%d")
    if date_from is None or date_to is None:
        start = today_ist() - timedelta(days=14)
        end = today_ist()
        date_from = start.strftime("%Y-%m-%d")
        date_to = end.strftime("%Y-%m-%d")
    else:
        if len(date_from) != 10 or date_from[4] != "-" or len(date_to) != 10 or date_to[4] != "-":
            raise HTTPException(status_code=400, detail="date_from and date_to must be YYYY-MM-DD")
        if date_from > date_to:
            raise HTTPException(status_code=400, detail="date_from must be <= date_to")

    q = {"date_ist": {"$gte": date_from, "$lte": date_to}}
    q.update(gym_filter(gym_id))
    cursor = attendance_collection.find(q)

    grid = defaultdict(int)
    durations_minutes = []

    async for doc in cursor:
        date_ist = doc.get("date_ist") or ""
        if not date_ist:
            continue
        try:
            ci_str = doc.get("check_in_at_ist")
            if not ci_str:
                continue
            if hasattr(ci_str, "isoformat"):
                check_in = ci_str.astimezone(IST) if getattr(ci_str, "tzinfo", None) else datetime.fromisoformat(str(ci_str).replace("Z", "+00:00")).astimezone(IST)
            else:
                s = str(ci_str).strip()
                if s and "+" not in s and "Z" not in s:
                    s = s + "+05:30"
                check_in = datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(IST)
        except Exception:
            continue
        co_str = doc.get("check_out_at_ist") or doc.get("check_out_at_utc")
        if co_str:
            try:
                if hasattr(co_str, "isoformat"):
                    check_out = co_str.astimezone(IST) if getattr(co_str, "tzinfo", None) else datetime.fromisoformat(str(co_str).replace("Z", "+00:00")).astimezone(IST)
                else:
                    s = str(co_str).strip()
                    if s and "+" not in s and "Z" not in s:
                        s = s + "+05:30"
                    check_out = datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(IST)
            except Exception:
                check_out = check_in.replace(hour=23, minute=59)
        else:
            check_out = check_in.replace(hour=23, minute=59)
        if check_out.date() != check_in.date():
            check_out = check_in.replace(hour=23, minute=59)
        h_start = check_in.hour
        h_end = check_out.hour
        for h in range(h_start, min(h_end + 1, 24)):
            grid[(date_ist, h)] += 1
        if co_str:
            durations_minutes.append((check_out - check_in).total_seconds() / 60)

    today_count = await attendance_collection.count_documents({**gym_filter(gym_id), "date_ist": today_str})
    today_check_outs = await attendance_collection.count_documents({
        **gym_filter(gym_id),
        "date_ist": today_str,
        "check_out_at_ist": {"$exists": True, "$ne": None, "$ne": ""},
    })
    currently_in_gym = today_count - today_check_outs

    heatmap_list = [{"date_ist": d, "hour": h, "count": c} for (d, h), c in sorted(grid.items())]
    avg_duration = round(sum(durations_minutes) / len(durations_minutes), 1) if durations_minutes else None

    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    dow_hour_agg = defaultdict(list)
    for (d, h), c in grid.items():
        try:
            dt = datetime.strptime(d, "%Y-%m-%d")
            dow = day_names[dt.weekday()]
            dow_hour_agg[(dow, h)].append(c)
        except Exception:
            pass
    quietest = []
    for (dow, h), counts in dow_hour_agg.items():
        avg = sum(counts) / len(counts) if counts else 0
        quietest.append({"day_of_week": dow, "hour": h, "avg_count": round(avg, 1), "sample_days": len(counts)})
    quietest.sort(key=lambda x: (x["avg_count"], -x["sample_days"]))
    quietest_slots = quietest[:15]
    quietest_keys = {(s["day_of_week"], s["hour"]) for s in quietest_slots}
    busiest = sorted(quietest, key=lambda x: (-x["avg_count"], -x["sample_days"]))
    busiest_slots = [s for s in busiest[:15] if (s["day_of_week"], s["hour"]) not in quietest_keys]

    return {
        "today_summary": {
            "check_ins": today_count,
            "currently_in_gym": currently_in_gym,
            "avg_duration_minutes": avg_duration,
        },
        "date_from": date_from,
        "date_to": date_to,
        "heatmap": heatmap_list,
        "avg_duration_minutes": avg_duration,
        "quietest_slots": quietest_slots,
        "busiest_slots": busiest_slots,
    }


@router.delete("/attendance/{attendance_id}")
async def delete_attendance(attendance_id: str, gym_id: str = Depends(get_gym_admin)):
    try:
        oid = ObjectId(attendance_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid attendance ID")
    q = {"_id": oid}
    q.update(gym_filter(gym_id))
    result = await attendance_collection.delete_one(q)
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Attendance record not found")
    return {"message": "Attendance record deleted"}


__all__ = ["router"]
