// ---------------------------------------------------------------------------
// Billing – walk-in (new member + first invoice), invoice list, mark paid, export.
// ---------------------------------------------------------------------------
// Tabs: Issue (walk-in), History (invoices), Export. Uses [export_helper] to
// download Excel. All amounts in ₹; dates via [date_utils].
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
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _invoices = [];
  bool _loadingMembers = false;
  bool _loadingInvoices = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMembers();
    _loadInvoices();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
            Tab(text: 'Walk-in'),
            Tab(text: 'Existing Member'),
            Tab(text: 'Invoice / History'),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _WalkInTab(onSuccess: () { _loadMembers(); _loadInvoices(); }),
              _ExistingMemberTab(members: _members, loading: _loadingMembers, onSuccess: () { _loadMembers(); _loadInvoices(); }),
              _InvoiceHistoryTab(invoices: _invoices, loading: _loadingInvoices, onRefresh: _loadInvoices, loadInvoices: _loadInvoices),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalkInTab extends StatefulWidget {
  final VoidCallback onSuccess;

  const _WalkInTab({required this.onSuccess});

  @override
  State<_WalkInTab> createState() => _WalkInTabState();
}

class _WalkInTabState extends State<_WalkInTab> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String _membershipType = 'Regular';
  String _batch = 'Morning';
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty || _email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ApiClient.instance.post(
        '/billing/issue',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          'membership_type': _membershipType,
          'batch': _batch,
        }),
      );
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        ApiClient.instance.invalidateCache();
        final inv = jsonDecode(r.body) as Map<String, dynamic>;
        widget.onSuccess();
        _name.clear();
        _phone.clear();
        _email.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Member added. Invoice #${inv['id']} issued for ₹${inv['total']}')));
      } else {
        final body = jsonDecode(r.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body['detail']?.toString() ?? 'Failed')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
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
          Text(
            'Walk-in (new member)',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a new member who has come for the first time and issue their first bill (registration + first month).',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          Card(
            color: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _membershipType,
                    decoration: InputDecoration(
                      labelText: 'Membership',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                    ),
                    items: ['Regular', 'PT'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _membershipType = v ?? 'Regular'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _batch,
                    decoration: InputDecoration(
                      labelText: 'Batch',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                    ),
                    items: ['Morning', 'Evening', 'Ladies'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _batch = v ?? 'Morning'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _loading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Add Member & Issue First Bill', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ExistingMemberTab extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final bool loading;
  final VoidCallback onSuccess;

  const _ExistingMemberTab({required this.members, required this.loading, required this.onSuccess});

  @override
  State<_ExistingMemberTab> createState() => _ExistingMemberTabState();
}

class _ExistingMemberTabState extends State<_ExistingMemberTab> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.members;
    return widget.members.where((m) => (m['name'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    if (widget.members.isEmpty) return const Center(child: Text('No members. Use Walk-in or Members tab.'));
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: LayoutConstants.screenPadding(context)),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search by name…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(LayoutConstants.screenPadding(context)),
            itemCount: _filteredMembers.length,
            itemBuilder: (context, i) {
              final m = _filteredMembers[i];
              final name = m['name'] as String? ?? '';
              final id = m['id'] as String? ?? '';
              final type = (m['membership_type'] as String? ?? 'Regular').toLowerCase();
              final amount = type == 'pt' ? 2000 : 500;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(name),
                  subtitle: Text('$type • ₹$amount/month'),
                  trailing: TextButton(
                    onPressed: () => _showExistingMemberPayDialog(context, id, name, type, amount, widget.onSuccess),
                    child: const Text('Log payment'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static void _showExistingMemberPayDialog(BuildContext context, String memberId, String name, String membershipType, int monthlyAmount, VoidCallback onSuccess) async {
    List<Map<String, dynamic>> payments = [];
    try {
      final r = await ApiClient.instance.get('/payments', queryParameters: {'member_id': memberId}, useCache: false);
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List<dynamic>;
        payments = list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final unpaid = payments.where((p) => p['status'] != 'Paid').toList();
          final unpaidMonthly = unpaid.where((p) => (p['fee_type'] as String? ?? '') == 'monthly').toList();
          final unpaidRegistration = unpaid.where((p) => (p['fee_type'] as String? ?? '') == 'registration').toList();

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Dues for $name', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Existing members: only monthly charges (₹${membershipType == 'pt' ? '2000' : '500'}/month). Registration is one-time at signup.',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                // Unpaid registration: show as info only (one-time, paid at signup — no Pay button)
                ...unpaidRegistration.map((p) => ListTile(
                  title: Text(
                    'registration • ₹${p['amount']}',
                    style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text('One-time, paid at new member signup', style: TextStyle(fontSize: 12)),
                  trailing: const SizedBox.shrink(),
                )),
                // Unpaid monthly: show with Pay button
                ...unpaidMonthly.map((p) => ListTile(
                  title: Text('${p['fee_type']} • ₹${p['amount']}'),
                  trailing: FilledButton(
                    onPressed: () async {
                      final pid = p['id'];
                      final pay = await ApiClient.instance.post('/payments/pay?member_id=$memberId&payment_id=$pid');
                      if (pay.statusCode >= 200 && pay.statusCode < 300) {
                        ApiClient.instance.invalidateCache();
                        final idx = payments.indexWhere((x) => x['id'] == pid);
                        if (idx >= 0) payments[idx]['status'] = 'Paid';
                        setModalState(() {});
                        onSuccess();
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Payment recorded')));
                      }
                    },
                    child: const Text('Pay'),
                  ),
                )),
                if (unpaidMonthly.isEmpty && unpaidRegistration.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('No pending dues')),
                const SizedBox(height: 16),
                const Divider(),
                Text('Log Payment and issue invoice', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '₹$monthlyAmount for ${membershipType == 'pt' ? 'Personal Training' : 'Regular'}. Payment date will be recorded.',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 20),
                  label: const Text('Log Payment and issue invoice'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showLogMonthlyDialog(context, memberId, name, monthlyAmount, onSuccess);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static void _showLogMonthlyDialog(BuildContext context, String memberId, String name, int amount, VoidCallback onSuccess) async {
    final now = DateTime.now();
    final periodController = TextEditingController(text: formatApiDate(now).substring(0, 7));
    final dateController = TextEditingController(text: formatApiDate(now));
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Log payment • $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Amount: ₹$amount (monthly)', style: GoogleFonts.poppins()),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('Period (YYYY-MM)'),
                subtitle: Text(periodController.text),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: now, firstDate: DateTime(2020), lastDate: now);
                  if (d != null) {
                    periodController.text = formatApiDate(d).substring(0, 7);
                    setState(() {});
                  }
                },
              ),
              ListTile(
                title: const Text('Payment date'),
                subtitle: Text(parseApiDate(dateController.text) != null ? formatDisplayDate(parseApiDate(dateController.text)) : dateController.text),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: now, firstDate: DateTime(2020), lastDate: now);
                  if (d != null) {
                    dateController.text = formatApiDate(d);
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final period = periodController.text.trim();
                final paymentDate = dateController.text.trim();
                Navigator.pop(ctx);
                try {
                  final r = await ApiClient.instance.post(
                    '/payments/log-monthly',
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'member_id': memberId, 'period': period, 'amount': amount, 'payment_date': paymentDate}),
                  );
                  if (r.statusCode >= 200 && r.statusCode < 300) {
                    ApiClient.instance.invalidateCache();
                    onSuccess();
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monthly payment logged')));
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
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
                    final issuedStr = issuedAt != null ? formatDisplayDate(parseApiDate(issuedAt.toString())) : null;
                    final paidStr = paidAt != null ? formatDisplayDate(parseApiDate(paidAt.toString())) : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(inv['member_name'] ?? ''),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('₹${inv['total']} • ${inv['status']} • #${inv['id']?.toString().substring(0, 8) ?? ''}'),
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
        title: Text('Invoice • ${inv['member_name']}'),
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
