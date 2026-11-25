import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';

Future<List<Opt>> _bookCategoryOpts() async => optsOf(await Lookups.bookCategories());

String bookPrice(Json b) {
  final sp = toNum(b['selling_price']) ?? 0, mrp = toNum(b['mrp']) ?? 0;
  if (sp == 0 && mrp == 0) return 'Free';
  if (sp > 0 && mrp > 0 && sp < mrp) return '${money(sp)} (MRP ${money(mrp)})';
  return money(sp > 0 ? sp : mrp);
}

const _conditions = {'new': 'New', 'like_new': 'Like new', 'good': 'Good', 'fair': 'Fair', 'poor': 'Poor'};

/// Approve / reject buttons used as a sticky bottom bar on detail pages.
class ApprovalBar extends StatelessWidget {
  const ApprovalBar({super.key, required this.onApprove, required this.onReject, this.approveLabel = 'Approve', this.rejectLabel = 'Reject'});
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final String approveLabel;
  final String rejectLabel;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: context.tones.danger),
        onPressed: onReject,
        icon: const Icon(Icons.close_rounded),
        label: Text(rejectLabel),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(child: FilledButton.icon(onPressed: onApprove, icon: const Icon(Icons.check_rounded), label: Text(approveLabel))),
  ]);
}

// ───────────────────────────── Books ─────────────────────────────

class BooksPage extends StatelessWidget {
  const BooksPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Books',
    subtitle: 'Second-hand book marketplace listings',
    path: 'admin/books',
    tabs: const [TabOption('pending', 'Pending'), TabOption('approved', 'Approved'), TabOption('all', 'All')],
    tabQuery: (t) => {if (t != 'all') 'is_approved': t == 'approved' ? 1 : 0},
    filters: [
      const PagedFilter('college_id', 'College', icon: Icons.apartment_rounded, loadOptions: Lookups.collegeOpts),
      const PagedFilter('category_id', 'Category', icon: Icons.category_outlined, loadOptions: _bookCategoryOpts),
      PagedFilter('status', 'Status', icon: Icons.sell_outlined, options: [for (final s in const ['active', 'reserved', 'sold', 'removed']) Opt(s, pretty(s))]),
    ],
    actions: [
      IconButton(tooltip: 'Book categories', onPressed: () => push(context, const BookCategoriesPage()), icon: const Icon(Icons.category_outlined)),
    ],
    emptyIcon: Icons.menu_book_outlined,
    emptyTitle: 'No books found',
    itemBuilder: (context, b, reload) {
      final approved = truthy(b['is_approved']);
      final image = pick(b, ['cover_image', 'image', 'image_url', 'images.0.url', 'images.0']);
      return RecordTile(
        leading: image.startsWith('http')
            ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(image, width: 46, height: 58, fit: BoxFit.cover, errorBuilder: (_, _, _) => const IconBadge(Icons.menu_book_rounded)))
            : const IconBadge(Icons.menu_book_rounded, tone: Tone.info),
        title: str(b['title'], 'Untitled book'),
        subtitle: [bookPrice(b), personName(b['user'], '')].where((e) => e.isNotEmpty).join(' · '),
        meta: [collegeName(b['college'], ''), pick(b, ['category.name']), timeAgo(b['created_at'])].where((e) => e.isNotEmpty).join(' · '),
        pills: [Pill(approved ? 'Approved' : 'Pending', tone: approved ? Tone.success : Tone.warning), if (b['status'] != null) Pill.status(b['status'])],
        trailing: IconButton(
          tooltip: approved ? 'Unapprove' : 'Approve',
          onPressed: () async {
            if (await runAction(context, () => api.put('admin/books/${b['id']}', {'is_approved': !approved}), success: approved ? 'Approval removed' : 'Book approved')) reload();
          },
          icon: Icon(approved ? Icons.remove_done_rounded : Icons.check_circle_outline_rounded, color: approved ? null : context.tones.success),
        ),
        onTap: () async {
          await push(context, BookManagePage(slug: str(b['slug'], '${b['id']}'), initial: b));
          reload();
        },
      );
    },
  );
}

