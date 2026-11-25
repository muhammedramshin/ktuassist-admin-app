import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';

const paymentMethods = ['upi', 'bank_transfer', 'cash', 'card', 'other'];
const _placements = ['home_banner', 'whatsapp', 'instagram', 'push'];
const _campaignStatuses = ['pending', 'approved', 'active', 'paused', 'rejected', 'completed', 'cancelled', 'draft'];

String _owner(Json c) => pick(c, ['business_profile.business_name', 'user.name'], '—');

Color? _hex(String v) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
  return m == null ? null : Color(int.parse('FF${m.group(1)}', radix: 16));
}

// ───────────────────────────── Campaigns ─────────────────────────────

class CampaignsPage extends StatelessWidget {
  const CampaignsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Campaigns',
    subtitle: 'Business promotions, pricing and payments',
    path: 'admin/campaigns',
    perPage: 30,
    rowKeys: const ['campaigns'],
    extraQuery: const {'sort': 'latest'},
    searchKey: 'search',
    searchHint: 'Search campaigns',
    tabs: [for (final s in _campaignStatuses) TabOption(s, pretty(s))],
    tabQuery: (t) => {'status': t},
    countsOf: (res) => asMap(asMap(res)['counts']),
    actions: [
      PopupMenuButton<String>(
        onSelected: (v) => push(context, switch (v) {
          'packages' => const CampaignPackagesPage(),
          'payments' => const CampaignPaymentsPage(),
          _ => const HomeBannersPage(),
        }),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'packages', child: ListTile(leading: Icon(Icons.inventory_2_outlined), title: Text('Packages'))),
          PopupMenuItem(value: 'payments', child: ListTile(leading: Icon(Icons.payments_outlined), title: Text('Payments queue'))),
          PopupMenuItem(value: 'banners', child: ListTile(leading: Icon(Icons.view_carousel_outlined), title: Text('Home banners'))),
        ],
      ),
    ],
    emptyIcon: Icons.campaign_outlined,
    emptyTitle: 'No campaigns',
    itemBuilder: (context, c, reload) => RecordTile(
      leading: const IconBadge(Icons.campaign_rounded, tone: Tone.violet),
      title: str(c['title'], 'Campaign #${c['id']}'),
      subtitle: [_owner(c), pick(c, ['package.name'])].where((e) => e.isNotEmpty && e != '—').join(' · '),
      meta: [if (c['total'] != null) money(c['total']), if (c['start_date'] != null) '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}'].join(' · '),
      pills: [
        Pill.status(c['status']),
        if (c['payment_status'] != null) Pill(pretty(c['payment_status']), dense: true, tone: toneFor(c['payment_status'])),
        if (truthy(c['is_live'])) const Pill('Live', dense: true, tone: Tone.success, icon: Icons.circle),
      ],
      onTap: () async {
        await push(context, CampaignManagePage(id: c['id']));
        reload();
      },
    ),
  );
}

class CampaignManagePage extends StatefulWidget {
  const CampaignManagePage({super.key, required this.id});
  final dynamic id;
  @override
  State<CampaignManagePage> createState() => _CampaignManagePageState();
}

