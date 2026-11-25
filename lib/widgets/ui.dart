import 'package:flutter/material.dart';

import '../core/json.dart';
import '../theme/app_theme.dart';

/// Standard page: large collapsing title, optional header (filters), body
/// children with skeleton / error states, pull to refresh and a FAB.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.header,
    this.children = const [],
    this.slivers,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onRefresh,
    this.fab,
    this.bottomBar,
    this.leading,
    this.maxWidth = 1100,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 120),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? header;
  final List<Widget> children;
  final List<Widget>? slivers;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final Widget? fab;
  final Widget? bottomBar;
  final Widget? leading;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Widget constrain(Widget child) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
    final body = loading
        ? const SliverToBoxAdapter(child: SkeletonList())
        : error != null
        ? SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(message: error!, onRetry: onRetry),
          )
        : slivers != null
        ? SliverMainAxisGroup(slivers: slivers!)
        : SliverList.list(
            children: [
              for (var i = 0; i < children.length; i++)
                i < 8 ? Entrance(child: children[i]) : children[i],
            ],
          );
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverAppBar.medium(
          pinned: true,
          titleTextStyle: context.text.headlineSmall,
          leading: leading,
          actions: [...actions, const SizedBox(width: 8)],
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (subtitle != null || header != null)
          SliverToBoxAdapter(
            child: constrain(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    if (subtitle != null && header != null)
                      const SizedBox(height: 14),
                    ?header,
                  ],
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: padding,
          sliver: SliverCrossAxisConstrained(maxWidth: maxWidth, child: body),
        ),
      ],
    );
    return Scaffold(
      floatingActionButton: fab,
      bottomNavigationBar: bottomBar == null
          ? null
          : Material(
              color: context.colors.surfaceContainerLow,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: bottomBar,
                ),
              ),
            ),
      body: onRefresh == null
          ? scroll
          : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
    );
  }
}

/// Centers a sliver and caps its width on tablets and desktops.
class SliverCrossAxisConstrained extends StatelessWidget {
  const SliverCrossAxisConstrained({
    super.key,
    required this.maxWidth,
    required this.child,
  });
  final double maxWidth;
  final Widget child;
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final extra =
          (constraints.crossAxisExtent - maxWidth).clamp(0.0, double.infinity) /
          2;
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: extra),
        sliver: child,
      );
    },
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.color,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: color ?? context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        side: BorderSide(color: borderColor ?? context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

enum Tone { neutral, success, warning, danger, info, violet, brand }

Tone toneFor(dynamic status) {
  final s = str(status).toLowerCase();
  if (const [
    'approved',
    'active',
    'verified',
    'sent',
    'paid',
    'resolved',
    'live',
    'completed',
    'allowed',
    'enabled',
    'yes',
    'healthy',
    'studying',
    'registered',
    'visible',
  ].contains(s)) {
    return Tone.success;
  }
  if (const [
    'pending',
    'reviewing',
    'open',
    'pending_verification',
    'draft',
    'scheduled',
    'paused',
    'reserved',
    'default',
    'partial',
  ].contains(s)) {
    return Tone.warning;
  }
  if (const [
    'rejected',
    'banned',
    'failed',
    'blocked',
    'cancelled',
    'deleted',
    'removed',
    'inactive',
    'error',
    'unpaid',
    'refunded',
    'no',
    'hidden',
  ].contains(s)) {
    return Tone.danger;
  }
  if (const ['sold', 'closed', 'archived', 'expired'].contains(s)) {
    return Tone.neutral;
  }
  return Tone.info;
}

({Color fg, Color bg}) toneColors(BuildContext context, Tone tone) {
  final t = context.tones;
  return switch (tone) {
    Tone.success => (fg: t.success, bg: t.successBg),
    Tone.warning => (fg: t.warning, bg: t.warningBg),
    Tone.danger => (fg: t.danger, bg: t.dangerBg),
    Tone.info => (fg: t.info, bg: t.infoBg),
    Tone.violet => (fg: t.violet, bg: t.violetBg),
    Tone.brand => (
      fg: context.colors.onPrimaryContainer,
      bg: context.colors.primaryContainer,
    ),
    Tone.neutral => (
      fg: context.colors.onSurfaceVariant,
      bg: context.colors.surfaceContainer,
    ),
  };
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone, this.icon, this.dense = false});
  final String label;
  final Tone? tone;
  final IconData? icon;
  final bool dense;

  factory Pill.status(dynamic status, {Key? key, String? label}) =>
      Pill(label ?? pretty(status), key: key, tone: toneFor(status));

  @override
  Widget build(BuildContext context) {
    final c = toneColors(context, tone ?? Tone.neutral);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: c.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: c.fg,
              fontWeight: FontWeight.w800,
              fontSize: dense ? 10.5 : 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.neutral,
    this.caption,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(context, tone);
    return Panel(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: c.fg, size: 20),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: context.text.headlineSmall),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.text.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Responsive grid of [MetricTile]s (2 columns on phones, up to 4 on wide screens).
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160,
  });
  final List<Widget> children;
  final double minTileWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = (c.maxWidth / minTileWidth).floor().clamp(1, 4);
      final width = (c.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((w) => SizedBox(width: width, child: w))
            .toList(),
      );
    },
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.trailing,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 0, 10),
    child: LayoutBuilder(
      builder: (context, box) {
        final titleWidget = Text(title, style: context.text.titleMedium);
        final accessory =
            trailing ??
            (action == null
                ? null
                : TextButton.icon(
                    onPressed: onAction,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text(action!),
                  ));
        if (box.maxWidth < 360 &&
            MediaQuery.textScalerOf(context).scale(14) > 17) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget,
              if (accessory != null) ...[const SizedBox(height: 8), accessory],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titleWidget),
            if (accessory != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: accessory,
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title = 'Nothing here yet',
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, size: 32, color: context.colors.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: context.text.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.tones.dangerBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              size: 32,
              color: context.tones.danger,
            ),
          ),
          const SizedBox(height: 16),
          Text('Couldn’t load this', style: context.text.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}

