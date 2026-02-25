import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  static const FlutterSecureStorage _s = FlutterSecureStorage();

  static const String _kToken = 'Token';
  static const String _kExpiresAt = 'tokenExpiresAt';
  static const String _kClientType = 'clientType';
  static const String _kUserInfo = 'userInfo';

  static Future<void> clearAll() async {
    await _s.deleteAll();
  }

  /// IMPORTANT:
  /// If token is missing/empty -> clear everything to prevent stale values.
  static Future<String?> getToken() async {
    final t = await _s.read(key: _kToken);
    if (t == null || t.trim().isEmpty) {
      await clearAll();
      return null;
    }
    return t.trim();
  }

  static Future<void> saveLogin({
    required String tokenAccess,
    required String tokenExpiresAt,
    required String clientType,
    required Map<String, dynamic> userInfo,
  }) async {
    await _s.write(key: _kToken, value: tokenAccess);
    await _s.write(key: _kExpiresAt, value: tokenExpiresAt);
    await _s.write(key: _kClientType, value: clientType);
    await _s.write(key: _kUserInfo, value: jsonEncode(userInfo));
  }

  static Future<Map<String, dynamic>?> getUserInfo() async {
    // If token missing -> getToken() will clear all and return null
    final token = await getToken();
    if (token == null) return null;

    final raw = await _s.read(key: _kUserInfo);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// Returns true if expired, and clears everything when expired.
  static Future<bool> isTokenExpired() async {
    final token = await getToken();
    if (token == null) return true; // already cleared

    final expRaw = await _s.read(key: _kExpiresAt);
    if (expRaw == null || expRaw.trim().isEmpty) {
      await clearAll();
      return true;
    }

    final exp = DateTime.tryParse(expRaw);
    if (exp == null) {
      await clearAll();
      return true;
    }

    final expired = DateTime.now().isAfter(exp);
    if (expired) await clearAll();
    return expired;
  }
}
