// ---------------------------------------------------------------------------
// Attendance report – view/filter check-in/out by date or range, delete record.
// ---------------------------------------------------------------------------
// Admin tab: fetches attendance via /attendance/by-date or by-date-range,
// displays [AttendanceEntry] list. Supports date picker and optional batch filter.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Breakpoint below which layout stacks vertically (e.g. title + button).
const double _attendanceNarrowBreakpoint = 480;

class AttendanceEntry {
  final String id;
  final String memberId;
  final String memberName;
  final String? memberPhone;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final String dateIst;
  final String batch;

  AttendanceEntry({
    required this.id,
    required this.memberId,
    required this.memberName,
    this.memberPhone,
    required this.checkInAt,
    this.checkOutAt,
    required this.dateIst,
    required this.batch,
  });

  String get durationMinutes {
    if (checkOutAt == null) return '—';
    final min = checkOutAt!.difference(checkInAt).inMinutes;
    if (min < 60) return '${min}m';
    return '${min ~/ 60}h ${min % 60}m';
  }

  factory AttendanceEntry.fromJson(Map<String, dynamic> json) {
    final checkInStr = json['check_in_at'] as String?;
    DateTime checkIn = DateTime.now();
    if (checkInStr != null) {
      final parsed = parseApiDateTime(checkInStr);
      if (parsed != null) checkIn = parsed;
      else checkIn = DateTime.parse(checkInStr);
    }
    DateTime? checkOut;
    final checkOutStr = json['check_out_at'] as String?;
    if (checkOutStr != null && checkOutStr.isNotEmpty) {
      checkOut = parseApiDateTime(checkOutStr) ?? DateTime.tryParse(checkOutStr);
    }
    return AttendanceEntry(
      id: json['id'] as String? ?? '',
      memberId: json['member_id'] as String? ?? '',
      memberName: json['member_name'] as String? ?? '',
      memberPhone: json['member_phone'] as String?,
      checkInAt: checkIn,
      checkOutAt: checkOut,
      dateIst: json['date_ist'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
    );
  }
}

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  List<AttendanceEntry> _entries = [];
  bool _loading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  bool _useRange = false;
  DateTime _rangeStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _rangeEnd = DateTime.now();
  Map<String, dynamic>? _summary;
  final _searchController = TextEditingController();
  String _filterBatch = 'All'; // All, Morning, Evening, Ladies

  @override
  void initState() {
    super.initState();
    _load();
    _loadSummary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final r = await ApiClient.instance.get('/attendance/summary', useCache: false);
      if (mounted && r.statusCode == 200) {
        setState(() => _summary = jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = _useRange
          ? await ApiClient.instance.get(
              '/attendance/by-date-range',
              queryParameters: {
                'date_from': formatApiDate(_rangeStart),
                'date_to': formatApiDate(_rangeEnd),
              },
              useCache: false,
            )
          : await ApiClient.instance.get(
              '/attendance/by-date',
              queryParameters: {'date': formatApiDate(_selectedDate)},
              useCache: false,
            );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final list = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          _entries = list.map((e) => AttendanceEntry.fromJson(e as Map<String, dynamic>)).toList();
          _loading = false;
          _error = null;
        });
        _loadSummary();
      } else {
        setState(() {
          _error = 'Failed to load attendance';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().split('\n').first;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  Future<void> _pickRange() async {
    final from = await showDatePicker(
      context: context,
      initialDate: _rangeStart,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: _rangeEnd.isBefore(from) ? from : _rangeEnd,
      firstDate: from,
      lastDate: DateTime.now(),
    );
    if (to != null && mounted) {
      setState(() {
        _rangeStart = from;
        _rangeEnd = to;
        _useRange = true;
      });
      _load();
    }
  }

  Future<void> _deleteAttendance(AttendanceEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove check-in?'),
        content: Text('Remove ${e.memberName} (${e.batch}) from this date? Use for wrong person or duplicate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final r = await ApiClient.instance.delete('/attendance/${e.id}');
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in removed')));
        _load();
        _loadSummary();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${r.statusCode}')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove')));
    }
  }

  static const _batchOrder = ['Morning', 'Evening', 'Ladies'];

  List<AttendanceEntry> _sortedByBatch() {
    final copy = List<AttendanceEntry>.from(_entries);
    copy.sort((a, b) {
      final ai = _batchOrder.indexOf(a.batch);
      final bi = _batchOrder.indexOf(b.batch);
      if (ai != bi) return ai.compareTo(bi);
      return a.checkInAt.compareTo(b.checkInAt);
    });
    return copy;
  }