class Banner2 extends StatelessWidget {
  const Banner2(this.message, {super.key, this.tone = Tone.info, this.icon});
  final String message;
  final Tone tone;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(context, tone);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ??
                switch (tone) {
                  Tone.danger => Icons.error_outline_rounded,
                  Tone.warning => Icons.warning_amber_rounded,
                  Tone.success => Icons.check_circle_outline_rounded,
                  _ => Icons.info_outline_rounded,
                },
            color: c.fg,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: c.fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 6});
  final int count;
  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.surfaceContainerHigh;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return FadeTransition(
      opacity: Tween(begin: .45, end: 1.0).animate(_c),
      child: Column(
        children: List.generate(
          widget.count,
          (_) => Panel(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(180, 14),
                      const SizedBox(height: 8),
                      bar(120, 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 42});
  final String name;
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final palette = [
      context.tones.violetBg,
      context.tones.infoBg,
      context.tones.successBg,
      context.tones.warningBg,
      context.colors.primaryContainer,
    ];
    final fg = [
      context.tones.violet,
      context.tones.info,
      context.tones.success,
      context.tones.warning,
      context.colors.onPrimaryContainer,
    ];
    final i = name.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length;
    final hasUrl = url != null && url!.startsWith('http');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette[i],
        borderRadius: BorderRadius.circular(size * .34),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: hasUrl
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, _, _) => _initial(context, initial, fg[i]),
            )
          : _initial(context, initial, fg[i]),
    );
  }

  Widget _initial(BuildContext context, String initial, Color color) => Text(
    initial,
    style: context.text.titleMedium?.copyWith(
      color: color,
      fontSize: size * .4,
      fontWeight: FontWeight.w800,
    ),
  );
}

class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.tone = Tone.brand,
    this.size = 42,
  });
  final IconData icon;
  final Tone tone;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, color: c.fg, size: size * .5),
    );
  }
}