class _CampaignManagePageState extends State<CampaignManagePage> {
  Json c = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      c = asMap(unwrap(await api.get('admin/campaigns/${widget.id}')));
      error = null;
    } catch (e) {
      error = errorText(e, 'Could not load campaign.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _do(Future<dynamic> Function() task, String fallback) async {
    try {
      final res = asMap(await task());
      if (mounted) toast(context, str(res['message'], fallback));
      await _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  Future<void> _review(String action) async {
    final reason = await promptText(
      context,
      title: action == 'approve' ? 'Approve campaign' : 'Reject campaign',
      label: action == 'approve' ? 'Admin notes (optional)' : 'Rejection reason',
      required: action == 'reject',
      confirmLabel: action == 'approve' ? 'Approve' : 'Reject',
      destructive: action == 'reject',
    );
    if (reason == null) return;
    await _do(
      () => api.put('admin/campaigns/${widget.id}/review', {
        'action': action,
        if (action == 'reject') 'rejection_reason': reason,
        if (action == 'approve' && reason.isNotEmpty) 'admin_notes': reason,
      }),
      'Updated',
    );
  }

  Future<void> _status(String action) async {
    final note = await promptText(context, title: '${pretty(action)} campaign', label: 'Note (optional)', required: false, confirmLabel: pretty(action), destructive: action == 'cancel');
    if (note == null) return;
    await _do(() => api.put('admin/campaigns/${widget.id}/status', {'action': action, if (note.isNotEmpty) 'note': note}), 'Status updated');
  }

  Future<void> _pricing() async {
    final saved = await showFormSheet(
      context,
      title: 'Pricing',
      initial: c,
      submitLabel: 'Save pricing',
      fields: const [
        FieldSpec('rate', 'Rate', type: FieldType.decimal, min: 0),
        FieldSpec('discount', 'Discount', type: FieldType.decimal, min: 0),
        FieldSpec('tax_amount', 'Tax', type: FieldType.decimal, min: 0),
        FieldSpec('admin_notes', 'Admin notes', type: FieldType.multiline),
      ],
      onSubmit: (v) => api.put('admin/campaigns/${widget.id}', {...v, 'admin_notes': v['admin_notes'] ?? ''}),
    );
    if (saved != null && mounted) {
      toast(context, 'Pricing saved');
      _load();
    }
  }

  Future<void> _recordPayment() async {
    final saved = await showFormSheet(
      context,
      title: 'Record offline payment',
      initial: {'method': 'cash', 'amount': c['amount_due']},
      submitLabel: 'Record payment',
      fields: [
        const FieldSpec('amount', 'Amount', type: FieldType.decimal, required: true, min: 1),
        FieldSpec('method', 'Method', type: FieldType.select, required: true, options: [for (final m in paymentMethods) Opt(m, pretty(m))]),
        const FieldSpec('transaction_ref', 'Reference'),
        const FieldSpec('notes', 'Notes', type: FieldType.multiline),
      ],
      onSubmit: (v) => api.multipart('admin/campaigns/${widget.id}/payments', {
        'amount': '${v['amount']}',
        'method': '${v['method']}',
        if (v['transaction_ref'] != null) 'transaction_ref': '${v['transaction_ref']}',
        if (v['notes'] != null) 'notes': '${v['notes']}',
      }),
    );
    if (saved != null && mounted) {
      toast(context, 'Payment recorded');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = str(c['status']);
    final payments = rowsOf(c['payments'] ?? const []);
    return AppPage(
      title: str(c['title'], 'Campaign'),
      loading: loading && c.isEmpty,
      error: c.isEmpty ? error : null,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Status',
          onSelected: (v) => v == 'banner' ? showHomeBannerForm(context, preset: {'type': 'campaign', 'campaign_id': c['id']}) : _status(v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'pause', child: ListTile(leading: Icon(Icons.pause_circle_outline_rounded), title: Text('Pause'))),
            PopupMenuItem(value: 'resume', child: ListTile(leading: Icon(Icons.play_circle_outline_rounded), title: Text('Resume'))),
            PopupMenuItem(value: 'complete', child: ListTile(leading: Icon(Icons.task_alt_rounded), title: Text('Complete'))),
            PopupMenuItem(value: 'cancel', child: ListTile(leading: Icon(Icons.cancel_outlined), title: Text('Cancel'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'banner', child: ListTile(leading: Icon(Icons.view_carousel_outlined), title: Text('Create home banner'))),
          ],
        ),
      ],
      bottomBar: st == 'pending' ? _ApproveRejectBar(onApprove: () => _review('approve'), onReject: () => _review('reject')) : null,
      children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_owner(c), style: context.text.titleMedium),
            if (pick(c, ['user.email']).isNotEmpty) Text(pick(c, ['user.email']), style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Pill.status(st),
              if (c['payment_status'] != null) Pill(pretty(c['payment_status']), tone: toneFor(c['payment_status'])),
              if (truthy(c['is_live'])) const Pill('Live', tone: Tone.success),
            ]),
          ]),
        ),
        MetricGrid(minTileWidth: 120, children: [
          MetricTile(label: 'Total', value: money(c['total']), icon: Icons.receipt_long_rounded),
          MetricTile(label: 'Paid', value: money(c['amount_paid']), icon: Icons.check_circle_outline_rounded, tone: Tone.success),
          MetricTile(label: 'Due', value: money(c['amount_due']), icon: Icons.pending_outlined, tone: Tone.warning),
        ]),
        if (str(c['rejection_reason']).isNotEmpty) Banner2('Rejected: ${c['rejection_reason']}', tone: Tone.danger),
        DetailCard(
          title: 'Campaign',
          trailing: TextButton.icon(onPressed: _pricing, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Pricing')),
          children: [
            KV('Package', pick(c, ['package.name'], '—')),
            if (c['type'] != null) KV('Type', pretty(c['type'])),
            KV('Schedule', '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}'),
            KV('Rate', money(c['rate'])),
            KV('Discount', money(c['discount'])),
            KV('Tax', money(c['tax_amount'])),
            if (str(c['admin_notes']).isNotEmpty) KV('Admin notes', str(c['admin_notes'])),
            if (str(c['description']).isNotEmpty) KV('Description', str(c['description'])),
          ],
        ),
        SectionHeader('Payments', action: 'Record', onAction: _recordPayment),
        if (payments.isEmpty) const Banner2('No payments yet.', tone: Tone.neutral),
        ...payments.map((p) => PaymentTile(payment: p, onChanged: _load)),
      ],
    );
  }
}

