// ---------------------------------------------------------------------------
// Member – strongly-typed model for /members API.
// ---------------------------------------------------------------------------

import '../core/date_utils.dart';

/// Member entity from GET /members or GET /members/:id.
/// Use [fromJson] for API responses; [toJson] for PATCH body (partial).
class Member {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String membershipType;
  final String batch;
  final String status;
  final String? address;
  final String? dateOfBirth;
  final String? gender;
  final String? workoutSchedule;
  final String? dietChart;
  final String? photoBase64;
  final String? idDocumentBase64;
  final String? idDocumentType;
  final DateTime? createdAt;
  final DateTime? lastAttendanceDate;
  final bool? isCheckedInToday;
  final bool? isCheckedOutToday;

  const Member({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.membershipType,
    required this.batch,
    required this.status,
    this.address,
    this.dateOfBirth,
    this.gender,
    this.workoutSchedule,
    this.dietChart,
    this.photoBase64,
    this.idDocumentBase64,
    this.idDocumentType,
    this.createdAt,
    this.lastAttendanceDate,
    this.isCheckedInToday,
    this.isCheckedOutToday,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    final createdAt = parseApiDateTime(json['created_at']?.toString());
    final lastAttendanceDate = parseApiDate(json['last_attendance_date']?.toString());
    bool? isCheckedIn;
    bool? isCheckedOut;
    try {
      final todayStatus = json['today_status'] as Map<String, dynamic>?;
      if (todayStatus != null) {
        isCheckedIn = todayStatus['checked_in'] as bool?;
        isCheckedOut = todayStatus['checked_out'] as bool?;
      }
    } catch (_) {}
    return Member(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      membershipType: json['membership_type'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
      status: json['status'] as String? ?? 'Active',
      address: json['address'] as String?,
      dateOfBirth: json['date_of_birth']?.toString(),
      gender: json['gender'] as String?,
      workoutSchedule: json['workout_schedule'] as String?,
      dietChart: json['diet_chart'] as String?,
      photoBase64: json['photo_base64'] as String?,
      idDocumentBase64: json['id_document_base64'] as String?,
      idDocumentType: json['id_document_type'] as String?,
      createdAt: createdAt,
      lastAttendanceDate: lastAttendanceDate,
      isCheckedInToday: isCheckedIn,
      isCheckedOutToday: isCheckedOut,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'name': name,
      'phone': phone,
      'email': email,
      'membership_type': membershipType,
      'batch': batch,
      'status': status,
    };
    if (address != null) m['address'] = address;
    if (dateOfBirth != null) m['date_of_birth'] = dateOfBirth;
    if (gender != null) m['gender'] = gender;
    if (workoutSchedule != null) m['workout_schedule'] = workoutSchedule;
    if (dietChart != null) m['diet_chart'] = dietChart;
    return m;
  }

  /// For PATCH: only non-null fields (caller builds partial map as needed).
  Map<String, dynamic> toJsonPatch() => toJson();
}
