import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

String _docLabel(dynamic v) => switch (str(v)) {
  'college_id_card' => 'College ID card',
  'university_id_card' => 'University ID card',
  'other' => 'Other',
  '' => 'ID card',
  final s => s,
};

class VerificationRequestsPage extends StatefulWidget {
  const VerificationRequestsPage({super.key});
  @override
  State<VerificationRequestsPage> createState() => _VerificationRequestsPageState();
}

class _VerificationRequestsPageState extends State<VerificationRequestsPage> {
  String status = 'pending';
  final search = TextEditingController();
  dynamic collegeId;
  String collegeLabel = '';
  List<Json> rows = [];
  PageMeta meta = const PageMeta();
  Json counts = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([int page = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = asMap(await api.get('admin/verification-requests', query: {'status': status, 'search': search.text.trim(), 'college_id': collegeId, 'page': page}));
      final payload = res['requests'] != null ? res : asMap(res['data'] ?? res);
      counts = asMap(payload['counts']);
      final pageData = payload['requests'] ?? payload;
      rows = rowsOf(pageData);
      meta = PageMeta.of(pageData);
    } catch (e) {
      error = errorText(e, 'Could not load verification requests.');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    int c(String k) => toInt(counts[k]);
    return AppPage(
      title: 'ID verification',
      subtitle: 'Review student ID cards and verify accounts',
      onRefresh: () => _load(meta.page),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBox(controller: search, hint: 'Search name, email or ID number', onSubmitted: (_) => _load()),
          const SizedBox(height: 12),
          ChipTabs<String>(
            selected: status,
            onSelected: (v) {
              setState(() => status = v);
              _load();
            },
            options: [
              TabOption('pending', 'Pending', count: c('pending')),
              TabOption('approved', 'Approved', count: c('approved')),
              TabOption('rejected', 'Rejected', count: c('rejected')),
              TabOption('all', 'All', count: c('pending') + c('approved') + c('rejected')),
            ],
          ),
          const SizedBox(height: 10),
          ActionChip(
            avatar: const Icon(Icons.apartment_rounded, size: 16),
            label: Text(collegeId == null ? 'All colleges' : collegeLabel),
            onPressed: () async {
              final opts = await Lookups.collegeOpts().catchError((_) => <Opt>[]);
              if (!context.mounted) return;
              final p = await pickFromOptions(context, 'College', [const Opt(null, 'All colleges'), ...opts], selected: [collegeId]);
              if (p == null) return;
              setState(() {
                collegeId = p.first;
                collegeLabel = opts.where((o) => o.value == collegeId).firstOrNull?.label ?? '';
              });
              _load();
            },
          ),
        ],
      ),
      children: [
        if (loading)
          const SkeletonList()
        else if (error != null)
          ErrorState(message: error!, onRetry: () => _load(meta.page))
        else if (rows.isEmpty)
          EmptyState(icon: Icons.verified_user_outlined, title: status == 'pending' ? 'No pending requests' : 'No requests found', message: status == 'pending' ? 'You are all caught up.' : null)
        else ...[
          ...rows.map((r) {
            final user = asMap(r['user']);
            return RecordTile(
              leading: Avatar(name: str(user['name'], 'S')),
              title: str(user['name'], 'Student'),
              subtitle: [str(user['email'], str(user['mobile'], '—')), collegeName(r['college'], '')].where((e) => e.isNotEmpty).join(' · '),
              meta: fmtDate(r['created_at'], time: true),
              pills: [
                Pill.status(r['status']),
                Pill(_docLabel(r['document_type']), dense: true),
                if (str(r['id_number']).isNotEmpty) Pill(str(r['id_number']), dense: true, tone: Tone.info),
              ],
              onTap: () async {
                await push(context, VerificationReviewPage(id: r['id']));
                _load(meta.page);
              },
            );
          }),
          Pager(meta: meta, onPage: _load),
        ],
      ],
    );
  }
}

class VerificationReviewPage extends StatefulWidget {
  const VerificationReviewPage({super.key, required this.id});
  final dynamic id;
  @override
  State<VerificationReviewPage> createState() => _VerificationReviewPageState();
}

