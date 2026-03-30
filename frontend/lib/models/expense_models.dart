// ---------------------------------------------------------------------------
// Expense & BalanceSheetSummary – models for /expenses API.
// ---------------------------------------------------------------------------

import '../core/date_utils.dart';

/// Single expense from GET /expenses or POST /expenses.
class Expense {
  final String id;
  final String gymId;
  final int amount;
  final String category;
  final String? description;
  final String expenseDate;
  final String? receiptRef;
  final DateTime? createdAt;

  const Expense({
    required this.id,
    required this.gymId,
    required this.amount,
    required this.category,
    this.description,
    required this.expenseDate,
    this.receiptRef,
    this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as String? ?? '',
      gymId: json['gym_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'Other',
      description: json['description'] as String?,
      expenseDate: json['expense_date'] as String? ?? '',
      receiptRef: json['receipt_ref'] as String?,
      createdAt: parseApiDateTime(json['created_at']?.toString()),
    );
  }

  static List<Expense> fromJsonList(dynamic list) {
    if (list == null) return [];
    final lst = list is List<dynamic> ? list : [];
    return lst.map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'category': category,
      'description': description,
      'expense_date': expenseDate,
      'receipt_ref': receiptRef,
    };
  }
}

/// Balance sheet summary from GET /expenses/balance-sheet.
class BalanceSheetSummary {
  final String month;
  final int totalCollections;
  final int totalExpenses;
  final int netBalance;
  final Map<String, int> categoryBreakdown;

  const BalanceSheetSummary({
    required this.month,
    required this.totalCollections,
    required this.totalExpenses,
    required this.netBalance,
    required this.categoryBreakdown,
  });

  factory BalanceSheetSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['category_breakdown'];
    final Map<String, int> breakdown = {};
    if (raw is Map) {
      for (final e in raw.entries) {
        final k = e.key?.toString() ?? 'Other';
        final v = (e.value as num?)?.toInt() ?? 0;
        breakdown[k] = v;
      }
    }
    return BalanceSheetSummary(
      month: json['month'] as String? ?? '',
      totalCollections: (json['total_collections'] as num?)?.toInt() ?? 0,
      totalExpenses: (json['total_expenses'] as num?)?.toInt() ?? 0,
      netBalance: (json['net_balance'] as num?)?.toInt() ?? 0,
      categoryBreakdown: breakdown,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'month': month,
      'total_collections': totalCollections,
      'total_expenses': totalExpenses,
      'net_balance': netBalance,
      'category_breakdown': categoryBreakdown,
    };
  }
}