class _ApproveRejectBar extends StatelessWidget {
  const _ApproveRejectBar({required this.onApprove, required this.onReject});
  final VoidCallback onApprove, onReject;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: context.tones.danger),
        onPressed: onReject,
        icon: const Icon(Icons.close_rounded),
        label: const Text('Reject'),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(child: FilledButton.icon(onPressed: onApprove, icon: const Icon(Icons.check_rounded), label: const Text('Approve'))),
  ]);
}

/// A campaign payment with proof preview and verify / reject / refund actions.
class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.payment, required this.onChanged, this.showCampaign = false});
  final Json payment;
  final VoidCallback onChanged;
  final bool showCampaign;

  Future<void> _review(BuildContext context, String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await promptText(context, title: 'Reject payment', label: 'Why is this payment rejected?', confirmLabel: 'Reject', destructive: true);
      if (reason == null) return;
    } else {
      final ok = await confirmDialog(context, title: '${pretty(action)} this payment?', confirmLabel: pretty(action), destructive: action == 'refund');
      if (!ok) return;
    }
    if (!context.mounted) return;
    if (await runAction(context, () => api.put('admin/campaign-payments/${payment['id']}/review', {'action': action, 'rejection_reason': ?reason}), success: 'Payment updated')) onChanged();
  }

  Future<void> _proof(BuildContext context) async {
    try {
      final bytes = await api.bytes(str(payment['proof']));
      if (!context.mounted) return;
      final pdf = bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF';
      if (pdf) {
        shareBytes(context, bytes, 'payment-${payment['id']}-proof.pdf', 'application/pdf');
      } else {
        showImagePreview(context, bytes: bytes, title: 'Payment proof');
      }
    } catch (e) {
      if (context.mounted) toast(context, errorText(e, 'Could not load the proof.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = str(payment['status'], 'pending');
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(money(payment['amount']), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Pill.status(st),
          const Spacer(),
          Text(pretty(payment['method']), style: context.text.labelLarge),
        ]),
        const SizedBox(height: 6),
        Text(
          [
            if (showCampaign) pick(payment, ['campaign.title']),
            if (showCampaign) personName(payment['user'], ''),
            str(payment['transaction_ref']),
            fmtDate(payment['created_at'], time: true),
          ].where((e) => e.isNotEmpty && e != '—').join(' · '),
          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        if (str(payment['rejection_reason']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(str(payment['rejection_reason']), style: TextStyle(color: context.tones.danger))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (str(payment['proof']).isNotEmpty) OutlinedButton.icon(onPressed: () => _proof(context), icon: const Icon(Icons.receipt_outlined, size: 18), label: const Text('Proof')),
          if (st == 'pending') ...[
            FilledButton.tonalIcon(onPressed: () => _review(context, 'verify'), icon: const Icon(Icons.verified_outlined, size: 18), label: const Text('Verify')),
            TextButton(style: TextButton.styleFrom(foregroundColor: context.tones.danger), onPressed: () => _review(context, 'reject'), child: const Text('Reject')),
          ],
          if (st == 'verified') TextButton(onPressed: () => _review(context, 'refund'), child: const Text('Refund')),
        ]),
      ]),
    );
  }
}

