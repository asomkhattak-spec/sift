import 'package:flutter/material.dart';

import '../core/theme/sift_theme.dart';

/// The one search field used on the home and results screens. It keeps a
/// soft white pill, a blue leading icon and only actions that do something:
/// clear, choose sources, or submit.
class SiftSearchBar extends StatefulWidget {
  const SiftSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.onChanged,
    this.onSources,
    this.hintText = 'Search with Sift',
    this.compact = false,
    this.autofocus = false,
    this.leading,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSources;
  final String hintText;
  final bool compact;
  final bool autofocus;
  final Widget? leading;

  @override
  State<SiftSearchBar> createState() => _SiftSearchBarState();
}

class _SiftSearchBarState extends State<SiftSearchBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SiftSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused == widget.focusNode.hasFocus) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final height = widget.compact ? 48.0 : 54.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: height,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(
          color: _focused ? p.moss : p.line.withOpacity(0.82),
          width: _focused ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(SiftRadius.pill),
        boxShadow: [
          BoxShadow(
            color: p.isDark
                ? const Color(0x2E000000)
                : const Color(0x0F000000),
            blurRadius: _focused ? 12 : 7,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: widget.compact ? 14 : 16,
              right: widget.compact ? 8 : 10,
            ),
            child: widget.leading ??
                Icon(
                  Icons.search_rounded,
                  size: widget.compact ? 20 : 22,
                  color: p.moss,
                ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: true,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              cursorColor: p.moss,
              cursorWidth: 1.6,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    fontSize: widget.compact ? 15 : 16,
                    color: p.ink,
                  ),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                      fontSize: widget.compact ? 15 : 16,
                      color: p.faint,
                    ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.text.isNotEmpty)
                    _BarAction(
                      tooltip: 'Clear search',
                      icon: Icons.close_rounded,
                      onPressed: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                        widget.focusNode.requestFocus();
                      },
                    ),
                  if (widget.onSources != null)
                    _BarAction(
                      tooltip: 'Search sources',
                      icon: Icons.tune_rounded,
                      onPressed: widget.onSources,
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      2,
                      widget.compact ? 5 : 7,
                      5,
                      widget.compact ? 5 : 7,
                    ),
                    child: Semantics(
                      button: true,
                      label: 'Search',
                      child: Material(
                        color: p.moss,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            if (widget.controller.text.trim().isEmpty) {
                              widget.focusNode.requestFocus();
                              return;
                            }
                            widget.onSubmitted(widget.controller.text);
                          },
                          child: SizedBox(
                            width: widget.compact ? 38 : 40,
                            height: widget.compact ? 38 : 40,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: widget.compact ? 18 : 19,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 19,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
      style: IconButton.styleFrom(
        foregroundColor: p.muted,
        highlightColor: p.surfaceRaised,
      ),
      icon: Icon(icon),
    );
  }
}