import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'admin_push_channel.dart';

const _channelId = 'ktu_admin_alerts';
const _channelName = 'Admin alerts';
const _icon = 'ic_stat_admin';

final _local = FlutterLocalNotificationsPlugin();

const _localSettings = InitializationSettings(
  android: AndroidInitializationSettings(_icon),
);

AdminPushChannel createAdminPushChannel() => _AndroidChannel();

/// Notification payloads are shown by the system while the app is in the
/// background. This only covers a data-only message.
@pragma('vm:entry-point')
Future<void> adminFirebaseBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  final title = (message.data['title'] ?? '').trim();
  final body = (message.data['body'] ?? '').trim();
  if (title.isEmpty && body.isEmpty) return;
  try {
    await Firebase.initializeApp();
    await _local.initialize(settings: _localSettings);
    await _local.show(
      id: (message.messageId ?? '${DateTime.now().microsecondsSinceEpoch}')
          .hashCode
          .abs(),
      title: title.isEmpty ? 'KTU Assist Admin' : title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _icon,
        ),
      ),
      payload: (message.data['event'] ?? '').toString(),
    );
  } catch (_) {}
}

class _AndroidChannel implements AdminPushChannel {
  Future<void>? _starting;
  bool _failed = false;
  bool _asked = false;
  bool _listening = false;
  String _permission = 'default';
  void Function(String event)? _onOpen;

  @override
  bool get supported => Platform.isAndroid && !_failed;

  @override
  Future<String> permission() async {
    await _ensure();
    return supported ? _permission : 'unsupported';
  }

  @override
  Future<void> start({
    required void Function(String event) onOpen,
    required void Function() onToken,
  }) async {
    _onOpen = onOpen;
    await _ensure();
    if (!supported || _listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen((message) async {
      final title = (message.notification?.title ?? message.data['title'] ?? '')
          .trim();
      final body = (message.notification?.body ?? message.data['body'] ?? '')
          .trim();
      if (title.isEmpty && body.isEmpty) return;
      await _local.show(
        id: (message.messageId ?? '${DateTime.now().microsecondsSinceEpoch}')
            .hashCode
            .abs(),
        title: title.isEmpty ? 'KTU Assist Admin' : title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
            icon: _icon,
          ),
        ),
        payload: (message.data['event'] ?? '').toString(),
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _onOpen?.call((message.data['event'] ?? '').toString());
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => onToken());
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final event = (initial?.data['event'] ?? '').toString();
    if (event.isNotEmpty) _onOpen?.call(event);
  }

  @override
  Future<String> requestPermission() async {
    await _ensure();
    if (!supported) return 'unsupported';
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      _asked = true;
      _permission = _map(settings.authorizationStatus);
    } catch (_) {
      _permission = 'denied';
    }
    return _permission;
  }

  @override
  Future<String?> getToken() async {
    await _ensure();
    if (!supported) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensure() {
    if (!Platform.isAndroid) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(adminFirebaseBackgroundHandler);
      await _local.initialize(
        settings: _localSettings,
        onDidReceiveNotificationResponse: (response) {
          final event = response.payload ?? '';
          if (event.isNotEmpty) _onOpen?.call(event);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Signups, uploads, requests and review items',
              importance: Importance.high,
            ),
          );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      _permission = _map(settings.authorizationStatus);
    } catch (_) {
      _failed = true;
    }
  }

  String _map(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return 'granted';
      case AuthorizationStatus.notDetermined:
        return 'default';
      case AuthorizationStatus.denied:
        return Platform.isAndroid && !_asked ? 'default' : 'denied';
      case AuthorizationStatus.deniedPermanently:
        return 'denied';
    }
  }
}
