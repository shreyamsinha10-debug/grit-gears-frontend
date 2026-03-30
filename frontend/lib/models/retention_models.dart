// ---------------------------------------------------------------------------
// Retention Alerts – at-risk members (declining attendance).
// ---------------------------------------------------------------------------

/// Single retention alert from GET /analytics/retention-alerts.
class RetentionAlert {
  final String memberId;
  final String name;
  final String phone;
  final String? lastAttendanceDate; // YYYY-MM-DD or null
  final int daysSinceLastVisit;
  final String riskLevel; // Slipping | High Risk | Critical

  const RetentionAlert({
    required this.memberId,
    required this.name,
    required this.phone,
    this.lastAttendanceDate,
    required this.daysSinceLastVisit,
    required this.riskLevel,
  });

  factory RetentionAlert.fromJson(Map<String, dynamic> json) {
    return RetentionAlert(
      memberId: json['member_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      lastAttendanceDate: json['last_attendance_date'] as String?,
      daysSinceLastVisit: (json['days_since_last_visit'] as int?) ?? 0,
      riskLevel: json['risk_level'] as String? ?? 'Slipping',
    );
  }

  Map<String, dynamic> toJson() => {
        'member_id': memberId,
        'name': name,
        'phone': phone,
        'last_attendance_date': lastAttendanceDate,
        'days_since_last_visit': daysSinceLastVisit,
        'risk_level': riskLevel,
      };

  static List<RetentionAlert> fromJsonList(dynamic list) {
    if (list is! List) return [];
    return list
        .map((e) => RetentionAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
