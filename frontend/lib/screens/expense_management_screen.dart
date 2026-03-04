// ---------------------------------------------------------------------------
// Expense Management – P&L / Expenses module (gym admin).
// ---------------------------------------------------------------------------
// Month selector, net balance card, add expense form, category breakdown,
// and recent expenses list. Responsive: mobile (<800) vs web/tablet (>=800).
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

const List<String> _expenseCategories = [
  'Electricity',
  'Water',
  'Housekeeping',
  'Maintenance',
  'Rent',
  'Salary',
  'Marketing',
  'Software',
  'Other',
];

String _currentMonthStr() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key});

  @override
  State<ExpenseManagementScreen> createState() => _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  late String _selectedMonth;
  List<Expense> _expenses = [];
  BalanceSheetSummary? _balanceSheet;
  bool _loading = false;
  bool _saving = false;

  // Add form
  String _formCategory = 'Other';
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _receiptRefController = TextEditingController();
  DateTime _formDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedMonth = _currentMonthStr();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _receiptRefController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final expenses = await ApiClient.instance.getExpenses(_selectedMonth);
      final sheet = await ApiClient.instance.getBalanceSheet(_selectedMonth);
      if (mounted) {
        setState(() {
          _expenses = expenses;
          _balanceSheet = sheet;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  void _changeMonth(int delta) {
    final parts = _selectedMonth.split('-');
    int y = int.parse(parts[0]);
    int m = int.parse(parts[1]);
    m += delta;
    if (m > 12) {
      m = 1;
      y++;
    } else if (m < 1) {
      m = 12;
      y--;
    }
    setState(() => _selectedMonth = '$y-${m.toString().padLeft(2, '0')}');
    _loadData();
  }

  Future<void> _submitExpense() async {
    final amountStr = _amountController.text.trim();
    final amount = int.tryParse(amountStr);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    final expenseDate = formatApiDate(_formDate);
    setState(() => _saving = true);
    try {
      final body = {
        'amount': amount,
        'category': _formCategory,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'expense_date': expenseDate,
        'receipt_ref': _receiptRefController.text.trim().isEmpty ? null : _receiptRefController.text.trim(),
      };
      final created = await ApiClient.instance.addExpense(body);
      if (mounted) {
        setState(() => _saving = false);
        if (created != null) {
          _amountController.clear();
          _descriptionController.clear();
          _receiptRefController.clear();
          _formDate = DateTime.now();
          _formCategory = 'Other';
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense saved')));
          _loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save expense')));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  void _showEditExpenseDialog(Expense e) {
    final amountController = TextEditingController(text: e.amount.toString());
    final descriptionController = TextEditingController(text: e.description ?? '');
    final receiptRefController = TextEditingController(text: e.receiptRef ?? '');
    String category = e.category;
    DateTime expenseDate = parseApiDate(e.expenseDate) ?? DateTime.now();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Expense'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: category,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: _expenseCategories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => category = v ?? 'Other'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Amount (₹)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(labelText: 'Description (optional)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: receiptRefController,
                        decoration: const InputDecoration(labelText: 'Receipt / Reference (optional)'),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Date'),
                        subtitle: Text(formatDisplayDate(expenseDate)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: expenseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setDialogState(() => expenseDate = picked);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = int.tryParse(amountController.text.trim());
                    if (amount == null || amount < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid amount')),
                      );
                      return;
                    }
                    final body = {
                      'amount': amount,
                      'category': category,
                      'description': descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      'expense_date': formatApiDate(expenseDate),
                      'receipt_ref': receiptRefController.text.trim().isEmpty
                          ? null
                          : receiptRefController.text.trim(),
                    };
                    final updated = await ApiClient.instance.updateExpense(e.id, body);
                    if (!context.mounted) return;
                    Navigator.of(ctx).pop();
                    if (updated != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Expense updated')),
                      );
                      _loadData();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to update expense')),
                      );
                    }
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      amountController.dispose();
      descriptionController.dispose();
      receiptRefController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;
        return Scaffold(
          appBar: AppBar(
            title: const Text('P&L / Expenses'),
            leading: Tooltip(
              message: 'Back to dashboard',
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              Tooltip(
                message: 'Logout',
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => LoginScreen.logout(context),
                ),
              ),
            ],
          ),
          body: _loading && _expenses.isEmpty && _balanceSheet == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: isWide ? _buildWideLayout(constraints) : _buildNarrowLayout(constraints),
                ),
        );
      },
    );
  }

  Widget _buildNarrowLayout(BoxConstraints constraints) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMonthSelector(),
          const SizedBox(height: 12),
          _buildNetBalanceCard(),
          const SizedBox(height: 16),
          _buildAddExpenseCard(),
          const SizedBox(height: 16),
          _buildCategoryBreakdownCard(),
          const SizedBox(height: 16),
          _buildRecentExpensesCard(),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BoxConstraints constraints) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMonthSelector(),
                const SizedBox(height: 12),
                _buildNetBalanceCard(),
                const SizedBox(height: 16),
                _buildAddExpenseCard(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCategoryBreakdownCard(),
                const SizedBox(height: 16),
                _buildRecentExpensesCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tooltip(
              message: 'Previous month',
              child: IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _changeMonth(-1),
              ),
            ),
            Text(
              _selectedMonth,
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Tooltip(
              message: 'Next month',
              child: IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _changeMonth(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetBalanceCard() {
    final net = _balanceSheet?.netBalance ?? 0;
    final isProfit = net >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Net Balance',
              style: GoogleFonts.poppins(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${net.abs()} ${isProfit ? "Profit" : "Loss"}',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isProfit ? AppTheme.success : AppTheme.error,
              ),
            ),
            if (_balanceSheet != null) ...[
              const SizedBox(height: 8),
              Text(
                'Collections ₹${_balanceSheet!.totalCollections}  ·  Expenses ₹${_balanceSheet!.totalExpenses}',
                style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddExpenseCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Expense',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _formCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'Select expense category',
              ),
              items: _expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _formCategory = v ?? 'Other'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                hintText: 'Enter amount in rupees',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. Monthly electricity bill',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _receiptRefController,
              decoration: const InputDecoration(
                labelText: 'Receipt / Reference (optional)',
                hintText: 'Bill or invoice number',
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Choose expense date',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(formatDisplayDate(_formDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _formDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null && mounted) setState(() => _formDate = picked);
                },
              ),
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: 'Save this expense to the selected month',
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submitExpense,
                  child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Expense'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdownCard() {
    final sheet = _balanceSheet;
    final total = sheet?.totalExpenses ?? 0;
    final breakdown = sheet?.categoryBreakdown ?? {};
    final entries = breakdown.entries.toList()..sort((a, b) => (b.value).compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category Breakdown',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'No expenses this month',
                style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              ...entries.map((e) {
                final pct = total > 0 ? (e.value / total) : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: GoogleFonts.poppins(fontSize: 14)),
                          Text('₹${e.value}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentExpensesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Expenses',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_expenses.isEmpty)
              Text(
                'No expenses this month',
                style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _expenses.length,
                itemBuilder: (context, i) {
                  final e = _expenses[i];
                  return Tooltip(
                    message: 'Tap to edit expense',
                    child: ListTile(
                      title: Text('${e.category} · ₹${e.amount}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        [e.expenseDate, if (e.description != null && e.description!.isNotEmpty) e.description].join(' · '),
                        style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      onTap: () => _showEditExpenseDialog(e),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
