// ---------------------------------------------------------------------------
// Member Inbox – messages from gym admin (broadcasts and direct).
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../theme/app_theme.dart';

class MemberInboxScreen extends StatefulWidget {
  const MemberInboxScreen({super.key});

  @override
  State<MemberInboxScreen> createState() => _MemberInboxScreenState();
}

class _MemberInboxScreenState extends State<MemberInboxScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiClient.instance.get('/messages/inbox', useCache: false);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        final list = jsonDecode(r.body) as List<dynamic>? ?? [];
        setState(() {
          _messages = list.map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList();
          _loading = false;
        });
      } else if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      final dt = DateTime.tryParse(v.toString());
      return dt != null ? formatDisplayDateTime(dt) : v.toString();
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = LayoutConstants.screenPadding(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Inbox', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text('No messages yet', style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        Text('Your gym will send updates here.', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(padding),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: AppTheme.surfaceVariant,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.all(padding),
                          title: Text(
                            msg['title']?.toString() ?? '—',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _formatDate(msg['created_at']),
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  msg['body']?.toString() ?? '',
                                  style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface, height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
