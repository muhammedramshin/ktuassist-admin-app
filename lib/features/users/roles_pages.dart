import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

class RolesPage extends StatelessWidget {
  const RolesPage({super.key, this.associative = false});
  final bool associative;
  @override
  Widget build(BuildContext context) {
    final path = 'admin/${associative ? 'associative' : 'account'}-roles';
    return CrudPage(
      CrudConfig(
        title: associative ? 'Associative roles' : 'Account roles',
        subtitle: associative
            ? 'Badges and permissions assigned alongside account roles'
            : 'Manage account types and their availability',
        singular: 'role',
        icon: Icons.admin_panel_settings_outlined,
        load: () async => rowsOf(await api.get(path)),
        titleOf: (r) => str(r['name']),
        subtitleOf: (r) => str(r['description']),
        metaOf: (r) => [
          str(r['code']),
          if (associative)
            rowsOf(r['permissions']).map((p) => str(p['name'])).join(', '),
        ].where((s) => s.isNotEmpty).join(' · '),
        pillsOf: (_, r) => [
          Pill.status(str(r['status'])),
          if (truthy(r['is_system'])) const Pill('System'),
        ],
        filters: [CrudFilter('Status', (r) => str(r['status']))],
        initialOf: (r) => {
          ...r,
          'permission_ids': rowsOf(
            r['permissions'],
          ).map((p) => p['id']).toList(),
        },
        fields: (r) => [
          const FieldSpec('name', 'Name', required: true, maxLength: 80),
          FieldSpec(
            'code',
            'Code',
            required: true,
            maxLength: 32,
            readOnly: truthy(r?['is_system']),
            validator: (v, _) =>
                RegExp(r'^[A-Za-z][A-Za-z0-9_ -]{0,31}$').hasMatch(str(v))
                ? null
                : 'Start with a letter; use letters, numbers, spaces, _ or -.',
          ),
          const FieldSpec(
            'description',
            'Description',
            type: FieldType.multiline,
            maxLength: 500,
          ),
          FieldSpec(
            'status',
            'Status',
            type: FieldType.select,
            required: true,
            defaultValue: 'active',
            options: [
              const Opt('active', 'Active'),
              const Opt('inactive', 'Inactive'),
              if (!associative) const Opt('hidden', 'Hidden'),
            ],
          ),
          const FieldSpec(
            'sort_order',
            'Sort order',
            type: FieldType.number,
            defaultValue: 0,
            min: 0,
            max: 9999,
          ),
          if (associative) ...[
            const FieldSpec(
              'badge_color',
              'Badge color',
              defaultValue: '#0F766E',
              maxLength: 32,
            ),
            const FieldSpec('badge_icon', 'Badge icon', maxLength: 64),
            FieldSpec(
              'permission_ids',
              'Permissions',
              type: FieldType.multiSelect,
              loadOptions: () async =>
                  rowsOf(await api.get('admin/permissions'))
                      .map(
                        (p) => Opt(
                          p['id'],
                          str(p['name'], str(p['code'])),
                          pretty(p['group']),
                        ),
                      )
                      .toList(),
            ),
          ],
        ],
        create: (v) async {
          await api.post(path, v);
        },
        update: (r, v) async {
          await api.put('$path/${r['id']}', v);
        },
      ),
    );
  }
}
