// ---------------------------------------------------------------------------
// Occupancy heatmap – gym admin view of busy/quiet times.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _rangePreset = '14';
  DateTime? _customFrom;
  DateTime? _customTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    String? dateFrom;
    String? dateTo;
    if (_rangePreset == 'custom' && _customFrom != null && _customTo != null) {
      dateFrom = formatApiDate(_customFrom!);
      dateTo = formatApiDate(_customTo!);
    } else {
      final days = int.tryParse(_rangePreset) ?? 14;
      final to = DateTime.now();
      final from = to.subtract(Duration(days: days));
      dateFrom = formatApiDate(from);
      dateTo = formatApiDate(to);
    }
    try {
      final r = await ApiClient.instance.get(
        '/attendance/heatmap',
        queryParameters: {'date_from': dateFrom, 'date_to': dateTo},
        useCache: false,
      );
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        setState(() { _data = jsonDecode(r.body) as Map<String, dynamic>; _loading = false; });
      } else {
        setState(() { _error = 'Failed to load'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().split('\n').first; _loading = false; });
    }
  }

  Future<void> _pickCustomRange() async {
    final from = _customFrom ?? DateTime.now().subtract(const Duration(days: 14));
    final to = _customTo ?? DateTime.now();
    final pickedFrom = await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (pickedFrom == null || !mounted) return;
    final pickedTo = await showDatePicker(context: context, initialDate: to.isAfter(pickedFrom) ? to : pickedFrom, firstDate: pickedFrom, lastDate: DateTime.now());
    if (pickedTo == null || !mounted) return;
    setState(() {
      _customFrom = pickedFrom;
      _customTo = pickedTo;
      _rangePreset = 'custom';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final padding = LayoutConstants.screenPadding(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('Occupancy heatmap', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        leading: Tooltip(
          message: 'Back to dashboard',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(_error!, style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSummaryCards(),
                        const SizedBox(height: 24),
                        _buildRangeFilter(padding),
                        const SizedBox(height: 20),
                        _buildHeatmapSection(),
                        const SizedBox(height: 24),
                        _buildLegend(),
                        const SizedBox(height: 24),
                        _buildBusiestSection(),
                        const SizedBox(height: 24),
                        _buildQuietestSection(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _data?['today_summary'] as Map<String, dynamic>? ?? {};
    final checkIns = summary['check_ins'] as int? ?? 0;
    final currentlyIn = summary['currently_in_gym'] as int? ?? 0;
    final avgMin = summary['avg_duration_minutes'];
    final avgStr = avgMin != null ? '${avgMin} min' : '—';
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(title: 'Today\'s check-ins', value: '$checkIns', icon: FontAwesomeIcons.rightToBracket, color: AppTheme.success),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(title: 'Currently in gym', value: '$currentlyIn', icon: FontAwesomeIcons.peopleGroup, color: Colors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(title: 'Avg session', value: avgStr, icon: FontAwesomeIcons.clock, color: AppTheme.primary),
        ),
      ],
    );
  }

  Widget _buildRangeFilter(double padding) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date range', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RangeChip(label: 'Last 7 days', value: '7', selected: _rangePreset == '7', onTap: () { setState(() => _rangePreset = '7'); _load(); }),
            _RangeChip(label: 'Last 14 days', value: '14', selected: _rangePreset == '14', onTap: () { setState(() => _rangePreset = '14'); _load(); }),
            _RangeChip(label: 'Last 30 days', value: '30', selected: _rangePreset == '30', onTap: () { setState(() => _rangePreset = '30'); _load(); }),
            _RangeChip(
              label: _customFrom != null && _customTo != null ? '${_customFrom!.day}/${_customFrom!.month} – ${_customTo!.day}/${_customTo!.month}' : 'Custom',
              value: 'custom',
              selected: _rangePreset == 'custom',
              onTap: _pickCustomRange,
            ),
          ],
        ),
        if (_data?['date_from'] != null && _data?['date_to'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Showing ${_data!['date_from']} to ${_data!['date_to']}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          ),
      ],
    );
  }

  Widget _buildHeatmapSection() {
    final heatmap = _data?['heatmap'] as List<dynamic>? ?? [];
    if (heatmap.isEmpty) {
      return Card(
        color: AppTheme.surfaceVariant,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_on_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text('No attendance data in this range', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }
    // Fixed gym hours: 5 AM to 11 PM (hours 5–23)
    const int minHour = 5;
    const int maxHour = 23;
    final hourRange = List.generate(maxHour - minHour + 1, (i) => minHour + i);

    final grid = <String, Map<int, int>>{};
    final Set<String> dates = {};
    for (final e in heatmap) {
      final m = e as Map<String, dynamic>;
      final d = m['date_ist'] as String? ?? '';
      final h = m['hour'] as int? ?? 0;
      if (h < minHour || h > maxHour) continue;
      dates.add(d);
      grid.putIfAbsent(d, () => {});
      grid[d]![h] = m['count'] as int? ?? 0;
    }
    final dateList = dates.where((d) => d.isNotEmpty).toList()..sort();

    int maxCount = 1;
    for (final row in grid.values) {
      for (final c in row.values) {
        if (c > maxCount) maxCount = c;
      }
    }

    // Occupancy levels: Empty (0), Light (1–33%), Medium (33–66%), Heavy (66%+)
    Color colorForCount(int c) {
      if (c == 0) return const Color(0xFFE8F5E9); // light green – empty
      if (maxCount <= 0) return const Color(0xFFE8F5E9);
      final t = c / maxCount;
      if (t <= 0.33) return const Color(0xFFFFF9C4); // light yellow – light
      if (t <= 0.66) return const Color(0xFFFFB74D); // orange – medium
      return const Color(0xFFE57373); // red – heavy
    }

    String levelLabel(int c) {
      if (c == 0) return 'Empty';
      if (maxCount <= 0) return 'Empty';
      final t = c / maxCount;
      if (t <= 0.33) return 'Light';
      if (t <= 0.66) return 'Medium';
      return 'Heavy';
    }

    String hourAmPm(int h) {
      if (h < 12) return '${h == 0 ? 12 : h}AM';
      if (h == 12) return '12PM';
      return '${h - 12}PM';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Occupancy by day & time (5 AM – 11 PM)', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        const SizedBox(height: 6),
        Text('Green = empty • Yellow = light • Orange = medium • Red = heavy', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        Card(
          color: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hour header: 5AM ... 11PM
                    Row(
                      children: [
                        SizedBox(width: 52, child: Text('Date', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                        ...hourRange.map((h) => SizedBox(
                              width: 32,
                              child: Center(
                                child: Text(hourAmPm(h), style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey.shade600)),
                              ),
                            )),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...dateList.reversed.take(21).map((dateIst) {
                      final dayLabel = dateIst.length >= 10 ? '${dateIst.substring(8)}/${dateIst.substring(5, 7)}' : dateIst;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 52, child: Text(dayLabel, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade700))),
                            ...hourRange.map((h) {
                              final c = (grid[dateIst]?[h] ?? 0);
                              final color = colorForCount(c);
                              final label = levelLabel(c);
                              final fg = c > 0 && (color.value == 0xFFE57373 || color.value == 0xFFFFB74D) ? Colors.white : AppTheme.onSurface;
                              return Tooltip(
                                message: '${hourAmPm(h)}: $label${c > 0 ? ' ($c people)' : ''}',
                                child: Container(
                                  width: 30,
                                  height: 28,
                                  margin: const EdgeInsets.only(right: 2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300, width: 0.5),
                                  ),
                                  child: Center(
                                    child: c > 0
                                        ? Text('$c', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: fg))
                                        : null,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBusiestSection() {
    final slots = _data?['busiest_slots'] as List<dynamic>? ?? [];
    if (slots.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.whatshot, size: 20, color: Colors.deepOrange.shade700),
            const SizedBox(width: 8),
            Text('Peak hours (heavily occupied)', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          ],
        ),
        const SizedBox(height: 6),
        Text('These times are typically busiest – suggest other slots if customers want less crowd.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        Card(
          color: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: slots.take(10).map<Widget>((s) {
                final m = s as Map<String, dynamic>;
                final dow = m['day_of_week'] as String? ?? '';
                final h = m['hour'] as int? ?? 0;
                final avg = m['avg_count'];
                final hourStr = h <= 11 ? '${h == 0 ? 12 : h}:00 AM' : (h == 12 ? '12:00 PM' : '${h - 12}:00 PM');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.deepOrange.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Text('$dow $hourStr', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.deepOrange.shade900)),
                      ),
                      const SizedBox(width: 12),
                      Text('~${avg ?? 0} people on avg', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuietestSection() {
    final slots = _data?['quietest_slots'] as List<dynamic>? ?? [];
    if (slots.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 20, color: AppTheme.success),
            const SizedBox(width: 8),
            Text('Best times to suggest to customers', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Quietest slots (fewer people) – good for saving time.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        Card(
          color: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: slots.take(10).map<Widget>((s) {
                final m = s as Map<String, dynamic>;
                final dow = m['day_of_week'] as String? ?? '';
                final h = m['hour'] as int? ?? 0;
                final avg = m['avg_count'];
                final hourStr = h <= 11 ? '${h == 0 ? 12 : h}:00 AM' : (h == 12 ? '12:00 PM' : '${h - 12}:00 PM');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text('$dow $hourStr', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      ),
                      const SizedBox(width: 12),
                      Text('~${avg ?? 0} people on avg', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Occupancy levels', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _legendItem(const Color(0xFFE8F5E9), 'Empty', 'No one'),
            _legendItem(const Color(0xFFFFF9C4), 'Light', 'Few people'),
            _legendItem(const Color(0xFFFFB74D), 'Medium', 'Moderate'),
            _legendItem(const Color(0xFFE57373), 'Heavy', 'Peak time'),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label, String sub) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade400)),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            Text(sub, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.4))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaIcon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(title, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primary.withOpacity(0.2),
      checkmarkColor: AppTheme.primary,
    );
  }
}
