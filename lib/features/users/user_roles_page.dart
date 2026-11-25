import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

class UserRolesPage extends StatefulWidget {
  const UserRolesPage({super.key, required this.userId, this.embedded = false});
  final dynamic userId;

  /// Renders inside the user details page instead of its own screen.
  final bool embedded;
  @override
  State<UserRolesPage> createState() => _UserRolesPageState();
}

class _UserRolesPageState extends State<UserRolesPage> {
  List<Json> roles = [];
  final Map<String, Json> assignments = {};
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = asMap(
        await api.get('admin/users/${widget.userId}/associative-roles'),
      );
      if (!mounted) return;
      setState(() {
        roles = rowsOf(res['roles']);
        assignments.clear();
        for (final a in rowsOf(res['data'])) {
          if (a['status'] != 'revoked') {
            assignments[str(a['associative_role_id'])] = {
              'associative_role_id': a['associative_role_id'],
              'expires_at': a['expires_at'],
            };
          }
        }
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errorText(e);
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    if (await runAction(
      context,
      () => api.put('admin/users/${widget.userId}/associative-roles', {
        'assignments': assignments.values.toList(),
      }),
      success: 'Roles updated',
    )) {
      await _load();
    }
    if (mounted) setState(() => saving = false);
  }

  List<Widget> _roleCards() => [
    for (final r in roles)
      Panel(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(str(r['name'])),
                subtitle: Text('${r['code']} · ${pretty(r['status'])}'),
                value: assignments.containsKey(str(r['id'])),
                onChanged: saving
                    ? null
                    : (on) => setState(() {
                        if (on) {
                          assignments[str(r['id'])] = {
                            'associative_role_id': r['id'],
                            'expires_at': null,
                          };
                        } else {
                          assignments.remove(str(r['id']));
                        }
                      }),
              ),
              if (assignments.containsKey(str(r['id'])))
                ListTile(
                  title: const Text('Expires'),
                  subtitle: Text(
                    fmtDate(
                      assignments[str(r['id'])]?['expires_at'],
                      fallback: 'Never',
                    ),
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: saving
                      ? null
                      : () async {
                          final result = await showFormSheet(
                            context,
                            title: 'Role expiry',
                            initial: assignments[str(r['id'])]!,
                            fields: const [
                              FieldSpec(
                                'expires_at',
                                'Expires on',
                                type: FieldType.date,
                              ),
                            ],
                            onSubmit: (_) async {},
                          );
                          if (result != null && mounted) {
                            setState(
                              () => assignments[str(r['id'])]!['expires_at'] =
                                  result['expires_at'],
                            );
                          }
                        },
                ),
            ],
          ),
        ),
  ];

  Widget _saveButton() => FilledButton(
    onPressed: loading || error != null || saving ? null : _save,
    child: Text(saving ? 'Saving…' : 'Save assignments'),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      if (loading) return const SkeletonList(count: 3);
      if (error != null) return ErrorState(message: error!, onRetry: _load);
      if (roles.isEmpty) {
        return const EmptyState(
          icon: Icons.badge_outlined,
          title: 'No associative roles are available yet',
          message: 'Create one under Associative roles.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Associative roles'),
              subtitle: Text(
                'Assign privilege packs with an optional expiry date.',
              ),
            ),
          ),
          ..._roleCards(),
          const SizedBox(height: 8),
          _saveButton(),
        ],
      );
    }
    return AppPage(
      title: 'User roles & badges',
      loading: loading,
      error: error,
      onRetry: _load,
      bottomBar: _saveButton(),
      children: _roleCards(),
    );
  }
}
