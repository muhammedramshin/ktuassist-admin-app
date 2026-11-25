import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/json.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'uploader.dart';

enum FieldType {
  text,
  multiline,
  number,
  decimal,
  email,
  url,
  phone,
  password,
  select,
  multiSelect,
  toggle,
  date,
  dateTime,
  upload,
  gallery,
}

/// What an upload field stores: the public URL, or the `addfile` record id.
enum UploadTarget { link, fileId }

class Opt {
  const Opt(this.value, this.label, [this.subtitle]);
  final dynamic value;
  final String label;
  final String? subtitle;
}

/// Builds options from API rows: `id` value and a label made of [labelKeys]
/// (first non-empty) with an optional `(code)` suffix.
List<Opt> optsOf(
  List<Json> rows, {
  List<String> labelKeys = const ['name'],
  bool withCode = false,
  String valueKey = 'id',
}) => rows.map((r) {
  final label = pick(r, labelKeys, '#${r[valueKey]}');
  final code = str(r['code']);
  return Opt(
    r[valueKey],
    withCode && code.isNotEmpty ? '$label ($code)' : label,
  );
}).toList();

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.hint,
    this.helper,
    this.loadHelper,
    this.maxLength,
    this.options = const [],
    this.loadOptions,
    this.readOnly = false,
    this.visibleWhen,
    this.validator,
    this.section,
    this.uploadTarget = UploadTarget.link,
    this.imagesOnly = true,
    this.folder = 'books',
    this.fileLabel,
    this.min,
    this.max,
    this.defaultValue,
    this.allowEmptyOption = true,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? hint;
  final String? helper;

  /// Async helper text for the current value (e.g. shared-course hint).
  final Future<String?> Function(dynamic value)? loadHelper;
  final int? maxLength;
  final List<Opt> options;
  final Future<List<Opt>> Function()? loadOptions;
  final bool readOnly;
  final bool Function(Json values)? visibleWhen;
  final String? Function(dynamic value, Json values)? validator;
  final String? section;
  final UploadTarget uploadTarget;
  final bool imagesOnly;

  /// Cloud Storage folder passed to [showUploader]. Other forms keep `books`.
  final String folder;

  /// Display name for an existing uploaded file (when the value is an id).
  final String? fileLabel;
  final num? min;
  final num? max;
  final dynamic defaultValue;
  final bool allowEmptyOption;
}

/// Opens a full-height form sheet. [onSubmit] receives cleaned values; throw
/// to keep the sheet open and show the error. Returns the values on success.
Future<Json?> showFormSheet(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  Json initial = const {},
  String submitLabel = 'Save',
  String? intro,
  required Future<void> Function(Json values) onSubmit,
}) => showModalBottomSheet<Json>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  builder: (_) => FractionallySizedBox(
    heightFactor: .94,
    child: FormSheet(
      title: title,
      fields: fields,
      initial: initial,
      submitLabel: submitLabel,
      intro: intro,
      onSubmit: onSubmit,
    ),
  ),
);

