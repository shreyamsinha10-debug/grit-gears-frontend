// ---------------------------------------------------------------------------
// Billing – Create Bill (member + plans + payment) and Invoice History.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../core/export_helper.dart';
import '../core/pdf_invoice_helper.dart';
import '../theme/app_theme.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _invoices = [];
  bool _loadingInvoices = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInvoices();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices({String? search, String? dateFrom, String? dateTo}) async {
    setState(() => _loadingInvoices = true);
    try {
      final params = <String, String>{};
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null && dateFrom.isNotEmpty) params['date_from'] = dateFrom;
      if (dateTo != null && dateTo.isNotEmpty) params['date_to'] = dateTo;
      final r = await ApiClient.instance.get('/billing/history', queryParameters: params.isEmpty ? null : params, useCache: false);
      if (mounted && r.statusCode == 200) {
        final list = jsonDecode(r.body) as List<dynamic>;
        setState(() {
          _invoices = list.map((e) => e as Map<String, dynamic>).toList();
          _loadingInvoices = false;
        });
      } else if (mounted) setState(() => _loadingInvoices = false);
    } catch (_) {
      if (mounted) setState(() => _loadingInvoices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Create Bill'),
            Tab(text: 'Invoice / History'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _CreateBillTab(
                onBillCreated: () {
                  _loadInvoices();
                  _tabController.animateTo(1);
                },
              ),
              _InvoiceHistoryTab(
                invoices: _invoices,
                loading: _loadingInvoices,
                onRefresh: _loadInvoices,
                loadInvoices: _loadInvoices,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Line item for the bill (from plan or custom).
class _BillLineItem {
  final String description;
  final int amount;
  _BillLineItem({required this.description, required this.amount});
}

class _CreateBillTab extends StatefulWidget {
  final VoidCallback onBillCreated;

  const _CreateBillTab({required this.onBillCreated});

  @override
  State<_CreateBillTab> createState() => _CreateBillTabState();
}

class _CreateBillTabState extends State<_CreateBillTab> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _plans = [];
  bool _loadingMembers = true;
  bool _loadingPlans = true;
  final _memberSearchController = TextEditingController();
  Map<String, dynamic>? _selectedMember;
  final List<_BillLineItem> _lineItems = [];
  final _amountController = TextEditingController(text: '0');
  String _paymentMethod = 'Cash';
  DateTime _paymentDate = DateTime.now();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadPlans();
  }

  @override
  void dispose() {
    _memberSearchController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    try {
      final r = await ApiClient.instance.get('/members', queryParameters: {'brief': 'true', 'limit': '500'}, useCache: true);
      if (mounted && r.statusCode == 200) {
        final list = jsonDecode(r.body) as List<dynamic>;
        setState(() {
          _members = list.map((e) => e as Map<String, dynamic>).toList();
          _loadingMembers = false;
        });
      } else if (mounted) setState(() => _loadingMembers = false);
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _loadPlans() async {
    setState(() => _loadingPlans = true);
    try {
      final r = await ApiClient.instance.get('/gym/profile', useCache: true);
      if (mounted && r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final plans = body['plans'] as List<dynamic>? ?? [];
        setState(() {
          _plans = plans.map((e) => e as Map<String, dynamic>).where((p) => p['is_active'] != false).toList();
          _loadingPlans = false;
        });
      } else if (mounted) setState(() => _loadingPlans = false);
    } catch (_) {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final q = _memberSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _members;
    return _members.where((m) {
      final name = (m['name'] as String? ?? '').toLowerCase();
      final phone = (m['phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
      final searchDigits = q.replaceAll(RegExp(r'\D'), '');
      return name.contains(q) || (searchDigits.isNotEmpty && phone.contains(searchDigits));
    }).toList();
  }

  int get _totalAmount {
    int sum = 0;
    for (final item in _lineItems) sum += item.amount;
    return sum;
  }

  void _updateAmountFromItems() {
    _amountController.text = _totalAmount.toString();
  }

  void _addPlanAsLineItem(Map<String, dynamic> plan) {
    final name = plan['name'] as String? ?? 'Plan';
    final price = int.tryParse(plan['price']?.toString() ?? '0') ?? 0;
    if (price <= 0) return;
    setState(() {
      _lineItems.add(_BillLineItem(description: name, amount: price));
      _updateAmountFromItems();
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems.removeAt(index);
      _updateAmountFromItems();
    });
  }

  Future<void> _submitBill() async {
    if (_selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a member')));
      return;
    }
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one plan or line item')));
      return;
    }
    final total = int.tryParse(_amountController.text.trim()) ?? 0;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final body = jsonEncode({
        'member_id': _selectedMember!['id'],
        'items': _lineItems.map((e) => {'description': e.description, 'amount': e.amount}).toList(),
        'total': total,
        'payment_method': _paymentMethod,
        'payment_date': formatApiDate(_paymentDate),
        'reference': _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      });
      final r = await ApiClient.instance.post(
        '/billing/create',
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        ApiClient.instance.invalidateCache();
        final inv = jsonDecode(r.body) as Map<String, dynamic>;
        final billNo = inv['bill_number'] as String? ?? inv['id']?.toString().substring(0, 8) ?? '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bill $billNo created for ₹$total')));
        widget.onBillCreated();
        setState(() {
          _submitting = false;
          _selectedMember = null;
          _lineItems.clear();
          _amountController.text = '0';
          _referenceController.clear();
          _notesController.clear();
        });
      } else {
        final detail = (jsonDecode(r.body) as Map<String, dynamic>)['detail'] ?? r.body;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $detail')));
        setState(() => _submitting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = LayoutConstants.screenPadding(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Create Bill', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          const SizedBox(height: 2),
          Text('Bill No: —', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          // Select Member
          Text('Select Member', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _memberSearchController,
            decoration: const InputDecoration(
              hintText: 'Search by name or phone...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_selectedMember != null) ...[
            const SizedBox(height: 8),
            Card(
              color: AppTheme.surfaceVariant,
              child: ListTile(
                title: Text(_selectedMember!['name'] ?? ''),
                subtitle: Text(_selectedMember!['phone'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedMember = null),
                ),
              ),
            ),
          ] else if (_filteredMembers.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredMembers.length,
                itemBuilder: (context, i) {
                  final m = _filteredMembers[i];
                  return ListTile(
                    title: Text(m['name'] ?? ''),
                    subtitle: Text(m['phone'] ?? ''),
                    onTap: () => setState(() {
                      _selectedMember = m;
                      _memberSearchController.clear();
                    }),
                  );
                },
              ),
            ),
          ] else if (!_loadingMembers)
            Padding(padding: const EdgeInsets.all(8), child: Text('No members found', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600))),
          const SizedBox(height: 20),
          // Membership Plans
          Text('Membership Plans', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Add one or more plans (e.g. Registration + Monthly)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          if (_loadingPlans)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
          else if (_plans.isEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text('No plans in gym settings', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _plans.map((p) {
                final name = p['name'] as String? ?? '';
                final price = int.tryParse(p['price']?.toString() ?? '0') ?? 0;
                return FilterChip(
                  label: Text('$name — ₹$price'),
                  onSelected: (_) => _addPlanAsLineItem(p),
                );
              }).toList(),
            ),
          if (_lineItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._lineItems.asMap().entries.map((e) => ListTile(
              title: Text(e.value.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('₹${e.value.amount}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: () => _removeLineItem(e.key)),
                ],
              ),
            )),
          ],
          const SizedBox(height: 20),
          // Payment Details
          Card(
            color: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Amount', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: '₹ ', border: OutlineInputBorder(), isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text('Method', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
                  DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'Online', child: Text('Online')),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v ?? 'Cash'),
                  ),
                  const SizedBox(height: 12),
                  Text('Date', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(formatDisplayDate(_paymentDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _paymentDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setState(() => _paymentDate = d);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Reference (optional)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
                  TextField(
                    controller: _referenceController,
                    decoration: const InputDecoration(hintText: 'UPI ref, etc.', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),
                  Text('Total Paid: ₹${int.tryParse(_amountController.text.trim()) ?? 0}', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Notes (Optional)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'e.g. July Fees', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submitBill,
            icon: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
            label: Text('Complete Bill — ₹${int.tryParse(_amountController.text.trim()) ?? 0}.00'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceHistoryTab extends StatefulWidget {
  final List<Map<String, dynamic>> invoices;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function({String? search, String? dateFrom, String? dateTo}) loadInvoices;

  const _InvoiceHistoryTab({required this.invoices, required this.loading, required this.onRefresh, required this.loadInvoices});

  @override
  State<_InvoiceHistoryTab> createState() => _InvoiceHistoryTabState();
}

class _InvoiceHistoryTabState extends State<_InvoiceHistoryTab> {
  final _searchController = TextEditingController();
  String? _dateFrom;
  String? _dateTo;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    widget.loadInvoices(
      search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
      dateFrom: _dateFrom,
      dateTo: _dateTo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(LayoutConstants.screenPadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by invoice # or member name',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _applyFilter(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(_dateFrom != null ? formatDisplayDate(parseApiDate(_dateFrom)) : 'From', style: GoogleFonts.poppins(fontSize: 12)),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (d != null) setState(() => _dateFrom = formatApiDate(d));
                    },
                    child: const Text('Date from'),
                  ),
                  Text(_dateTo != null ? formatDisplayDate(parseApiDate(_dateTo)) : 'To', style: GoogleFonts.poppins(fontSize: 12)),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (d != null) setState(() => _dateTo = formatApiDate(d));
                    },
                    child: const Text('Date to'),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _applyFilter, child: const Text('Apply')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Invoices', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: () async {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting...')));
                      final savedPath = await saveExportToDownloads('/export/billing', 'billing_history.xlsx');
                      if (!context.mounted) return;
                      if (savedPath != null) {
                        final label = await exportLocationLabel();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $label')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed. Try again.')));
                      }
                    },
                    icon: const Icon(FontAwesomeIcons.fileExport, size: 18),
                    label: const Text('Export all'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : ListView.builder(
                  padding: EdgeInsets.all(LayoutConstants.screenPadding(context)),
                  itemCount: widget.invoices.length,
                  itemBuilder: (context, i) {
                    final inv = widget.invoices[i];
                    final issuedAt = inv['issued_at'];
                    final paidAt = inv['paid_at'];
                    final issuedStr = issuedAt != null ? formatDisplayDate(parseApiDateTime(issuedAt.toString())) : null;
                    final paidStr = paidAt != null ? formatDisplayDate(parseApiDateTime(paidAt.toString())) : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(inv['member_name'] ?? ''),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('₹${inv['total']} • ${inv['status']} • ${inv['bill_number'] ?? '#${inv['id']?.toString().substring(0, 8) ?? ''}'}', style: GoogleFonts.poppins(fontSize: 13)),
                            if (issuedStr != null) Text('Issued: $issuedStr', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                            if (paidStr != null && inv['status'] == 'Paid') Text('Paid on: $paidStr', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.success)),
                          ],
                        ),
                        trailing: inv['status'] == 'Unpaid'
                            ? FilledButton(
                                onPressed: () => _InvoiceHistoryTabState.showInvoiceWithQR(context, inv, widget.onRefresh),
                                child: const Text('View / Pay'),
                              )
                            : null,
                        onTap: () => _InvoiceHistoryTabState.showInvoiceWithQR(context, inv, widget.onRefresh),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static void showInvoiceWithQR(BuildContext context, Map<String, dynamic> inv, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Invoice • ${inv['member_name']}${inv['bill_number'] != null ? ' • ${inv['bill_number']}' : ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...(inv['items'] as List<dynamic>? ?? []).map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e['description'] ?? ''),
                    Text('₹${e['amount']}'),
                  ],
                ),
              )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                  Text('₹${inv['total']}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                ],
              ),
              if (inv['status'] == 'Unpaid') ...[
                const SizedBox(height: 16),
                const Center(child: Text('Simulated UPI QR', style: TextStyle(color: Colors.grey))),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.qr_code_2, size: 80),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              Map<String, dynamic>? gymProfile;
              try {
                final r = await ApiClient.instance.get('/gym/profile', useCache: true);
                if (r.statusCode >= 200 && r.statusCode < 300) {
                  gymProfile = jsonDecode(r.body) as Map<String, dynamic>?;
                }
              } catch (_) {}
              if (ctx.mounted) {
                await PdfInvoiceHelper.generateAndPrint(inv, gymProfile: gymProfile);
              }
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Print / PDF'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (inv['status'] == 'Unpaid')
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final r = await ApiClient.instance.post('/billing/pay?invoice_id=${inv['id']}');
                if (r.statusCode >= 200 && r.statusCode < 300) {
                  ApiClient.instance.invalidateCache();
                  onRefresh();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded')));
                }
              },
              child: const Text('Mark as Paid'),
            ),
        ],
      ),
    );
  }
}
