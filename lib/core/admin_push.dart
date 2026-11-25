import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_event_routes.dart';
import 'admin_push_channel.dart';
import 'admin_push_factory.dart';
import 'api.dart';
import 'session.dart';

/// Registers this Android device for admin event pushes and opens the
/// matching screen when a notification is tapped.
class AdminPush {
  AdminPush._();
  static final AdminPush instance = AdminPush._();

  final AdminPushChannel _channel = createAdminPushChannel();
  NavigatorState? Function()? _navigator;
  String? _pendingEvent;
  bool _started = false;
  bool _syncing = false;

  bool get supported => _channel.supported;

  /// `granted`, `denied`, or `unsupported`.
  Future<String> permission() => _channel.permission();

  void attach(NavigatorState? Function() navigator) {
    _navigator = navigator;
    if (_started) return;
    _started = true;
    session.addListener(_onSession);
    unawaited(_start());
  }

  Future<void> _start() async {
    await _channel.start(
      onOpen: openEvent,
      onToken: () => unawaited(_syncToken()),
    );
    if (session.signedIn && session.pushEnabled == true) {
      final status = await _channel.permission();
      if (status == 'granted') await _syncToken();
    }
    _flushPending();
  }

  /// After a successful admin login. Asks for notification permission once.
  Future<void> registerAfterLogin() async {
    if (!supported || session.pushEnabled == false) return;
    try {
      final status = await _channel.requestPermission();
      if (status != 'granted') {
        await session.setPushEnabled(false);
        return;
      }
      await session.setPushEnabled(true);
      await _syncToken();
    } catch (_) {
      // Push stays optional. A failed register must not fail login.
    }
  }

  /// Master switch on the preferences screen.
  Future<String> setPhoneEnabled(bool enabled) async {
    if (!supported) return 'unsupported';
    if (!enabled) {
      await _unregister();
      await session.setPushEnabled(false);
      return 'denied';
    }
    final status = await _channel.requestPermission();
    if (status != 'granted') {
      await session.setPushEnabled(false);
      return status;
    }
    await session.setPushEnabled(true);
    await _syncToken();
    return 'granted';
  }

  void openEvent(String event) {
    if (event.isEmpty) return;
    if (!session.signedIn || _navigator?.call() == null) {
      _pendingEvent = event;
      return;
    }
    _pendingEvent = null;
    final nav = _navigator?.call();
    if (nav == null) return;
    final page = pageForAdminEvent(event);
    if (page == null) {
      nav.popUntil((route) => route.isFirst);
      return;
    }
    nav.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _onSession() {
    if (!session.signedIn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushPending());
  }

  void _flushPending() {
    final event = _pendingEvent;
    if (event == null || !session.signedIn) return;
    _pendingEvent = null;
    openEvent(event);
  }

  Future<void> _syncToken() async {
    if (!session.signedIn || session.pushEnabled != true || _syncing) return;
    _syncing = true;
    try {
      final token = await _channel.getToken();
      if (token == null || token.isEmpty || !session.signedIn) return;
      await api.post('user/push-tokens', {
        'token': token,
        'platform': 'android',
        'app': 'admin',
      });
      await session.setPushToken(token);
    } catch (_) {
      // The next token refresh or login tries again.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _unregister() async {
    final token = session.pushToken;
    await session.setPushToken(null);
    if (token == null || token.isEmpty || !session.signedIn) return;
    try {
      await api.delete('user/push-tokens', body: {'token': token});
    } catch (_) {}
  }
}
