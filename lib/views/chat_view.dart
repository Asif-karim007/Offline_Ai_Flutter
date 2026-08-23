import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../agent/documents/local_document_reference.dart';
import '../agent/response_provenance.dart';
import '../domain/chat_message.dart';
import '../model_management/app_settings.dart';
import '../model_management/model_catalog.dart';
import '../viewmodels/chat_view_model.dart';
import 'composer_view.dart';
import 'error_banner.dart';
import 'generation_debug_view.dart';
import 'message_bubble.dart';
import 'temporary_chat_banner.dart';
import 'theme.dart';

/// The reading measure.
///
/// A conversation is a single column of prose, and prose stops being readable long before a
/// tablet in landscape runs out of width. The transcript is capped here and centred; below
/// this width it simply fills the pane, so phones are unaffected.
const double _contentMaxWidth = 760;

/// The chat screen.
///
/// There is exactly one of these for the life of the shell — selecting a conversation mutates
/// the view model rather than pushing a route, which is what keeps the engine's context and
/// the scroll position from being rebuilt on every navigation.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.onNewChat,
    required this.onToggleTemporaryChat,
    this.onShowSidebar,
  });

  final VoidCallback onNewChat;
  final VoidCallback onToggleTemporaryChat;

  /// Null in the wide layout, where the sidebar is already on screen and a button that
  /// reveals it would do nothing.
  final VoidCallback? onShowSidebar;

  /// The empty state's three starters, verbatim.
  static const List<String> suggestions = [
    'Explain Swift actors',
    'Create a study plan',
    'Help me debug Swift code',
  ];

  /// The Swift `[.pdf, .plainText, .json, .commaSeparatedText, .sourceCode, .text]` expanded
  /// into extensions, since `file_picker` filters by extension rather than by UTI.
  /// `.sourceCode` has no finite extension list, so the common ones stand in for it.
  static const List<String> importableDocumentExtensions = [
    'pdf',
    'txt',
    'text',
    'json',
    'csv',
    'md',
    'markdown',
    'dart',
    'swift',
    'py',
    'js',
    'ts',
    'java',
    'kt',
    'c',
    'h',
    'cpp',
    'rs',
    'go',
    'yaml',
    'yml',
    'xml',
    'html',
  ];

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();

  ChatViewModel? _observed;
  int _lastMessageCount = 0;
  int _lastTailLength = 0;

  @override
  void initState() {
    super.initState();
    _composerController.addListener(_pushComposerTextToViewModel);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewModel = context.read<ChatViewModel>();
    if (identical(viewModel, _observed)) {
      return;
    }
    _observed?.removeListener(_onViewModelChanged);
    _observed = viewModel;
    viewModel.addListener(_onViewModelChanged);
    _composerController.text = viewModel.composerText;
  }

  @override
  void dispose() {
    _observed?.removeListener(_onViewModelChanged);
    _composerController.removeListener(_pushComposerTextToViewModel);
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _syncingComposer = false;

  void _pushComposerTextToViewModel() {
    if (_syncingComposer) {
      return;
    }
    _observed?.composerText = _composerController.text;
  }

  /// Two jobs: keep the text field in step with a view model that clears it on send, and
  /// drive the autoscroll.
  void _onViewModelChanged() {
    final viewModel = _observed;
    if (viewModel == null) {
      return;
    }

    if (_composerController.text != viewModel.composerText) {
      _syncingComposer = true;
      _composerController.value = TextEditingValue(
        text: viewModel.composerText,
        selection: TextSelection.collapsed(offset: viewModel.composerText.length),
      );
      _syncingComposer = false;
    }

    // The two `.onChange` observers from the Swift view, collapsed into one: the message
    // count changes when a bubble appears, and the last message's length changes on every
    // flushed batch of tokens.
    final messages = viewModel.messages;
    final count = messages.length;
    final tailLength = messages.isEmpty ? 0 : messages.last.content.length;
    if (count != _lastMessageCount || tailLength != _lastTailLength) {
      _lastMessageCount = count;
      _lastTailLength = tailLength;
      _scrollToBottom();
    }
  }

  /// Unconditional, as in the original: there is no "the user scrolled up, leave them alone"
  /// suppression. Replicated rather than improved so the two apps behave the same.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickDocument() async {
    final viewModel = context.read<ChatViewModel>();
    // A failed pick is silently ignored here, matching the Swift `fileImporter` handler on
    // this screen (the model importer's failures *are* surfaced; document ones are not).
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ChatView.importableDocumentExtensions,
      );
      final path = result?.files.single.path;
      if (path == null) {
        return;
      }
      await viewModel.addDocument(path);
    } on Object {
      // Deliberately ignored — see above.
    }
  }

  Future<void> _showDebugMetrics() async {
    final viewModel = context.read<ChatViewModel>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The sheet's child is a `Scaffold`; a fraction of the available height gives it the
      // bounded constraint it needs and leaves the sheet reading as a card rather than a
      // full-screen route.
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: GenerationDebugView(
          metrics: viewModel.lastMetrics,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debugMetricsEnabled =
        context.select<AppSettings, bool>((settings) => settings.debugMetricsEnabled);
    final showSidebar = widget.onShowSidebar;

    return Scaffold(
      backgroundColor: AppColors.page(context),
      appBar: AppBar(
        // Stated outright even though the theme already does it: the app bar and the page
        // are one continuous surface, and nothing about that should depend on a default.
        backgroundColor: AppColors.page(context),
        leading: showSidebar == null
            ? null
            : Semantics(
                label: 'Show Conversations',
                button: true,
                child: IconButton(
                  onPressed: showSidebar,
                  icon: const Icon(AppIcons.sidebarLeft),
                  tooltip: 'Show Conversations',
                ),
              ),
        title: const _ChatTitle(),
        actions: [
          Semantics(
            label: 'New Chat',
            button: true,
            child: IconButton(
              onPressed: widget.onNewChat,
              icon: const Icon(AppIcons.squareAndPencil),
              tooltip: 'New Chat',
            ),
          ),
          Semantics(
            label: 'Start Temporary Chat',
            button: true,
            child: IconButton(
              onPressed: widget.onToggleTemporaryChat,
              icon: const Icon(AppIcons.eyeSlash),
              tooltip: 'Start Temporary Chat',
            ),
          ),
          if (debugMetricsEnabled)
            Semantics(
              label: 'Debug Metrics',
              button: true,
              child: IconButton(
                onPressed: _showDebugMetrics,
                icon: const Icon(AppIcons.speedometer),
                tooltip: 'Debug Metrics',
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Selector<ChatViewModel, bool>(
              selector: (_, viewModel) => viewModel.isTemporary,
              builder: (context, isTemporary, _) =>
                  isTemporary ? const TemporaryChatBanner() : const SizedBox.shrink(),
            ),
            Selector<ChatViewModel, String?>(
              selector: (_, viewModel) => viewModel.errorMessage,
              builder: (context, message, _) {
                if (message == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
                  child: ErrorBanner(
                    message: message,
                    onDismiss: () =>
                        context.read<ChatViewModel>().errorMessage = null,
                  ),
                );
              },
            ),
            Expanded(child: _ChatBody(scrollController: _scrollController)),
            Selector<ChatViewModel, String?>(
              selector: (_, viewModel) => viewModel.pendingWebSearchQuery,
              builder: (context, query, _) => query == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
                      child: _WebSearchConfirmationBanner(query: query),
                    ),
            ),
            Selector<ChatViewModel, String?>(
              selector: (_, viewModel) => viewModel.activityStatus,
              builder: (context, status, _) => status == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              status,
                              style: AppText.footnote(context).copyWith(
                                color: AppColors.secondaryLabel(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const _AttachedDocumentsStrip(),
            Selector<ChatViewModel, _ComposerFlags>(
              selector: (_, viewModel) => _ComposerFlags(
                isGenerating:
                    viewModel.generationState == ChatGenerationState.generating,
                canSend: viewModel.canSend,
              ),
              builder: (context, flags, _) => ComposerView(
                controller: _composerController,
                isGenerating: flags.isGenerating,
                canSend: flags.canSend,
                onSend: () => unawaited(context.read<ChatViewModel>().send()),
                onStop: context.read<ChatViewModel>().stopGeneration,
                onAttachFile: _pickDocument,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The composer's two booleans, bundled so one `Selector` covers both.
class _ComposerFlags {
  const _ComposerFlags({required this.isGenerating, required this.canSend});

  final bool isGenerating;
  final bool canSend;

  @override
  bool operator ==(Object other) =>
      other is _ComposerFlags &&
      other.isGenerating == isGenerating &&
      other.canSend == canSend;

  @override
  int get hashCode => Object.hash(isGenerating, canSend);
}

/// The app bar's centred title: the loaded model's short name, with a chevron beside it.
///
/// The name is the one piece of state a reader actually needs up there — which brain is
/// answering — and it is already reachable, so nothing new had to be added to a view model
/// for it: [AppSettings.selectedModelFileName] is the file the engine was pointed at, and
/// [ModelCatalog.byFileName] turns the ones this app ships with into a human name.
///
/// The chevron is a label, not a button. [ChatView]'s constructor is fixed — other files
/// construct it — so there is no "open the model manager" callback to hang off it, and the
/// model manager stays where it already lives, on the sidebar's overflow menu.
///
/// Before a model has ever been chosen there is no name to show, so the conversation title
/// this screen used before takes the slot instead.
class _ChatTitle extends StatelessWidget {
  const _ChatTitle();

  @override
  Widget build(BuildContext context) {
    final modelFileName = context.select<AppSettings, String?>(
      (settings) => settings.selectedModelFileName,
    );

    if (modelFileName == null || modelFileName.isEmpty) {
      return Selector<ChatViewModel, String>(
        selector: (_, viewModel) => viewModel.isTemporary
            ? 'Temporary Chat'
            : (viewModel.conversationTitle ?? 'New Chat'),
        builder: (context, title, _) => Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: AppText.headline(context),
        ),
      );
    }

    final label = _shortModelName(modelFileName);
    return Semantics(
      header: true,
      label: 'Model: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline(context),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            AppIcons.chevronDown,
            size: 18,
            color: AppColors.secondaryLabel(context),
          ),
        ],
      ),
    );
  }

  /// `Qwen3.5-2B-Q4_K_M.gguf` → `Qwen3.5-2B`.
  ///
  /// The quantisation suffix is the first thing to go: it is the one part of the name that
  /// says nothing about what the model *is*, and it is what pushes these names past the
  /// width a centred title has.
  static String _shortModelName(String fileName) {
    final catalogEntry = ModelCatalog.byFileName(fileName);
    final raw = catalogEntry?.displayName ?? fileName;
    final withoutExtension = raw.toLowerCase().endsWith('.gguf')
        ? raw.substring(0, raw.length - '.gguf'.length)
        : raw;

    final kept = <String>[];
    for (final part in withoutExtension.split(RegExp(r'[-_ ]'))) {
      if (_looksLikeQuantisationTag(part)) {
        break;
      }
      kept.add(part);
    }

    final label = kept.join('-');
    return label.isEmpty ? withoutExtension : label;
  }

  /// `Q4`, `Q8`, `IQ3`, `F16` and friends. Deliberately narrow: a name fragment that merely
  /// starts with a Q — `Qwen` — has a letter after it, not a digit, and must survive.
  static bool _looksLikeQuantisationTag(String part) {
    final lower = part.toLowerCase();
    if (lower == 'f16' || lower == 'f32' || lower == 'bf16') {
      return true;
    }
    return RegExp(r'^i?q\d').hasMatch(lower);
  }
}

/// Empty state or transcript.
class _ChatBody extends StatelessWidget {
  const _ChatBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        context.select<ChatViewModel, bool>((viewModel) => viewModel.messages.isEmpty);
    return isEmpty
        ? const _EmptyState()
        : _MessageList(scrollController: scrollController);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final isModelReady =
        context.select<ChatViewModel, bool>((viewModel) => viewModel.isModelReady);
    final isBusy = context
        .select<ChatViewModel, bool>((viewModel) => viewModel.generationState.isBusy);
    final enabled = isModelReady && !isBusy;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(),
                  Text(
                    'How can I help?',
                    textAlign: TextAlign.center,
                    style: AppText.title(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Everything you ask is answered by a model on this device.',
                    textAlign: TextAlign.center,
                    style: AppText.subheadline(context).copyWith(
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      children: [
                        for (final suggestion in ChatView.suggestions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: enabled
                                    ? () => unawaited(context
                                        .read<ChatViewModel>()
                                        .send(overrideText: suggestion))
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(suggestion),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isModelReady) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Model is not ready yet.',
                      style: AppText.footnote(context).copyWith(
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The transcript.
///
/// The outer selector watches only the list of message *ids*, so a streamed token — which
/// changes one message's content and nothing else — does not rebuild the list. Each row then
/// selects its own message, so exactly one bubble rebuilds per flush.
class _MessageList extends StatelessWidget {
  const _MessageList({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Selector<ChatViewModel, List<String>>(
      selector: (_, viewModel) =>
          viewModel.messages.map((message) => message.id).toList(growable: false),
      shouldRebuild: (previous, next) => !_sameIds(previous, next),
      builder: (context, ids, _) => ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemCount: ids.length,
        // A turn is a unit of reading; 24 is what stops two of them from being read as one
        // and is the same rhythm the composer's own padding sets up underneath.
        separatorBuilder: (_, __) => const SizedBox(height: 24),
        // The key stays on the row the sliver sees, as before. The measure is imposed here
        // rather than around the `ListView` so the whole pane still takes scroll gestures on
        // a wide screen, not just the column of text.
        itemBuilder: (context, index) => Center(
          key: ValueKey<String>(ids[index]),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            // Without this the box would shrink-wrap its content, and a one-line assistant
            // answer would sit centred in the pane instead of on the measure's left edge.
            child: SizedBox(
              width: double.infinity,
              child: _MessageRow(messageId: ids[index]),
            ),
          ),
        ),
      ),
    );
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// One row's own slice of view-model state.
class _MessageRowData {
  const _MessageRowData(this.message, this.provenance);

  final ChatMessage? message;
  final ResponseProvenance provenance;

  @override
  bool operator ==(Object other) =>
      other is _MessageRowData &&
      other.message == message &&
      other.provenance == provenance;

  @override
  int get hashCode => Object.hash(message, provenance);
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({super.key, required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context) {
    return Selector<ChatViewModel, _MessageRowData>(
      selector: (_, viewModel) => _MessageRowData(
        viewModel.messageById(messageId),
        viewModel.provenanceFor(messageId),
      ),
      builder: (context, data, _) {
        final message = data.message;
        if (message == null) {
          return const SizedBox.shrink();
        }
        return MessageBubble(
          message: message,
          provenance: data.provenance,
          onCopy: () => unawaited(Clipboard.setData(
            ClipboardData(text: context.read<ChatViewModel>().copyText(message)),
          )),
        );
      },
    );
  }
}

class _WebSearchConfirmationBanner extends StatelessWidget {
  const _WebSearchConfirmationBanner({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<ChatViewModel>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.thickMaterial(context),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Curly quotes around the query, exactly as in the original.
          Text('Search the web for “$query”?', style: AppText.footnote(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => unawaited(viewModel.declinePendingWebSearch()),
                child: const Text('Not Now'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => unawaited(viewModel.confirmPendingWebSearch()),
                child: const Text('Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachedDocumentsStrip extends StatelessWidget {
  const _AttachedDocumentsStrip();

  @override
  Widget build(BuildContext context) {
    return Selector<ChatViewModel, List<LocalDocumentReference>>(
      selector: (_, viewModel) => viewModel.attachedDocuments,
      shouldRebuild: (previous, next) => !_sameDocuments(previous, next),
      builder: (context, documents, _) {
        if (documents.isEmpty) {
          return const SizedBox.shrink();
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
          child: Row(
            children: [
              for (final document in documents)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _DocumentChip(document: document),
                ),
            ],
          ),
        );
      },
    );
  }

  static bool _sameDocuments(
    List<LocalDocumentReference> a,
    List<LocalDocumentReference> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

class _DocumentChip extends StatelessWidget {
  const _DocumentChip({required this.document});

  final LocalDocumentReference document;

  @override
  Widget build(BuildContext context) {
    // A Material rather than a decorated Container: the remove button's ink would
    // otherwise paint into the Scaffold's Material, i.e. *behind* this chip's opaque fill,
    // and the tap would look like it did nothing.
    return Material(
      color: AppColors.thickMaterial(context),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.docText, size: 14, color: AppColors.secondaryLabel(context)),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                document.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption(context),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              label: 'Remove ${document.displayName}',
              button: true,
              child: InkWell(
                onTap: () => unawaited(
                    context.read<ChatViewModel>().removeDocument(document.id)),
                customBorder: const CircleBorder(),
                child: Icon(
                  AppIcons.xmarkCircleFill,
                  size: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
