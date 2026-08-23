import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../persistence/conversation.dart';
import '../persistence/conversation_repository.dart';
import '../viewmodels/app_view_model.dart';
import '../viewmodels/chat_view_model.dart';
import '../viewmodels/model_manager_view_model.dart';
import '../viewmodels/sidebar_view_model.dart';
import 'chat_view.dart';
import 'model_manager_view.dart';
import 'sidebar_view.dart';
import 'theme.dart';

/// The two-column shell, and the owner of the three long-lived view models.
///
/// `NavigationSplitView(.balanced)` has no Flutter equivalent, so the adaptation is explicit:
/// at [wideLayoutBreakpoint] and above the sidebar is a permanent column in a `Row`; below it
/// the sidebar is a `Drawer` and the "Show Conversations" toolbar button opens it. There is
/// still exactly **one** `ChatView` either way — selecting a conversation mutates the chat
/// view model rather than pushing a route.
class MainSplitView extends StatefulWidget {
  const MainSplitView({super.key});

  /// The width at which the sidebar stops being a drawer and becomes a column.
  static const double wideLayoutBreakpoint = 900;

  static const double sidebarWidth = 320;

  @override
  State<MainSplitView> createState() => _MainSplitViewState();
}

class _MainSplitViewState extends State<MainSplitView> {
  final GlobalKey<ScaffoldState> _shellKey = GlobalKey<ScaffoldState>();

  late final ChatViewModel _chatViewModel;
  late final SidebarViewModel _sidebarViewModel;
  late final ModelManagerViewModel _modelManagerViewModel;

  String? _selectedConversationId;

  @override
  void initState() {
    super.initState();
    final appViewModel = context.read<AppViewModel>();
    final repository = context.read<ConversationRepository>();

    _sidebarViewModel = SidebarViewModel(repository: repository);
    _chatViewModel = ChatViewModel(
      chatEngine: appViewModel.chatEngine,
      agentOrchestrator: appViewModel.agentOrchestrator,
      documentManager: appViewModel.documentManager,
      repository: repository,
      settings: appViewModel.settings,
      // Stands in for SwiftData's `@Query`: the sidebar has no live query to lean on, so the
      // chat view model tells it when a conversation has been created, written to or touched.
      onConversationsChanged: () => unawaited(_sidebarViewModel.refresh()),
    );
    _modelManagerViewModel = ModelManagerViewModel(
      modelStore: appViewModel.modelStore,
      chatEngine: appViewModel.chatEngine,
      settings: appViewModel.settings,
    );
  }

  @override
  void dispose() {
    _chatViewModel.dispose();
    _sidebarViewModel.dispose();
    _modelManagerViewModel.dispose();
    super.dispose();
  }

  // --- transition gating ------------------------------------------------------------------

  /// Wraps every navigation that would destroy the current chat.
  ///
  /// While a temporary chat holds messages, the transition is parked behind the "End
  /// Temporary Chat?" confirmation instead of running immediately.
  Future<void> _requestTransition(Future<void> Function() action) async {
    if (!_chatViewModel.temporaryChatNeedsDiscardConfirmation()) {
      await action();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Temporary Chat?'),
        content: const Text(
          'This conversation is not saved and will be permanently discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) {
      await action();
    }
  }

  void _requestNewChat() {
    unawaited(_requestTransition(() async {
      await _chatViewModel.startNewPersistentChat();
      if (!mounted) {
        return;
      }
      setState(() => _selectedConversationId = null);
      _closeDrawer();
    }));
  }

  void _requestTemporaryChat() {
    unawaited(_requestTransition(() async {
      await _chatViewModel.startTemporaryChat();
      if (!mounted) {
        return;
      }
      setState(() => _selectedConversationId = null);
      _closeDrawer();
    }));
  }

  void _requestSelectConversation(ConversationSummary conversation) {
    unawaited(_requestTransition(() async {
      await _chatViewModel.loadConversation(
        id: conversation.id,
        title: conversation.title,
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectedConversationId = conversation.id);
      _closeDrawer();
    }));
  }

  void _closeDrawer() {
    final scaffold = _shellKey.currentState;
    if (scaffold != null && scaffold.hasDrawer && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    }
  }

  Future<void> _openModelManager() async {
    _closeDrawer();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.92,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<ModelManagerViewModel>.value(
              value: _modelManagerViewModel,
            ),
          ],
          child: ModelManagerView(
            onWillSwitchModel: () async {
              await _chatViewModel.startNewPersistentChat();
              if (!mounted) {
                return;
              }
              setState(() => _selectedConversationId = null);
            },
          ),
        ),
      ),
    );
  }

  // --- layout ------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatViewModel>.value(value: _chatViewModel),
        ChangeNotifierProvider<SidebarViewModel>.value(value: _sidebarViewModel),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= MainSplitView.wideLayoutBreakpoint;
          return isWide ? _buildWide(context) : _buildCompact(context);
        },
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return Scaffold(
      key: _shellKey,
      backgroundColor: AppColors.page(context),
      body: Row(
        children: [
          SizedBox(width: MainSplitView.sidebarWidth, child: _sidebar()),
          // One hairline. The luminance step between the two grounds does most of the work
          // already, so anything heavier here would read as a border around the chat.
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppColors.hairline(context),
          ),
          // No "Show Conversations" button here: the sidebar is already on screen, and a
          // toolbar button that does nothing is worse than one that is absent.
          Expanded(child: _chat(onShowSidebar: null)),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Scaffold(
      key: _shellKey,
      backgroundColor: AppColors.page(context),
      drawer: Drawer(
        width: MainSplitView.sidebarWidth,
        backgroundColor: AppColors.sidebar(context),
        child: _sidebar(),
      ),
      body: _chat(
        onShowSidebar: () => _shellKey.currentState?.openDrawer(),
      ),
    );
  }

  Widget _sidebar() {
    // Watched rather than read: while a temporary chat is active no saved row is
    // highlighted, and starting or ending one has to repaint the selection.
    return Selector<ChatViewModel, bool>(
      selector: (_, viewModel) => viewModel.isTemporary,
      builder: (context, isTemporary, _) {
        final theme = Theme.of(context);
        // `SidebarView` is a `Scaffold`, so it paints `scaffoldBackgroundColor` — the *page*
        // colour — over whatever this pane sets behind it. Handing that subtree a theme
        // whose scaffold and app bar sit on the sidebar ground is what gives the two panes
        // their luminance step, and it does it from here rather than by editing a file this
        // change has no other business in.
        return Theme(
          data: theme.copyWith(
            scaffoldBackgroundColor: AppColors.sidebar(context),
            appBarTheme: theme.appBarTheme.copyWith(
              backgroundColor: AppColors.sidebar(context),
            ),
          ),
          child: SidebarView(
            selectedConversationId: isTemporary ? null : _selectedConversationId,
            onSelectConversation: _requestSelectConversation,
            onNewChat: _requestNewChat,
            onOpenModelManager: () => unawaited(_openModelManager()),
          ),
        );
      },
    );
  }

  Widget _chat({required VoidCallback? onShowSidebar}) {
    return ChatView(
      onShowSidebar: onShowSidebar,
      onNewChat: _requestNewChat,
      onToggleTemporaryChat: _requestTemporaryChat,
    );
  }
}
