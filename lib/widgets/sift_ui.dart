import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/sift_theme.dart';

/// Shared interface primitives. Structure comes from rules, spacing and type;
/// there are deliberately no gradient fills or ambient shadows in this file.
class SiftRule extends StatelessWidget {
  const SiftRule({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    this.height = 1,
  });

  final double indent;
  final double endIndent;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: EdgeInsets.only(left: indent, right: endIndent),
      color: color ?? context.sift.line,
    );
  }
}

class SiftWordmark extends StatelessWidget {
  const SiftWordmark({super.key, this.size = 26, this.onTap});

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final word = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'sift',
            style: TextStyle(
              fontFamily: 'Instrument Serif',
              fontSize: size,
              height: 0.95,
              letterSpacing: -0.5,
              color: p.ink,
            ),
          ),
          TextSpan(
            text: '.',
            style: TextStyle(
              fontFamily: 'Instrument Serif',
              fontSize: size,
              height: 0.95,
              color: p.clay,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return word;
    return Semantics(
      button: true,
      label: 'Sift home',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: word,
        ),
      ),
    );
  }
}

class SiftIconButton extends StatelessWidget {
  const SiftIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 21,
    this.active = false,
    this.badge,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool active;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: const EdgeInsets.all(10),
      style: IconButton.styleFrom(
        foregroundColor: active ? p.moss : p.inkSoft,
        disabledForegroundColor: p.faint,
        backgroundColor: active ? p.mossWash : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadius.sm),
        ),
      ),
      icon: Icon(icon),
    );
    if (badge == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 4,
          top: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: p.clay,
              borderRadius: BorderRadius.circular(SiftRadius.xs),
            ),
            child: Text(
              badge!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFFFF8F2),
                    fontSize: 8,
                    height: 1.1,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

enum SiftButtonTone { moss, clay, quiet, line }

class SiftButton extends StatelessWidget {
  const SiftButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = SiftButtonTone.moss,
    this.busy = false,
    this.expand = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SiftButtonTone tone;
  final bool busy;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final enabled = onPressed != null && !busy;
    final (background, foreground, border) = switch (tone) {
      SiftButtonTone.moss => (p.mossDeep, p.paper, p.mossDeep),
      SiftButtonTone.clay => (p.clay, const Color(0xFFFFF8F2), p.clay),
      SiftButtonTone.quiet => (p.mossWash, p.mossDeep, p.mossWash),
      SiftButtonTone.line => (Colors.transparent, p.ink, p.lineStrong),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? background : background.withOpacity(0.45),
        borderRadius: BorderRadius.circular(SiftRadius.sm),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(SiftRadius.sm),
          child: Container(
            height: compact ? 38 : 48,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 18,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: enabled ? border : p.line,
              ),
              borderRadius: BorderRadius.circular(SiftRadius.sm),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: foreground,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: 17, color: foreground),
                if (busy || icon != null) const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontSize: compact ? 13 : 14,
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

class SiftTextAction extends StatelessWidget {
  const SiftTextAction({
    required this.label,
    this.onTap,
    this.icon = Icons.arrow_forward_rounded,
    this.color,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SiftRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: onTap == null ? p.faint : (color ?? p.moss),
                    letterSpacing: 0.4,
                    fontSize: 11,
                  ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 5),
              Icon(
                icon,
                size: 14,
                color: onTap == null ? p.faint : (color ?? p.moss),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SiftFilterTab extends StatelessWidget {
  const SiftFilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SiftRadius.xs),
      child: Padding(
        padding: const EdgeInsets.only(right: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? p.ink : p.muted,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 13.5,
                        ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: selected ? p.clay : p.faint,
                            fontSize: 9,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              height: 2,
              width: selected ? 22 : 0,
              color: p.clay,
            ),
          ],
        ),
      ),
    );
  }
}

class SiftSectionHead extends StatelessWidget {
  const SiftSectionHead({
    required this.title,
    this.kicker,
    this.action,
    this.onAction,
    this.bottomPadding = 14,
    super.key,
  });

