import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'json.dart';

class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  late SharedPreferences _prefs;
  Json user = {};
  ThemeMode themeMode = ThemeMode.system;
  /// Shown once on the login screen after a forced sign-out (idle/session expiry).
  String? signedOutNotice;
  bool get signedIn => api.token != null && api.token!.isNotEmpty;
  String get name => str(user['name'], str(user['email'], 'Admin').split('@').first);
  String get role => pretty(str(user['role'], 'admin'));

  static const pushTokenKey = 'adminFcmToken';
  static const pushEnabledKey = 'adminPushEnabled';

  /// Null until the admin chooses. False means they turned this phone off.
  bool? get pushEnabled =>
      _prefs.containsKey(pushEnabledKey) ? _prefs.getBool(pushEnabledKey) : null;

  String? get pushToken => _prefs.getString(pushTokenKey);

  Future<void> setPushEnabled(bool enabled) async {
    await _prefs.setBool(pushEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setPushToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(pushTokenKey);
    } else {
      await _prefs.setString(pushTokenKey, token);
    }
  }

  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    api.token = _prefs.getString('token');
    user = asMap(jsonDecode(_prefs.getString('user') ?? '{}'));
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == _prefs.getString('theme'),
      orElse: () => ThemeMode.system,
    );
    api.onUnauthorized = (message) => signOut(
          remote: false,
          notice: (message != null && message.trim().isNotEmpty)
              ? message.trim()
              : 'Your admin session ended. Sign in again.',
        );
  }

  Future<void> signIn(String token, Json profile) async {
    api.token = token;
    user = profile;
    signedOutNotice = null;
    await _prefs.setString('token', token);
    await _prefs.setString('user', jsonEncode(profile));
    notifyListeners();
  }

  Future<void> signOut({bool remote = true, String? notice}) async {
    final pushToken = this.pushToken;
    if (remote && signedIn) {
      try {
        await api.post('logout', {
          if (pushToken != null && pushToken.isNotEmpty) 'token': pushToken,
        });
      } catch (_) {}
    }
    api.token = null;
    user = {};
    signedOutNotice = notice;
    await _prefs.remove('token');
    await _prefs.remove('user');
    await _prefs.remove(pushTokenKey);
    notifyListeners();
  }

  void clearSignedOutNotice() {
    if (signedOutNotice == null) return;
    signedOutNotice = null;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    await _prefs.setString('theme', mode.name);
    notifyListeners();
  }
}

final session = Session.instance;
