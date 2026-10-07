import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../agent/response_provenance.dart';
import '../agent/source_reference.dart';
import '../domain/chat_message.dart';
import '../domain/chat_role.dart';
import '../l10n/app_strings.dart';
import 'theme.dart';

/// One message row.
///
/// The two roles are shaped deliberately differently, and the asymmetry is the point:
///
///  * **The user's turn** is a grey capsule, right-aligned, capped at 78 % of the width. It
///    is short, it is a quotation of something the reader already knows they typed, and the
///    capsule lets the eye skip it.
///  * **The assistant's turn** has no container at all — no fill, no border, no avatar
///    gutter — just prose on the page, full measure. A bubble around a long streamed answer
///    wastes horizontal space on padding, forces a second background colour under every
///    paragraph, and makes code blocks and lists look boxed-in twice over.
///
/// This is why the class is still called `MessageBubble` while only half of it draws a
/// bubble: the name is what the rest of the app imports, and renaming it would touch files
/// that have no other reason to change.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.provenance = ResponseProvenance.empty,
    this.onCopy,
  });

  final ChatMessage message;
  final ResponseProvenance provenance;
  final VoidCallback? onCopy;

  bool get _isUser => message.role == ChatRole.user;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _isUser ? AppStrings.of(context).you : AppStrings.of(context).assistant,
      value: message.content,
      container: true,
      child: _isUser ? _buildUser(context) : _buildAssistant(context),
    );
  }

  // ---------------------------------------------------------------------------------------
  // User
  // ---------------------------------------------------------------------------------------

  Widget _buildUser(BuildContext context) {
    // Measured against the incoming constraints, not `MediaQuery.sizeOf`. The chat list
    // caps its content at 760 px and the wide layout takes a further ~320 px for the
    // sidebar, so screen width overstates the available measure on every layout except a
    // phone — and an overstated cap is no cap at all: the capsule runs the full width and
    // stops reading as one.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: available * 0.78),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.userBubble(context),
                // 22 against a 16 px body with 11 px of vertical padding puts the corner
                // arc just inside the cap height, which is what makes it read as a capsule
                // on one line and as a rounded card on several.
                borderRadius: const BorderRadius.all(Radius.circular(22)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(message.content, style: AppText.body(context)),
                  if (message.status == MessageStatus.failed) ...[
                    const SizedBox(height: 6),
                    _CaptionLabel(
                      icon: AppIcons.exclamationmarkTriangle,
                      text: message.errorDescription ?? AppStrings.of(context).failedToSend,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------------------
  // Assistant
  // ---------------------------------------------------------------------------------------

  Widget _buildAssistant(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sources = provenance.sources;
    final isComplete = message.status == MessageStatus.complete;
    final hasText = message.content.isNotEmpty;
    final canCopy = hasText && onCopy != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hasText && message.isStreaming)
          const _ThinkingIndicator()
        else if (hasText)
          // Rendered, not shown raw: answers are markdown with LaTeX math, and a student
          // reading `$$S_{20} = \\frac{20}{2}[2(3) + 19 \\times 4]$$` instead of the formula is
          // being taught the notation of the renderer, not the mathematics. `SelectionArea`
          // keeps the text selectable, as `SelectableText` made it before.
          SelectionArea(
            child: GptMarkdown(
              message.content,
              style: AppText.body(context),
              // Qwen writes math as `$...$` / `$$...$$`, which the renderer leaves as text
              // unless told otherwise. Safe here: students in Bangladesh write money as
              // টাকা / ৳, so a stray `$` price being read as math is the rare case.
              useDollarSignsForLatex: true,
            ),
          ),

        if (message.status == MessageStatus.stopped) ...[
          const SizedBox(height: 8),
          _CaptionLabel(
            icon: AppIcons.stopCircle,
            text: AppStrings.of(context).stopped,
            color: AppColors.secondaryLabel(context),
          ),
        ],
        if (message.status == MessageStatus.failed) ...[
          const SizedBox(height: 8),
          _CaptionLabel(
            icon: AppIcons.exclamationmarkTriangle,
            text: message.errorDescription ?? AppStrings.of(context).generationFailed,
            color: scheme.error,
          ),
        ],

        if (sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SourcesFooter(sources: sources),
        ],

        // The action row only appears once the answer has finished. Showing it mid-stream
        // would make it jump down the screen on every token.
        if (isComplete && hasText) ...[
          const SizedBox(height: 4),
          _AssistantActions(
            provenance: provenance,
            onCopy: canCopy ? onCopy : null,
          ),
        ],
      ],
    );
  }
}

