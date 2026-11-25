import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api.dart';
import '../../core/job_poll.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/document_preview.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

Future<void> shareAdminFile(
  BuildContext context,
  String path,
  String name,
) async {
  await runAction(context, () async {
    final bytes = await api.bytes(path);
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
        fileNameOverrides: [name],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  });
}

const _stampDefaults = {
  'stamp_mode': 'stamp_only',
  'watermark_enabled': true,
  'text': 'app.ktuassist.in',
  'link': 'https://app.ktuassist.in',
  'position': 'bottom-left',
  'angle': 0,
  'opacity': 0.12,
  'margin': 18,
  'promo_enabled': true,
};

Future<List<Map<String, dynamic>>> loadStampPresets() async {
  final data = await api.get('materials/stamp-configs');
  final raw = data is Map ? data['configs'] : null;
  if (raw is! List) return [];
  return [
    for (final row in raw)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

Map<String, dynamic> stampFormFromConfig(Map<String, dynamic> preset) {
  final watermark = preset['watermark'] is Map
      ? Map<String, dynamic>.from(preset['watermark'] as Map)
      : <String, dynamic>{};
  final promo = preset['promo_page'] is Map
      ? Map<String, dynamic>.from(preset['promo_page'] as Map)
      : <String, dynamic>{};
  return {
    ..._stampDefaults,
    'watermark_enabled': watermark['enabled'] ?? true,
    'text': watermark['text'] ?? _stampDefaults['text'],
    'link': watermark['link'] ?? _stampDefaults['link'],
    'position': watermark['position'] ?? 'bottom-left',
    'font_size': watermark['font_size'],
    'angle': watermark['angle'] ?? 0,
    'opacity': watermark['opacity'] ?? .12,
    'margin': watermark['margin'] ?? 18,
    'promo_enabled': promo['enabled'] ?? true,
    if (promo['template_id'] != null) 'template_id': promo['template_id'],
    'template_name': preset['name'] ?? '',
  };
}

Future<void> saveStampConfig(
  String name,
  Map<String, dynamic> values, {
  String? id,
}) async {
  final font = values['font_size'];
  final template = values['template_id'];
  final body = {
    'name': name,
    'watermark': {
      'enabled': truthy(values['watermark_enabled']),
      'position': values['position'],
      'text': values['text'],
      'link': values['link'],
      'font_size': font == null || '$font'.trim().isEmpty ? null : font,
      'angle': values['angle'],
      'opacity': values['opacity'],
      'margin': values['margin'],
    },
    'promo_page': {
      'enabled': truthy(values['promo_enabled']),
      'template_id': template == null || '$template'.trim().isEmpty
          ? null
          : template,
    },
  };
  if (id != null && id.isNotEmpty) {
    await api.put('materials/stamp-configs/$id', body);
  } else {
    await api.post('materials/stamp-configs', body);
  }
}

class MaterialTools extends StatefulWidget {
  const MaterialTools({
    super.key,
    required this.material,
    required this.onChanged,
  });
  final Json material;
  final Future<void> Function() onChanged;
  @override
  State<MaterialTools> createState() => _MaterialToolsState();
}

class _MaterialToolsState extends State<MaterialTools> {
  bool busy = false;
  Json get m => widget.material;
  Json get file => asMap(m['file_data']);
  Future<void> _scan() async {
    setState(() => busy = true);
    final fileId = file['id'] ?? m['file_id'] ?? m['file'];
    if (await runAction(
      context,
      () async {
        await api.post('admin/files/$fileId/scan');
        num? sizeBytes = num.tryParse('${file['size_bytes'] ?? ''}');
        final attempts = jobPollMaxAttempts(JobPollKind.scan, sizeBytes);
        for (var i = 0; i < attempts; i++) {
          await Future<void>.delayed(
            Duration(milliseconds: jobPollDelayMs(i, JobPollKind.scan, sizeBytes)),
          );
          final res = asMap(await api.get('files/$fileId'));
          final row = asMap(res['data'] ?? res);
          sizeBytes = num.tryParse('${row['size_bytes'] ?? ''}') ?? sizeBytes;
          final result = '${row['scan_result'] ?? ''}';
          final status = '${row['status'] ?? ''}';
          if (const {'clean', 'infected', 'failed'}.contains(result) ||
              status == 'ready' ||
              status == 'rejected') {
            if (result == 'failed') {
              throw ApiException(422, 'The scan could not be completed.');
            }
            return row;
          }
        }
        throw ApiException(408, 'Scan is still running on the server. Refresh in a minute.');
      },
      success: 'File scan completed',
    )) {
      await widget.onChanged();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _stamp() async {
    final presets = await loadStampPresets();
    var initial = Map<String, dynamic>.from(_stampDefaults);
    String? presetId;
    if (presets.isNotEmpty) {
      if (!mounted) return;
      final picked = await pickFromOptions(context, 'Stamp configuration', [
        const Opt('defaults', 'Recommended defaults'),
        for (final preset in presets) Opt(preset['id'], '${preset['name']}'),
      ]);
      if (picked == null || picked.isEmpty) return;
      final chosen = picked.first;
      if (chosen != 'defaults') {
        Map<String, dynamic>? match;
        for (final preset in presets) {
          if (preset['id'] == chosen) match = preset;
        }
        if (match != null) initial = stampFormFromConfig(match);
        presetId = '$chosen';
      }
    }
    if (!mounted) return;
    final savedName = '${initial['template_name'] ?? ''}'.trim();
    final result = await showFormSheet(
      context,
      title: 'Stamp material PDF',
      intro:
          'Choose a saved setup first, or name this one so you can reuse it.',
      initial: initial,
      fields: [
        const FieldSpec(
          'template_name',
          'Configuration template',
          hint: 'Leave empty to stamp without saving',
          maxLength: 80,
        ),
        FieldSpec(
          'stamp_mode',
          'Output',
          type: FieldType.select,
          required: true,
          defaultValue: 'stamp_only',
          options: const [
            Opt('stamp_only', 'Stamp only'),
            Opt('compress_and_stamp', 'Compress & stamp'),
          ],
        ),
        const FieldSpec(
          'watermark_enabled',
          'Watermark',
          type: FieldType.toggle,
          defaultValue: true,
        ),
        const FieldSpec(
          'text',
          'Watermark text',
          required: true,
          defaultValue: 'app.ktuassist.in',
          maxLength: 120,
        ),
        const FieldSpec(
          'link',
          'Watermark link',
          required: true,
          type: FieldType.url,
          defaultValue: 'https://app.ktuassist.in',
        ),
        FieldSpec(
          'position',
          'Position',
          type: FieldType.select,
          defaultValue: 'bottom-left',
          options: [
            for (final v in [
              'top-left',
              'top-center',
              'top-right',
              'center-left',
              'center-center',
              'center-right',
              'bottom-left',
              'bottom-center',
              'bottom-right',
            ])
              Opt(v, pretty(v)),
          ],
        ),
        const FieldSpec(
          'font_size',
          'Font size (blank for automatic)',
          type: FieldType.decimal,
          min: 8,
          max: 72,
        ),
        const FieldSpec(
          'angle',
          'Angle',
          type: FieldType.decimal,
          min: -90,
          max: 90,
          defaultValue: 0,
        ),
        const FieldSpec(
          'opacity',
          'Opacity',
          type: FieldType.decimal,
          min: 0,
          max: 1,
          defaultValue: .12,
        ),
        const FieldSpec(
          'margin',
          'Margin',
          type: FieldType.decimal,
          min: 4,
          max: 80,
          defaultValue: 18,
        ),
        const FieldSpec(
          'promo_enabled',
          'Append branding page',
          type: FieldType.toggle,
          defaultValue: true,
        ),
        FieldSpec(
          'template_id',
          'Branding template',
          type: FieldType.select,
          required: true,
          visibleWhen: (v) => truthy(v['promo_enabled']),
          loadOptions: () async => optsOf(
            rowsOf(await api.get('materials/stamp-templates'), ['templates']),
            labelKeys: ['name', 'label', 'title'],
          ),
        ),
      ],
      onSubmit: (v) async {
        final queued = asMap(await api.post('materials/${m['id']}/stamp', {
          'compress': '${v['stamp_mode']}' == 'compress_and_stamp',
          'watermark': {
            'enabled': truthy(v['watermark_enabled']),
            for (final k in [
              'text',
              'link',
              'position',
              'font_size',
              'angle',
              'opacity',
              'margin',
            ])
              k: v[k],
          },
          'promo_page': {
            'enabled': truthy(v['promo_enabled']),
            'template_id': v['template_id'],
          },
        }));
        final jobId = queued['job_id'];
        if (jobId != null) {
          final sizeBytes = num.tryParse('${file['size_bytes'] ?? ''}');
          final attempts = jobPollMaxAttempts(JobPollKind.stamp, sizeBytes);
          for (var i = 0; i < attempts; i++) {
            await Future<void>.delayed(
              Duration(
                milliseconds: jobPollDelayMs(i, JobPollKind.stamp, sizeBytes),
              ),
            );
            final status = asMap(
              await api.get('materials/${m['id']}/stamp-jobs/$jobId'),
            );
            if (status['finished'] == true || status['status'] == 'succeeded') {
              break;
            }
            if (status['status'] == 'failed') {
              throw ApiException(
                422,
                '${status['error'] ?? 'Stamp job failed.'}',
              );
            }
          }
        }
        final name = '${v['template_name'] ?? ''}'.trim();
        if (name.isNotEmpty) {
          await saveStampConfig(
            name,
            {
              for (final key in [
                'watermark_enabled',
                'text',
                'link',
                'position',
                'font_size',
                'angle',
                'opacity',
                'margin',
                'promo_enabled',
                'template_id',
              ])
                key: v[key],
            },
            id: presetId != null && name == savedName ? presetId : null,
          );
        }
      },
    );
    if (result != null) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DetailCard(
        title: 'File safety & PDF tools',
        children: [
          KV('Scan', pretty(file['scan_result'] ?? 'not_scanned')),
          KV('File status', pretty(file['status'])),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy || file.isEmpty ? null : _scan,
                icon: const Icon(Icons.security_outlined),
                label: Text(busy ? 'Scanning…' : 'Scan file'),
              ),
              OutlinedButton.icon(
                onPressed: busy || file.isEmpty ? null : _stamp,
                icon: const Icon(Icons.branding_watermark_outlined),
                label: const Text('Stamp PDF'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final templates = rowsOf(
                      await api.get('materials/stamp-templates'),
                      ['templates'],
                    );
                    if (!context.mounted) return;
                    final chosen = await pickFromOptions(
                      context,
                      'Preview branding template',
                      optsOf(templates, labelKeys: ['name', 'label', 'title']),
                    );
                    if (chosen != null && context.mounted) {
                      await push(
                        context,
                        DocumentPreviewPage(
                          url:
                              'materials/stamp-templates/${Uri.encodeComponent(str(chosen.first))}/preview',
                          title: 'Branding preview',
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      toast(context, errorText(e), error: true);
                    }
                  }
                },
                child: const Text('Preview templates'),
              ),
            ],
          ),
        ],
      ),
      if (rowsOf(m['stamped_files']).isNotEmpty)
        const SectionHeader('Stamped variants'),
      for (final variant in rowsOf(m['stamped_files']))
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RecordTile(
                title: pick(variant, [
                  'file.name',
                ], 'Stamped PDF #${variant['id']}'),
                meta: fmtDate(variant['created_at'], time: true),
                pills: [
                  if ('${variant['file_id'] ?? dig(variant, 'file.id')}' ==
                      '${file['id']}')
                    const Pill('Assigned', tone: Tone.success),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => push(
                      context,
                      DocumentPreviewPage(
                        url: pick(variant, ['file.link']),
                        title: 'Stamped PDF',
                      ),
                    ),
                    child: const Text('Preview'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final link = pick(variant, ['file.link']);
                      if (link.isNotEmpty) {
                        await shareAdminFile(
                          context,
                          link,
                          'material-${m['id']}-stamp-${variant['id']}.pdf',
                        );
                      }
                    },
                    child: const Text('Download'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final result = await showFormSheet(
                        context,
                        title: 'Assign stamped PDF',
                        intro: 'This changes the file students receive.',
                        fields: const [
                          FieldSpec(
                            'keep_original',
                            'Keep original PDF',
                            type: FieldType.toggle,
                            defaultValue: false,
                            helper:
                                'Turning this off deletes the original PDF from storage.',
                          ),
                        ],
                        onSubmit: (v) async {
                          if (!truthy(v['keep_original']) &&
                              !await confirmDialog(
                                context,
                                title: 'Delete original PDF?',
                                destructive: true,
                                confirmLabel: 'Delete original',
                              )) {
                            throw const FormatException(
                              'Assignment cancelled.',
                            );
                          }
                          await api.post(
                            'materials/${m['id']}/stamped-files/${variant['id']}/assign',
                            v,
                          );
                        },
                      );
                      if (result != null) await widget.onChanged();
                    },
                    child: const Text('Assign'),
                  ),
                  IconButton(
                    tooltip: 'Delete variant',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (!await confirmDialog(
                            context,
                            title: 'Delete stamped variant?',
                            message:
                                'If assigned, the material reverts to its original file when available.',
                            destructive: true,
                            confirmLabel: 'Delete',
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      if (await runAction(
                        context,
                        () => api.delete(
                          'materials/${m['id']}/stamped-files/${variant['id']}',
                        ),
                        success: 'Variant deleted',
                      )) {
                        await widget.onChanged();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}
