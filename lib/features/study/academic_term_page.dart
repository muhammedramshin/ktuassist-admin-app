import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';

const _defaultMessage = 'Confirm your current semester so we can show the right materials.';

class AcademicTermPage extends StatefulWidget {
  const AcademicTermPage({super.key});
  @override
  State<AcademicTermPage> createState() => _AcademicTermPageState();
}

class _AcademicTermPageState extends State<AcademicTermPage> {
  Json term = {};
  bool loading = true;
  bool saving = false;
  String? error;
  final label = TextEditingController();
  final message = TextEditingController();
  DateTime? promptAt;
  DateTime? startsAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Json _read(dynamic res) {
    final body = res is Map && res['data'] is Map ? asMap(res['data']) : asMap(res);
    return asMap(body['academic_term'] ?? body['term'] ?? body);
  }

  void _apply(Json t) {
    term = t;
    label.text = str(t['label']);
    message.text = str(t['message']);
    promptAt = parseDate(t['prompt_at']);
    startsAt = parseDate(t['starts_at']);
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      _apply(_read(await api.get('admin/academic-term')));
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<DateTime?> _pick(DateTime? current, {bool time = true}) async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: current ?? now, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 3));
    if (date == null || !time || !mounted) return date;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
    return t == null ? null : DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final l = label.text.trim();
    if (l.isEmpty) {
      toast(context, 'Term label is required, e.g. 2026 Even.', error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: promptAt != null ? 'Start prompting students?' : 'Stop prompting?',
      message: promptAt != null
          ? 'Ask every studying student to confirm their semester for "$l" from ${DateFormat('d MMM y, h:mm a').format(promptAt!)}?'
          : 'Stop asking students to confirm their semester?',
    );
    if (!ok || !mounted) return;
    setState(() => saving = true);
    try {
      final res = await api.put('admin/academic-term', {
        'label': l,
        'prompt_at': promptAt == null ? null : isoWithOffset(promptAt!),
        'starts_at': startsAt == null ? null : isoWithOffset(startsAt!),
        'message': message.text.trim().isEmpty ? null : message.text.trim(),
      });
      final t = _read(res);
      if (str(t['label']).isNotEmpty || t['prompt_at'] != null) {
        _apply(t);
      } else {
        await _load();
      }
      if (mounted) toast(context, promptAt != null ? 'Saved. Students will be asked to confirm their semester.' : 'Saved. Students will not be prompted.');
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final prompting = term['prompt_at'] != null;
    return AppPage(
      title: 'Academic term',
      subtitle: 'Ask students to confirm their current semester at the start of each term.',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            gradient: LinearGradient(colors: context.isDark ? [const Color(0xff2A2610), const Color(0xff1B1C21)] : [Brand.yellowSoft, Colors.white]),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(str(term['label'], 'No label'), style: context.text.headlineSmall)),
                Pill(prompting ? 'Prompting students' : 'Not prompting', tone: prompting ? Tone.success : Tone.neutral),
              ]),
              const SizedBox(height: 12),
              KV('Prompt from', term['prompt_at'] == null ? '—' : fmtDate(term['prompt_at'], time: true)),
              KV('Term starts', term['starts_at'] == null ? '—' : fmtDate(term['starts_at'])),
              const SizedBox(height: 4),
              Text(str(term['message'], _defaultMessage), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        ),
        DetailCard(
          title: 'Update term',
          children: [
            const SizedBox(height: 8),
            TextField(controller: label, maxLength: 100, decoration: const InputDecoration(labelText: 'Term label *', hintText: '2026 Even')),
            const SizedBox(height: 8),
            _DateRow(
              label: 'Ask students from',
              value: promptAt,
              withTime: true,
              onPick: () async {
                final d = await _pick(promptAt);
                if (d != null) setState(() => promptAt = d);
              },
              onNow: () => setState(() => promptAt = DateTime.now()),
              onClear: () => setState(() => promptAt = null),
            ),
            const SizedBox(height: 12),
            _DateRow(
              label: 'Term starts (optional)',
              value: startsAt,
              onPick: () async {
                final d = await _pick(startsAt, time: false);
                if (d != null) setState(() => startsAt = d);
              },
              onClear: () => setState(() => startsAt = null),
            ),
            const SizedBox(height: 12),
            TextField(controller: message, maxLength: 500, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Message to students', hintText: _defaultMessage, alignLabelWithHint: true)),
            const SizedBox(height: 8),
            Text(
              'Leaving “Ask students from” empty stops prompting.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save term')),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value, required this.onPick, required this.onClear, this.onNow, this.withTime = false});
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final VoidCallback? onNow;
  final bool withTime;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(labelText: label, suffixIcon: Icon(withTime ? Icons.schedule_rounded : Icons.calendar_today_rounded)),
            child: value == null ? null : Text(DateFormat(withTime ? 'd MMM y, h:mm a' : 'd MMM y').format(value!)),
          ),
        ),
      ),
      if (onNow != null) TextButton(onPressed: onNow, child: const Text('Now')),
      IconButton(onPressed: value == null ? null : onClear, icon: const Icon(Icons.close_rounded)),
    ],
  );
}