  final String title;
  final String? kicker;
  final String? action;
  final VoidCallback? onAction;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null) ...[
                  SiftKicker(kicker!),
                  const SizedBox(height: 7),
                ],
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SiftTextAction(label: action!, onTap: onAction),
            ),
        ],
      ),
    );
  }
}

class SiftPageTitle extends StatelessWidget {
  const SiftPageTitle({
    required this.title,
    this.kicker,
    this.subtitle,
    this.actions = const [],
    this.bottom = 22,
    super.key,
  });

  final String title;
  final String? kicker;
  final String? subtitle;
  final List<Widget> actions;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actions.isNotEmpty)
            Row(
              children: [
                if (kicker != null) Expanded(child: SiftKicker(kicker!)),
                if (kicker == null) const Spacer(),
                ...actions,
              ],
            )
          else if (kicker != null)
            SiftKicker(kicker!),
          if (kicker != null || actions.isNotEmpty) const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.displaySmall),
          if (subtitle != null) ...[
            const SizedBox(height: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.sift.muted,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SiftSurface extends StatelessWidget {
  const SiftSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.radius = SiftRadius.sm,
    this.onTap,
    this.clip = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final box = Container(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        border: Border.all(color: borderColor ?? p.line),
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: box,
      ),
    );
  }
}

class SiftBadge extends StatelessWidget {
  const SiftBadge(
    this.label, {
    this.color,
    this.background,
    this.icon,
    super.key,
  });

  final String label;
  final Color? color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? p.mossWash,
        borderRadius: BorderRadius.circular(SiftRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color ?? p.mossDeep),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color ?? p.mossDeep,
                  fontSize: 9,
                  height: 1.2,
                  letterSpacing: 0.8,
                ),
          ),
        ],
      ),
    );
  }
}

class SiftEmpty extends StatelessWidget {
  const SiftEmpty({
    required this.title,
    required this.body,
    this.icon = Icons.article_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 10),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: p.lineStrong),
              borderRadius: BorderRadius.circular(SiftRadius.md),
            ),
            child: Icon(icon, size: 21, color: p.muted),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.muted,
                    height: 1.55,
                  ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}

class SiftErrorNote extends StatelessWidget {
  const SiftErrorNote({
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: p.clayWash,
        border: Border.all(color: p.clay.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(SiftRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: p.clay),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.inkSoft,
                    height: 1.45,
                  ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            SiftTextAction(label: retryLabel, onTap: onRetry),
          ],
        ],
      ),
    );
  }
}

class SiftSkeletonRows extends StatelessWidget {
  const SiftSkeletonRows({this.rows = 4, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Column(
      children: [
        for (var index = 0; index < rows; index++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: index.isEven ? 140 : 112,
                  height: 8,
                  color: p.line,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 15,
                  color: p.line.withOpacity(0.8),
                ),
                const SizedBox(height: 7),
                Container(
                  width: index.isEven ? 260 : 300,
                  height: 15,
                  color: p.line.withOpacity(0.8),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 9,
                  color: p.line.withOpacity(0.55),
                ),
                const SizedBox(height: 5),
                Container(
                  width: 220,
                  height: 9,
                  color: p.line.withOpacity(0.55),
                ),
              ],
            ),
          ),
          if (index != rows - 1) const SiftRule(),
        ],
      ],
    );
  }
}

Future<T?> showSiftSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final p = context.sift;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(
              top: BorderSide(color: p.lineStrong),
              left: BorderSide(color: p.line),
              right: BorderSide(color: p.line),
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: builder(sheetContext),
        ),
      );
    },
  );
}

class SiftSheetTitle extends StatelessWidget {
  const SiftSheetTitle({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 34,
            height: 3,
            margin: const EdgeInsets.only(top: 10, bottom: 18),
            decoration: BoxDecoration(
              color: p.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.muted,
                            height: 1.5,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

void showSiftToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_rounded,
              size: 17,
              color: error
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onPrimary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

class SiftSelectableLine extends StatelessWidget {
  const SiftSelectableLine(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      style: style ?? Theme.of(context).textTheme.bodySmall,
    );
  }
}

void copyText(BuildContext context, String text, [String? message]) {
  Clipboard.setData(ClipboardData(text: text));
  showSiftToast(context, message ?? 'Copied to clipboard');
}
