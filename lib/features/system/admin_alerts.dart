import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/admin_event_routes.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';

/// Header and the alerts page share this so a read on one updates the other.
class AdminAlertBus {
  static final tick = ValueNotifier<int>(0);
  static void changed() => tick.value++;
}

class AdminAlertButton extends StatefulWidget {
  const AdminAlertButton({
    super.key,
    required this.openPage,
    required this.openEvent,
  });

  final void Function() openPage;
  final void Function(String event) openEvent;

  @override
  State<AdminAlertButton> createState() => _AdminAlertButtonState();
}

class _AdminAlertButtonState extends State<AdminAlertButton> {
  final _key = GlobalKey();
  int unread = 0;
  List<Json> items = [];
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    AdminAlertBus.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AdminAlertBus.tick.removeListener(_load);
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = asMap(
        await api.get('admin/notifications', query: {'per_page': 8}),
      );
      if (!mounted) return;
      setState(() {
        items = rowsOf(res);
        unread = toInt(dig(res, 'meta.unread'));
      });
      _entry?.markNeedsBuild();
    } catch (_) {}
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(380.0, screen.width - 16);
    final left = math.max(8.0, origin.dx + box.size.width - width);
    final top = origin.dy + box.size.height + 6;
    _entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: _AlertPanel(
              items: items,
              onOpenPage: () {
                _close();
                widget.openPage();
              },
              onOpen: (row) async {
                _close();
                await _markRead(row);
                final event = str(row['event']);
                if (event.isEmpty || pageForAdminEvent(event) == null) {
                  widget.openPage();
                } else {
                  widget.openEvent(event);
                }
              },
              onReadAll: () async {
                _close();
                try {
                  await api.post('admin/notifications/read-all');
                  AdminAlertBus.changed();
                } catch (e) {
                  if (mounted) {
                    toast(context, errorText(e, 'Could not mark alerts read.'), error: true);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    _load();
  }

  Future<void> _markRead(Json row) async {
    if (row['read'] == true) return;
    try {
      await api.post('admin/notifications/${str(row['id'])}/read');
      AdminAlertBus.changed();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final label = unread == 0 ? 'Alerts' : '$unread unread alerts';
    return IconButton(
      key: _key,
      tooltip: label,
      onPressed: _toggle,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class _AlertPanel extends StatelessWidget {
  const _AlertPanel({
    required this.items,
    required this.onOpenPage,
    required this.onOpen,
    required this.onReadAll,
  });

  final List<Json> items;
  final VoidCallback onOpenPage;
  final Future<void> Function(Json row) onOpen;
  final Future<void> Function() onReadAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      elevation: 8,
      color: colors.surfaceContainerLowest,
      surfaceTintColor: colors.surfaceTint,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text('Alerts', style: context.text.titleMedium)),
                  TextButton(onPressed: onReadAll, child: const Text('Mark all read')),
                ],
              ),
            ),
            const Divider(height: 1),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No alerts yet.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = items[index];
                    final read = row['read'] == true;
                    return ListTile(
                      onTap: () => onOpen(row),
                      title: Text(
                        str(row['title'], str(row['event_label'])),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: read ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        '${str(row['body'])}\n${_when(str(row['created_at']))}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: read
                          ? null
                          : Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onOpenPage, child: const Text('See all alerts')),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminAlertsPage extends StatefulWidget {
  const AdminAlertsPage({super.key});

  @override
  State<AdminAlertsPage> createState() => _AdminAlertsPageState();
}

class _AdminAlertsPageState extends State<AdminAlertsPage> {
  List<Json> items = [];
  bool loading = true;
  String? error;
  String filter = 'all';
  bool marking = false;

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
      final res = asMap(
        await api.get('admin/notifications', query: {'filter': filter, 'per_page': 50}),
      );
      if (!mounted) return;
      setState(() {
        items = rowsOf(res);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = errorText(e, 'Could not load alerts.');
      });
    }
  }

  Future<void> _open(Json row) async {
    if (row['read'] != true) {
      try {
        await api.post('admin/notifications/${str(row['id'])}/read');
        AdminAlertBus.changed();
      } catch (_) {}
    }
    if (!mounted) return;
    final page = pageForAdminEvent(str(row['event']));
    if (page == null) {
      setState(() => row['read'] = true);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  Future<void> _readAll() async {
    setState(() => marking = true);
    try {
      await api.post('admin/notifications/read-all');
      AdminAlertBus.changed();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not mark alerts read.'), error: true);
    } finally {
      if (mounted) setState(() => marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Alerts',
      subtitle: 'Events sent to your admin account.',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      maxWidth: 760,
      header: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'unread', label: Text('Unread')),
              ButtonSegment(value: 'read', label: Text('Read')),
            ],
            selected: {filter},
            onSelectionChanged: (value) {
              setState(() => filter = value.first);
              _load();
            },
          ),
          TextButton(
            onPressed: marking ? null : _readAll,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      children: [
        if (!loading && items.isEmpty)
          const Panel(child: Text('No alerts in this list.'))
        else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final row in items)
                  ListTile(
                    onTap: () => _open(row),
                    title: Text(str(row['title'], str(row['event_label']))),
                    subtitle: Text(
                      [
                        str(row['event_label']),
                        str(row['body']),
                        _when(str(row['created_at'])),
                      ].where((part) => part.isNotEmpty).join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: Pill(
                      row['read'] == true ? 'Read' : 'Unread',
                      dense: true,
                      tone: row['read'] == true ? Tone.neutral : Tone.info,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String _when(String raw) {
  final time = DateTime.tryParse(raw)?.toLocal();
  if (time == null) return raw;
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.day}/${time.month} $hour:$minute';
}
