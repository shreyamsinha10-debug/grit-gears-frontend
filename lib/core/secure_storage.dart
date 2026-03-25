// ---------------------------------------------------------------------------
// Secure storage – admin phone, PIN, and theme preference.
// ---------------------------------------------------------------------------
// Uses Android Keystore / iOS Keychain so credentials are not stored in plain
// SharedPreferences. Required for Play Store policy. Theme (dark/light) is
// stored here so it persists across app restarts.
// ---------------------------------------------------------------------------

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure key-value storage for sensitive data (admin phone, PIN).
/// Uses platform secure storage (Android Keystore / iOS Keychain) for Play Store compliance.
class SecureStorage {
  SecureStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const String _keyAdminPhone = 'admin_phone';
  static const String _keyAdminPin = 'admin_pin';
  static const String _keyThemeDark = 'theme_dark';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyAuthRole = 'auth_role';

  static Future<String?> getAuthToken() => _storage.read(key: _keyAuthToken);
  static Future<void> setAuthToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _keyAuthToken);
      await _storage.delete(key: _keyAuthRole);
    } else {
      await _storage.write(key: _keyAuthToken, value: value);
    }
  }

  static Future<String?> getAuthRole() => _storage.read(key: _keyAuthRole);
  static Future<void> setAuthRole(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _keyAuthRole);
    } else {
      await _storage.write(key: _keyAuthRole, value: value);
    }
  }

  static Future<String?> getAdminPhone() => _storage.read(key: _keyAdminPhone);
  static Future<void> setAdminPhone(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _keyAdminPhone);
    } else {
      await _storage.write(key: _keyAdminPhone, value: value);
    }
  }

  static Future<String?> getAdminPin() => _storage.read(key: _keyAdminPin);
  static Future<void> setAdminPin(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _keyAdminPin);
    } else {
      await _storage.write(key: _keyAdminPin, value: value);
    }
  }

  static Future<bool> getThemeDark() async {
    final v = await _storage.read(key: _keyThemeDark);
    return v == 'true';
  }

  static Future<void> setThemeDark(bool value) async {
    await _storage.write(key: _keyThemeDark, value: value.toString());
  }
}
