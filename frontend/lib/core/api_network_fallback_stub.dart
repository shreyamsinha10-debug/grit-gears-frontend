// Stub for platforms without dart:io (e.g. web). DoH/IP fallback is skipped.
import 'dart:convert';

import 'package:http/http.dart' as http;

Future<http.Response?> requestViaIp({
  required String baseUrl,
  required String path,
  required String method,
  Map<String, String>? queryParameters,
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  required Duration connectTimeout,
  required Duration receiveTimeout,
  required Map<String, String> hostToIp,
}) async {
  return null;
}
