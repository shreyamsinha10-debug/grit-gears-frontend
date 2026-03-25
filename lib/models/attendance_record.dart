// ---------------------------------------------------------------------------
// AttendanceRecord – strongly-typed model for /attendance API.
// ---------------------------------------------------------------------------

import '../core/date_utils.dart';

/// Single attendance record from GET /attendance or member attendance list.
class AttendanceRecord {
  final String id;
  final String memberId;
  final String? memberName;
  final String? memberPhone;
  final DateTime? checkInAt;
  final String dateIst;
  final String batch;
  final DateTime? checkOutAt;

  const AttendanceRecord({
    required this.id,
    required this.memberId,
    this.memberName,
    this.memberPhone,
    this.checkInAt,
    required this.dateIst,
    required this.batch,
    this.checkOutAt,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as String? ?? '',
      memberId: json['member_id'] as String? ?? '',
      memberName: json['member_name'] as String?,
      memberPhone: json['member_phone'] as String?,
      checkInAt: parseApiDateTime(json['check_in_at']?.toString()),
      dateIst: json['date_ist'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
      checkOutAt: parseApiDateTime(json['check_out_at']?.toString()),
    );
  }

  static List<AttendanceRecord> fromJsonList(dynamic list) {
    if (list == null) return [];
    final lst = list is List<dynamic> ? list : [];
    return lst.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'member_name': memberName,
      'member_phone': memberPhone,
      'check_in_at': checkInAt?.toIso8601String(),
      'date_ist': dateIst,
      'batch': batch,
      'check_out_at': checkOutAt?.toIso8601String(),
    };
  }
}
