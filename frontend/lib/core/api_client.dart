// ---------------------------------------------------------------------------
// API client – single HTTP client for all backend calls.
// ---------------------------------------------------------------------------
// Use [ApiClient.instance] for GET/POST. Handles base URL (env or saved),
// timeouts, optional GET cache, and DNS fallback (DoH) when device DNS fails.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Enterprise-grade API client: connection reuse, timeouts, optional GET cache.
/// Use [ApiClient.instance] everywhere instead of raw [http.get] for faster loads.
///
/// When device DNS fails (e.g. "Failed host lookup" on Android), falls back to
/// resolving the API host via DNS-over-HTTPS (Google) and connecting by IP.
///
/// For shared APK: build with --dart-define=API_BASE_URL=https://... or set URL in app.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  static const String _defaultBaseUrl = 'https://gymsaas-production-87a0.up.railway.app';
  static const String _prefsKey = 'api_base_url';

  /// Optional Bearer token for gym_admin / super_admin. When set, all get/post/patch/delete add Authorization header.
  static String? _authToken;
  static String? get authToken => _authToken;
  static set authToken(String? value) {
    _authToken = value;
  }

  /// Call after login with gym_admin or super_admin token; call with null on logout.
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Merge optional Authorization header for authenticated requests.
  static Map<String, String> _authHeaders(Map<String, String>? existing) {
    final m = Map<String, String>.from(existing ?? {});
    if (_authToken != null && _authToken!.isNotEmpty) {
      m['Authorization'] = 'Bearer $_authToken';
    }
    return m;
  }

  /// Runtime override (e.g. from SharedPreferences). Set via [loadSavedBaseUrl] or user "Set server URL".
  static String? _overrideBaseUrl;

  /// When host lookup fails, we resolve via DoH and cache host -> IP. Cleared when baseUrl changes.
  static final Map<String, String> _hostToIp = {};

  static String get baseUrl {
    final override = _overrideBaseUrl?.trim();
    if (override != null && override.isNotEmpty) {
      return override.endsWith('/') ? override.substring(0, override.length - 1) : override;
    }
    const fromEnv = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultBaseUrl,
    );
    return fromEnv.isEmpty ? _defaultBaseUrl : fromEnv;
  }

  static set overrideBaseUrl(String? value) {
    _overrideBaseUrl = value;
    _hostToIp.clear();
  }

  /// Call at startup to apply URL saved in SharedPreferences.
  static Future<void> loadSavedBaseUrl(Future<String?> Function() read) async {
    final saved = await read();
    if (saved != null && saved.trim().isNotEmpty) {
      _overrideBaseUrl = saved.trim();
    }
  }

  static String get prefsKey => _prefsKey;
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 25);
  static const Duration cacheTtl = Duration(seconds: 90);

  static const _dohUrl = 'https://dns.google/resolve';

  http.Client? _client;
  final Map<String, _CacheEntry> _getCache = {};

  http.Client get _clientOrCreate {
    _client ??= http.Client();
    return _client!;
  }

  Uri get _baseUri => Uri.parse(baseUrl);
  String get _host => _baseUri.host;
  bool get _isHttps => _baseUri.scheme == 'https';

  bool _isLookupError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('host lookup') ||
        s.contains('no address associated') ||
        s.contains('errno = 7') ||
        (e is SocketException && (e.osError?.errorCode == 7 || e.message.contains('lookup')));
  }

  /// Resolve host to IP via Google DNS-over-HTTPS. Returns null if DoH fails (e.g. no network).
  Future<String?> _resolveViaDoH(String host) async {
    try {
      final uri = Uri.parse('$_dohUrl?name=${Uri.encodeComponent(host)}&type=A');
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

  Future<String?> _resolveHost() async {
    final host = _host;
    if (host.isEmpty) return null;
    if (_hostToIp.containsKey(host)) return _hostToIp[host];
    final ip = await _resolveViaDoH(host);
    if (ip != null) _hostToIp[host] = ip;
    return ip;
  }

  /// Perform one request via resolved IP (HTTPS only), with Host header and cert check for intended hostname.
  Future<http.Response> _requestViaIp({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final host = _host;
    final ip = await _resolveHost();
    if (ip == null || ip.isEmpty) throw SocketException('Could not resolve host via DoH', osError: OSError('No address', 7));

    final pathWithQuery = queryParameters != null && queryParameters.isNotEmpty
        ? path + '?' + queryParameters.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')
        : path;
    final uri = Uri.parse('https://$ip$pathWithQuery');

    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = receiveTimeout;
    try {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        final sub = cert.subject.toLowerCase();
        return sub.contains(host.toLowerCase()) ||
            host.toLowerCase().contains('.railway.app') ||
            sub.contains('railway');
      };

      HttpClientRequest req;
      switch (method.toUpperCase()) {
        case 'GET':
          req = await client.getUrl(uri);
          break;
        case 'POST':
          req = await client.postUrl(uri);
          break;
        case 'PATCH':
          req = await client.patchUrl(uri);
          break;
        case 'DELETE':
          req = await client.deleteUrl(uri);
          break;
        default:
          req = await client.getUrl(uri);
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

  Future<http.Response> get(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool useCache = true,
  }) async {
    final uri = queryParameters != null && queryParameters.isNotEmpty
        ? Uri.parse(baseUrl + path).replace(queryParameters: queryParameters)
        : Uri.parse(baseUrl + path);
    final key = uri.toString();

    if (useCache && headers == null) {
      final cached = _getCache[key];
      if (cached != null && !cached.isExpired) {
        return http.Response(cached.body, cached.statusCode);
      }
    }

    try {
      final response = await _clientOrCreate
          .get(uri, headers: _authHeaders(headers))
          .timeout(receiveTimeout);

      if (useCache && headers == null && response.statusCode >= 200 && response.statusCode < 300) {
        _getCache[key] = _CacheEntry(
          body: response.body,
          statusCode: response.statusCode,
          cachedAt: DateTime.now(),
        );
      }
      return response;
    } catch (e) {
      if (_isHttps && _isLookupError(e)) {
        final fallback = await _requestViaIp(method: 'GET', path: path, queryParameters: queryParameters, headers: _authHeaders(headers));
        if (useCache && headers == null && fallback.statusCode >= 200 && fallback.statusCode < 300) {
          _getCache[key] = _CacheEntry(
            body: fallback.body,
            statusCode: fallback.statusCode,
            cachedAt: DateTime.now(),
          );
        }
        return fallback;
      }
      rethrow;
    }
  }

  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    try {
      final response = await _clientOrCreate
          .post(Uri.parse(baseUrl + path), headers: _authHeaders(headers), body: body, encoding: encoding)
          .timeout(receiveTimeout);
      _clearCache();
      return response;
    } catch (e) {
      if (_isHttps && _isLookupError(e)) {
        final r = await _requestViaIp(method: 'POST', path: path, headers: _authHeaders(headers), body: body, encoding: encoding);
        _clearCache();
        return r;
      }
      rethrow;
    }
  }

  Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    try {
      final response = await _clientOrCreate
          .patch(Uri.parse(baseUrl + path), headers: _authHeaders(headers), body: body, encoding: encoding)
          .timeout(receiveTimeout);
      _clearCache();
      return response;
    } catch (e) {
      if (_isHttps && _isLookupError(e)) {
        final r = await _requestViaIp(method: 'PATCH', path: path, headers: _authHeaders(headers), body: body, encoding: encoding);
        _clearCache();
        return r;
      }
      rethrow;
    }
  }

  /// For multipart file upload (e.g. import Excel/CSV).
  /// Prefer [fileBytes] when available (e.g. from file_picker with withData: true) so the file is read in memory and works on all platforms; otherwise uses [filePath].
  Future<http.Response> postMultipart(String path, {required String fileField, String? filePath, List<int>? fileBytes, String? filename}) async {
    final uri = Uri.parse(baseUrl + path);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_authHeaders(null));
    final String fname = filename ?? filePath?.split(RegExp(r'[/\\]')).last ?? 'file.csv';
    if (fileBytes != null && fileBytes.isNotEmpty) {
      request.files.add(http.MultipartFile.fromBytes(fileField, fileBytes, filename: fname));
    } else if (filePath != null && filePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath, filename: fname));
    } else {
      throw StateError('postMultipart: provide filePath or fileBytes');
    }
    const uploadTimeout = Duration(seconds: 60);
    final streamed = await request.send().timeout(uploadTimeout);
    return http.Response.fromStream(streamed).timeout(uploadTimeout);
  }

  Future<http.Response> delete(String path, {Map<String, String>? headers}) async {
    try {
      final response = await _clientOrCreate
          .delete(Uri.parse(baseUrl + path), headers: _authHeaders(headers))
          .timeout(receiveTimeout);
      _clearCache();
      return response;
    } catch (e) {
      if (_isHttps && _isLookupError(e)) {
        final r = await _requestViaIp(method: 'DELETE', path: path, headers: _authHeaders(null));
        _clearCache();
        return r;
      }
      rethrow;
    }
  }

  void _clearCache() {
    if (_getCache.isNotEmpty) _getCache.clear();
  }

  void invalidateCache() => _clearCache();

  void close() {
    _client?.close();
    _client = null;
    _clearCache();
  }
}

class _CacheEntry {
  final String body;
  final int statusCode;
  final DateTime cachedAt;

  _CacheEntry({required this.body, required this.statusCode, required this.cachedAt});

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > ApiClient.cacheTtl;
}