class BookManagePage extends StatefulWidget {
  const BookManagePage({super.key, required this.slug, this.initial});
  final String slug;
  final Json? initial;
  @override
  State<BookManagePage> createState() => _BookManagePageState();
}

class _BookManagePageState extends State<BookManagePage> {
  late Json book = widget.initial ?? {};
  List<Json>? interested;
  List<Json>? flagged;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      book = asMap(unwrap(await api.get('admin/books/${widget.slug}')));
      error = null;
    } catch (e) {
      if (book.isEmpty) error = errorText(e, 'Could not load the book.');
    }
    if (mounted) setState(() => loading = false);
    final slug = Uri.encodeComponent(widget.slug);
    api.get('admin/books/slug/$slug/interested-students').then((r) => rowsOf(r, ['interested_students']), onError: (_) => <Json>[]).then((v) {
      if (mounted) setState(() => interested = v);
    });
    api.get('admin/books/slug/$slug/flagged-students').then((r) => rowsOf(r, ['flagged_students']), onError: (_) => <Json>[]).then((v) {
      if (mounted) setState(() => flagged = v);
    });
  }

  Future<void> _update(Json body, String success) async {
    try {
      final res = asMap(unwrap(await api.put('admin/books/${book['id']}', body)));
      setState(() => book = {...book, ...res, ...body});
      if (mounted) toast(context, success);
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = truthy(book['is_approved']);
    final images = (book['images'] as List? ?? const []).map((i) => i is Map ? pick(i, ['url', 'image_url', 'path']) : str(i)).where((u) => u.startsWith('http')).toList();
    final cover = pick(book, ['cover_image', 'image', 'image_url']);
    if (cover.startsWith('http') && !images.contains(cover)) images.insert(0, cover);
    return AppPage(
      title: str(book['title'], 'Book'),
      loading: loading && book.isEmpty,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: 'Soft delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'Soft delete this listing?', confirmLabel: 'Delete', destructive: true);
            if (ok && context.mounted && await runAction(context, () => api.put('admin/books/${book['id']}', {'is_deleted': true}), success: 'Book soft deleted') && context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
      ],
      bottomBar: FilledButton.tonalIcon(
        onPressed: () => _update({'is_approved': !approved}, approved ? 'Approval removed' : 'Book approved'),
        icon: Icon(approved ? Icons.remove_done_rounded : Icons.check_rounded),
        label: Text(approved ? 'Remove approval' : 'Approve listing'),
      ),
      children: [
        if (images.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => showImagePreview(context, url: images[i]),
                child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(images[i], width: 150, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 150))),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(approved ? 'Approved' : 'Pending', tone: approved ? Tone.success : Tone.warning),
          Pill.status(book['status'] ?? 'active'),
          Pill(_conditions[str(book['condition_type'], 'good')] ?? pretty(book['condition_type']), tone: Tone.info),
        ]),
        const SizedBox(height: 12),
        Panel(
          child: Row(children: [
            Expanded(child: Text(bookPrice(book), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            PopupMenuButton<String>(
              tooltip: 'Change status',
              onSelected: (s) => _update({'status': s}, 'Status updated'),
              itemBuilder: (_) => [for (final s in const ['active', 'reserved', 'sold', 'removed']) PopupMenuItem(value: s, child: Text(pretty(s)))],
              child: Chip(avatar: const Icon(Icons.swap_horiz_rounded, size: 16), label: Text(pretty(book['status'] ?? 'active'))),
            ),
          ]),
        ),
        if (str(book['description']).isNotEmpty) DetailCard(title: 'Description', children: [Text(str(book['description']))]),
        DetailCard(title: 'Listing', children: [
          if (str(book['author']).isNotEmpty) KV('Author', str(book['author'])),
          KV('Category', pick(book, ['category.name'], '—')),
          KV('College', collegeName(book['college'])),
          KV('Seller', personName(book['user'])),
          if (pick(book, ['user.email']).isNotEmpty) KV('Email', pick(book, ['user.email'])),
          if (pick(book, ['user.mobile', 'contact_phone']).isNotEmpty) KV('Phone', pick(book, ['user.mobile', 'contact_phone'])),
          KV('Listed', fmtDate(book['created_at'], time: true)),
        ]),
        SectionHeader('Interested students', trailing: interested == null ? null : Pill('${interested!.length}', dense: true)),
        if (interested == null)
          const SkeletonList(count: 2)
        else if (interested!.isEmpty)
          const Banner2('No one has shown interest yet.', tone: Tone.neutral)
        else
          ...interested!.map((s) => RecordTile(
            leading: Avatar(name: personName(s['user'] ?? s, '?')),
            title: personName(s['user'] ?? s),
            subtitle: pick(s, ['user.email', 'email'], '—'),
            meta: s['created_at'] == null ? null : timeAgo(s['created_at']),
          )),
        SectionHeader('Flagged by', trailing: flagged == null ? null : Pill('${flagged!.length}', dense: true, tone: flagged!.isEmpty ? Tone.neutral : Tone.danger)),
        if (flagged == null)
          const SkeletonList(count: 2)
        else if (flagged!.isEmpty)
          const Banner2('No reports for this listing.', tone: Tone.success)
        else
          ...flagged!.map((s) => RecordTile(
            leading: const IconBadge(Icons.flag_rounded, tone: Tone.danger),
            title: personName(s['user'] ?? s),
            subtitle: str(s['reason'] ?? s['details'], '—'),
            meta: s['created_at'] == null ? null : timeAgo(s['created_at']),
          )),
      ],
    );
  }
}