List<String> _urlList(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

class FormSheet extends StatefulWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.fields,
    required this.initial,
    required this.submitLabel,
    required this.onSubmit,
    this.intro,
  });
  final String title;
  final List<FieldSpec> fields;
  final Json initial;
  final String submitLabel;
  final String? intro;
  final Future<void> Function(Json values) onSubmit;
  @override
  State<FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<FormSheet> {
  final values = <String, dynamic>{};
  final controllers = <String, TextEditingController>{};
  final options = <String, List<Opt>>{};
  final fileLabels = <String, String>{};
  final savedImages = <String, List<String>>{};
  final dynamicHelpers = <String, String?>{};
  final errors = <String, String>{};
  bool saving = false;
  final _loadingOptions = <String>{};
  final _failedOptions = <String>{};
  String? error;

  static const _textTypes = {
    FieldType.text,
    FieldType.multiline,
    FieldType.number,
    FieldType.decimal,
    FieldType.email,
    FieldType.url,
    FieldType.phone,
    FieldType.password,
  };

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final raw = widget.initial.containsKey(f.key)
          ? widget.initial[f.key]
          : f.defaultValue;
      if (_textTypes.contains(f.type)) {
        controllers[f.key] = TextEditingController(
          text: raw == null ? '' : '$raw',
        );
      } else if (f.type == FieldType.toggle) {
        values[f.key] = raw == null ? false : truthy(raw);
      } else if (f.type == FieldType.multiSelect) {
        values[f.key] = raw is List ? List.of(raw) : <dynamic>[];
      } else if (f.type == FieldType.dateTime || f.type == FieldType.date) {
        values[f.key] = parseDate(raw);
      } else if (f.type == FieldType.gallery) {
        // API images stay on screen. The submitted value is only URLs added in this session.
        savedImages[f.key] = _urlList(raw);
        values[f.key] = <String>[];
      } else {
        values[f.key] = raw;
      }
      if (f.fileLabel != null) fileLabels[f.key] = f.fileLabel!;
      options[f.key] = f.options;
      if (f.loadOptions != null) {
        _loadingOptions.add(f.key);
        f.loadOptions!()
            .then((list) {
              if (!mounted) return;
              setState(() {
                _loadingOptions.remove(f.key);
                options[f.key] = list;
                if (f.type == FieldType.select) {
                  values[f.key] = _match(list, values[f.key]);
                }
              });
              _refreshHelper(f);
            })
            .catchError((Object e) {
              if (mounted) {
                setState(() {
                  _loadingOptions.remove(f.key);
                  _failedOptions.add(f.key);
                  errors[f.key] =
                      'Could not load options. Reopen this form to retry.';
                });
              }
            });
      } else if (f.type == FieldType.select) {
        values[f.key] = _match(f.options, values[f.key]);
      }
      _refreshHelper(f);
    }
  }

  dynamic _match(List<Opt> list, dynamic value) {
    if (value == null || value == '') return null;
    final raw = value is Map ? value['id'] : value;
    for (final o in list) {
      if ('${o.value}' == '$raw') return o.value;
    }
    return raw;
  }

  String? _helperText(FieldSpec f) => dynamicHelpers[f.key] ?? f.helper;

  Future<void> _refreshHelper(FieldSpec f) async {
    if (f.loadHelper == null) return;
    final value = values[f.key];
    try {
      final text = await f.loadHelper!(value);
      if (!mounted) return;
      if (dynamicHelpers[f.key] == text) return;
      setState(() => dynamicHelpers[f.key] = text);
    } catch (_) {
      if (!mounted) return;
      if (dynamicHelpers[f.key] != null) {
        setState(() => dynamicHelpers[f.key] = null);
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Json get _snapshot {
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      out[f.key] = _valueOf(f);
    }
    return out;
  }

  dynamic _valueOf(FieldSpec f) {
    if (_textTypes.contains(f.type)) {
      final text = controllers[f.key]!.text.trim();
      if (text.isEmpty) return null;
      if (f.type == FieldType.number) {
        return int.tryParse(text) ?? num.tryParse(text);
      }
      if (f.type == FieldType.decimal) return num.tryParse(text);
      return f.type == FieldType.password ? controllers[f.key]!.text : text;
    }
    if (f.type == FieldType.date) {
      final d = values[f.key] as DateTime?;
      return d == null ? null : ymd(d);
    }
    return values[f.key];
  }

  bool _visible(FieldSpec f, Json snapshot) =>
      f.visibleWhen?.call(snapshot) ?? true;

  Future<void> _submit() async {
    if (saving) return;
    final snapshot = _snapshot;
    final unavailable = widget.fields.where(
      (f) =>
          _visible(f, snapshot) &&
          (_loadingOptions.contains(f.key) || _failedOptions.contains(f.key)),
    );
    if (unavailable.isNotEmpty) {
      setState(
        () => error =
            'Options are unavailable for ${unavailable.map((f) => f.label).join(', ')}. Wait for loading or reopen the form to retry.',
      );
      return;
    }
    errors.clear();
    for (final f in widget.fields) {
      if (!_visible(f, snapshot)) continue;
      final v = snapshot[f.key];
      final empty =
          v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty);
      if (f.required && empty && f.type != FieldType.toggle) {
        errors[f.key] = '${f.label} is required';
        continue;
      }
      if (!empty &&
          (f.type == FieldType.number || f.type == FieldType.decimal)) {
        if (v is! num) {
          errors[f.key] = 'Enter a valid number';
          continue;
        }
        if (f.type == FieldType.number && v is! int) {
          errors[f.key] = 'Enter a whole number';
          continue;
        }
        if (f.min != null && v < f.min!) {
          errors[f.key] = 'Must be at least ${f.min}';
        }
        if (f.max != null && v > f.max!) {
          errors[f.key] = 'Must be at most ${f.max}';
        }
      }
      if (!empty &&
          f.type == FieldType.email &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch('$v')) {
        errors[f.key] = 'Enter a valid email';
      }
      final custom = f.validator?.call(v, snapshot);
      if (custom != null) errors[f.key] = custom;
    }
    if (errors.isNotEmpty) {
      setState(() => error = 'Please fix the highlighted fields.');
      return;
    }
    final cleaned = <String, dynamic>{};
    for (final f in widget.fields) {
      if (_visible(f, snapshot)) cleaned[f.key] = snapshot[f.key];
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSubmit(cleaned);
      if (mounted) Navigator.pop(context, cleaned);
    } catch (e) {
      if (mounted) {
        setState(() => error = errorText(e, 'Could not save. Try again.'));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final children = <Widget>[];
    String? section;
    for (final f in widget.fields) {
      if (!_visible(f, snapshot)) continue;
      if (f.section != null && f.section != section) {
        section = f.section;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 10),
            child: Text(
              f.section!.toUpperCase(),
              style: context.text.labelMedium?.copyWith(
                letterSpacing: 1.1,
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      }
      children.add(
        Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(f)),
      );
    }
    return PopScope(
      canPop: !saving,
      child: Material(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: context.text.titleLarge),
                  ),
                  IconButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                children: [
                  if (widget.intro != null) Banner2(widget.intro!),
                  ...children,
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.colors.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) Banner2(error!, tone: Tone.danger),
                    FilledButton(
                      onPressed: saving ? null : _submit,
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.submitLabel),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(FieldSpec f) {
    final err = errors[f.key];
    switch (f.type) {
      case FieldType.toggle:
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.outline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SwitchListTile(
            title: Text(f.label),
            subtitle: _helperText(f) == null ? null : Text(_helperText(f)!),
            value: values[f.key] == true,
            onChanged: f.readOnly
                ? null
                : (v) => setState(() => values[f.key] = v),
          ),
        );
      case FieldType.select:
        final opts = options[f.key]!;
        final current = opts
            .where((o) => '${o.value}' == '${values[f.key]}')
            .firstOrNull;
        return _Tappable(
          label: '${f.label}${f.required ? ' *' : ''}',
          value:
              current?.label ??
              (values[f.key] == null ? null : '#${values[f.key]}'),
          hint: f.loadOptions != null && opts.isEmpty && err == null
              ? 'Loading…'
              : (f.hint ?? 'Select'),
          error: err,
          helper: _helperText(f),
          icon: Icons.unfold_more_rounded,
          onClear: f.readOnly || values[f.key] == null || !f.allowEmptyOption
              ? null
              : () {
                  setState(() => values[f.key] = null);
                  _refreshHelper(f);
                },
          onTap: f.readOnly
              ? null
              : () async {
                  final picked = await pickFromOptions(
                    context,
                    f.label,
                    opts,
                    selected: [values[f.key]],
                  );
                  if (picked != null) {
                    setState(() => values[f.key] = picked.first);
                    _refreshHelper(f);
                  }
                },
        );
      case FieldType.multiSelect:
        final opts = options[f.key]!;
        final selected = (values[f.key] as List);
        if (opts.length <= 12) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: f.label,
              errorText: err,
              helperText: f.helper,
            ),
            child: opts.isEmpty
                ? Text(
                    f.loadOptions != null ? 'Loading…' : 'No options',
                    style: context.text.bodySmall,
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: opts.map((o) {
                      final on = selected.any((s) => '$s' == '${o.value}');
                      return FilterChip(
                        label: Text(o.label),
                        selected: on,
                        labelStyle: TextStyle(
                          color: on
                              ? (context.isDark ? Brand.ink : Colors.white)
                              : null,
                        ),
                        onSelected: (yes) => setState(() {
                          selected.removeWhere((s) => '$s' == '${o.value}');
                          if (yes) selected.add(o.value);
                        }),
                      );
                    }).toList(),
                  ),
          );
        }
        final labels = opts
            .where((o) => selected.any((s) => '$s' == '${o.value}'))
            .map((o) => o.label)
            .toList();
        return _Tappable(
          label: f.label,
          value: labels.isEmpty ? null : labels.join(', '),
          hint: 'Select',
          error: err,
          icon: Icons.checklist_rounded,
          onTap: () async {
            final picked = await pickFromOptions(
              context,
              f.label,
              opts,
              selected: selected,
              multi: true,
            );
            if (picked != null) setState(() => values[f.key] = picked);
          },
        );
      case FieldType.date:
      case FieldType.dateTime:
        final d = values[f.key] as DateTime?;
        final withTime = f.type == FieldType.dateTime;
        return _Tappable(
          label: '${f.label}${f.required ? ' *' : ''}',
          value: d == null
              ? null
              : DateFormat(
                  withTime ? 'EEE, d MMM y · h:mm a' : 'EEE, d MMM y',
                ).format(d),
          hint: 'Choose ${withTime ? 'date & time' : 'date'}',
          error: err,
          helper: f.helper,
          icon: withTime
              ? Icons.schedule_rounded
              : Icons.calendar_today_rounded,
          onClear: d == null || f.readOnly
              ? null
              : () => setState(() => values[f.key] = null),
          onTap: f.readOnly
              ? null
              : () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: d ?? now,
                    firstDate: DateTime(1950),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (date == null || !mounted) return;
                  var result = date;
                  if (withTime) {
                    if (!mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(d ?? now),
                    );
                    if (time == null) return;
                    result = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  }
                  setState(() => values[f.key] = result);
                },
        );
      case FieldType.upload:
        final value = values[f.key];
        final isId = f.uploadTarget == UploadTarget.fileId;
        final url = isId ? null : str(value);
        return InputDecorator(
          decoration: InputDecoration(
            labelText: '${f.label}${f.required ? ' *' : ''}',
            errorText: err,
            helperText: f.helper,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (url != null &&
                  url.isNotEmpty &&
                  (f.imagesOnly ||
                      RegExp(
                        r'\.(png|jpe?g|gif|webp|bmp|svg)|alt=media',
                        caseSensitive: false,
                      ).hasMatch(url)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    key: ValueKey('banner:${f.key}:$url'),
                    width: double.infinity,
                    height: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(height: 120),
                      ),
                    ),
                  ),
                ),
              Text(
                value == null || '$value'.isEmpty
                    ? 'No file selected'
                    : isId
                    ? (fileLabels[f.key] ?? 'File #$value')
                    : url!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await showUploader(
                        context,
                        register: isId,
                        imagesOnly: f.imagesOnly,
                        folder: f.folder,
                      );
                      if (result == null) return;
                      setState(() {
                        values[f.key] = isId ? result.id : result.link;
                        fileLabels[f.key] = result.name;
                      });
                    },
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(value == null ? 'Add' : 'Replace'),
                  ),
                  if (value != null && !f.required)
                    TextButton(
                      onPressed: () => setState(() => values[f.key] = null),
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        );
      case FieldType.gallery:
        return _gallery(f, err);
      default:
        return TextField(
          controller: controllers[f.key],
          readOnly: f.readOnly,
          obscureText: f.type == FieldType.password,
          maxLength: f.maxLength,
          minLines: f.type == FieldType.multiline ? 3 : 1,
          maxLines: f.type == FieldType.multiline ? 8 : 1,
          onChanged:
              f.visibleWhen != null ||
                  widget.fields.any((x) => x.visibleWhen != null)
              ? (_) => setState(() {})
              : null,
          keyboardType: switch (f.type) {
            FieldType.number => TextInputType.number,
            FieldType.decimal => const TextInputType.numberWithOptions(
              decimal: true,
            ),
            FieldType.email => TextInputType.emailAddress,
            FieldType.url => TextInputType.url,
            FieldType.phone => TextInputType.phone,
            FieldType.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
          decoration: InputDecoration(
            labelText: '${f.label}${f.required ? ' *' : ''}',
            hintText: f.hint,
            helperText: f.helper,
            helperMaxLines: 3,
            errorText: err,
            alignLabelWithHint: f.type == FieldType.multiline,
          ),
        );
    }
  }

  Widget _gallery(FieldSpec f, String? err) {
    final saved = savedImages[f.key] ?? const <String>[];
    final pending = List<String>.from(values[f.key] as List);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: f.label,
        errorText: err,
        helperText: f.helper,
        helperMaxLines: 3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (saved.isEmpty && pending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('No images yet', style: context.text.bodySmall),
            ),
          if (saved.isNotEmpty) ...[
            Text('Saved', style: context.text.labelMedium),
            const SizedBox(height: 8),
            _imageRow(f.key, saved, removable: false),
            const SizedBox(height: 10),
          ],
          if (pending.isNotEmpty) ...[
            Text('New', style: context.text.labelMedium),
            const SizedBox(height: 8),
            _imageRow(f.key, pending, removable: true),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: () => _addGalleryImage(f, saved, pending),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add image'),
          ),
        ],
      ),
    );
  }

  Widget _imageRow(String field, List<String> urls, {required bool removable}) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final url = urls[i];
          return SizedBox(
            key: ValueKey('${removable ? 'pending' : 'saved'}:$field:$url'),
            width: 84,
            height: 84,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: context.colors.surfaceContainerHighest,
                        child: const Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                ),
                if (removable)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: 'Remove new image',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          setState(() => (values[field] as List).remove(url)),
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addGalleryImage(
    FieldSpec f,
    List<String> saved,
    List<String> pending,
  ) async {
    final result = await showUploader(
      context,
      register: false,
      imagesOnly: true,
      folder: f.folder,
    );
    if (!mounted || result == null) return;
    final link = result.link.trim();
    final duplicate = saved.contains(link) || pending.contains(link);
    setState(() {
      if (link.length > 2048) {
        errors[f.key] = 'Must be 2048 characters or fewer';
      } else if (duplicate) {
        errors[f.key] = 'This image is already in the gallery';
      } else if (link.isNotEmpty) {
        errors.remove(f.key);
        (values[f.key] as List).add(link);
      }
    });
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.label,
    this.value,
    this.hint,
    this.error,
    this.helper,
    required this.icon,
    this.onTap,
    this.onClear,
  });
  final String label;
  final String? value;
  final String? hint;
  final String? error;
  final String? helper;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: InputDecorator(
      isEmpty: value == null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        helperText: helper,
        helperMaxLines: 3,
        suffixIcon: onClear != null
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onClear,
              )
            : Icon(icon, size: 20),
      ),
      child: value == null
          ? null
          : Text(value!, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );
}

