import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

const _locationTypes = [
  Opt('on_campus', 'On campus'),
  Opt('off_campus', 'Off campus'),
  Opt('online', 'Online'),
  Opt('hybrid', 'Hybrid'),
];
const _visibility = [
  Opt('public', 'Public'),
  Opt('university_only', 'University only'),
  Opt('private_invite', 'Private invite'),
];
const _eventStatuses = [
  Opt('scheduled', 'Scheduled'),
  Opt('cancelled', 'Cancelled'),
  Opt('completed', 'Completed'),
];

String _utc(dynamic v) {
  final d = parseDate(v);
  return d == null ? '' : d.toUtc().toIso8601String().substring(0, 19);
}

String _label(List<Opt> opts, dynamic v) =>
    opts.where((o) => o.value == v).firstOrNull?.label ?? pretty(v);

/// Creates (`event == null`) or edits an event. Returns the saved payload.
Future<Json?> showEventForm(BuildContext context, {Json? event}) {
  final editing = event != null;
  bool physical(Json v) => v['location_type'] != 'online';
  bool virtual(Json v) =>
      v['location_type'] == 'online' || v['location_type'] == 'hybrid';
  return showFormSheet(
    context,
    title: editing ? 'Edit event' : 'New event',
    submitLabel: editing ? 'Save changes' : 'Create event',
    initial: editing
        ? {
            ...event,
            'category_id': event['category_id'] ?? dig(event, 'category.id'),
            'college_id': event['college_id'] ?? dig(event, 'college.id'),
            'tag_ids': (event['tags'] as List? ?? const [])
                .map((t) => t is Map ? t['id'] : t)
                .where((e) => e != null)
                .toList(),
            'is_registration_required': truthy(
              event['is_registration_required'],
            ),
          }
        : const {
            'timezone': 'Asia/Kolkata',
            'location_type': 'online',
            'visibility': 'public',
            'currency': 'INR',
          },
    fields: [
      const FieldSpec(
        'title',
        'Title',
        required: true,
        maxLength: 200,
        section: 'Basics',
      ),
      const FieldSpec(
        'description',
        'Description',
        type: FieldType.multiline,
        required: true,
      ),
      const FieldSpec(
        'category_id',
        'Category',
        type: FieldType.select,
        loadOptions: Lookups.eventCategoryOpts,
      ),
      const FieldSpec(
        'tag_ids',
        'Tags',
        type: FieldType.multiSelect,
        loadOptions: Lookups.tagOpts,
      ),
      const FieldSpec(
        'college_id',
        'College',
        type: FieldType.select,
        loadOptions: Lookups.collegeOpts,
        allowEmptyOption: true,
        helper: 'Leave empty for an event open to everyone',
      ),
      const FieldSpec(
        'visibility',
        'Visibility',
        type: FieldType.select,
        options: _visibility,
      ),
      if (editing)
        const FieldSpec(
          'status',
          'Status',
          type: FieldType.select,
          options: _eventStatuses,
          defaultValue: 'scheduled',
        ),
      const FieldSpec(
        'start_datetime',
        'Starts',
        type: FieldType.dateTime,
        required: true,
        section: 'Schedule',
      ),
      FieldSpec(
        'end_datetime',
        'Ends',
        type: FieldType.dateTime,
        validator: (v, all) {
          final s = parseDate(all['start_datetime']), e = parseDate(v);
          return s != null && e != null && e.isBefore(s)
              ? 'End must be after the start'
              : null;
        },
      ),
      const FieldSpec('timezone', 'Timezone', defaultValue: 'Asia/Kolkata'),
      const FieldSpec(
        'location_type',
        'Location type',
        type: FieldType.select,
        required: true,
        options: _locationTypes,
        section: 'Location',
      ),
      FieldSpec('venue_name', 'Venue', visibleWhen: physical),
      FieldSpec(
        'address_text',
        'Address',
        type: FieldType.multiline,
        visibleWhen: physical,
      ),
      FieldSpec(
        'meeting_url',
        'Meeting link',
        type: FieldType.url,
        visibleWhen: virtual,
      ),
      const FieldSpec('organizer_name', 'Organizer name', section: 'Organizer'),
      const FieldSpec(
        'organizer_email',
        'Organizer email',
        type: FieldType.email,
      ),
      const FieldSpec(
        'organizer_phone',
        'Organizer phone',
        type: FieldType.phone,
      ),
      const FieldSpec(
        'is_registration_required',
        'Registration required',
        type: FieldType.toggle,
        section: 'Registration',
      ),
      FieldSpec(
        'registration_url',
        'Registration link',
        type: FieldType.url,
        visibleWhen: (v) => truthy(v['is_registration_required']),
      ),
      const FieldSpec('capacity', 'Capacity', type: FieldType.number, min: 1),
      const FieldSpec(
        'fee_amount',
        'Fee',
        type: FieldType.decimal,
        min: 0,
        hint: 'Leave empty for free events',
      ),
      const FieldSpec('currency', 'Currency', defaultValue: 'INR'),
      if (editing) ...[
        const FieldSpec(
          'cover_image_url',
          'Cover image',
          type: FieldType.upload,
          imagesOnly: true,
          section: 'Media',
        ),
        const FieldSpec(
          'poster_url',
          'Poster',
          type: FieldType.upload,
          imagesOnly: true,
        ),
      ],
    ],
    onSubmit: (v) {
      final payload = {
        ...v,
        'start_datetime': _utc(v['start_datetime']),
        'end_datetime': v['end_datetime'] == null
            ? null
            : _utc(v['end_datetime']),
        'timezone': str(v['timezone'], 'Asia/Kolkata'),
        'currency': str(v['currency'], 'INR'),
        'visibility': str(v['visibility'], 'public'),
        'is_registration_required': truthy(v['is_registration_required']),
        'tag_ids': v['tag_ids'] ?? const [],
        'venue_name': v['venue_name'],
        'address_text': v['address_text'],
        'meeting_url': v['meeting_url'],
        'registration_url': v['registration_url'],
      };
      return editing
          ? api.put('events/${event['id']}', payload)
          : api.post('admin/event', payload);
    },
  );
}

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  String tab = 'pending';
  dynamic categoryId;
  List<Json> rows = [];
  List<Opt> categories = [];
  PageMeta meta = const PageMeta();
  bool loading = true;
  String? error;
  final busy = <dynamic>{};

  @override
  void initState() {
    super.initState();
    Lookups.eventCategoryOpts().then(
      (c) => mounted ? setState(() => categories = c) : null,
      onError: (_) {},
    );
    _load();
  }

  Future<void> _load([int page = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await api.get(
        'admin/events',
        query: {
          'per_page': 15,
          'page': page,
          if (tab != 'all') 'approval_status': tab,
          'category_id': categoryId,
        },
      );
      rows = rowsOf(res);
      meta = PageMeta.of(res);
    } catch (e) {
      error = errorText(e);
      rows = [];
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _approval(Json ev, String status) async {
    setState(() => busy.add(ev['id']));
    if (await runAction(
      context,
      () => api.put('events/${ev['id']}/approval', {'approval_status': status}),
      success: 'Event $status',
    )) {
      await _load(meta.page);
    }
    if (mounted) setState(() => busy.remove(ev['id']));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Events',
      subtitle: 'Approve, edit and manage campus events',
      onRefresh: () => _load(meta.page),
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) => push(
            context,
            v == 'categories' ? const EventCategoriesPage() : const TagsPage(),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'categories',
              child: ListTile(
                leading: Icon(Icons.category_outlined),
                title: Text('Event categories'),
              ),
            ),
            PopupMenuItem(
              value: 'tags',
              child: ListTile(
                leading: Icon(Icons.sell_outlined),
                title: Text('Tags'),
              ),
            ),
          ],
        ),
      ],
      fab: FloatingActionButton.extended(
        heroTag: 'events-fab',
        onPressed: () async {
          if (await showEventForm(context) != null && context.mounted) {
            toast(context, 'Event created');
            _load();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New event'),
      ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChipTabs<String>(
            selected: tab,
            onSelected: (v) {
              setState(() => tab = v);
              _load();
            },
            options: const [
              TabOption('pending', 'Pending'),
              TabOption('approved', 'Approved'),
              TabOption('rejected', 'Rejected'),
              TabOption('all', 'All'),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            ActionChip(
              avatar: const Icon(Icons.category_outlined, size: 16),
              label: Text(
                categoryId == null
                    ? 'All categories'
                    : _label(categories, categoryId),
              ),
              onPressed: () async {
                final p = await pickFromOptions(
                  context,
                  'Category',
                  [const Opt(null, 'All categories'), ...categories],
                  selected: [categoryId],
                );
                if (p != null) {
                  setState(() => categoryId = p.first);
                  _load();
                }
              },
            ),
          ],
        ],
      ),
      children: [
        if (loading)
          const SkeletonList()
        else if (error != null)
          ErrorState(message: error!, onRetry: () => _load(meta.page))
        else if (rows.isEmpty)
          EmptyState(
            icon: Icons.event_busy_outlined,
            title: tab == 'pending'
                ? 'No events waiting for approval'
                : 'No events found',
          )
        else ...[
          ...rows.map((ev) {
            final approval = str(ev['approval_status'], 'pending');
            final isBusy = busy.contains(ev['id']);
            return RecordTile(
              leading: _EventDate(ev['start_datetime']),
              title: str(ev['title'], 'Untitled event'),
              subtitle: [
                str(dig(ev, 'category.name')),
                personName(ev['created_by'] ?? ev['user'], ''),
              ].where((e) => e.isNotEmpty).join(' · '),
              meta: [
                _label(_locationTypes, ev['location_type']),
                if (ev['status'] != null) pretty(ev['status']),
              ].join(' · '),
              pills: [Pill.status(approval)],
              trailing: isBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : approval == 'pending'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Reject',
                          onPressed: () => _approval(ev, 'rejected'),
                          icon: Icon(
                            Icons.close_rounded,
                            color: context.tones.danger,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Approve',
                          onPressed: () => _approval(ev, 'approved'),
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ],
                    )
                  : null,
              onTap: () async {
                await push(context, EventManagePage(id: ev['id'], initial: ev));
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

class _EventDate extends StatelessWidget {
  const _EventDate(this.value);
  final dynamic value;
  @override
  Widget build(BuildContext context) {
    final d = parseDate(value);
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return Container(
      width: 48,
      height: 52,
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: d == null
          ? Icon(Icons.event_rounded, color: context.colors.onPrimaryContainer)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  months[d.month - 1],
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${d.day}',
                  style: context.text.titleLarge?.copyWith(
                    color: context.colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
    );
  }
}

class EventManagePage extends StatefulWidget {
  const EventManagePage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<EventManagePage> createState() => _EventManagePageState();
}

class _EventManagePageState extends State<EventManagePage> {
  late Json event = widget.initial ?? {};
  bool loading = true;
  String? error;
  String tab = 'details';
  List<Json>? registrations;
  List<Json>? comments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = asMap(unwrap(await api.get('admin/events/${widget.id}')));
      event = asMap(res['event'] ?? res);
      error = null;
      if (event.isEmpty) error = 'Event not found.';
    } catch (e) {
      if (event.isEmpty) error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadRegistrations() async {
    try {
      final res = await api.get('events/${widget.id}/registrations');
      final regs = asMap(res)['registrations'] ?? res;
      registrations = rowsOf(regs);
    } catch (_) {
      registrations = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadComments() async {
    try {
      comments = rowsOf(await api.get('events/${widget.id}/comments'));
    } catch (_) {
      comments = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _approval(String status) async {
    if (await runAction(
      context,
      () =>
          api.put('events/${widget.id}/approval', {'approval_status': status}),
      success: 'Event $status',
    )) {
      setState(() => event['approval_status'] = status);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this event?',
      message: 'This soft-deletes "${event['title']}".',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok &&
        mounted &&
        await runAction(
          context,
          () => api.delete('events/${widget.id}'),
          success: 'Event deleted',
        ) &&
        mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approval = str(event['approval_status'], 'pending');
    return AppPage(
      title: str(event['title'], 'Event'),
      loading: loading && event.isEmpty,
      error: error,
      onRetry: _load,
      onRefresh: () async {
        await _load();
        if (tab == 'registrations') await _loadRegistrations();
        if (tab == 'comments') await _loadComments();
      },
      actions: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: event.isEmpty
              ? null
              : () async {
                  final saved = await showEventForm(context, event: event);
                  if (saved != null && context.mounted) {
                    toast(context, 'Event updated');
                    _load();
                  }
                },
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: _delete,
        ),
      ],
      bottomBar: approval == 'pending'
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.tones.danger,
                    ),
                    onPressed: () => _approval('rejected'),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _approval('approved'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            )
          : null,
      header: ChipTabs<String>(
        selected: tab,
        onSelected: (v) {
          setState(() => tab = v);
          if (v == 'registrations' && registrations == null) {
            _loadRegistrations();
          }
          if (v == 'comments' && comments == null) _loadComments();
        },
        options: [
          const TabOption(
            'details',
            'Details',
            icon: Icons.info_outline_rounded,
          ),
          TabOption(
            'registrations',
            'Registrations',
            icon: Icons.how_to_reg_outlined,
            count: registrations?.length,
          ),
          TabOption(
            'comments',
            'Comments',
            icon: Icons.forum_outlined,
            count: comments?.length,
          ),
        ],
      ),
      children: switch (tab) {
        'registrations' => _registrations(),
        'comments' => _comments(),
        _ => _details(),
      },
    );
  }

  List<Widget> _details() {
    final cover = str(event['cover_image_url'] ?? event['poster_url']);
    final tags = (event['tags'] as List? ?? const [])
        .map((t) => t is Map ? str(t['name']) : str(t))
        .where((e) => e.isNotEmpty)
        .toList();
    final fee = toNum(event['fee_amount']);
    return [
      if (cover.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => showImagePreview(
              context,
              url: cover,
              title: str(event['title']),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Brand.radius),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Pill.status(event['approval_status'] ?? 'pending'),
          if (event['status'] != null) Pill.status(event['status']),
          Pill(_label(_visibility, event['visibility']), tone: Tone.info),
          for (final t in tags) Pill('#$t', dense: true),
        ],
      ),
      const SizedBox(height: 12),
      DetailCard(
        title: 'About',
        children: [
          Text(
            str(event['description'], 'No description'),
            style: context.text.bodyMedium,
          ),
        ],
      ),
      DetailCard(
        title: 'Schedule & location',
        children: [
          KV('Starts', fmtDate(event['start_datetime'], time: true)),
          if (event['end_datetime'] != null)
            KV('Ends', fmtDate(event['end_datetime'], time: true)),
          KV('Location', _label(_locationTypes, event['location_type'])),
          if (str(event['venue_name']).isNotEmpty)
            KV('Venue', str(event['venue_name'])),
          if (str(event['address_text']).isNotEmpty)
            KV('Address', str(event['address_text'])),
          if (str(event['meeting_url']).isNotEmpty)
            KV(
              'Meeting link',
              str(event['meeting_url']),
              onTap: () => openLink(context, str(event['meeting_url'])),
            ),
        ],
      ),
      DetailCard(
        title: 'Organisation',
        children: [
          KV('Category', pick(event, ['category.name'], '—')),
          KV(
            'College',
            event['college'] is Map ? collegeName(event['college']) : '—',
          ),
          KV('Created by', personName(event['created_by'] ?? event['user'])),
          if (str(event['organizer_name']).isNotEmpty)
            KV('Organizer', str(event['organizer_name'])),
          if (str(event['organizer_email']).isNotEmpty)
            KV('Email', str(event['organizer_email'])),
          if (str(event['organizer_phone']).isNotEmpty)
            KV('Phone', str(event['organizer_phone'])),
        ],
      ),
      DetailCard(
        title: 'Registration',
        children: [
          KV(
            'Required',
            truthy(event['is_registration_required']) ? 'Yes' : 'No',
          ),
          if (str(event['registration_url']).isNotEmpty)
            KV(
              'Link',
              str(event['registration_url']),
              onTap: () => openLink(context, str(event['registration_url'])),
            ),
          KV(
            'Capacity',
            event['capacity'] == null ? 'Unlimited' : '${event['capacity']}',
          ),
          KV(
            'Fee',
            fee == null || fee == 0
                ? 'Free'
                : '${str(event['currency'], 'INR')} $fee',
          ),
        ],
      ),
    ];
  }

  List<Widget> _registrations() {
    if (registrations == null) return const [SkeletonList(count: 4)];
    if (registrations!.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No registrations yet',
        ),
      ];
    }
    return [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => shareCsv(
            context,
            csvOf(
              const ['Name', 'Email', 'Status', 'Registered'],
              registrations!
                  .map(
                    (r) => [
                      personName(r['user'] ?? r),
                      pick(r, ['user.email', 'email']),
                      r['status'],
                      fmtDate(r['created_at'], time: true),
                    ],
                  )
                  .toList(),
            ),
            'event-${widget.id}-registrations.csv',
          ),
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text('Export CSV'),
        ),
      ),
      ...registrations!.map(
        (r) => RecordTile(
          leading: Avatar(name: personName(r['user'] ?? r, '?')),
          title: personName(r['user'] ?? r),
          subtitle: pick(r, ['user.email', 'email'], '—'),
          meta: fmtDate(r['created_at'], time: true),
          pills: [if (r['status'] != null) Pill.status(r['status'])],
          onTap: () async {
            final status = await pickFromOptions(
              context,
              'Registration status',
              [
                for (final s in [
                  'registered',
                  'waitlisted',
                  'attended',
                  'cancelled',
                ])
                  Opt(s, pretty(s)),
              ],
              selected: [r['status']],
            );
            if (status == null || !mounted) return;
            if (await runAction(
              context,
              () => api.put('admin/event-registrations/${r['id']}', {
                'status': status.first,
              }),
              success: 'Registration updated',
            )) {
              _loadRegistrations();
            }
          },
        ),
      ),
    ];
  }

  List<Widget> _comments() {
    if (comments == null) return const [SkeletonList(count: 4)];
    if (comments!.isEmpty) {
      return const [
        EmptyState(icon: Icons.forum_outlined, title: 'No comments yet'),
      ];
    }
    return comments!.map((c) {
      final flags = toInt(c['flagged_count'] ?? c['reports_count']);
      return RecordTile(
        leading: Avatar(name: personName(c['user'] ?? c, '?')),
        title: personName(c['user'] ?? c),
        subtitle: str(c['body'] ?? c['comment'] ?? c['content']),
        meta: timeAgo(c['created_at']),
        pills: [
          if (flags > 0)
            Pill(
              '$flags flag${flags == 1 ? '' : 's'}',
              tone: Tone.danger,
              dense: true,
            ),
        ],
        trailing: IconButton(
          tooltip: 'Delete comment',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            final ok = await confirmDialog(
              context,
              title: 'Delete this comment?',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (ok &&
                mounted &&
                await runAction(
                  context,
                  () => api.delete('events/${widget.id}/comments/${c['id']}'),
                  success: 'Comment deleted',
                )) {
              setState(() => comments!.removeWhere((x) => x['id'] == c['id']));
            }
          },
        ),
      );
    }).toList();
  }
}

class EventCategoriesPage extends StatelessWidget {
  const EventCategoriesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Event categories',
      onImport: (context) async {
        final choice = await pickOption(
          context,
          title: 'Import categories',
          options: const [
            SheetOption('file', 'Choose spreadsheet'),
            SheetOption('template', 'Download template'),
          ],
        );
        if (!context.mounted || choice == null) return;
        if (choice == 'template') {
          await shareCsv(
            context,
            'Name,Slug,Description,Active\nWorkshop,workshop,Hands-on workshops,yes\n',
            'event_categories_template.csv',
          );
          return;
        }
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['csv', 'xlsx', 'xls'],
        );
        if (file == null || !context.mounted) return;
        if (!await confirmDialog(
              context,
              title: 'Import ${file.name}?',
              message:
                  'Categories with matching slugs will be updated. New slugs create categories.',
              confirmLabel: 'Import',
            ) ||
            !context.mounted) {
          return;
        }
        await runAction(context, () async {
          final result = asMap(
            unwrap(
              await api.upload(
                'event-categories/import',
                'file',
                file.name,
                await file.readAsBytes(),
              ),
            ),
          );
          if (!context.mounted) return;
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Import result'),
              content: SingleChildScrollView(
                child: Text(
                  '${result['created'] ?? 0} created · ${result['updated'] ?? 0} updated · ${result['skipped'] ?? 0} skipped\n${(result['errors'] as List? ?? []).join('\n')}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        });
      },
      singular: 'category',
      icon: Icons.category_outlined,
      lookupKey: 'event_categories',
      load: () async => rowsOf(await api.get('admin/event-categories')),
      activeFilter: true,
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => [
        str(r['slug']),
        str(r['description']),
      ].where((e) => e.isNotEmpty).join(' · '),
      searchKeys: const ['name', 'slug', 'description'],
      csvHeader: const ['Name', 'Slug', 'Description'],
      csvRow: (r) => [r['name'], r['slug'], r['description']],
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec(
          'slug',
          'Slug',
          helper: 'Generated from the name if left empty',
        ),
        FieldSpec(
          'is_active',
          'Active',
          type: FieldType.toggle,
          defaultValue: true,
        ),
        FieldSpec('description', 'Description', type: FieldType.multiline),
      ],
      create: (v) async {
        final category = asMap(
          unwrap(
            await api.post('event-categories', {
              for (final e in v.entries)
                if (e.value != null) e.key: e.value,
            }),
          ),
        );
        if (!truthy(v['is_active'])) {
          await api.put('event-categories/${category['id']}', {
            'is_active': false,
          });
        }
      },
      update: (r, v) => api.put('event-categories/${r['id']}', {
        for (final e in v.entries)
          if (e.value != null) e.key: e.value,
      }),
    ),
  );
}

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Tags',
      singular: 'tag',
      icon: Icons.sell_outlined,
      lookupKey: 'tags',
      load: () async => rowsOf(await api.get('tags')),
      titleOf: (r) => '#${str(r['name'], '${r['id']}')}',
      subtitleOf: (r) => str(r['slug']),
      searchKeys: const ['name', 'slug'],
      csvHeader: const ['Name'],
      csvRow: (r) => [r['name']],
      fields: (_) => const [FieldSpec('name', 'Name', required: true)],
      create: (v) => api.post('tags', {'name': v['name']}),
      update: (r, v) => api.put('tags/${r['id']}', {'name': v['name']}),
      delete: (r) => api.delete('tags/${r['id']}'),
    ),
  );
}
