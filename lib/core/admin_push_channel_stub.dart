import 'admin_push_channel.dart';

AdminPushChannel createAdminPushChannel() => _StubChannel();

class _StubChannel implements AdminPushChannel {
  @override
  bool get supported => false;

  @override
  Future<String> permission() async => 'unsupported';

  @override
  Future<void> start({
    required void Function(String event) onOpen,
    required void Function() onToken,
  }) async {}

  @override
  Future<String> requestPermission() async => 'unsupported';

  @override
  Future<String?> getToken() async => null;
}
