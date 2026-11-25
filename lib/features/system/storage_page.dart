import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});
  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  String prefix = '';
  String? next;
  List<Json> folders = [], files = [];
  bool loading = true, more = false;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    final current = ++request;
    setState(() {
      if (append) {
        more = true;
      } else {
        loading = true;
      }
      error = null;
    });
    try {
      final r = asMap(
        await api.get(
          'admin/storage/browse',
          query: {'path': prefix, if (append) 'page_token': next},
        ),
      );
      if (!mounted || current != request) return;
      setState(() {
        final newFolders = rowsOf(r['folders']);
        folders = append
            ? [
                ...folders,
                ...newFolders.where(
                  (f) => !folders.any((old) => old['path'] == f['path']),
                ),
              ]
            : newFolders;
        files = append ? [...files, ...rowsOf(r['files'])] : rowsOf(r['files']);
        next = r['next_page_token'];
        loading = false;
        more = false;
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(() {
          error = errorText(e);
          loading = false;
          more = false;
        });
      }
    }
  }

  void _go(String p) {
    prefix = p;
    _load();
  }

  Future<void> _inspect(Json f) async {
    try {
      final r = asMap(
        await api.get('admin/storage/usages', query: {'path': f['path']}),
      );
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: .8,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                str(f['name']),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${f['size']} bytes · ${fmtDate(f['updated_at'], time: true)}',
              ),
              const SectionHeader('Used by'),
              if (rowsOf(r['usages']).isEmpty)
                const Text('No linked records found.'),
              for (final u in rowsOf(r['usages']))
                ListTile(
                  title: Text(str(u['label'])),
                  subtitle: Text(pretty(u['type'])),
                  trailing: truthy(u['removed']) ? const Pill('Removed') : null,
                ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: f['url'] == null
                    ? null
                    : () => openLink(context, str(f['url'])),
                child: const Text('Open file'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  if (!await confirmDialog(
                        context,
                        title: 'Delete storage file?',
                        message:
                            'This permanently removes the file. ${r['count'] ?? 0} linked records may lose their attachment.',
                        destructive: true,
                        confirmLabel: 'Delete file',
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  if (await runAction(
                        context,
                        () => api.delete(
                          'admin/storage/object',
                          body: {'path': f['path']},
                        ),
                        success: 'File deleted',
                      ) &&
                      context.mounted) {
                    Navigator.pop(context);
                    _load();
                  }
                },
                child: const Text('Delete file'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = prefix.split('/').where((s) => s.isNotEmpty).toList();
    return AppPage(
      title: 'Storage',
      subtitle: 'Browse files and inspect where they are used',
      loading: loading,
      error: error,
      onRetry: () => _load(),
      onRefresh: () => _load(),
      header: Wrap(
        spacing: 8,
        children: [
          ActionChip(label: const Text('Root'), onPressed: () => _go('')),
          for (var i = 0; i < parts.length; i++)
            ActionChip(
              label: Text(parts[i]),
              onPressed: () => _go('${parts.take(i + 1).join('/')}/'),
            ),
        ],
      ),
      children: [
        if (folders.isEmpty && files.isEmpty)
          const EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'This folder is empty',
          ),
        for (final f in folders)
          RecordTile(
            leading: const IconBadge(Icons.folder_rounded),
            title: str(f['name']),
            onTap: () => _go(str(f['path'])),
          ),
        for (final f in files)
          RecordTile(
            leading: const IconBadge(
              Icons.insert_drive_file_outlined,
              tone: Tone.info,
            ),
            title: str(f['name']),
            subtitle: '${f['size']} bytes · ${str(f['content_type'])}',
            meta: fmtDate(f['updated_at'], time: true),
            onTap: () => _inspect(f),
          ),
        if (next != null)
          OutlinedButton(
            onPressed: more ? null : () => _load(append: true),
            child: Text(more ? 'Loading…' : 'Load more'),
          ),
      ],
    );
  }
}
