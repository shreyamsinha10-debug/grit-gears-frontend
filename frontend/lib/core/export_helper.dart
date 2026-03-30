// ---------------------------------------------------------------------------
// Export helper – download Excel exports from backend and save (web-safe).
// ---------------------------------------------------------------------------
// Uses file_saver package: works on web (trigger download) and mobile
// (saves to Downloads/app directory). No dart:io.
// ---------------------------------------------------------------------------

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Downloads an export file from the API and saves it (web: download, mobile: Downloads).
/// Returns a non-null label on success (e.g. filename), null on failure.
Future<String?> saveExportToDownloads(String path, String filename) async {
  try {
    final response = await ApiClient.instance.get(path, useCache: false);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return null;

    final name = filename.contains('.') ? filename.split('.').first : filename;
    final ext = filename.contains('.') ? filename.split('.').last : 'xlsx';
    final mimeType = ext == 'xlsx' || ext == 'xls'
        ? MimeType.microsoftExcel
        : (ext == 'csv' ? MimeType.csv : MimeType.other);

    await FileSaver.instance.saveFile(
      name: name,
      bytes: Uint8List.fromList(bytes),
      fileExtension: ext,
      mimeType: mimeType,
    );
    return filename;
  } catch (_) {
    return null;
  }
}

/// User-facing label for the save location.
Future<String> exportLocationLabel() async {
  if (kIsWeb) return 'Downloads';
  return 'Downloads';
}