/// Searchable option picker (single or multi). Returns the chosen values.
Future<List<dynamic>?> pickFromOptions(
  BuildContext context,
  String title,
  List<Opt> options, {
  List<dynamic> selected = const [],
  bool multi = false,
}) => showModalBottomSheet<List<dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: options.length > 8 ? .85 : .6,
    child: _OptionPicker(
      title: title,
      options: options,
      selected: selected,
      multi: multi,
    ),
  ),
);

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({
    required this.title,
    required this.options,
    required this.selected,
    required this.multi,
  });
  final String title;
  final List<Opt> options;
  final List<dynamic> selected;
  final bool multi;
  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  final query = TextEditingController();
  late final picked = widget.selected
      .where((e) => e != null)
      .map((e) => '$e')
      .toSet();

  @override
  Widget build(BuildContext context) {
    final q = query.text.toLowerCase();
    final list = widget.options
        .where(
          (o) =>
              q.isEmpty ||
              o.label.toLowerCase().contains(q) ||
              (o.subtitle ?? '').toLowerCase().contains(q),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: context.text.titleLarge),
              ),
              if (widget.multi)
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    widget.options
                        .where((o) => picked.contains('${o.value}'))
                        .map((o) => o.value)
                        .toList(),
                  ),
                  child: Text('Done (${picked.length})'),
                ),
            ],
          ),
        ),
        if (widget.options.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBox(
              controller: query,
              hint: 'Search ${widget.options.length} options',
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final o = list[i];
                    final on = picked.contains('${o.value}');
                    return ListTile(
                      title: Text(o.label),
                      subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                      trailing: widget.multi
                          ? Checkbox(value: on, onChanged: (_) => _toggle(o))
                          : on
                          ? const Icon(Icons.check_circle_rounded)
                          : null,
                      onTap: () {
                        if (widget.multi) {
                          _toggle(o);
                        } else {
                          Navigator.pop(context, [o.value]);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _toggle(Opt o) => setState(() {
    final key = '${o.value}';
    picked.contains(key) ? picked.remove(key) : picked.add(key);
  });
}