class BookCategoriesPage extends StatelessWidget {
  const BookCategoriesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Book categories',
      singular: 'category',
      icon: Icons.category_outlined,
      lookupKey: 'book_categories',
      load: () async => rowsOf(await api.get('admin/book-categories')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => str(r['slug']),
      searchKeys: const ['name', 'slug'],
      activeFilter: true,
      isActive: (r) => r['is_active'] != false && r['is_active'] != 0,
      csvHeader: const ['Name', 'Slug', 'Status'],
      csvRow: (r) => [r['name'], r['slug'], r['is_active'] != false ? 'Active' : 'Inactive'],
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('slug', 'Slug', helper: 'Generated from the name if left empty'),
        FieldSpec('is_active', 'Active', type: FieldType.toggle, defaultValue: true),
      ],
      initialOf: (r) => {...r, 'is_active': r['is_active'] != false && r['is_active'] != 0},
      create: (v) => api.post('admin/book-categories', {'name': v['name'], 'slug': ?v['slug'], 'is_active': truthy(v['is_active'])}),
      update: (r, v) => api.put('admin/book-categories/${r['id']}', {'name': v['name'], 'slug': ?v['slug'], 'is_active': truthy(v['is_active'])}),
      delete: (r) => api.delete('admin/book-categories/${r['id']}'),
    ),
  );
}

// ───────────────────────────── Tuition ─────────────────────────────

String tuitionFee(Json t) {
  final amt = toNum(t['fee_amount']) ?? 0;
  if (amt == 0) return '—';
  const labels = {'per_subject': 'per subject', 'per_module': 'per module', 'per_hour': 'per hour', 'fixed': 'total'};
  final type = str(t['fee_type'], 'fixed');
  return '${str(t['currency'], 'INR')} $amt (${labels[type] ?? type})';
}

