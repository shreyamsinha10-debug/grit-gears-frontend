// ---------------------------------------------------------------------------
// API client – single HTTP client for all backend calls.
// ---------------------------------------------------------------------------
// Use [ApiClient.instance] for GET/POST. Handles base URL (env or saved),
// timeouts, optional GET cache. On mobile, DNS fallback (DoH) when device DNS fails.
// No dart:io so web builds are safe.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

import 'api_network_fallback_stub.dart' if (dart.library.io) 'api_network_fallback_io.dart' as network_fallback;

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

  static const String _defaultBaseUrl = 'https://gymsaas-production-b4a0.up.railway.app';
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

  http.Client? _client;
  final Map<String, _CacheEntry> _getCache = {};

  http.Client get _clientOrCreate {
    _client ??= http.Client();
    return _client!;
  }

  Uri get _baseUri => Uri.parse(baseUrl);
  bool get _isHttps => _baseUri.scheme == 'https';

  bool _isLookupError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('host lookup') ||
        s.contains('no address associated') ||
        s.contains('errno = 7') ||
        s.contains('lookup');
  }

  Future<http.Response?> _requestViaIp({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return network_fallback.requestViaIp(
      baseUrl: baseUrl,
      path: path,
      method: method,
      queryParameters: queryParameters,
      headers: headers,
      body: body,
      encoding: encoding,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      hostToIp: _hostToIp,
    );
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
        if (fallback != null && useCache && headers == null && fallback.statusCode >= 200 && fallback.statusCode < 300) {
          _getCache[key] = _CacheEntry(
            body: fallback.body,
            statusCode: fallback.statusCode,
            cachedAt: DateTime.now(),
          );
        }
        if (fallback != null) return fallback;
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
        if (r != null) {
          _clearCache();
          return r;
        }
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
        if (r != null) {
          _clearCache();
          return r;
        }
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
        if (r != null) {
          _clearCache();
          return r;
        }
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

  // --- Typed response parsers (use with response.body when statusCode is 2xx) ---

  static Member parseMember(String body) {
    return Member.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  static List<Member> parseMembers(String body) {
    final list = jsonDecode(body) as List<dynamic>? ?? [];
    return list.map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
  }

  static GymProfile parseGymProfile(String body) {
    return GymProfile.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  static List<Payment> parsePayments(String body) {
    return Payment.fromJsonList(jsonDecode(body));
  }

  static List<Invoice> parseInvoices(String body) {
    return Invoice.fromJsonList(jsonDecode(body));
  }

  static List<AttendanceRecord> parseAttendanceRecords(String body) {
    return AttendanceRecord.fromJsonList(jsonDecode(body));
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
