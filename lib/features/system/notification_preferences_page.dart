import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/admin_push.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/session.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';

class _EventPref {
  _EventPref(this.key, this.label, this.group, this.enabled);
  final String key;
  final String label;
  final String group;
  bool enabled;
}

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  List<_EventPref> events = [];
  bool loading = true;
  String? error;
  String phone = 'default';
  String? saving;
  bool testing = false;
  List<Json> deliveries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final status = await AdminPush.instance.permission();
      final res = await api.get('admin/notification-preferences');
      final log = await api.get('admin/notification-deliveries');
      final rows = rowsOf(res, const ['events']);
      if (!mounted) return;
      setState(() {
        phone = status;
        events = [
          for (final row in rows)
            _EventPref(
              str(row['key']),
              str(row['label'], str(row['key'])),
              str(row['group'], 'Other'),
              row['enabled'] == true ||
                  row['enabled'] == 1 ||
                  str(row['enabled']) == 'true',
            ),
        ];
        deliveries = rowsOf(log);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = errorText(e, 'Could not load notification settings.');
      });
    }
  }

  bool get _phoneOn => session.pushEnabled == true && phone == 'granted';

  Future<void> _setPhone(bool enabled) async {
    final status = await AdminPush.instance.setPhoneEnabled(enabled);
    if (!mounted) return;
    setState(() => phone = status);
    if (enabled && status != 'granted') {
      toast(
        context,
        status == 'unsupported'
            ? 'Notifications on this phone are only available on Android.'
            : 'Allow notifications for KTU Assist Admin to receive alerts.',
        error: true,
      );
    }
  }

  Future<void> _setEvent(_EventPref event, bool enabled) async {
    final previous = event.enabled;
    setState(() {
      event.enabled = enabled;
      saving = event.key;
    });
    try {
      await api.put('admin/notification-preferences', {
        'events': {event.key: enabled},
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => event.enabled = previous);
      toast(context, errorText(e, 'Could not save that setting.'), error: true);
    } finally {
      if (mounted) setState(() => saving = null);
    }
  }

  Future<void> _sendTest() async {
    setState(() => testing = true);
    try {
      final res = asMap(await api.post('admin/notification-preferences/test'));
      if (!mounted) return;
      toast(context, str(res['message'], 'Test notification sent.'));
    } catch (e) {
      if (!mounted) return;
      toast(context, errorText(e, 'Could not send the test notification.'), error: true);
    } finally {
      if (mounted) {
        setState(() => testing = false);
        await _load();
      }
    }
  }

  String _when(String raw) {
    final time = DateTime.tryParse(raw)?.toLocal();
    if (time == null) return raw;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.day}/${time.month} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_EventPref>>{};
    for (final event in events) {
      groups.putIfAbsent(event.group, () => []).add(event);
    }
    return AppPage(
      title: 'Notifications',
      subtitle: 'Choose which events reach this phone.',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      maxWidth: 760,
      children: [
        const SectionHeader('This phone'),
        Panel(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notifications on this phone'),
            subtitle: Text(
              AdminPush.instance.supported
                  ? 'Android alerts for the events you leave on.'
                  : 'Available on the Android admin app.',
            ),
            value: _phoneOn,
            onChanged: AdminPush.instance.supported
                ? (value) => unawaited(_setPhone(value))
                : null,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: testing ? null : () => unawaited(_sendTest()),
          icon: testing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.notifications_active_outlined),
          label: Text(testing ? 'Sending test…' : 'Send test notification'),
        ),
        const SectionHeader('Recent alerts'),
        if (deliveries.isEmpty)
          const Panel(child: Text('No admin alerts have been sent yet.'))
        else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final row in deliveries)
                  ListTile(
                    title: Text(str(row['event_label'], str(row['title']))),
                    subtitle: Text(
                      [
                        str(row['body']),
                        if (str(row['error']).isNotEmpty) str(row['error']),
                        [
                          _when(str(row['created_at'])),
                          if (str(dig(row, 'recipient.name')).isNotEmpty) str(dig(row, 'recipient.name')),
                          if (str(row['token_suffix']).isNotEmpty) 'device …${str(row['token_suffix'])}',
                        ].where((part) => part.isNotEmpty).join(' · '),
                      ].where((part) => part.isNotEmpty).join('\n'),
                    ),
                    trailing: Pill(
                      str(row['status']) == 'sent' ? 'Sent' : 'Failed',
                      dense: true,
                      tone: str(row['status']) == 'sent' ? Tone.success : Tone.danger,
                    ),
                  ),
              ],
            ),
          ),
        for (final entry in groups.entries) ...[
          SectionHeader(entry.key),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final event in entry.value)
                  SwitchListTile(
                    title: Text(event.label),
                    value: event.enabled,
                    onChanged: saving == event.key
                        ? null
                        : (value) => unawaited(_setEvent(event, value)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
