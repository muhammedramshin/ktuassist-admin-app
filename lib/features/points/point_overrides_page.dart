import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/forms.dart';

class PointOverridesPage extends StatelessWidget {
  const PointOverridesPage({super.key, required this.action});
  final Json action;
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Point overrides',
      subtitle: str(action['name']),
      singular: 'override',
      icon: Icons.rule_outlined,
      load: () async {
        final actions = rowsOf(await api.get('point-actions/admin'));
        final fresh = actions
            .where((r) => str(r['id']) == str(action['id']))
            .firstOrNull;
        return rowsOf(fresh?['overrides']);
      },
      titleOf: (r) => r['scope'] == 'role'
          ? pretty(r['role'])
          : personName(r['user'], 'User #${r['user_id']}'),
      subtitleOf: (r) => str(r['note']),
      metaOf: (r) => '${r['points']} points · ${r['scope']}',
      activeFilter: true,
      fields: (r) => [
        if (r == null) ...[
          const FieldSpec(
            'scope',
            'Apply to',
            required: true,
            type: FieldType.select,
            defaultValue: 'role',
            options: [
              Opt('role', 'Account role'),
              Opt('user', 'Specific user'),
            ],
          ),
          FieldSpec(
            'role',
            'Account role',
            type: FieldType.select,
            required: true,
            visibleWhen: (v) => v['scope'] == 'role',
            loadOptions: () async => optsOf(
              rowsOf(await api.get('admin/account-roles')),
              valueKey: 'code',
            ),
          ),
          FieldSpec(
            'user_id',
            'User',
            type: FieldType.select,
            required: true,
            visibleWhen: (v) => v['scope'] == 'user',
            loadOptions: Lookups.userOpts,
          ),
        ],
        const FieldSpec(
          'points',
          'Points',
          type: FieldType.number,
          required: true,
          min: 0,
        ),
        const FieldSpec('note', 'Note', type: FieldType.multiline),
        const FieldSpec(
          'is_active',
          'Active',
          type: FieldType.toggle,
          defaultValue: true,
        ),
      ],
      create: (v) async {
        final body = {...v};
        body.remove(body['scope'] == 'role' ? 'user_id' : 'role');
        await api.post('point-actions/${action['id']}/overrides', body);
      },
      update: (r, v) async {
        await api.put('point-action-overrides/${r['id']}', v);
      },
      delete: (r) async {
        await api.delete('point-action-overrides/${r['id']}');
      },
      deleteMessage: (_) =>
          'Remove this override? Points will fall back to the next applicable rule.',
    ),
  );
}

class EffectivePointsPage extends StatelessWidget {
  const EffectivePointsPage({super.key, required this.userId});
  final dynamic userId;
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Effective points',
      subtitle: 'Resolved earning and spending rules for this user',
      load: () async => rowsOf(
        await api.get('point-actions/effective', query: {'user_id': userId}),
      ),
      titleOf: (r) => str(r['name'], str(r['code'])),
      subtitleOf: (r) =>
          '${r['effective_points'] ?? r['points']} points · ${pretty(r['source'])}',
      icon: Icons.toll_outlined,
    ),
  );
}
