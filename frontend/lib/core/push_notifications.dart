import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

class PushNotifications {
  PushNotifications._();

  static bool _initialized = false;
  static bool _backgroundHandlerSet = false;

  static Future<void> initForMember(String memberId) async {
    if (kIsWeb || memberId.trim().isEmpty) return;
    if (!_backgroundHandlerSet) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      _backgroundHandlerSet = true;
    }
    if (!_initialized) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // Firebase may be intentionally unconfigured in local/dev environments.
        return;
      }
      _initialized = true;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {}

    await _syncToken(memberId, await messaging.getToken());
    messaging.onTokenRefresh.listen((token) => _syncToken(memberId, token));
  }

  static Future<void> _syncToken(String memberId, String? token) async {
    if (token == null || token.trim().isEmpty) return;
    try {
      await ApiClient.instance.post(
        '/members/$memberId/device-token',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token.trim(),
          'platform': defaultTargetPlatform.name,
        }),
      );
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

