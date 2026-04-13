import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuthLocalStorage {
  static const String _tokenKey = 'auth_user_token';
  static const String _userKey = 'auth_user_payload';
  static const int _maxCachedAvatarLength = 180000;

  Future<void> saveSession({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(_sanitizeUserForCache(user)));
  }

  Future<String?> readToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, dynamic>?> readUser() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final Object decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<void> updateUser(Map<String, dynamic> user) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_sanitizeUserForCache(user)));
  }

  Map<String, dynamic> _sanitizeUserForCache(Map<String, dynamic> user) {
    final Map<String, dynamic> sanitized = Map<String, dynamic>.from(user);
    final Object? avatar = sanitized['avatar_data_url'];

    if (avatar is String && avatar.length > _maxCachedAvatarLength) {
      sanitized.remove('avatar_data_url');
    }

    return sanitized;
  }

  Future<void> clearSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