/// A list row card: leading badge/avatar, title, subtitle, pills and trailing.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.pills = const [],
    this.meta,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dimmed = false,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> pills;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dimmed;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dimmed ? .55 : 1,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? context.colors.primaryContainer
            : context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          side: BorderSide(
            color: selected
                ? context.colors.primary
                : context.colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(fontSize: 15),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (pills.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: pills),
                      ],
                      if (meta != null && meta!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          meta!,
                          style: context.text.labelSmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    (onTap != null
                        ? Icon(
                            Icons.chevron_right_rounded,
                            color: context.colors.onSurfaceVariant,
                          )
                        : const SizedBox()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class KV extends StatelessWidget {
  const KV(this.label, this.value, {super.key, this.onTap, this.mono = false, this.trailing});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool mono;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    str(value, '—'),
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: mono ? 'monospace' : null,
                      color: onTap != null ? context.tones.info : null,
                      decoration: onTap != null ? TextDecoration.underline : null,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class DetailCard extends StatelessWidget {
  const DetailCard({
    super.key,
    this.title,
    required this.children,
    this.trailing,
  });
  final String? title;
  final List<Widget> children;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(child: Text(title!, style: context.text.titleMedium)),
                ?trailing,
              ],
            ),
          ),
        ...children,
      ],
    ),
  );
}

class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.controller,
    this.hint = 'Search',
    this.onSubmitted,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: TextInputAction.search,
    onSubmitted: onSubmitted,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      suffixIcon: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                  onSubmitted?.call('');
                },
              ),
      ),
    ),
  );
}

class TabOption<T> {
  const TabOption(this.value, this.label, {this.count, this.icon});
  final T value;
  final String label;
  final int? count;
  final IconData? icon;
}

/// Horizontally scrolling single-select chips used for status tabs.
class ChipTabs<T> extends StatelessWidget {
  const ChipTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final List<TabOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final o = options[i];
        final active = o.value == selected;
        return ChoiceChip(
          selected: active,
          showCheckmark: false,
          avatar: o.icon == null
              ? null
              : Icon(
                  o.icon,
                  size: 16,
                  color: active
                      ? (context.isDark ? Brand.ink : Colors.white)
                      : null,
                ),
          label: Text(o.count == null ? o.label : '${o.label}  ${o.count}'),
          labelStyle: context.text.labelLarge?.copyWith(
            color: active
                ? (context.isDark ? Brand.ink : Colors.white)
                : context.colors.onSurface,
          ),
          onSelected: (_) => onSelected(o.value),
        );
      },
    ),
  );
}

class Pager extends StatelessWidget {
  const Pager({super.key, required this.meta, required this.onPage});
  final PageMeta meta;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) {
    if (meta.lastPage <= 1) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: meta.hasPrev ? () => onPage(meta.page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              'Page ${meta.page} of ${meta.lastPage}${meta.total == null ? '' : ' · ${meta.total} total'}',
              textAlign: TextAlign.center,
              style: context.text.labelLarge,
            ),
          ),
          IconButton.filledTonal(
            onPressed: meta.hasNext ? () => onPage(meta.page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// A labelled dropdown used for filters.
class FilterSelect<T> extends StatelessWidget {
  const FilterSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width,
  });
  final String label;
  final T? value;
  final List<TabOption<T?>> options;
  final ValueChanged<T?> onChanged;
  final double? width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T?>(
      key: ValueKey('$label$value${options.length}'),
      initialValue: options.any((o) => o.value == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      items: options
          .map(
            (o) => DropdownMenuItem<T?>(
              value: o.value,
              child: Text(o.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    ),
  );
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Brand.yellow,
      borderRadius: BorderRadius.circular(size * .3),
      boxShadow: [
        BoxShadow(
          color: Brand.yellow.withValues(alpha: .35),
          blurRadius: size * .4,
          offset: Offset(0, size * .12),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.asset('assets/icons/ktu-assist-admin.png', fit: BoxFit.cover),
  );
}

/// Wrap of action buttons with consistent spacing.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );
}

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      if (busy)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: .08),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
    ],
  );
}

/// A short, one-time reveal that respects the system's reduced-motion setting.
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
