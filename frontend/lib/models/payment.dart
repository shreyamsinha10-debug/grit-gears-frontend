// ---------------------------------------------------------------------------
// Payment – strongly-typed model for /payments API.
// ---------------------------------------------------------------------------

import '../core/date_utils.dart';

/// Payment record from GET /payments or GET /billing/history.
class Payment {
  final String id;
  final String memberId;
  final String memberName;
  final int amount;
  final String feeType;
  final String? period;
  final String status;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final DateTime? createdAt;

  const Payment({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.feeType,
    this.period,
    required this.status,
    this.dueDate,
    this.paidAt,
    this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String? ?? '',
      memberId: json['member_id'] as String? ?? '',
      memberName: json['member_name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      feeType: json['fee_type'] as String? ?? '',
      period: json['period'] as String?,
      status: json['status'] as String? ?? 'Due',
      dueDate: parseApiDate(json['due_date']?.toString()),
      paidAt: parseApiDateTime(json['paid_at']?.toString()),
      createdAt: parseApiDateTime(json['created_at']?.toString()),
    );
  }

  static List<Payment> fromJsonList(dynamic list) {
    if (list == null) return [];
    final lst = list is List<dynamic> ? list : [];
    return lst.map((e) => Payment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'member_name': memberName,
      'amount': amount,
      'fee_type': feeType,
      'period': period,
      'status': status,
      'due_date': dueDate != null ? dueDate!.toIso8601String().substring(0, 10) : null,
      'paid_at': paidAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
