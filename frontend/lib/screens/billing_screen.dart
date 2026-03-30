// ---------------------------------------------------------------------------
// Billing – Create Bill and Invoice / History.
// ---------------------------------------------------------------------------
// Create Bill: select member → plan auto-populated → payment details → submit.
// Invoice History: list of all paid/unpaid invoices with search and filter.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../core/export_helper.dart';
import '../core/pdf_invoice_helper.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Invoice> _invoices = [];
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
        setState(() {
          _invoices = ApiClient.parseInvoices(r.body);
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

// ---------------------------------------------------------------------------
// Create Bill Tab
// ---------------------------------------------------------------------------

class _CreateBillTab extends StatefulWidget {
  final VoidCallback onBillCreated;
  const _CreateBillTab({required this.onBillCreated});

  @override
  State<_CreateBillTab> createState() => _CreateBillTabState();
}

class _CreateBillTabState extends State<_CreateBillTab> {
  // Data
  List<Member> _members = [];
  List<GymPlan> _plans = [];
  bool _loadingMembers = true;
  bool _loadingPlans = true;
  String _previewBillNo = 'Loading...';

  // Member selection
  final _memberSearchController = TextEditingController();
  Member? _selectedMember;

  // Line items
  final List<Map<String, dynamic>> _items = []; // [{description, amount, duration_type?}]

  // Add-item form
  GymPlan? _addPlan; // selected plan from dropdown
  final _customDescController = TextEditingController();
  final _customAmountController = TextEditingController();
  bool _addingCustom = false;

  // Payment
  String _paymentMethod = 'Cash';
  DateTime _paymentDate = DateTime.now();
  DateTime? _endDateOverride; // user-adjusted end date; when null, use computed from plan duration
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _submitting = false;

  /// Editable batch for invoice (defaults to member's batch when member selected).
  final _batchController = TextEditingController();

  /// Map plan duration_type to days (1m=30, 3m=90, etc.). Returns null for one_time or unknown.
  static int? _durationTypeToDays(String? dt) {
    switch (dt) {
      case '1m': return 30;
      case '2m': return 60;
      case '3m': return 90;
      case '6m': return 180;
      case '1yr': return 365;
      default: return null;
    }
  }

  /// Max duration in days from current line items (from plans with duration_type). Null if none.
  int? get _maxPlanDays {
    int? maxDays;
    for (final item in _items) {
      final dt = item['duration_type'] as String?;
      final d = _durationTypeToDays(dt);
      if (d != null && (maxDays == null || d > maxDays)) maxDays = d;
    }
    return maxDays;
  }

  /// System-computed end date from start date + longest plan duration. Null if no plan duration.
  DateTime? get _computedEndDate {
    final days = _maxPlanDays;
    if (days == null || days <= 0) return null;
    return _paymentDate.add(Duration(days: days));
  }

  /// Display end date: user override or computed. Used for "Ends: ..." and editable picker.
  DateTime? get _displayEndDate => _endDateOverride ?? _computedEndDate;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadPlans();
    _loadNextBillNumber();
  }

  @override
  void dispose() {
    _memberSearchController.dispose();
    _customDescController.dispose();
    _customAmountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _loadNextBillNumber() async {
    try {
      final r = await ApiClient.instance.get('/billing/next-bill-number', useCache: false);
      if (mounted && r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _previewBillNo = data['bill_number'] as String? ?? '—');
      } else if (mounted) setState(() => _previewBillNo = '—');
    } catch (_) {
      if (mounted) setState(() => _previewBillNo = '—');
    }
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    try {
      final r = await ApiClient.instance.get('/members', queryParameters: {'brief': 'true', 'limit': '500'}, useCache: true);
      if (mounted && r.statusCode == 200) {
        setState(() {
          _members = ApiClient.parseMembers(r.body);
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
        final profile = ApiClient.parseGymProfile(r.body);
        setState(() {
          _plans = profile.plans.where((p) => p.isActive).toList();
          _loadingPlans = false;
        });
      } else if (mounted) setState(() => _loadingPlans = false);
    } catch (_) {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  List<Member> get _filteredMembers {
    final q = _memberSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _members;
    return _members.where((m) {
      final name = m.name.toLowerCase();
      final phone = m.phone.replaceAll(RegExp(r'\D'), '');
      final digits = q.replaceAll(RegExp(r'\D'), '');
      return name.contains(q) || (digits.isNotEmpty && phone.contains(digits));
    }).toList();
  }

  int get _total => _items.fold(0, (sum, e) => sum + ((e['amount'] as num?)?.toInt() ?? 0));

  void _selectMember(Member m) {
    setState(() {
      _selectedMember = m;
      _memberSearchController.clear();
      _items.clear();
      _batchController.text = m.batch;
    });
    // Auto-add a matching plan
    if (_plans.isNotEmpty) {
      final memberType = m.membershipType.toLowerCase();
      GymPlan? matched;
      if (memberType.isNotEmpty) {
        try {
          matched = _plans.firstWhere(
            (p) => p.name.toLowerCase().contains(memberType),
          );
        } catch (_) {}
      }
      matched ??= _plans.first;
      final price = matched.price;
      if (price > 0) {
        setState(() {
          _items.add({
            'description': matched!.name,
            'amount': price,
            'duration_type': matched.durationType,
          });
        });
      }
    }
  }

  void _addPlanItem() {
    if (_addPlan == null) {
      _showSnack('Select a plan to add');
      return;
    }
    final price = _addPlan!.price;
    setState(() {
      _items.add({
        'description': _addPlan!.name,
        'amount': price,
        'duration_type': _addPlan!.durationType,
      });
      _addPlan = null;
      _endDateOverride = null;
    });
  }

  void _addCustomItem() {
    final desc = _customDescController.text.trim();
    final amt = int.tryParse(_customAmountController.text.trim()) ?? 0;
    if (desc.isEmpty) { _showSnack('Enter a description'); return; }
    if (amt <= 0) { _showSnack('Enter a valid amount'); return; }
    setState(() {
      _items.add({'description': desc, 'amount': amt});
      _customDescController.clear();
      _customAmountController.clear();
      _addingCustom = false;
    });
  }

  Future<void> _submitBill() async {
    if (_selectedMember == null) { _showSnack('Please select a member first'); return; }
    if (_items.isEmpty) { _showSnack('Add at least one plan or item'); return; }
    if (_total <= 0) { _showSnack('Total must be greater than ₹0'); return; }

    setState(() => _submitting = true);
    try {
      // Build item descriptions for invoice: plan items get "Plan - X days (Start - End)"
      final endDate = _displayEndDate;
      final startStr = formatDisplayDate(_paymentDate);
      final endStr = endDate != null ? formatDisplayDate(endDate) : null;
      final itemsForApi = _items.map<Map<String, dynamic>>((item) {
        final desc = item['description'] as String? ?? '';
        final amount = (item['amount'] as num?)?.toInt() ?? 0;
        final dt = item['duration_type'] as String?;
        final days = dt != null ? _durationTypeToDays(dt) : null;
        String finalDesc = desc;
        if (days != null && endStr != null) {
          finalDesc = '$desc - $days days ($startStr - $endStr)';
        }
        return {'description': finalDesc, 'amount': amount};
      }).toList();

      final bodyMap = <String, dynamic>{
        'member_id': _selectedMember!.id,
        'items': itemsForApi,
        'total': _total,
        'payment_method': _paymentMethod,
        'payment_date': formatApiDate(_paymentDate),
        'reference': _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      };
      if (_displayEndDate != null) bodyMap['end_date'] = formatApiDate(_displayEndDate!);
      final batchVal = _batchController.text.trim();
      if (batchVal.isNotEmpty) bodyMap['batch'] = batchVal;
      if (_selectedMember!.phone.isNotEmpty) bodyMap['member_phone'] = _selectedMember!.phone;
      if (_selectedMember!.email.isNotEmpty) bodyMap['member_email'] = _selectedMember!.email;

      final body = jsonEncode(bodyMap);
      final r = await ApiClient.instance.post('/billing/create', headers: {'Content-Type': 'application/json'}, body: body);
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final inv = jsonDecode(r.body) as Map<String, dynamic>;
        final billNo = inv['bill_number'] as String? ?? '—';
        // Success dialog with option to print the created invoice (all line items)
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                Text('Bill Created!', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      _infoRow('Bill No', billNo),
                      _infoRow('Member', _selectedMember!.name),
                      _infoRow('Total', '₹$_total'),
                      _infoRow('Method', _paymentMethod),
                      _infoRow('Date', formatDisplayDate(_paymentDate)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  GymProfile? gymProfile;
                  try {
                    final rp = await ApiClient.instance.get('/gym/profile', useCache: true);
                    if (rp.statusCode >= 200 && rp.statusCode < 300) gymProfile = ApiClient.parseGymProfile(rp.body);
                  } catch (_) {}
                  if (ctx.mounted) await PdfInvoiceHelper.generateAndPrint(inv, gymProfile: gymProfile?.toJson());
                },
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('Print / PDF'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        ApiClient.instance.invalidateCache();
        widget.onBillCreated();
        setState(() {
          _submitting = false;
          _selectedMember = null;
          _items.clear();
          _referenceController.clear();
          _notesController.clear();
          _paymentMethod = 'Cash';
          _paymentDate = DateTime.now();
          _endDateOverride = null;
          _addPlan = null;
          _addingCustom = false;
          _batchController.clear();
        });
        _loadNextBillNumber();
      } else {
        final detail = (jsonDecode(r.body) as Map<String, dynamic>?)?['detail'] ?? r.body;
        _showSnack('Failed: $detail');
        setState(() => _submitting = false);
      }
    } catch (e) {
      if (mounted) { _showSnack('Error: $e'); setState(() => _submitting = false); }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pad = LayoutConstants.screenPadding(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create Bill', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                    Text('Bill No: $_previewBillNo', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Text(formatDisplayDate(DateTime.now()), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Step 1: Select Member ──────────────────────────────────────
          _sectionLabel('1', 'Select Member'),
          const SizedBox(height: 8),
          if (_selectedMember != null) ...[
            _memberCard(_selectedMember!),
            const SizedBox(height: 12),
            Text('Batch (for invoice)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            TextField(
              controller: _batchController,
              decoration: InputDecoration(
                hintText: 'e.g. Morning, Evening',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              style: GoogleFonts.poppins(),
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            TextField(
              controller: _memberSearchController,
              decoration: InputDecoration(
                hintText: _loadingMembers ? 'Loading members...' : 'Search by name or phone...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              enabled: !_loadingMembers,
              onChanged: (_) => setState(() {}),
            ),
            if (_memberSearchController.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Card(
                  elevation: 3,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: _filteredMembers.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('No members found', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _filteredMembers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final m = _filteredMembers[i];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.primary.withOpacity(0.15),
                                child: Text((m.name.isNotEmpty ? m.name[0] : '?').toUpperCase(), style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(m.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                              subtitle: Text('${m.phone} · ${m.membershipType} · ${m.batch}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                              onTap: () => _selectMember(m),
                            );
                          },
                        ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),

          // ── Step 2: Line Items ─────────────────────────────────────────
          _sectionLabel('2', 'Plans & Items'),
          const SizedBox(height: 8),
          if (_selectedMember == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Select a member first to add items', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
            )
          else ...[
            // Current items
            if (_items.isNotEmpty) ...[
              ..._items.asMap().entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: AppTheme.surfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  dense: true,
                  title: Text(e.value['description'] as String? ?? '', style: GoogleFonts.poppins(fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹${e.value['amount']}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                        onPressed: () => setState(() { _items.removeAt(e.key); _endDateOverride = null; }),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('₹$_total', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: AppTheme.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Add plan from list
            if (!_loadingPlans && _plans.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<GymPlan>(
                      value: _addPlan,
                      decoration: InputDecoration(
                        hintText: 'Select plan to add...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _plans.map((p) {
                        final name = p.name;
                        final price = p.price;
                        return DropdownMenuItem<GymPlan>(value: p, child: Text('$name — ₹$price', style: GoogleFonts.poppins(fontSize: 13)));
                      }).toList(),
                      onChanged: (v) => setState(() => _addPlan = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addPlanItem,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Add custom item
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _addingCustom ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: TextButton.icon(
                onPressed: () => setState(() => _addingCustom = true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add custom item'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              ),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _customDescController,
                    decoration: InputDecoration(
                      hintText: 'Description (e.g. Registration Fee)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customAmountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: 'Amount (₹)',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _addCustomItem,
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                        child: const Text('Add'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => setState(() { _addingCustom = false; _customDescController.clear(); _customAmountController.clear(); }),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // ── Step 3: Payment Details ────────────────────────────────────
          _sectionLabel('3', 'Payment Details'),
          const SizedBox(height: 8),
          Card(
            color: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Method
                  Text('Payment Method', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Row(
                    children: ['Cash', 'Online'].map((m) {
                      final selected = _paymentMethod == m;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _paymentMethod = m),
                            icon: Icon(m == 'Cash' ? Icons.payments_outlined : Icons.phone_android, size: 18),
                            label: Text(m),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected ? AppTheme.primary : null,
                              foregroundColor: selected ? Colors.white : AppTheme.primary,
                              side: BorderSide(color: AppTheme.primary),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Start date (membership start; API still uses payment_date)
                  Text('Start date', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _paymentDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setState(() { _paymentDate = d; _endDateOverride = null; });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(formatDisplayDate(_paymentDate), style: GoogleFonts.poppins(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  if (_displayEndDate != null) ...[
                    const SizedBox(height: 8),
                    Text('End date (editable)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      'Ends: ${formatDisplayDate(_displayEndDate)}${_maxPlanDays != null ? ' · ${_maxPlanDays} days from start' : ''}',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _displayEndDate!,
                          firstDate: _paymentDate,
                          lastDate: _paymentDate.add(const Duration(days: 365 * 2)),
                        );
                        if (d != null) setState(() => _endDateOverride = d);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event, size: 18, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(formatDisplayDate(_displayEndDate), style: GoogleFonts.poppins(fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Reference
                  Text('Reference (optional)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _referenceController,
                    decoration: InputDecoration(
                      hintText: 'UPI ref, transaction ID, etc.',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Notes
                  Text('Notes (optional)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'e.g. July membership fee',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Submit ────────────────────────────────────────────────────
          Tooltip(
            message: 'Create and save the bill for the selected member',
            child: FilledButton.icon(
              onPressed: (_submitting || _selectedMember == null || _items.isEmpty) ? null : _submitBill,
              icon: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.receipt_long_rounded),
              label: Text(
                _submitting
                    ? 'Creating Bill...'
                    : _total > 0
                        ? 'Complete Bill — ₹$_total'
                        : 'Complete Bill',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _memberCard(Member m) => Card(
    color: AppTheme.primary.withOpacity(0.07),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.primary.withOpacity(0.3))),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.primary.withOpacity(0.2),
        child: Text((m.name.isNotEmpty ? m.name[0] : '?').toUpperCase(), style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
      ),
      title: Text(m.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${m.phone} · ${m.membershipType} · ${m.batch}',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 20),
        onPressed: () => setState(() { _selectedMember = null; _items.clear(); _addPlan = null; _batchController.clear(); }),
        tooltip: 'Change member',
      ),
    ),
  );

  Widget _sectionLabel(String step, String title) => Row(
    children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: AppTheme.primary,
        child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 8),
      Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Invoice History Tab
// ---------------------------------------------------------------------------

class _InvoiceHistoryTab extends StatefulWidget {
  final List<Invoice> invoices;
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

  void _clearFilter() {
    setState(() { _searchController.clear(); _dateFrom = null; _dateTo = null; });
    widget.loadInvoices();
  }

  @override
  Widget build(BuildContext context) {
    final pad = LayoutConstants.screenPadding(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by bill # or member name',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () { setState(() => _searchController.clear()); _applyFilter(); })
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _applyFilter(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                        if (d != null) setState(() => _dateFrom = formatApiDate(d));
                      },
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(_dateFrom != null ? formatDisplayDate(parseApiDate(_dateFrom)) : 'From date', style: GoogleFonts.poppins(fontSize: 12)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), side: BorderSide(color: Colors.grey.shade400)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                        if (d != null) setState(() => _dateTo = formatApiDate(d));
                      },
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(_dateTo != null ? formatDisplayDate(parseApiDate(_dateTo)) : 'To date', style: GoogleFonts.poppins(fontSize: 12)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), side: BorderSide(color: Colors.grey.shade400)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _applyFilter, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), child: const Text('Search')),
                  if (_dateFrom != null || _dateTo != null || _searchController.text.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: _clearFilter, tooltip: 'Clear filters'),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${widget.invoices.length} invoice${widget.invoices.length == 1 ? '' : 's'}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
                    icon: const Icon(FontAwesomeIcons.fileExport, size: 14),
                    label: const Text('Export'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : widget.invoices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('No invoices found', style: GoogleFonts.poppins(fontSize: 15, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text('Create a bill to see it here', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => widget.onRefresh(),
                      child: ListView.builder(
                        padding: EdgeInsets.all(pad),
                        itemCount: widget.invoices.length,
                        itemBuilder: (context, i) {
                          final inv = widget.invoices[i];
                          final isPaid = inv.status == 'Paid';
                          final paidStr = inv.paidAt != null ? formatDisplayDate(inv.paidAt) : null;
                          final billNo = inv.billNumber ?? '#${inv.id.length >= 8 ? inv.id.substring(0, 8) : inv.id}';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _InvoiceHistoryTabState.showInvoiceDialog(context, inv, widget.onRefresh),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(inv.memberName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: isPaid ? Colors.green.shade300 : Colors.orange.shade300),
                                          ),
                                          child: Text(isPaid ? 'Paid' : 'Unpaid', style: GoogleFonts.poppins(fontSize: 12, color: isPaid ? Colors.green.shade700 : Colors.orange.shade700, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(billNo, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                                        const Spacer(),
                                        Text('₹${inv.total}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                      ],
                                    ),
                                    if (isPaid && paidStr != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade600),
                                          const SizedBox(width: 4),
                                          Text('Paid on $paidStr${inv.paymentMethod != null ? ' · ${inv.paymentMethod}' : ''}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700)),
                                        ],
                                      ),
                                    ] else if (!isPaid && inv.issuedAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text('Issued: ${formatDisplayDate(inv.issuedAt)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                                    ],
                                    if (inv.notes != null && inv.notes!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(inv.notes!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                    if (!isPaid) ...[
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () => _InvoiceHistoryTabState.showInvoiceDialog(context, inv, widget.onRefresh),
                                          icon: const Icon(Icons.payment, size: 16),
                                          label: const Text('View & Pay'),
                                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 10)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  static void showInvoiceDialog(BuildContext context, Invoice inv, VoidCallback onRefresh) {
    final isPaid = inv.status == 'Paid';
    final billNo = inv.billNumber ?? '#${inv.id.length >= 8 ? inv.id.substring(0, 8) : inv.id}';
    final paidStr = inv.paidAt != null ? formatDisplayDate(inv.paidAt) : null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(inv.memberName, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(billNo, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...inv.items.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(e.description, style: GoogleFonts.poppins(fontSize: 14))),
                    Text('₹${e.amount}', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('₹${inv.total}', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.primary)),
                ],
              ),
              if (isPaid && paidStr != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 16),
                    const SizedBox(width: 6),
                    Text('Paid on $paidStr${inv.paymentMethod != null ? ' via ${inv.paymentMethod}' : ''}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.green.shade700)),
                  ],
                ),
              ],
              if (inv.endDate != null) ...[
                const SizedBox(height: 6),
                Text('Valid until ${formatDisplayDate(inv.endDate)}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
              ],
              if (!isPaid) ...[
                const SizedBox(height: 16),
                const Center(child: Icon(Icons.qr_code_2, size: 80, color: Colors.grey)),
                const Center(child: Text('Scan to pay (coming soon)', style: TextStyle(fontSize: 12, color: Colors.grey))),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              GymProfile? gymProfile;
              try {
                final r = await ApiClient.instance.get('/gym/profile', useCache: true);
                if (r.statusCode >= 200 && r.statusCode < 300) gymProfile = ApiClient.parseGymProfile(r.body);
              } catch (_) {}
              if (ctx.mounted) await PdfInvoiceHelper.generateAndPrint(inv.toJson(), gymProfile: gymProfile?.toJson());
            },
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('Print / PDF'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _InvoiceHistoryTabState.showEditInvoiceDialog(context, inv, onRefresh);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          TextButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('Delete invoice?'),
                  content: const Text('This cannot be undone. The invoice and its payment history will be removed from all screens.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm != true || !ctx.mounted) return;
              final r = await ApiClient.instance.delete('/billing/invoices/${inv.id}');
              if (ctx.mounted) {
                Navigator.pop(ctx);
                onRefresh();
                if (r.statusCode >= 200 && r.statusCode < 300) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice deleted')));
                } else {
                  final detail = (jsonDecode(r.body) as Map<String, dynamic>?)?['detail'] ?? 'Failed to delete';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail.toString())));
                }
              }
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (!isPaid)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final r = await ApiClient.instance.post('/billing/pay?invoice_id=${inv.id}');
                if (r.statusCode >= 200 && r.statusCode < 300) {
                  ApiClient.instance.invalidateCache();
                  onRefresh();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded successfully')));
                }
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Mark as Paid'),
            ),
        ],
      ),
    );
  }

  static Future<void> showEditInvoiceDialog(BuildContext context, Invoice inv, VoidCallback onRefresh) async {
    List<Map<String, dynamic>> items = inv.items.map((e) => {'description': e.description, 'amount': e.amount}).toList();
    if (items.isEmpty) items = [{'description': '', 'amount': 0}];
    DateTime paymentDate = inv.paidAt ?? inv.issuedAt ?? DateTime.now();
    if (paymentDate.isUtc) paymentDate = paymentDate.toLocal();
    DateTime? endDate = inv.endDate;
    if (endDate != null && endDate.isUtc) endDate = endDate.toLocal();
    final notesController = TextEditingController(text: inv.notes ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          int total = items.fold(0, (s, e) => s + ((e['amount'] as int?) ?? 0));
          return AlertDialog(
            title: Text('Edit invoice', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Line items', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  ...items.asMap().entries.map((e) => Row(
                    key: ValueKey(e.key),
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          decoration: const InputDecoration(isDense: true, hintText: 'Description'),
                          controller: TextEditingController(text: e.value['description'] as String? ?? ''),
                          onChanged: (v) {
                            items[e.key]['description'] = v;
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          decoration: const InputDecoration(isDense: true, hintText: 'Amount'),
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(text: '${e.value['amount'] ?? 0}'),
                          onChanged: (v) {
                            items[e.key]['amount'] = int.tryParse(v) ?? 0;
                            setState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: items.length > 1 ? () => setState(() => items.removeAt(e.key)) : null,
                      ),
                    ],
                  )),
                  TextButton.icon(
                    onPressed: () => setState(() => items.add({'description': '', 'amount': 0})),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add line'),
                  ),
                  const SizedBox(height: 12),
                  Text('Payment date', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: paymentDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setState(() => paymentDate = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                      child: Text(formatDisplayDate(paymentDate), style: GoogleFonts.poppins()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('End date (optional)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: endDate ?? paymentDate, firstDate: paymentDate, lastDate: DateTime.now().add(const Duration(days: 365 * 2)));
                      if (d != null) setState(() => endDate = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                      child: Text(endDate != null ? formatDisplayDate(endDate) : '—', style: GoogleFonts.poppins()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes', isDense: true),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      Text('₹$total', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final itemsToSend = items.where((e) => (e['description'] as String? ?? '').trim().isNotEmpty || ((e['amount'] as int?) ?? 0) > 0).toList();
                  if (itemsToSend.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one line item')));
                    return;
                  }
                  final totalToSend = itemsToSend.fold(0, (s, e) => s + ((e['amount'] as int?) ?? 0));
                  if (totalToSend <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Total must be greater than 0')));
                    return;
                  }
                  final body = <String, dynamic>{
                    'items': itemsToSend.map((e) => {'description': (e['description'] as String? ?? '').trim().isEmpty ? 'Item' : e['description'], 'amount': e['amount'] as int? ?? 0}).toList(),
                    'total': totalToSend,
                    'payment_date': formatApiDate(paymentDate),
                    'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                  };
                  if (endDate != null) body['end_date'] = formatApiDate(endDate!);
                  final r = await ApiClient.instance.patch(
                    '/billing/invoices/${inv.id}',
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  );
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    onRefresh();
                    if (r.statusCode >= 200 && r.statusCode < 300) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice updated')));
                    } else {
                      final detail = (jsonDecode(r.body) as Map<String, dynamic>?)?['detail'] ?? 'Failed to update';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail.toString())));
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