class CampaignPaymentsPage extends StatelessWidget {
  const CampaignPaymentsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Campaign payments',
    subtitle: 'Verify payment proofs from businesses',
    path: 'admin/campaign-payments',
    rowKeys: const ['payments'],
    tabs: const [TabOption('pending', 'Pending'), TabOption('verified', 'Verified'), TabOption('rejected', 'Rejected'), TabOption('refunded', 'Refunded'), TabOption('all', 'All')],
    tabQuery: (t) => {'status': t},
    countsOf: (res) => asMap(asMap(res)['counts']),
    emptyIcon: Icons.payments_outlined,
    emptyTitle: 'No payments',
    itemBuilder: (context, p, reload) => PaymentTile(payment: p, onChanged: reload, showCampaign: true),
  );
}

class CampaignPackagesPage extends StatelessWidget {
  const CampaignPackagesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Campaign packages',
      singular: 'package',
      icon: Icons.inventory_2_outlined,
      load: () async => rowsOf(await api.get('admin/campaign-packages')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => '${money(r['rate'])} · ${r['duration_days'] ?? 0} days · ${r['push_count'] ?? 0} pushes',
      metaOf: (r) => (r['placements'] as List? ?? const []).map(pretty).join(', '),
      searchKeys: const ['name', 'code', 'description'],
      activeFilter: true,
      csvHeader: const ['Name', 'Code', 'Rate', 'Days', 'Pushes', 'Placements', 'Status'],
      csvRow: (r) => [r['name'], r['code'], r['rate'], r['duration_days'], r['push_count'], (r['placements'] as List? ?? const []).join(' '), truthy(r['is_active']) ? 'Active' : 'Inactive'],
      fields: (_) => [
        const FieldSpec('name', 'Name', required: true),
        const FieldSpec('code', 'Code', required: true),
        const FieldSpec('rate', 'Rate (INR)', type: FieldType.decimal, required: true, min: 0, defaultValue: 0),
        const FieldSpec('duration_days', 'Duration (days)', type: FieldType.number, required: true, min: 1, defaultValue: 7),
        const FieldSpec('push_count', 'Push notifications included', type: FieldType.number, min: 0, defaultValue: 0),
        const FieldSpec('sort_order', 'Sort order', type: FieldType.number, defaultValue: 1),
        FieldSpec('placements', 'Placements', type: FieldType.multiSelect, options: [for (final p in _placements) Opt(p, pretty(p))], defaultValue: const ['home_banner']),
        const FieldSpec('description', 'Description', type: FieldType.multiline),
        const FieldSpec('is_active', 'Active', type: FieldType.toggle, defaultValue: true),
      ],
      initialOf: (r) => {...r, 'is_active': truthy(r['is_active'])},
      create: (v) => api.post('admin/campaign-packages', {...v, 'currency': 'INR', 'is_active': truthy(v['is_active'])}),
      update: (r, v) => api.put('admin/campaign-packages/${r['id']}', {...v, 'currency': 'INR', 'is_active': truthy(v['is_active'])}),
      delete: (r) => api.delete('admin/campaign-packages/${r['id']}'),
    ),
  );
}