class TuitionPage extends StatelessWidget {
  const TuitionPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Tuition',
    subtitle: 'Tuition and coaching listings',
    path: 'admin/tuition-listings',
    tabs: const [TabOption('pending', 'Pending'), TabOption('approved', 'Approved'), TabOption('rejected', 'Rejected'), TabOption('cancelled', 'Cancelled'), TabOption('all', 'All')],
    tabQuery: (t) => {if (t != 'all') 'status': t},
    filters: const [
      PagedFilter('college_id', 'College', icon: Icons.apartment_rounded, loadOptions: Lookups.collegeOpts),
      PagedFilter('offered_by', 'Offered by', icon: Icons.person_pin_outlined, options: [Opt('institute', 'Institute'), Opt('individual', 'Individual')]),
    ],
    emptyIcon: Icons.school_outlined,
    emptyTitle: 'No tuition listings',
    itemBuilder: (context, t, reload) {
      final st = str(t['status'], 'pending');
      Future<void> approval(String s) async {
        if (await runAction(context, () => api.put('admin/tuition-listings/${t['id']}/approval', {'status': s}), success: 'Listing $s')) reload();
      }

      return RecordTile(
        leading: const IconBadge(Icons.school_rounded, tone: Tone.info),
        title: str(t['title'], 'Tuition #${t['id']}'),
        subtitle: [tuitionFee(t), personName(t['user'], '')].where((e) => e.isNotEmpty && e != '—').join(' · '),
        meta: [pretty(t['offered_by']), collegeName(t['college'], ''), pick(t, ['branch.name']), timeAgo(t['created_at'])].where((e) => e.isNotEmpty).join(' · '),
        pills: [Pill.status(st)],
        trailing: st == 'pending'
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Reject', onPressed: () => approval('rejected'), icon: Icon(Icons.close_rounded, color: context.tones.danger)),
                IconButton.filledTonal(tooltip: 'Approve', onPressed: () => approval('approved'), icon: const Icon(Icons.check_rounded)),
              ])
            : null,
        onTap: () async {
          await push(context, TuitionManagePage(id: t['id'], initial: t));
          reload();
        },
      );
    },
  );
}

class TuitionManagePage extends StatefulWidget {
  const TuitionManagePage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<TuitionManagePage> createState() => _TuitionManagePageState();
}