/// The row of small controls under a finished answer, with the provenance badge trailing it.
///
/// Only Copy is wired: this app has no rating pipeline and no regenerate command on the view
/// model, and a button that does nothing is worse than an absent one.
class _AssistantActions extends StatelessWidget {
  const _AssistantActions({required this.provenance, this.onCopy});

  final ResponseProvenance provenance;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.secondaryLabel(context);

    return Row(
      children: [
        if (onCopy != null)
          _IconAction(
            icon: AppIcons.docOnDoc,
            tooltip: AppStrings.of(context).copy,
            color: muted,
            onPressed: onCopy,
          ),
        const Spacer(),
        Flexible(
          child: _CaptionLabel(
            icon: _badgeIcon(provenance.badgeIcon),
            text: provenance.badgeText,
            color: muted,
          ),
        ),
      ],
    );
  }

  static IconData _badgeIcon(ProvenanceBadgeIcon icon) => switch (icon) {
        ProvenanceBadgeIcon.document => AppIcons.docText,
        ProvenanceBadgeIcon.network => AppIcons.network,
        ProvenanceBadgeIcon.device => AppIcons.iphone,
      };
}

/// A 32 px tappable square holding an 17 px glyph — small enough not to shout under the
/// text, still inside the 32 px touch floor for a secondary control.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

/// Three dots that breathe while the model is still producing its first token.
///
/// A [CircularProgressIndicator] would spin at a constant rate and read as "the app is
/// fetching"; this reads as "something is composing". It is also cheap: one controller
/// driving an opacity, no layout work per frame.
class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = AppColors.secondaryLabel(context);

    return Semantics(
      label: AppStrings.of(context).thinkingLabel,
      liveRegion: true,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    // A sixth of a cycle between dots: enough to read as a travelling
                    // wave, not so much that they look unsynchronised.
                    final phase = (_controller.value + i * 0.17) % 1.0;
                    final eased = Curves.easeInOut.transform(
                      phase < 0.5 ? phase * 2 : (1 - phase) * 2,
                    );
                    return Opacity(opacity: 0.3 + eased * 0.7, child: child);
                  },
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaptionLabel extends StatelessWidget {
  const _CaptionLabel({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: AppText.caption2(context).copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The citation list under an answer.
///
/// Sources with a URL are rendered in the link colour and are selectable, so the address can
/// be copied out. They are **not** tappable: opening a URL needs `url_launcher`, which is not
/// a dependency of this project, and a link that silently does nothing would be worse than
/// one that plainly is not a link.
class _SourcesFooter extends StatelessWidget {
  const _SourcesFooter({required this.sources});

  final List<SourceReference> sources;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.thickMaterial(context),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.of(context).sources,
            style: AppText.caption2(context).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: source.url != null
                  ? SelectableText(
                      _label(source, AppStrings.of(context)),
                      style: AppText.caption(context).copyWith(
                        color: AppColors.link(context),
                      ),
                    )
                  : Text(
                      _label(source, AppStrings.of(context)),
                      style: AppText.caption(context).copyWith(
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  static String _label(SourceReference source, AppStrings strings) {
    final base = '[${source.id}] ${source.title}';
    final page = source.page;
    return page == null ? base : strings.sourceWithPage(base, page);
  }
}