// ───────────────────────────── Home banners ─────────────────────────────

Future<bool> showHomeBannerForm(BuildContext context, {Json? banner, Json? preset}) async {
  final editing = banner != null;
  final links = (banner?['links'] as List? ?? const []).whereType<Map>().map((l) => '${l['label'] ?? ''} | ${l['url'] ?? ''}').join('\n');
  String? color(dynamic v, Json _) => v != null && _hex('$v') == null ? 'Use a hex colour like #1e3a8a' : null;
  final saved = await showFormSheet(
    context,
    title: editing ? 'Edit home banner' : 'New home banner',
    submitLabel: editing ? 'Save banner' : 'Create banner',
    initial: {
      'type': 'custom',
      'theme_color': '#1e3a8a',
      'text_color': '#ffffff',
      'action_type': 'details',
      'is_active': true,
      ...?preset,
      ...?banner,
      'links': links,
      if (banner != null) 'is_active': truthy(banner['is_active']),
    },
    fields: [
      const FieldSpec('type', 'Type', type: FieldType.select, required: true, options: [Opt('custom', 'Custom'), Opt('campaign', 'Campaign')], section: 'Source'),
      FieldSpec(
        'campaign_id',
        'Campaign',
        type: FieldType.select,
        required: true,
        visibleWhen: (v) => v['type'] == 'campaign',
        loadOptions: () async => optsOf(rowsOf(await api.get('admin/home-banners/campaign-options')), labelKeys: const ['title', 'name', 'label']),
      ),
      const FieldSpec('eyebrow', 'Eyebrow', section: 'Content'),
      const FieldSpec('title', 'Title'),
      const FieldSpec('subtitle', 'Subtitle'),
      const FieldSpec('description', 'Description', type: FieldType.multiline),
      const FieldSpec('body_content', 'Body content', type: FieldType.multiline),
      const FieldSpec('links', 'Links', type: FieldType.multiline, helper: 'One per line: Label | https://…'),
      const FieldSpec('image_small', 'Image (small)', type: FieldType.upload, imagesOnly: true, section: 'Look'),
      const FieldSpec('image_large', 'Image (large)', type: FieldType.upload, imagesOnly: true),
      FieldSpec('theme_color', 'Theme colour', validator: color),
      FieldSpec('text_color', 'Text colour', validator: color),
      const FieldSpec('action_type', 'Action', type: FieldType.select, options: [Opt('details', 'Details'), Opt('internal_route', 'Internal route'), Opt('external_link', 'External link'), Opt('none', 'None')], section: 'Action'),
      FieldSpec('action_label', 'Action label', visibleWhen: (v) => v['action_type'] != 'none'),
      FieldSpec('action_value', 'Action value', visibleWhen: (v) => v['action_type'] == 'internal_route' || v['action_type'] == 'external_link', hint: '/events or https://…'),
      const FieldSpec('is_active', 'Active', type: FieldType.toggle),
    ],
    onSubmit: (v) {
      final linkRows = str(v['links']).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).map((l) {
        final parts = l.split('|').map((p) => p.trim()).toList();
        final label = parts.first, url = parts.length > 1 ? parts[1] : '';
        return {'label': label.isEmpty ? 'Link' : label, 'url': url.isEmpty ? label : url};
      }).toList();
      final body = {
        for (final e in v.entries)
          if (e.key != 'links' && e.value != null) e.key: e.value,
        'campaign_id': v['type'] == 'campaign' ? v['campaign_id'] : null,
        'links': linkRows,
        'action_type': str(v['action_type'], 'details'),
        'is_active': truthy(v['is_active']),
      }..removeWhere((k, val) => k == 'campaign_id' && val == null);
      return editing ? api.put('admin/home-banners/${banner['id']}', body) : api.post('admin/home-banners', body);
    },
  );
  if (saved != null && context.mounted) toast(context, editing ? 'Banner saved' : 'Banner created');
  return saved != null;
}