class _TuitionManagePageState extends State<TuitionManagePage> {
  late Json t = widget.initial ?? {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      t = asMap(unwrap(await api.get('admin/tuition-listings/${widget.id}')));
      error = null;
    } catch (e) {
      if (t.isEmpty) error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _approval(String s) async {
    try {
      final res = asMap(unwrap(await api.put('admin/tuition-listings/${widget.id}/approval', {'status': s})));
      setState(() => t = {...t, ...res, 'status': res['status'] ?? s});
      if (mounted) toast(context, 'Listing $s');
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = str(t['status'], 'pending');
    return AppPage(
      title: str(t['title'], 'Tuition listing'),
      loading: loading && t.isEmpty,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              final ok = await confirmDialog(context, title: 'Soft delete this listing?', confirmLabel: 'Delete', destructive: true);
              if (ok && context.mounted && await runAction(context, () => api.delete('admin/tuition-listings/${widget.id}'), success: 'Listing deleted') && context.mounted) Navigator.pop(context);
            } else {
              _approval(v);
            }
          },
          itemBuilder: (_) => [
            if (st != 'cancelled') const PopupMenuItem(value: 'cancelled', child: Text('Mark cancelled')),
            if (st != 'approved') const PopupMenuItem(value: 'approved', child: Text('Approve')),
            if (st != 'rejected') const PopupMenuItem(value: 'rejected', child: Text('Reject')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
      bottomBar: st == 'pending' ? ApprovalBar(onApprove: () => _approval('approved'), onReject: () => _approval('rejected')) : null,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [Pill.status(st), if (t['offered_by'] != null) Pill(pretty(t['offered_by']), tone: Tone.violet)]),
        const SizedBox(height: 12),
        Panel(child: Text(tuitionFee(t), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
        if (str(t['description']).isNotEmpty) DetailCard(title: 'Description', children: [Text(str(t['description']))]),
        DetailCard(title: 'Class details', children: [
          KV('Mode', pretty(t['mode'] ?? '—')),
          if (t['class_mode_type'] != null) KV('Class type', pretty(t['class_mode_type'])),
          if (str(t['duration_text']).isNotEmpty) KV('Duration', str(t['duration_text'])),
          KV('Starts', fmtDate(t['start_date'])),
          KV('Ends', fmtDate(t['end_date'])),
          if (str(t['city']).isNotEmpty) KV('City', str(t['city'])),
          if (str(t['address']).isNotEmpty) KV('Address', str(t['address'])),
          KV('College', collegeName(t['college'])),
          KV('Branch', pick(t, ['branch.name'], '—')),
          KV('Posted', fmtDate(t['created_at'], time: true)),
        ]),
        DetailCard(title: 'Contact', children: [
          KV('Posted by', personName(t['user'])),
          KV('Email', pick(t, ['user.email', 'contact_email'], '—')),
          KV('Phone', pick(t, ['user.mobile', 'contact_phone'], '—')),
          if (str(t['registration_link']).isNotEmpty) KV('Registration', str(t['registration_link']), onTap: () => openLink(context, str(t['registration_link']))),
        ]),
      ],
    );
  }
}

// ───────────────────────────── Jobs ─────────────────────────────

String jobPay(Json j) {
  final intern = j['type'] == 'internship';
  final min = j[intern ? 'stipend_min' : 'salary_min'], max = j[intern ? 'stipend_max' : 'salary_max'];
  final cur = str(j['currency'], 'INR');
  if (min != null && max != null) return '$cur $min–$max';
  if (min != null) return '$cur $min+';
  if (max != null) return '$cur up to $max';
  return '—';
}

class JobsPage extends StatelessWidget {
  const JobsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Jobs & internships',
    subtitle: 'Approve postings from companies and alumni',
    path: 'admin/job-postings',
    tabs: const [
      TabOption('pending', 'Pending'),
      TabOption('approved', 'Approved'),
      TabOption('rejected', 'Rejected'),
      TabOption('draft', 'Draft'),
      TabOption('archived', 'Archived'),
      TabOption('all', 'All'),
    ],
    tabQuery: (t) => {if (t != 'all') 'status': t},
    filters: const [
      PagedFilter('type', 'Type', icon: Icons.work_outline_rounded, options: [Opt('job', 'Job'), Opt('internship', 'Internship')]),
      PagedFilter('visibility', 'Visibility', icon: Icons.visibility_outlined, options: [Opt('public', 'Public'), Opt('campus_only', 'Campus only')]),
    ],
    emptyIcon: Icons.work_off_outlined,
    emptyTitle: 'No job postings',
    itemBuilder: (context, j, reload) {
      final st = str(j['status'], 'pending');
      return RecordTile(
        leading: IconBadge(j['type'] == 'internship' ? Icons.school_outlined : Icons.work_rounded, tone: Tone.violet),
        title: str(j['title'], 'Job #${j['id']}'),
        subtitle: [str(j['company_name']), jobPay(j)].where((e) => e.isNotEmpty && e != '—').join(' · '),
        meta: [pretty(j['type']), pretty(j['work_mode']), personName(j['user'], ''), timeAgo(j['created_at'])].where((e) => e.isNotEmpty).join(' · '),
        pills: [Pill.status(st), if (j['visibility'] == 'campus_only') const Pill('Campus only', dense: true, tone: Tone.info)],
        trailing: st == 'pending'
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Reject', onPressed: () async {
                  if (await rejectJob(context, j['id'])) reload();
                }, icon: Icon(Icons.close_rounded, color: context.tones.danger)),
                IconButton.filledTonal(tooltip: 'Approve', onPressed: () async {
                  if (await runAction(context, () => api.put('admin/job-postings/${j['id']}/approval', {'status': 'approved'}), success: 'Job approved')) reload();
                }, icon: const Icon(Icons.check_rounded)),
              ])
            : null,
        onTap: () async {
          await push(context, JobManagePage(id: j['id'], initial: j));
          reload();
        },
      );
    },
  );
}

Future<bool> rejectJob(BuildContext context, dynamic id) async {
  final reason = await promptText(context, title: 'Reject job posting', label: 'Rejection reason (optional)', required: false, confirmLabel: 'Reject', destructive: true);
  if (reason == null || !context.mounted) return false;
  return runAction(context, () => api.put('admin/job-postings/$id/approval', {'status': 'rejected', if (reason.isNotEmpty) 'rejection_reason': reason}), success: 'Job rejected');
}

