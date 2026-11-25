import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/admin_event_routes.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import '../study/materials_pages.dart';
import '../system/admin_alerts.dart';
import '../users/user_manage_page.dart';
import 'admin_modules.dart';

/// Tracks the root navigator so the launcher works on detail pages as well as tabs.
class AdminNavigation extends NavigatorObserver {
  final key = GlobalKey<NavigatorState>();
  final modalVisible = ValueNotifier(false);
  final List<Route<dynamic>> _routes = [];
  bool _disposed = false;
  void dispose() {
    _disposed = true;
    modalVisible.dispose();
  }

  bool get hasModal => _routes.isNotEmpty && _routes.last is PopupRoute;
  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        modalVisible.value = hasModal;
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _changed();
  }

  void open({bool search = false}) {
    final context = key.currentState?.overlay?.context;
    if (context != null && !hasModal) {
      showModuleLauncher(context, autofocus: search);
    }
  }
}

/// The bar reserves its own space instead of covering page actions or forms.
class AdminNavigationFrame extends StatelessWidget {
  const AdminNavigationFrame({
    super.key,
    required this.navigation,
    required this.child,
  });
  final AdminNavigation navigation;
  final Widget child;
  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            navigation.open(search: true),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            navigation.open(search: true),
        const SingleActivator(
          LogicalKeyboardKey.keyM,
          meta: true,
          shift: true,
        ): () =>
            navigation.open(),
        const SingleActivator(
          LogicalKeyboardKey.keyM,
          control: true,
          shift: true,
        ): () =>
            navigation.open(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Material(
              color: context.colors.surfaceContainerLowest,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: context.colors.outlineVariant),
                    ),
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: navigation.modalVisible,
                    builder: (context, modal, _) => Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/icons/ktu-assist-admin.png',
                            width: 36,
                            height: 36,
                            semanticLabel: 'KTU Assist Admin',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'KTU Admin',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('global-modules'),
                          tooltip: 'Open modules · Ctrl/⌘ Shift M',
                          onPressed: modal ? null : () => navigation.open(),
                          icon: const Icon(Icons.apps_rounded),
                        ),
                        AdminAlertButton(
                          openPage: () => navigation.key.currentState?.push(
                            MaterialPageRoute(builder: (_) => const AdminAlertsPage()),
                          ),
                          openEvent: (event) {
                            final page = pageForAdminEvent(event);
                            final nav = navigation.key.currentState;
                            if (nav == null || page == null) return;
                            nav.push(MaterialPageRoute(builder: (_) => page));
                          },
                        ),
                        IconButton(
                          key: const ValueKey('global-spotlight'),
                          tooltip: 'Spotlight search · Ctrl/⌘ K',
                          onPressed: modal
                              ? null
                              : () => navigation.open(search: true),
                          icon: const Icon(Icons.search_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Return a destination from the popup, then navigate using the still-mounted
/// parent Navigator. Never push through a closing bottom-sheet context.
Future<void> showModuleLauncher(
  BuildContext context, {
  bool autofocus = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final WidgetBuilder? destination;
  if (wide) {
    destination = await showDialog<WidgetBuilder>(
      context: context,
      useRootNavigator: true,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 800,
          height: math.min(760, MediaQuery.sizeOf(context).height * .84),
          child: ModuleLauncher(autofocus: autofocus),
        ),
      ),
    );
  } else {
    destination = await showModalBottomSheet<WidgetBuilder>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: math.max(
            180,
            (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    MediaQuery.paddingOf(context).top) *
                .9,
          ),
          child: ModuleLauncher(autofocus: autofocus),
        ),
      ),
    );
  }
  if (destination != null && navigator.mounted) {
    await navigator.push(MaterialPageRoute(builder: destination));
  }
}

class ModuleLauncher extends StatefulWidget {
  const ModuleLauncher({super.key, this.autofocus = false});
  final bool autofocus;
  @override
  State<ModuleLauncher> createState() => _ModuleLauncherState();
}

