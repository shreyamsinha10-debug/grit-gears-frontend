// DoH + IP fallback implementation for platforms with dart:io (Android, iOS, desktop).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  final uri = Uri.parse(baseUrl);
  final host = uri.host;
  if (host.isEmpty) return null;
  if (hostToIp.containsKey(host)) {
    // use cached IP
  } else {
    final ip = await _resolveViaDoH(host);
    if (ip != null) hostToIp[host] = ip;
  }
  final ip = hostToIp[host];
  if (ip == null || ip.isEmpty) return null;

  final pathWithQuery = queryParameters != null && queryParameters.isNotEmpty
      ? path + '?' + queryParameters.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')
      : path;
  final requestUri = Uri.parse('https://$ip$pathWithQuery');

  final client = HttpClient()
    ..connectionTimeout = connectTimeout
    ..idleTimeout = receiveTimeout;
  try {
    client.badCertificateCallback = (X509Certificate cert, String h, int port) {
      final sub = cert.subject.toLowerCase();
      return sub.contains(h.toLowerCase()) ||
          h.toLowerCase().contains('.railway.app') ||
          sub.contains('railway');
    };

    HttpClientRequest req;
    switch (method.toUpperCase()) {
      case 'GET':
        req = await client.getUrl(requestUri);
        break;
      case 'POST':
        req = await client.postUrl(requestUri);
        break;
      case 'PATCH':
        req = await client.patchUrl(requestUri);
        break;
      case 'DELETE':
        req = await client.deleteUrl(requestUri);
        break;
      default:
        req = await client.getUrl(requestUri);
    }

    req.headers.set('Host', host);
    if (headers != null) {
      for (final e in headers.entries) {
        req.headers.set(e.key, e.value);
      }
    }
    if (body != null && (method == 'POST' || method == 'PATCH')) {
      final bytes = encoding == null ? utf8.encode(body.toString()) : encoding.encode(body.toString());
      req.contentLength = bytes.length;
      req.add(bytes);
    }

    final response = await req.close();
    final bodyBytes = await consolidateHttpClientResponseBytes(response);
    return http.Response.bytes(bodyBytes, response.statusCode);
  } finally {
    client.close();
  }
}

Future<String?> _resolveViaDoH(String host) async {
  try {
    const dohUrl = 'https://dns.google/resolve';
    final uri = Uri.parse('$dohUrl?name=${Uri.encodeComponent(host)}&type=A');
    final c = http.Client();
    try {
      final r = await c.get(uri).timeout(const Duration(seconds: 10));
      c.close();
      if (r.statusCode != 200) return null;
      final map = jsonDecode(r.body) as Map<String, dynamic>?;
      final answer = map?['Answer'] as List<dynamic>?;
      if (answer == null || answer.isEmpty) return null;
      final data = (answer.first as Map<String, dynamic>)['data'] as String?;
      return data?.trim();
    } catch (_) {
      c.close();
      return null;
    }
  } catch (_) {
    return null;
  }
}