class JobManagePage extends StatefulWidget {
  const JobManagePage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<JobManagePage> createState() => _JobManagePageState();
}

class _JobManagePageState extends State<JobManagePage> {
  late Json j = widget.initial ?? {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      j = asMap(unwrap(await api.get('admin/job-postings/${widget.id}')));
      error = null;
    } catch (e) {
      if (j.isEmpty) error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _set(String status) async {
    if (status == 'rejected') {
      if (await rejectJob(context, widget.id)) _load();
      return;
    }
    if (await runAction(context, () => api.put('admin/job-postings/${widget.id}/approval', {'status': status}), success: 'Job ${pretty(status).toLowerCase()}')) _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = str(j['status'], 'pending');
    final branches = (j['branches'] as List? ?? const []).map((b) => b is Map ? str(b['name']) : str(b)).where((e) => e.isNotEmpty).join(', ');
    final location = [str(j['city']), str(j['state']), str(j['country'])].where((e) => e.isNotEmpty).join(', ');
    return AppPage(
      title: str(j['title'], 'Job posting'),
      loading: loading && j.isEmpty,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              final ok = await confirmDialog(context, title: 'Soft delete this posting?', confirmLabel: 'Delete', destructive: true);
              if (ok && context.mounted && await runAction(context, () => api.delete('admin/job-postings/${widget.id}'), success: 'Posting deleted') && context.mounted) Navigator.pop(context);
            } else {
              _set(v);
            }
          },
          itemBuilder: (_) => [
            if (st != 'approved') const PopupMenuItem(value: 'approved', child: Text('Approve')),
            if (st != 'rejected') const PopupMenuItem(value: 'rejected', child: Text('Reject')),
            if (st != 'archived') const PopupMenuItem(value: 'archived', child: Text('Archive')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
      bottomBar: st == 'pending' ? ApprovalBar(onApprove: () => _set('approved'), onReject: () => _set('rejected')) : null,
      children: [
        Panel(
          child: Row(children: [
            Avatar(name: str(j['company_name'], '?'), url: pick(j, ['company_logo', 'company_logo_url']), size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(j['company_name'], '—'), style: context.text.titleMedium),
                Text(jobPay(j), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              ]),
            ),
            Pill.status(st),
          ]),
        ),
        if (str(j['rejection_reason']).isNotEmpty) Banner2('Rejected: ${j['rejection_reason']}', tone: Tone.danger),
        if (str(j['description']).isNotEmpty) DetailCard(title: 'Description', children: [Text(str(j['description']))]),
        DetailCard(title: 'Role', children: [
          KV('Type', pretty(j['type'] ?? '—')),
          KV('Work mode', pretty(j['work_mode'] ?? '—')),
          KV('Visibility', pretty(j['visibility'] ?? '—')),
          if (location.isNotEmpty) KV('Location', location),
          if (j['employment_type'] != null) KV('Employment', pretty(j['employment_type'])),
          if (j['experience_level'] != null) KV('Experience', pretty(j['experience_level'])),
          if (j['type'] == 'internship' && j['internship_duration_weeks'] != null) KV('Duration', '${j['internship_duration_weeks']} weeks'),
          if (branches.isNotEmpty) KV('Branches', branches),
          KV('Deadline', fmtDate(j['application_deadline'])),
          KV('Posted', fmtDate(j['created_at'], time: true)),
        ]),
        DetailCard(title: 'Apply & contact', children: [
          KV('Posted by', personName(j['user'])),
          KV('Email', pick(j, ['user.email'], '—')),
          KV('Phone', pick(j, ['user.mobile', 'contact_phone'], '—')),
          if (str(j['apply_url']).isNotEmpty) KV('Apply link', str(j['apply_url']), onTap: () => openLink(context, str(j['apply_url']))),
          if (str(j['apply_email']).isNotEmpty) KV('Apply email', str(j['apply_email']), onTap: () => openLink(context, 'mailto:${j['apply_email']}')),
        ]),
      ],
    );
  }
}
