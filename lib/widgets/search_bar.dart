import 'package:flutter/material.dart';

import '../core/theme/sift_theme.dart';

class SiftSearchBar extends StatefulWidget {
  const SiftSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.onChanged,
    this.hintText = 'Search the web',
    this.compact = false,
    this.autofocus = false,
    this.leading,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
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
    final height = widget.compact ? 50.0 : 58.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      height: height,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(
          color: _focused ? p.moss : p.lineStrong,
          width: _focused ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(SiftRadius.md),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: widget.compact ? 8 : 10,
              right: widget.compact ? 2 : 4,
            ),
            child: widget.leading ??
                Icon(
                  Icons.search_rounded,
                  size: widget.compact ? 20 : 22,
                  color: _focused ? p.moss : p.muted,
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
                    fontSize: widget.compact ? 14.5 : 16,
                    color: p.ink,
                  ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                      fontSize: widget.compact ? 14.5 : 16,
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
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                        widget.focusNode.requestFocus();
                        setState(() {});
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: p.muted,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 40),
                      padding: const EdgeInsets.all(6),
                      visualDensity: VisualDensity.compact,
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      2,
                      widget.compact ? 6 : 7,
                      widget.compact ? 6 : 7,
                      widget.compact ? 6 : 7,
                    ),
                    child: Semantics(
                      button: true,
                      label: 'Submit search',
                      child: Material(
                        color: _focused || value.text.isNotEmpty
                            ? p.clay
                            : p.mossDeep,
                        borderRadius:
                            BorderRadius.circular(SiftRadius.sm),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(SiftRadius.sm),
                          onTap: () =>
                              widget.onSubmitted(widget.controller.text),
                          child: SizedBox(
                            width: widget.compact ? 38 : 44,
                            height: widget.compact ? 38 : 44,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: widget.compact ? 18 : 20,
                              color: const Color(0xFFFFF8F2),
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