class _VerificationReviewPageState extends State<VerificationReviewPage> {
  Json request = {};
  List<Json> previous = [];
  int reward = 20;
  bool loading = true;
  bool reviewing = false;
  String? error;
  String? message;
  final docs = <String, ({Uint8List bytes, bool pdf, String url})>{};
  final docErrors = <String>[];
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = asMap(await api.get('admin/verification-requests/${widget.id}'));
      final data = res['data'];
      request = data is Map && data['id'] != null ? asMap(data) : asMap(res['request'] ?? data ?? res);
      previous = rowsOf(res['previous_requests'] ?? asMap(data)['previous_requests'] ?? []);
      reward = toInt(res['reward_points'] ?? asMap(data)['reward_points'], 20);
      error = null;
      _loadDocs();
    } catch (e) {
      error = errorText(e, 'Could not load this request.');
    }
    if (mounted) setState(() => loading = false);
  }

  void _loadDocs() {
    docs.clear();
    docErrors.clear();
    for (final (label, key) in const [('Front', 'id_card_front'), ('Back', 'id_card_back')]) {
      final url = str(request[key]);
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) continue;
      api.bytes(url).then((b) {
        final pdf = b.length > 4 && String.fromCharCodes(b.sublist(0, 4)) == '%PDF';
        if (mounted) setState(() => docs[label] = (bytes: b, pdf: pdf, url: url));
      }).catchError((_) {
        if (mounted) setState(() => docErrors.add('Could not load the ${label.toLowerCase()} of the ID card.'));
      });
    }
  }

  Future<void> _review(String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await promptText(context,
          title: 'Reject verification', message: 'The student will see this reason.', label: 'Rejection reason', confirmLabel: 'Reject', destructive: true, maxLines: 4);
      if (reason == null) return;
    } else {
      final ok = await confirmDialog(context, title: 'Approve verification?', message: 'The account becomes verified and $reward points are credited once.', confirmLabel: 'Approve');
      if (!ok) return;
    }
    setState(() {
      reviewing = true;
      error = null;
    });
    try {
      final res = asMap(await api.put('admin/verification-requests/${request['id'] ?? widget.id}/review', {
        'action': action,
        if (notes.text.trim().isNotEmpty) 'admin_notes': notes.text.trim(),
        'rejection_reason': ?reason,
      }));
      message = str(res['message'], action == 'approve' ? 'Verification approved. $reward points credited to the user.' : 'Verification rejected.');
      if (mounted) toast(context, message!);
      await _load();
    } on ApiException catch (e) {
      error = e.status == 409 ? str(e.message, 'This request was already reviewed.') : e.message;
      if (e.status == 409) await _load();
    } catch (e) {
      error = errorText(e, 'Could not save this review.');
    }
    if (mounted) setState(() => reviewing = false);
  }

  String _profileName(dynamic v) => v == null ? '—' : v is String ? v : str(asMap(v)['name'] ?? asMap(v)['title'], '—');

  @override
  Widget build(BuildContext context) {
    final user = asMap(request['user']);
    final profile = asMap(user['student_profile']);
    final canReview = request['status'] == 'pending' && !reviewing;
    return AppPage(
      title: 'Request #${request['id'] ?? widget.id}',
      loading: loading && request.isEmpty,
      error: request.isEmpty ? error : null,
      onRetry: _load,
      onRefresh: _load,
      bottomBar: canReview
          ? Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: context.tones.danger),
                  onPressed: () => _review('reject'),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(onPressed: () => _review('approve'), icon: const Icon(Icons.check_rounded), label: const Text('Approve')),
              ),
            ])
          : null,
      children: [
        if (error != null && request.isNotEmpty) Banner2(error!, tone: Tone.danger),
        if (message != null) Banner2(message!, tone: Tone.success),
        Panel(
          child: Row(children: [
            Avatar(name: str(user['name'], 'S'), size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(user['name'], 'Student'), style: context.text.titleLarge),
                Text([str(user['email'], '—'), str(user['mobile'])].where((e) => e.isNotEmpty).join(' · '),
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
              ]),
            ),
            Pill.status(request['status']),
          ]),
        ),
        DetailCard(title: 'Document', children: [
          KV('Type', _docLabel(request['document_type'])),
          KV('ID number', str(request['id_number'], '—')),
          KV('Submitted', fmtDate(request['created_at'], time: true)),
          if (str(request['notes']).isNotEmpty) KV('Student notes', str(request['notes'])),
          if (str(request['rejection_reason']).isNotEmpty) KV('Rejection reason', str(request['rejection_reason'])),
          if (str(request['admin_notes']).isNotEmpty) KV('Admin notes', str(request['admin_notes'])),
        ]),
        for (final e in docErrors) Banner2(e, tone: Tone.warning),
        if (docs.isNotEmpty)
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final MapEntry(key: label, value: d) in docs.entries)
              SizedBox(
                width: context.isWide ? 360 : double.infinity,
                child: Panel(
                  padding: const EdgeInsets.all(10),
                  onTap: d.pdf ? () => shareBytes(context, d.bytes, 'id-card-${label.toLowerCase()}.pdf', 'application/pdf') : () => showImagePreview(context, bytes: d.bytes, title: label),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(label, style: context.text.titleSmall)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: d.pdf
                          ? Container(
                              height: 140,
                              color: context.colors.surfaceContainer,
                              alignment: Alignment.center,
                              child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.picture_as_pdf_rounded, size: 40), SizedBox(height: 6), Text('PDF · tap to open')]),
                            )
                          : Image.memory(d.bytes, height: 220, width: double.infinity, fit: BoxFit.cover),
                    ),
                  ]),
                ),
              ),
          ])
        else if (str(request['id_card_front']).isNotEmpty && docErrors.isEmpty)
          const Panel(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))),
        DetailCard(title: 'Student profile', children: [
          KV('College', _profileName(profile['college']) != '—' ? _profileName(profile['college']) : collegeName(request['college'])),
          KV('Course', _profileName(profile['course'])),
          KV('Branch', _profileName(profile['branch'])),
          KV('Semester', _profileName(profile['semester'])),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Approval credits $reward points, paid once.', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        ]),
        if (canReview)
          TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Admin notes (optional)', hintText: 'Only admins see these notes')),
        if (previous.isNotEmpty) ...[
          const SectionHeader('Previous requests'),
          ...previous.map((p) => RecordTile(
            title: 'Request #${p['id']}',
            meta: fmtDate(p['created_at']),
            pills: [Pill.status(p['status'])],
            onTap: () => push(context, VerificationReviewPage(id: p['id'])),
          )),
        ],
      ],
    );
  }
}