  List<AttendanceEntry> _filteredEntries() {
    var list = _sortedByBatch();
    if (_filterBatch != 'All') list = list.where((e) => e.batch == _filterBatch).toList();
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final name = e.memberName.toLowerCase();
        final phone = (e.memberPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');
        return name.contains(q) || (qDigits.isNotEmpty && phone.contains(qDigits));
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = !_useRange && _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;
    final padding = LayoutConstants.screenPadding(context);
    final summary = _summary ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh attendance data',
            onPressed: _loading ? null : () { _load(); _loadSummary(); },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _load(); await _loadSummary(); },
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title and subtitle only (Manual Check-in removed)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Attendance', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.onSurface)),
                  const SizedBox(height: 4),
                  Text('Track member check-ins and gym visits.', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _SummaryCard('Today\'s Check-ins', '${summary['today_check_ins'] ?? 0}', Icons.login, Colors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard('Currently In Gym', '${summary['currently_in_gym'] ?? 0}', Icons.people, Colors.blue)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _SummaryCard('This Week', '${summary['this_week'] ?? 0}', Icons.calendar_today, Colors.purple)),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard('Average Daily', '${summary['average_daily'] ?? 0}', Icons.show_chart, Colors.grey)),
                ],
              ),
              const SizedBox(height: 24),
              // Date navigation: < Today >
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous day',
                    onPressed: _loading ? null : () {
                      setState(() {
                        if (_useRange) {
                          _rangeStart = _rangeStart.subtract(const Duration(days: 1));
                          _rangeEnd = _rangeEnd.subtract(const Duration(days: 1));
                        } else {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                        }
                      });
                      _load();
                    },
                  ),
                  TextButton(
                    onPressed: _loading ? null : () async {
                      if (_useRange) {
                        _pickRange();
                      } else {
                        await _pickDate();
                      }
                    },
                    child: Text(
                      _useRange ? '${formatDisplayDate(_rangeStart)} – ${formatDisplayDate(_rangeEnd)}' : (isToday ? 'Today' : formatDisplayDate(_selectedDate)),
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next day',
                    onPressed: _loading ? null : () {
                      final now = DateTime.now();
                      setState(() {
                        if (_useRange) {
                          if (_rangeEnd.isBefore(now)) {
                            _rangeStart = _rangeStart.add(const Duration(days: 1));
                            _rangeEnd = _rangeEnd.add(const Duration(days: 1));
                            if (_rangeEnd.isAfter(now)) _rangeEnd = now;
                          }
                        } else {
                          if (_selectedDate.isBefore(now)) _selectedDate = _selectedDate.add(const Duration(days: 1));
                          if (_selectedDate.isAfter(now)) _selectedDate = now;
                        }
                      });
                      _load();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: () => setState(() { _useRange = false; _load(); }), child: const Text('Day')),
                  TextButton(onPressed: _loading ? null : _pickRange, child: const Text('Range')),
                ],
              ),
              const SizedBox(height: 16),
              // Search and filter – stack on narrow
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < _attendanceNarrowBreakpoint;
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by name or phone...',
                            prefixIcon: const Icon(Icons.search, size: 22),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _filterBatch,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: ['All', 'Morning', 'Evening', 'Ladies'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setState(() => _filterBatch = v ?? 'All'),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by name or phone...',
                            prefixIcon: const Icon(Icons.search, size: 22),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _filterBatch,
                        items: ['All', 'Morning', 'Evening', 'Ladies'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setState(() => _filterBatch = v ?? 'All'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Section title and header row for records
              Text('Attendance Records', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              else if (_filteredEntries().isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        Text('No attendance records found', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useTable = constraints.maxWidth > 500;
                    final list = _filteredEntries();
                    if (useTable) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: MaterialStateProperty.all<Color?>(AppTheme.primary.withOpacity(0.08)),
                          columns: const [
                            DataColumn(label: Text('Member', style: TextStyle(fontWeight: FontWeight.w600))),
                            DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.w600))),
                            DataColumn(label: Text('Check-in', style: TextStyle(fontWeight: FontWeight.w600))),
                            DataColumn(label: Text('Check-out', style: TextStyle(fontWeight: FontWeight.w600))),
                            DataColumn(label: Text('Duration', style: TextStyle(fontWeight: FontWeight.w600))),
                            DataColumn(label: Text('Batch', style: TextStyle(fontWeight: FontWeight.w600))),
                            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600))),
                          ],
                          rows: list.map((e) => DataRow(
                            cells: [
                              DataCell(Text(e.memberName)),
                              DataCell(Text(e.memberPhone ?? '—')),
                              DataCell(Text(formatDisplayTime(e.checkInAt))),
                              DataCell(Text(e.checkOutAt != null ? formatDisplayTime(e.checkOutAt!) : '—')),
                              DataCell(Text(e.durationMinutes)),
                              DataCell(Text(e.batch)),
                              DataCell(Tooltip(
                                message: 'Remove this attendance record',
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _deleteAttendance(e),
                                  color: Colors.red,
                                ),
                              )),
                            ],
                          )).toList(),
                        ),
                      );
                    }
                    // Mobile: header row + Column of cards (no nested ListView to avoid viewport crash)
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(bottom: BorderSide(color: AppTheme.primary.withOpacity(0.3))),
                          ),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text('Member', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurface), overflow: TextOverflow.ellipsis)),
                              Expanded(child: Text('In', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                              Expanded(child: Text('Out', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                              Expanded(child: Text('Dur.', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 40),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...List.generate(list.length * 2 - 1, (index) {
                          if (index.isOdd) return const SizedBox(height: 8);
                          final e = list[index ~/ 2];
                          return _AttendanceRecordCard(
                            entry: e,
                            onDelete: () => _deleteAttendance(e),
                          );
                        }),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single attendance record card for mobile list (avoids nested ListView viewport crash).
class _AttendanceRecordCard extends StatelessWidget {
  final AttendanceEntry entry;
  final VoidCallback onDelete;

  const _AttendanceRecordCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppTheme.surfaceVariant.withOpacity(0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.memberName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    if (e.memberPhone != null && e.memberPhone!.isNotEmpty)
                      Text(
                        e.memberPhone!.length > 12 ? '${e.memberPhone!.substring(0, 12)}…' : e.memberPhone!,
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(e.batch, style: GoogleFonts.poppins(fontSize: 11, color: AppTheme.primary)),
                  ],
                ),
              ),
              Expanded(child: Text(formatDisplayTime(e.checkInAt), style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
              Expanded(child: Text(e.checkOutAt != null ? formatDisplayTime(e.checkOutAt!) : '—', style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
              Expanded(child: Text(e.durationMinutes, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
                color: Colors.red,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.5))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(value, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.onSurface)),
            const SizedBox(height: 4),
            Text(title, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}
