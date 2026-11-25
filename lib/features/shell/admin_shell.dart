import 'admin_modules.dart';
export 'admin_modules.dart';
import 'admin_navigation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/json.dart';
import '../../core/session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';
import '../dashboard/dashboard_pages.dart';
import '../review/review_page.dart';
import '../study/academic_term_page.dart';
import '../system/app_pages.dart';
import '../system/notification_preferences_page.dart';
import '../system/security_page.dart';
import '../system/storage_page.dart';
import '../users/users_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int index = 0;
  final _visited = <int>{0};

  static const _destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
    (Icons.fact_check_outlined, Icons.fact_check_rounded, 'Review'),
    (Icons.people_alt_outlined, Icons.people_alt_rounded, 'Users'),
    (Icons.apps_outlined, Icons.apps_rounded, 'Modules'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
  ];

  Widget _page(int i) => switch (i) {
    0 => DashboardPage(onOpenModule: (_) => _go(3)),
    1 => const ReviewQueuePage(),
    2 => const UsersPage(),
    3 => const ModulesHub(),
    _ => const ProfilePage(),
  };

  void _go(int i) {
    if (i == 3) {
      showModuleLauncher(context);
      return;
    }
    setState(() {
      index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < _destinations.length; i++)
          _visited.contains(i)
              ? TickerMode(enabled: index == i, child: _page(i))
              : const SizedBox.shrink(),
      ],
    );
    final search = FloatingActionButton.small(
      heroTag: 'spotlight',
      tooltip: 'Search',
      onPressed: () => showSpotlight(context),
      child: const Icon(Icons.search_rounded),
    );
    if (context.isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.85,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    const BrandLogo(size: 40),
                    const SizedBox(height: 20),
                    search,
                  ],
                ),
              ),
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            VerticalDivider(
              width: 1,
              color: context.colors.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _go,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final (icon, selected, label) in _destinations)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: label,
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Modules hub ─────────────────────────────

class ModulesHub extends StatefulWidget {
  const ModulesHub({super.key});
  @override
  State<ModulesHub> createState() => _ModulesHubState();
}