class _ModuleLauncherState extends State<ModuleLauncher> {
  final query = TextEditingController();
  final searchFocus = FocusNode();
  Timer? debounce;
  String category = 'All';
  Set<String> pins = {};
  List<Json> users = [], materials = [];
  String? usersError, materialsError;
  bool loading = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => pins =
            (prefs.getStringList('admin.pinnedModules') ??
                    [
                      'Materials',
                      'Exam calendars',
                      'Point requests',
                      'Content reports',
                    ])
                .toSet(),
      );
    }
  }

  @override
  void dispose() {
    revision++;
    debounce?.cancel();
    query.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  String get term => query.text.trim().toLowerCase();
  List<(AdminModule, ModuleGroup)> get matches => [
    for (final group in moduleGroups)
      for (final module in group.modules)
        if ((term.isNotEmpty || category == 'All' || category == group.title) &&
            (term.isEmpty ||
                '${module.label} ${module.caption} ${module.keywords} ${group.title}'
                    .toLowerCase()
                    .contains(term)))
          (module, group),
  ];
  void _changed(String value) {
    debounce?.cancel();
    final request = ++revision;
    setState(() {
      users = [];
      materials = [];
      usersError = null;
      materialsError = null;
      loading = term.length >= 2;
    });
    if (term.length < 2) {
      return;
    }
    final search = term;
    debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(search, request),
    );
  }

  Future<void> _search(String search, int request) async {
    // A failed source must not hide the other source's successful results.
    Future<(List<Json>, String?)> source(String resource) async {
      try {
        return (
          rowsOf(
            await api.get(
              'admin/lists/$resource',
              query: {'query': search, 'per_page': 6},
            ),
          ),
          null,
        );
      } catch (e) {
        return (<Json>[], errorText(e, 'Search unavailable.'));
      }
    }

    final results = await Future.wait([source('users'), source('materials')]);
    if (!mounted || request != revision) {
      return;
    }
    setState(() {
      users = results[0].$1;
      usersError = results[0].$2;
      materials = results[1].$1;
      materialsError = results[1].$2;
      loading = false;
    });
  }

  void _choose(WidgetBuilder builder) => Navigator.pop(context, builder);
  void _submit() {
    final tools = matches;
    if (tools.isNotEmpty) {
      _choose(tools.first.$1.builder);
    } else if (users.isNotEmpty) {
      final user = users.first;
      _choose((_) => UserManagePage(userId: user['id']));
    } else if (materials.isNotEmpty) {
      final material = materials.first;
      _choose((_) => MaterialDetailPage(id: material['id'], initial: material));
    }
  }

  Future<void> _pin(AdminModule module) async {
    setState(() {
      if (!pins.add(module.label)) {
        pins.remove(module.label);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin.pinnedModules', pins.toList());
  }

  Widget _grid(List<(AdminModule, ModuleGroup)> entries) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (box.maxWidth / (scale > 1.3 ? 170 : 105)).floor().clamp(
        1,
        6,
      );
      final width = (box.maxWidth - (columns - 1) * 10) / columns;
      final labelStyle = context.text.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.4,
      );
      double labelHeight = 0;
      for (final (module, _) in entries) {
        final painter = TextPainter(
          text: TextSpan(text: module.label, style: labelStyle),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout(maxWidth: width - 18);
        labelHeight = math.max(labelHeight, painter.height);
        painter.dispose();
      }
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (module, group) in entries)
            SizedBox(
              width: width,
              height: 88 + labelHeight.ceilToDouble(),
              child: Tooltip(
                message:
                    '${module.caption.isEmpty ? module.label : module.caption} · Hold to ${pins.contains(module.label) ? 'unpin' : 'pin'}',
                child: Material(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _choose(module.builder),
                    onLongPress: () => _pin(module),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: context.colors.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          IconBadge(module.icon, tone: group.tone, size: 44),
                          const SizedBox(height: 10),
                          Text(
                            module.label,
                            textAlign: TextAlign.center,
                            style: labelStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _failure(String name, String? error) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$name: $error', style: context.text.bodySmall),
              ),
              TextButton(
                onPressed: () => _changed(query.text),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
  @override
  Widget build(BuildContext context) {
    final entries = matches;
    final favorites = entries.where((e) => pins.contains(e.$1.label)).toList();
    final searching = term.isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Material(
        color: context.colors.surfaceContainerLowest,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.apps_rounded, size: 25),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Modules', style: context.text.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Focus Spotlight',
                      onPressed: () => searchFocus.requestFocus(),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: 'Close modules',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('launcher-search'),
                  controller: query,
                  focusNode: searchFocus,
                  autofocus: widget.autofocus,
                  onChanged: _changed,
                  onSubmitted: (_) => _submit(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Spotlight: tools, users, materials',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              query.clear();
                              _changed('');
                              searchFocus.requestFocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                  ),
                ),
              ),
              if (!searching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: ChipTabs(
                    selected: category,
                    options: [
                      const TabOption('All', 'All tools'),
                      for (final group in moduleGroups)
                        TabOption(group.title, group.title),
                    ],
                    onSelected: (value) => setState(() => category = value),
                  ),
                ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Expanded(
                child: ListView(
                  key: const PageStorageKey('launcher-results'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (!searching)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Hold a tool to pin or unpin it.'),
                      ),
                    if (!searching &&
                        category == 'All' &&
                        favorites.isNotEmpty) ...[
                      const SectionHeader('Pinned shortcuts'),
                      _grid(favorites),
                    ],
                    if (entries.isNotEmpty) ...[
                      SectionHeader(
                        searching
                            ? 'Tools (${entries.length})'
                            : category == 'All'
                            ? 'All modules'
                            : category,
                      ),
                      _grid(entries),
                    ],
                    if (searching) ...[
                      if (users.isNotEmpty) const SectionHeader('Users'),
                      for (final user in users)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Avatar(
                            name: personName(user),
                            url: str(user['avatar_url'] ?? user['avatar']),
                          ),
                          title: Text(personName(user)),
                          subtitle: Text(str(user['email'])),
                          onTap: () => _choose(
                            (_) => UserManagePage(userId: user['id']),
                          ),
                        ),
                      _failure('Users', usersError),
                      if (materials.isNotEmpty)
                        const SectionHeader('Materials'),
                      for (final material in materials)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const IconBadge(
                            Icons.description_outlined,
                            tone: Tone.info,
                          ),
                          title: Text(
                            pick(material, [
                              'name',
                              'title',
                            ], 'Material #${material['id']}'),
                          ),
                          subtitle: Text(
                            pick(material, [
                              'subject_data.name',
                              'subject.name',
                            ]),
                          ),
                          onTap: () => _choose(
                            (_) => MaterialDetailPage(
                              id: material['id'],
                              initial: material,
                            ),
                          ),
                        ),
                      _failure('Materials', materialsError),
                      if (!loading &&
                          entries.isEmpty &&
                          users.isEmpty &&
                          materials.isEmpty &&
                          usersError == null &&
                          materialsError == null)
                        EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          message: term.length < 2
                              ? 'Type at least two characters to search users and materials.'
                              : 'Try another name, email or tool.',
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
