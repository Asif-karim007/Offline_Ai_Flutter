import 'package:flutter/material.dart';

import 'theme.dart';

/// The input bar.
///
/// One capsule holds everything: the add button, the growing field, and a single circular
/// action on the right that is the send arrow, the stop square, or a dimmed arrow depending
/// on state. Putting the controls *inside* the capsule rather than flanking it is what keeps
/// the bar to one visual object — the shape the thumb aims at is the same shape the text
/// sits in.
///
/// SwiftUI's `@Binding var text: String` becomes a [TextEditingController] owned by
/// `ChatView` and kept in step with `ChatViewModel.composerText` — that is the closest
/// Flutter has to a two-way binding, and it is the only structural difference from the
/// original.
class ComposerView extends StatelessWidget {
  const ComposerView({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.canSend,
    required this.onSend,
    required this.onStop,
    this.onAttachFile,
  });

  final TextEditingController controller;

  /// Note that `ChatView` passes `generationState == generating` on the nose, so `stopping`
  /// puts the send arrow back while the cancel is still in flight. Faithful to the original.
  final bool isGenerating;

  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// Absent means no attach button at all, not a disabled one.
  final VoidCallback? onAttachFile;

  @override
  Widget build(BuildContext context) {
    final attach = onAttachFile;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.page(context),
        // A single hairline, not a shadow: the composer is pinned to the page, not floating
        // over it, and a shadow here would imply the list scrolls underneath.
        border: Border(top: BorderSide(color: AppColors.hairline(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.composerFill(context),
              borderRadius: const BorderRadius.all(Radius.circular(26)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (attach != null)
                  _RoundIconButton(
                    icon: AppIcons.paperclip,
                    tooltip: 'Add File',
                    // Disabled mid-generation: the attachment would land on a turn that has
                    // already been sent.
                    onPressed: isGenerating ? null : attach,
                    foreground: AppColors.primaryLabel(context),
                    size: 34,
                    iconSize: 22,
                  )
                else
                  const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: attach == null ? 8 : 4,
                      right: 8,
                      // Aligns the first baseline with the centre of the 34 px buttons.
                      top: 8,
                      bottom: 8,
                    ),
                    child: TextField(
                      controller: controller,
                      enabled: !isGenerating,
                      minLines: 1,
                      // Grows to six lines and then scrolls, matching `.lineLimit(1...6)`.
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppText.body(context),
                      cursorColor: AppColors.primaryLabel(context),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: 'Message',
                        hintStyle: AppText.body(context).copyWith(
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ),
                  ),
                ),
                _SendButton(
                  isGenerating: isGenerating,
                  canSend: canSend,
                  onSend: onSend,
                  onStop: onStop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one filled control on the screen.
///
/// Three states, one shape — the disc never moves or resizes, so the arrow→square swap
/// during generation reads as the *same* button changing meaning rather than as one control
/// being replaced by another.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isGenerating,
    required this.canSend,
    required this.onSend,
    required this.onStop,
  });

  final bool isGenerating;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final enabled = isGenerating || canSend;

    return _RoundIconButton(
      icon: isGenerating ? AppIcons.stopFill : AppIcons.arrowUpCircleFill,
      tooltip: isGenerating ? 'Stop' : 'Send',
      // Always tappable while generating, so the stop is always reachable.
      onPressed: enabled ? (isGenerating ? onStop : onSend) : null,
      size: 34,
      iconSize: 20,
      // Dimmed rather than hidden when there is nothing to send: the empty state still shows
      // where the button will be, so it does not appear from nowhere on the first keystroke.
      background: enabled
          ? AppColors.accent(context)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      foreground: enabled
          ? AppColors.onAccent(context)
          : AppColors.tertiaryLabel(context),
    );
  }
}

/// A circular tap target with an optional fill.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    required this.foreground,
    this.background,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: background ?? Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Icon(icon, size: iconSize, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
