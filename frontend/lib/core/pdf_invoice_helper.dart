import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/app_theme.dart' show defaultGymName;
import 'date_utils.dart';

/// Converts an integer amount to Indian Rupees in words (e.g. "Rupees Two Thousand One Hundred Only").
String _amountInWords(int amount) {
  if (amount <= 0) return 'Rupees Zero Only';
  const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  String word(int n) {
    if (n == 0) return '';
    if (n < 20) return ones[n];
    if (n < 100) return '${tens[n ~/ 10]} ${word(n % 10)}'.trim();
    if (n < 1000) return '${ones[n ~/ 100]} Hundred ${word(n % 100)}'.trim();
    if (n < 100000) return '${word(n ~/ 1000)} Thousand ${word(n % 1000)}'.trim();
    if (n < 10000000) return '${word(n ~/ 100000)} Lakh ${word(n % 100000)}'.trim();
    return '${word(n ~/ 10000000)} Crore ${word(n % 10000000)}'.trim();
  }
  return 'Rupees ${word(amount)} Only';
}

class PdfInvoiceHelper {
  /// Generates a simple, standard PDF invoice. [gymProfile] optional: name, invoice_name, address_line1. No logo.
  static Future<void> generateAndPrint(Map<String, dynamic> invoice, {Map<String, dynamic>? gymProfile}) async {
    final pdf = await _generatePdf(invoice, gymProfile: gymProfile);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Invoice-${invoice['bill_number'] ?? invoice['id']}',
    );
  }

  static Future<pw.Document> _generatePdf(Map<String, dynamic> invoice, {Map<String, dynamic>? gymProfile}) async {
    final pdf = pw.Document();

    final gymName = gymProfile != null
        ? ((gymProfile['invoice_name'] as String?)?.trim().isNotEmpty == true
            ? (gymProfile['invoice_name'] as String).trim()
            : (gymProfile['name'] as String?)?.trim() ?? defaultGymName)
        : defaultGymName;
    final gymContact = gymProfile?['phone']?.toString() ?? gymProfile?['contact']?.toString() ?? '';
    final gymEmail = gymProfile?['email']?.toString() ?? '';

    final billNo = invoice['bill_number']?.toString() ?? 'BILL-${invoice['id']?.toString().substring(0, 8) ?? ''}';
    final dateStr = invoice['issued_at'] != null
        ? formatDisplayDate(parseApiDateTime(invoice['issued_at'].toString()))
        : formatDisplayDate(DateTime.now());
    final paidDateStr = invoice['paid_at'] != null
        ? formatDisplayDate(parseApiDateTime(invoice['paid_at'].toString()))
        : dateStr;

    final memberName = invoice['member_name']?.toString() ?? '';
    final memberPhone = invoice['member_phone']?.toString() ?? '';
    final memberEmail = invoice['member_email']?.toString() ?? '';
    final batch = invoice['batch']?.toString() ?? '';

    final total = (invoice['total'] as num?)?.toInt() ?? 0;
    final totalFormatted = _formatAmount(total);
    final amountWords = _amountInWords(total);

    final items = invoice['items'] as List<dynamic>? ?? [];
    final paymentMethod = (invoice['payment_method']?.toString() ?? 'Cash').toLowerCase();
    final isPaid = invoice['status']?.toString() == 'Paid';

    final black = PdfColors.black;
    final grey = PdfColor.fromInt(0xFF616161);
    final green = PdfColor.fromInt(0xFF2E7D32);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Title ─────────────────────────────────────────────────
              pw.Center(
                child: pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: black),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Invoice No: $billNo', style: pw.TextStyle(fontSize: 10, color: black)),
                  pw.Text('Date: $dateStr', style: pw.TextStyle(fontSize: 10, color: black)),
                ],
              ),
              pw.SizedBox(height: 20),

              // ── From / Bill To ─────────────────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('From', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: grey)),
                        pw.SizedBox(height: 4),
                        pw.Text(gymName, style: const pw.TextStyle(fontSize: 10)),
                        if (gymContact.isNotEmpty) pw.Text(gymContact, style: const pw.TextStyle(fontSize: 9)),
                        if (gymEmail.isNotEmpty) pw.Text(gymEmail, style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Bill To', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: grey)),
                        pw.SizedBox(height: 4),
                        pw.Text(memberName, style: const pw.TextStyle(fontSize: 10)),
                        if (memberPhone.isNotEmpty) pw.Text(memberPhone, style: const pw.TextStyle(fontSize: 9)),
                        if (memberEmail.isNotEmpty) pw.Text(memberEmail, style: const pw.TextStyle(fontSize: 9)),
                        if (batch.isNotEmpty) pw.Text('Batch: $batch', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // ── Table: #, Description, Rate, Amount ──────────────────────
              pw.Table(
                border: pw.TableBorder.all(color: grey, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.6),
                  1: const pw.FlexColumnWidth(4),
                  2: const pw.FlexColumnWidth(1.2),
                  3: const pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
                    children: [
                    _cell(' # ', 9, true),
                    _cell(' Description ', 9, true),
                    _cell(' Rate ', 9, true),
                    _cell(' Amount ', 9, true),
                  ]),
                  ...List.generate(items.length, (i) {
                    final item = items[i] as Map<String, dynamic>? ?? {};
                    final desc = item['description']?.toString() ?? '';
                    final amt = (item['amount'] as num?)?.toInt() ?? 0;
                    final amtStr = _formatAmount(amt);
                    return pw.TableRow(
                      children: [
                        _cell(' ${i + 1} ', 9, false),
                        _cell(' $desc ', 9, false),
                        _cell(' $amtStr ', 9, false),
                        _cell(' $amtStr ', 9, false),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 12),

              // ── Subtotal / Total / Amount Paid ─────────────────────────
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.SizedBox(
                  width: 180,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _summaryRow('Subtotal', totalFormatted),
                      _summaryRow('Total Amount', totalFormatted),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 4),
                          child: pw.Text('Amount Paid: -$totalFormatted', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: green)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 10),

              // ── Amount in words ─────────────────────────────────────────
              pw.Text('Amount in words: $amountWords', style: pw.TextStyle(fontSize: 9, color: grey, fontStyle: pw.FontStyle.italic)),
              pw.SizedBox(height: 16),

              // ── Payment status (PAID) ──────────────────────────────────
              if (isPaid)
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: pw.BoxDecoration(color: PdfColor.fromInt(0x26E8F5E9), borderRadius: pw.BorderRadius.circular(6)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PAID', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: green)),
                      pw.SizedBox(height: 4),
                      pw.Text('Method: $paymentMethod', style: pw.TextStyle(fontSize: 10, color: black)),
                      pw.Text('Date: $paidDateStr', style: pw.TextStyle(fontSize: 10, color: black)),
                    ],
                  ),
                ),
              pw.SizedBox(height: 24),

              // ── Footer notes ─────────────────────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: grey, width: 0.3)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('1. Membership fees are non-refundable.', style: pw.TextStyle(fontSize: 8, color: grey)),
                    pw.Text('2. This invoice is valid for the period mentioned.', style: pw.TextStyle(fontSize: 8, color: grey)),
                    pw.Text('3. For queries, please contact the gym.', style: pw.TextStyle(fontSize: 8, color: grey)),
                    pw.SizedBox(height: 6),
                    pw.Text('This is a computer generated invoice.', style: pw.TextStyle(fontSize: 8, color: grey, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _cell(String text, double fontSize, bool bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  static pw.Widget _summaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static String _formatAmount(int n) {
    if (n >= 1000) {
      final s = n.toString();
      final len = s.length;
      if (len <= 3) return s;
      return '${s.substring(0, len - 3)},${s.substring(len - 3)}';
    }
    return n.toString();
  }
}
