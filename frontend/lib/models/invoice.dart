// ---------------------------------------------------------------------------
// Invoice & InvoiceItem – strongly-typed models for /billing API.
// ---------------------------------------------------------------------------

import '../core/date_utils.dart';

/// Single line item on an invoice.
class InvoiceItem {
  final String description;
  final int amount;

  const InvoiceItem({required this.description, required this.amount});

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      description: json['description'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'description': description, 'amount': amount};

  static List<InvoiceItem> fromJsonList(dynamic list) {
    if (list == null) return [];
    final lst = list is List<dynamic> ? list : [];
    return lst.map((e) => InvoiceItem.fromJson((e as Map<String, dynamic>))).toList();
  }
}

/// Invoice from GET /billing/invoices or GET /billing/history.
class Invoice {
  final String id;
  final String memberId;
  final String memberName;
  final List<InvoiceItem> items;
  final int total;
  final String status;
  final DateTime? issuedAt;
  final DateTime? paidAt;
  final String? billNumber;
  final String? paymentMethod;
  final String? notes;
  final DateTime? endDate;
  final String? memberPhone;
  final String? memberEmail;
  final String? batch;

  const Invoice({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.items,
    required this.total,
    required this.status,
    this.issuedAt,
    this.paidAt,
    this.billNumber,
    this.paymentMethod,
    this.notes,
    this.endDate,
    this.memberPhone,
    this.memberEmail,
    this.batch,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] as String? ?? '',
      memberId: json['member_id'] as String? ?? '',
      memberName: json['member_name'] as String? ?? '',
      items: InvoiceItem.fromJsonList(json['items']),
      total: (json['total'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'Due',
      issuedAt: parseApiDateTime(json['issued_at']?.toString()),
      paidAt: parseApiDateTime(json['paid_at']?.toString()),
      billNumber: json['bill_number'] as String?,
      paymentMethod: json['payment_method'] as String?,
      notes: json['notes'] as String?,
      endDate: parseApiDateTime(json['end_date']?.toString()),
      memberPhone: json['member_phone'] as String?,
      memberEmail: json['member_email'] as String?,
      batch: json['batch'] as String?,
    );
  }

  static List<Invoice> fromJsonList(dynamic list) {
    if (list == null) return [];
    final lst = list is List<dynamic> ? list : [];
    return lst.map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'member_name': memberName,
      'items': items.map((e) => e.toJson()).toList(),
      'total': total,
      'status': status,
      'issued_at': issuedAt?.toIso8601String(),
      'paid_at': paidAt?.toIso8601String(),
      'bill_number': billNumber,
      'payment_method': paymentMethod,
      'notes': notes,
      'end_date': endDate?.toIso8601String(),
      'member_phone': memberPhone,
      'member_email': memberEmail,
      'batch': batch,
    };
  }
}