class HomeBannersPage extends StatefulWidget {
  const HomeBannersPage({super.key});
  @override
  State<HomeBannersPage> createState() => _HomeBannersPageState();
}

class _HomeBannersPageState extends State<HomeBannersPage> {
  List<Json> items = [];
  bool loading = true;
  String? error;
  bool reordering = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      items = rowsOf(await api.get('admin/home-banners'));
      error = null;
    } catch (e) {
      error = errorText(e, 'Could not load home banners.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _reorder(int from, int to) async {
    final row = items.removeAt(from);
    items.insert(to, row);
    setState(() => reordering = true);
    try {
      await api.put('admin/home-banners/reorder', {'ids': items.map((e) => e['id']).toList()});
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not reorder banners.'), error: true);
      await _load();
    }
    if (mounted) setState(() => reordering = false);
  }

  Future<void> _open(Json b) async {
    var full = b;
    try {
      full = asMap(unwrap(await api.get('admin/home-banners/${b['id']}')));
    } catch (_) {}
    if (!mounted) return;
    if (await showHomeBannerForm(context, banner: full)) _load();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Home banners',
    subtitle: 'Carousel on the student home screen. Drag to reorder.',
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    actions: [if (reordering) const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))],
    fab: FloatingActionButton.extended(
      heroTag: 'banner-fab',
      onPressed: () async {
        if (await showHomeBannerForm(context)) _load();
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('New banner'),
    ),
    slivers: [
      if (items.isEmpty)
        const SliverToBoxAdapter(child: EmptyState(icon: Icons.view_carousel_outlined, title: 'No home banners'))
      else
        SliverReorderableList(
          itemCount: items.length,
          onReorderItem: _reorder,
          itemBuilder: (context, i) {
            final b = items[i];
            final r = asMap(b['resolved']).isEmpty ? b : asMap(b['resolved']);
            final image = str(r['image_large'] ?? r['image_small']);
            final bg = _hex(str(r['theme_color'])) ?? const Color(0xFF13253F);
            final fg = _hex(str(r['text_color'])) ?? Colors.white;
            return ReorderableDelayedDragStartListener(
              key: ValueKey(b['id']),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: bg,
                  borderRadius: BorderRadius.circular(Brand.radius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(b),
                    child: Container(
                      height: 150,
                      decoration: image.startsWith('http')
                          ? BoxDecoration(image: DecorationImage(image: NetworkImage(image), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken)))
                          : null,
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Pill(pretty(b['type'] ?? 'custom'), dense: true, tone: Tone.brand),
                          const SizedBox(width: 6),
                          if (!truthy(b['is_active'])) const Pill('Inactive', dense: true, tone: Tone.danger),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Delete',
                            color: fg,
                            onPressed: () async {
                              final ok = await confirmDialog(context, title: 'Remove this banner from the carousel?', confirmLabel: 'Remove', destructive: true);
                              if (ok && context.mounted && await runAction(context, () => api.delete('admin/home-banners/${b['id']}'), success: 'Banner removed')) _load();
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                          ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, color: fg)),
                        ]),
                        const Spacer(),
                        if (str(r['eyebrow']).isNotEmpty) Text(str(r['eyebrow']).toUpperCase(), style: context.text.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8), letterSpacing: 1)),
                        Text(str(r['title'], 'Untitled banner'), style: context.text.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (str(r['subtitle']).isNotEmpty) Text(str(r['subtitle']), style: context.text.bodySmall?.copyWith(color: fg.withValues(alpha: 0.9)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ],
  );
}
