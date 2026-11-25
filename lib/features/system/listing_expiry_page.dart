import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';

class ListingExpiryPage extends StatefulWidget {
  const ListingExpiryPage({super.key});

  @override
  State<ListingExpiryPage> createState() => _ListingExpiryPageState();
}

class _ListingExpiryPageState extends State<ListingExpiryPage> {
  static const types = [
    ('tuition', 'Tuition'),
    ('books', 'Books'),
    ('jobs', 'Jobs'),
    ('internships', 'Internships'),
    ('events', 'Events'),
  ];

  final Map<String, TextEditingController> _controllers = {
    for (final t in types) t.$1: TextEditingController(),
  };
  List<Json> overrides = [];
  bool loading = true;
  String? error;
  final userIdCtrl = TextEditingController();
  final daysCtrl = TextEditingController(text: '30');
  String overrideType = 'tuition';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    userIdCtrl.dispose();
    daysCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final defaultsPayload = asMap(unwrap(await api.get('admin/listing-expiry')));
      final overridesPayload = await api.get('admin/listing-expiry/overrides');
      final defaults = asMap(defaultsPayload['listing_expiry_defaults']);
      for (final t in types) {
        _controllers[t.$1]!.text =
            '${toInt(defaults[t.$1], t.$1 == 'events' ? 40 : 30)}';
      }
      if (!mounted) return;
      setState(() {
        overrides = rowsOf(unwrap(overridesPayload));
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errorText(e, 'Could not load listing expiry.');
        });
      }
    }
  }

  Future<void> _saveDefaults() async {
    final body = <String, int>{};
    for (final t in types) {
      final days = int.tryParse(_controllers[t.$1]!.text.trim()) ?? 0;
      if (days < 1) {
        toast(context, 'Enter valid days for ${t.$2}');
        return;
      }
      body[t.$1] = days;
    }
    if (await runAction(
      context,
      () => api.put('admin/listing-expiry', {
        'listing_expiry_defaults': body,
      }),
      success: 'Defaults saved',
    )) {
      _load();
    }
  }

  Future<void> _saveOverride() async {
    final userId = int.tryParse(userIdCtrl.text.trim());
    final days = int.tryParse(daysCtrl.text.trim()) ?? 0;
    if (userId == null || days < 1) {
      toast(context, 'Enter user id and days');
      return;
    }
    if (await runAction(
      context,
      () => api.put('admin/listing-expiry/overrides', {
        'user_id': userId,
        'listing_type': overrideType,
        'days': days,
      }),
      success: 'Override saved',
    )) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Listing expiry',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      children: [
        const SectionHeader('Default listing days'),
        Panel(
          child: Column(
            children: [
              for (final t in types)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[t.$1],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t.$2,
                      helperText:
                          'Days until listing is hidden from public lists',
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _saveDefaults,
                  child: const Text('Save defaults'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Per-user overrides'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: userIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'User id'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: overrideType,
                items: [
                  for (final t in types)
                    DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                ],
                onChanged: (v) => setState(() => overrideType = v ?? 'tuition'),
                decoration: const InputDecoration(labelText: 'Listing type'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: daysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saveOverride,
                child: const Text('Save override'),
              ),
              const SizedBox(height: 16),
              if (overrides.isEmpty)
                const Text('No overrides yet.')
              else
                for (final row in overrides)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '#${row['user_id']} ${pick(row, ['user.name', 'user.username'])}',
                    ),
                    subtitle: Text(
                      '${row['listing_type']} · ${row['days']} days',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await runAction(
                          context,
                          () => api.delete(
                            'admin/listing-expiry/overrides/${row['id']}',
                          ),
                          success: 'Override removed',
                        )) {
                          _load();
                        }
                      },
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
