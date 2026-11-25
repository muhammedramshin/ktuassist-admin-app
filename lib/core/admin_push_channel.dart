import 'package:flutter/foundation.dart';

/// Firebase messaging entry points. Android uses [createAdminPushChannel]
/// from the IO library; other platforms use the stub.
abstract class AdminPushChannel {
  bool get supported;

  /// `granted`, `denied`, `default`, or `unsupported`.
  Future<String> permission();

  Future<void> start({
    required void Function(String event) onOpen,
    required void Function() onToken,
  });

  Future<String> requestPermission();

  Future<String?> getToken();
}

/// Referenced so this library is not tree-shaken as unused on web.
bool get adminPushChannelApi => kIsWeb;
