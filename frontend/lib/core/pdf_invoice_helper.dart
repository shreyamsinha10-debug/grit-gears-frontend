import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/app_theme.dart' show defaultGymName, defaultLogoAsset;

class PdfInvoiceHelper {
  /// [gymProfile] optional: { name, logo_base64, invoice_name } from GET /gym/profile. If provided, logo and name are used on the invoice.
  static Future<void> generateAndPrint(Map<String, dynamic> invoice, {Map<String, dynamic>? gymProfile}) async {
    final pdf = await _generatePdf(invoice, gymProfile: gymProfile);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Invoice-${invoice['id']}',
    );
  }

  static Future<pw.Document> _generatePdf(Map<String, dynamic> invoice, {Map<String, dynamic>? gymProfile}) async {
    final pdf = pw.Document();

    // Logo: prefer gym profile logo (base64), else fallback to asset
    pw.MemoryImage? logoImage;
    try {
      final logoBase64 = gymProfile?['logo_base64'] as String?;
      if (logoBase64 != null && logoBase64.isNotEmpty) {
        final bytes = base64Decode(logoBase64);
        logoImage = pw.MemoryImage(bytes);
      }
      if (logoImage == null) {
        final logoBytes = await rootBundle.load(defaultLogoAsset);
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      }
    } catch (_) {}

    // Gym / invoice name: from profile or default
    final gymDisplayName = gymProfile != null
        ? ((gymProfile['invoice_name'] as String?)?.trim().isNotEmpty == true
            ? (gymProfile['invoice_name'] as String).trim()
            : (gymProfile['name'] as String?)?.trim() ?? defaultGymName)
        : defaultGymName;
    final invoiceNo = invoice['id']?.toString().substring(0, 8).toUpperCase() ?? '';
    final date = invoice['issued_at'] != null
        ? DateTime.parse(invoice['issued_at'].toString()).toLocal().toString().split(' ')[0]
        : '';
    final memberName = invoice['member_name'] ?? '';
    final memberId = invoice['member_id']?.toString().substring(0, 8).toUpperCase() ?? '';
    final total = invoice['total']?.toString() ?? '0';
    
    // Find period from items if possible, or use current month
    String period = '';
    final items = invoice['items'] as List<dynamic>? ?? [];
    for (var item in items) {
      final desc = item['description']?.toString() ?? '';
      if (desc.contains('Monthly Fee')) {
        final match = RegExp(r'\((.*?)\)').firstMatch(desc);
        if (match != null) {
          period = match.group(1) ?? '';
          break;
        }
      }
    }
    if (period.isEmpty) {
      period = DateTime.now().toString().substring(0, 7);
    }

    // Colors
    final redColor = PdfColor.fromInt(0xFFD32F2F);
    final blackColor = PdfColor.fromInt(0xFF000000);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: redColor, width: 2),
            ),
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        width: 50,
                        height: 50,
                        child: pw.Image(logoImage),
                      ),
                    pw.SizedBox(width: 16),
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Text(
                            gymDisplayName,
                            style: pw.TextStyle(
                              fontSize: 32,
                              fontWeight: pw.FontWeight.bold,
                              color: redColor,
                              font: pw.Font.timesBold(),
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Doctor Colony, (Opp. of Arogya Nursing Home), P.O.- Chanchal, Dist- Malda, 732123',
                            style: const pw.TextStyle(fontSize: 10),
                            textAlign: pw.TextAlign.center,
                          ),
                          pw.Text(
                            'Ph no 9681007337/8171709657, Email address:miya.shah@gmail.com',
                            style: const pw.TextStyle(fontSize: 10),
                            textAlign: pw.TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),

                // Payment Slip Title
                pw.Center(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    color: redColor,
                    child: pw.Text(
                      'Payment Slip',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),

                // Fields
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('No. $invoiceNo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: $date'),
                  ],
                ),
                pw.SizedBox(height: 12),

                pw.Row(
                  children: [
                    pw.Text('Fees received from: '),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(style: pw.BorderStyle.dotted)),
                        ),
                        child: pw.Text(' $memberName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Text('Regd. No. '),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(style: pw.BorderStyle.dotted)),
                      ),
                      child: pw.Text(' $memberId'),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),

                pw.Row(
                  children: [
                    pw.Text('in the amount of Rs. '),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(style: pw.BorderStyle.dotted)),
                        ),
                        child: pw.Text(' $total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Text('for the month of '),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(style: pw.BorderStyle.dotted)),
                      ),
                      child: pw.Text(' $period'),
                    ),
                  ],
                ),
                pw.Spacer(),

                // Footer
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Note : Fees are non refundable',
                      style: pw.TextStyle(color: redColor, fontStyle: pw.FontStyle.italic, fontSize: 10),
                    ),
                    pw.Column(
                      children: [
                        pw.Container(width: 100, height: 1, color: blackColor),
                        pw.SizedBox(height: 4),
                        pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf;
  }
}