class _ModulesHubState extends State<ModulesHub> {
  final query = TextEditingController();
  final pinned = <String>{};
  String group = 'All';
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => pinned.addAll(
          prefs.getStringList('admin.pinnedModules') ??
              [
                'Materials',
                'Exam calendars',
                'Point requests',
                'Content reports',
              ],
        ),
      );
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _pin(AdminModule m) async {
    setState(
      () => pinned.contains(m.label)
          ? pinned.remove(m.label)
          : pinned.add(m.label),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin.pinnedModules', pinned.toList());
  }

  bool _matches(AdminModule m) => '${m.label} ${m.caption} ${m.keywords}'
      .toLowerCase()
      .contains(query.text.toLowerCase().trim());
  Widget _grid(List<(AdminModule, Tone)> modules) => LayoutBuilder(
    builder: (context, box) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      final cols = largeText ? 1 : (box.maxWidth / 170).floor().clamp(1, 4);
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (m, tone) in modules)
            SizedBox(
              width: w,
              child: _ModuleCard(
                module: m,
                tone: tone,
                pinned: pinned.contains(m.label),
                onPin: () => _pin(m),
              ),
            ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    final groups = moduleGroups
        .where(
          (g) =>
              (group == 'All' || group == g.title) && g.modules.any(_matches),
        )
        .toList();
    final favorites = [
      for (final g in moduleGroups)
        for (final m in g.modules)
          if (pinned.contains(m.label) && _matches(m)) (m, g.tone),
    ];
    return AppPage(
      title: 'Workspace',
      subtitle:
          '${moduleGroups.fold<int>(0, (n, g) => n + g.modules.length)} tools to keep KTU Assist moving',
      actions: [
        IconButton(
          tooltip: 'Search users and materials',
          onPressed: () => showSpotlight(context),
          icon: const Icon(Icons.person_search_outlined),
        ),
      ],
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBox(
            controller: query,
            hint: 'Find a tool, page or workflow',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          ChipTabs(
            selected: group,
            options: [
              const TabOption('All', 'All tools'),
              for (final g in moduleGroups)
                TabOption(g.title, g.title, icon: g.icon),
            ],
            onSelected: (v) => setState(() => group = v),
          ),
        ],
      ),
      children: [
        if (favorites.isNotEmpty && group == 'All' && query.text.isEmpty) ...[
          const SectionHeader(
            'Pinned for you',
            trailing: Pill('Your shortcuts', dense: true, tone: Tone.brand),
          ),
          _grid(favorites),
          const SizedBox(height: 14),
        ],
        if (groups.isEmpty)
          EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No tools found',
            message: 'Try a different name or choose All tools.',
          ),
        for (final g in groups) ...[
          SectionHeader(
            g.title,
            trailing: Pill(
              '${g.modules.where(_matches).length}',
              dense: true,
              tone: g.tone,
            ),
          ),
          _grid([for (final m in g.modules.where(_matches)) (m, g.tone)]),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.tone,
    required this.pinned,
    required this.onPin,
  });
  final AdminModule module;
  final Tone tone;
  final bool pinned;
  final VoidCallback onPin;
  @override
  Widget build(BuildContext context) => Panel(
    margin: EdgeInsets.zero,
    padding: const EdgeInsets.all(16),
    onTap: () => push(context, module.builder(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBadge(module.icon, tone: tone, size: 42),
            const Spacer(),
            IconButton(
              tooltip: pinned ? 'Unpin ${module.label}' : 'Pin ${module.label}',
              onPressed: onPin,
              icon: Icon(
                pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 18,
              ),
              color: pinned
                  ? context.colors.onSurface
                  : context.colors.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          module.label,
          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          module.caption.isEmpty
              ? 'Manage ${module.label.toLowerCase()}'
              : module.caption,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

// Kept as a shared entry point for the workspace and desktop rail.
Future<void> showSpotlight(BuildContext context) =>
    showModuleLauncher(context, autofocus: true);

// ───────────────────────────── Profile ─────────────────────────────

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final u = session.user;
      return AppPage(
        title: 'Account',
        maxWidth: 760,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radius),
              gradient: const LinearGradient(
                colors: [Brand.ink, Color(0xFF2A2D35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Avatar(name: session.name, url: str(u['avatar']), size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name,
                        style: context.text.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        str(u['email']),
                        style: context.text.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Pill(
                        session.role,
                        tone: Tone.brand,
                        dense: true,
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Appearance'),
          Panel(
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {session.themeMode},
              onSelectionChanged: (s) => session.setTheme(s.first),
            ),
          ),
          const SectionHeader('Workspace'),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (icon, label, page) in <(IconData, String, Widget)>[
                  (
                    Icons.notifications_outlined,
                    'Notifications',
                    const NotificationPreferencesPage(),
                  ),
                  (
                    Icons.shield_outlined,
                    'Security & 2FA',
                    const SecurityPage(),
                  ),
                  (Icons.cloud_outlined, 'Storage', const StoragePage()),
                  (
                    Icons.query_stats_rounded,
                    'Analytics',
                    const AnalyticsPage(),
                  ),
                  (Icons.sensors_rounded, 'Live users', const LiveUsersPage()),
                  (
                    Icons.system_update_alt_rounded,
                    'App version',
                    const AppVersionPage(),
                  ),
                  (
                    Icons.event_repeat_rounded,
                    'Academic term',
                    const AcademicTermPage(),
                  ),
                ])
                  ListTile(
                    leading: Icon(icon),
                    title: Text(label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => push(context, page),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.tones.danger,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () async {
              if (await confirmDialog(
                context,
                title: 'Sign out?',
                confirmLabel: 'Sign out',
                destructive: true,
              )) {
                await session.signOut();
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      );
    },
  );
}
