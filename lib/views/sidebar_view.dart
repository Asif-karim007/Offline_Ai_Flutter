import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../persistence/conversation.dart';
import '../viewmodels/sidebar_view_model.dart';
import 'theme.dart';

/// The conversation list.
///
/// The Swift version had no list of its own — SwiftData's `@Query` supplied a live one. Here
/// the list lives on [SidebarViewModel] and is refreshed on first appearance, after every
/// mutation, and whenever the chat view model reports a write.
///
/// **Layout.** The pane follows the convention every mainstream assistant app has converged
/// on: a search capsule at the top, a "New chat" row directly under it, the conversations as
/// rounded pills grouped under date headers, and a single pinned settings row at the foot.
/// No app bar — a drawer that is already a pane does not need a second title strip, and the
/// vertical space is worth more to the list.
class SidebarView extends StatefulWidget {
  const SidebarView({
    super.key,
    required this.selectedConversationId,
    required this.onSelectConversation,
    required this.onNewChat,
    required this.onOpenModelManager,
  });

  /// Null while a temporary chat is active, so no row is highlighted.
  final String? selectedConversationId;

  final void Function(ConversationSummary conversation) onSelectConversation;
  final VoidCallback onNewChat;
  final VoidCallback onOpenModelManager;

  @override
  State<SidebarView> createState() => _SidebarViewState();
}

class _SidebarViewState extends State<SidebarView> {
  final TextEditingController _searchController = TextEditingController();
  String? _shownErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(context.read<SidebarViewModel>().refresh());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The Swift `SidebarViewModel.errorMessage` was written by every async method and rendered
  /// by nothing — a rename or delete that failed did so silently. Surfacing it is the one
  /// deliberate behavioural change on this screen.
  void _surfaceErrors(SidebarViewModel viewModel) {
    final message = viewModel.errorMessage;
    if (message == null || message == _shownErrorMessage) {
      return;
    }
    _shownErrorMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      viewModel.errorMessage = null;
      _shownErrorMessage = null;
    });
  }

  Future<void> _confirmDeleteAll(SidebarViewModel viewModel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all conversations?'),
        content: const Text(
          "This permanently deletes every saved conversation. This can't be undone.",
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
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.deleteAll();
    }
  }

  Future<void> _rename(
    SidebarViewModel viewModel,
    ConversationSummary conversation,
  ) async {
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    // Deferred a frame: the dialog's exit transition still has the TextField mounted, and
    // the focus manager's unfocus can write back through `controller.value` after this
    // point — which on a disposed controller throws "used after being disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (title != null) {
      // An empty title is a silent no-op inside the view model, matching the original.
      await viewModel.rename(conversationId: conversation.id, title: title);
    }
  }

  Future<void> _showRowMenu(
    SidebarViewModel viewModel,
    ConversationSummary conversation,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      return;
    }
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(AppIcons.pencil),
            title: Text('Rename'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              AppIcons.trash,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
    switch (action) {
      case 'rename':
        await _rename(viewModel, conversation);
      case 'delete':
        await viewModel.delete(conversation.id);
    }
  }

  /// The search capsule, and — because the pane no longer has an app bar to hang it from —
  /// the overflow menu that carries "Delete All History".
  Widget _buildSearchBar(BuildContext context, SidebarViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) => viewModel.searchText = value,
              textInputAction: TextInputAction.search,
              style: AppText.body(context),
              decoration: InputDecoration(
                hintText: 'Search',
                isDense: true,
                filled: true,
                fillColor: AppColors.thickMaterial(context),
                prefixIcon: Icon(
                  AppIcons.magnifyingglass,
                  size: 20,
                  color: AppColors.secondaryLabel(context),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                contentPadding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(AppIcons.ellipsisCircle),
            tooltip: 'More',
            onSelected: (_) => unawaited(_confirmDeleteAll(viewModel)),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'deleteAll',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    AppIcons.trash,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete All History',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewChatRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        onTap: widget.onNewChat,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        minLeadingWidth: 0,
        leading: const Icon(AppIcons.squareAndPencil, size: 20),
        title: Text(
          'New chat',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.body(context),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Material(
      color: AppColors.sidebar(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline(context))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              onTap: widget.onOpenModelManager,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
              minLeadingWidth: 0,
              leading: const Icon(AppIcons.gearshape, size: 20),
              title: Text(
                'Settings & Models',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SidebarViewModel>();
    _surfaceErrors(viewModel);

    // The field is the source of truth for the query and pushes into the view model, never
    // the other way round. Writing back to the controller here would mutate it mid-build and
    // trip `markNeedsBuild` on the `TextField` that is currently building.
    final all = viewModel.conversations;
    final filtered = viewModel.filteredConversations;
    final items = _groupByDate(filtered);

    return Scaffold(
      backgroundColor: AppColors.sidebar(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(context, viewModel),
            _buildNewChatRow(context),
            const SizedBox(height: 4),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyState(hasAnyConversations: all.isNotEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        if (item is _SectionHeaderItem) {
                          return _SectionHeader(label: item.label);
                        }
                        final conversation =
                            (item as _ConversationItem).conversation;
                        return _ConversationRow(
                          key: ValueKey(conversation.id),
                          conversation: conversation,
                          isSelected:
                              conversation.id == widget.selectedConversationId,
                          onTap: () => widget.onSelectConversation(conversation),
                          onDelete: () => viewModel.delete(conversation.id),
                          onLongPress: (position) => unawaited(
                            _showRowMenu(viewModel, conversation, position),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }
}

// -------------------------------------------------------------------------------------------
// Date grouping
// -------------------------------------------------------------------------------------------

/// The buckets, in the order they are rendered. `ConversationSummary.updatedAt` is the only
/// timestamp the sidebar has, and it is the one the list is already sorted by.
enum _DateGroup { today, yesterday, previousWeek, previousMonth, older }

String _labelForGroup(_DateGroup group) => switch (group) {
      _DateGroup.today => 'Today',
      _DateGroup.yesterday => 'Yesterday',
      _DateGroup.previousWeek => 'Previous 7 Days',
      _DateGroup.previousMonth => 'Previous 30 Days',
      _DateGroup.older => 'Older',
    };

/// Compared by calendar day rather than by elapsed hours: something written at 23:50 is
/// "Yesterday" at 00:10, not "22 hours ago".
_DateGroup _groupFor(DateTime timestamp, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
  final elapsedDays = today.difference(day).inDays;
  if (elapsedDays <= 0) {
    return _DateGroup.today;
  }
  if (elapsedDays == 1) {
    return _DateGroup.yesterday;
  }
  if (elapsedDays <= 7) {
    return _DateGroup.previousWeek;
  }
  if (elapsedDays <= 30) {
    return _DateGroup.previousMonth;
  }
  return _DateGroup.older;
}

/// Flattens the list into headers and rows. Order within a bucket is the order the
/// repository returned — newest activity first — and is never re-sorted here.
List<_SidebarItem> _groupByDate(List<ConversationSummary> conversations) {
  final now = DateTime.now();
  final buckets = <_DateGroup, List<ConversationSummary>>{};
  for (final conversation in conversations) {
    buckets
        .putIfAbsent(
          _groupFor(conversation.updatedAt, now),
          () => <ConversationSummary>[],
        )
        .add(conversation);
  }

  final items = <_SidebarItem>[];
  for (final group in _DateGroup.values) {
    final bucket = buckets[group];
    if (bucket == null || bucket.isEmpty) {
      continue;
    }
    items.add(_SectionHeaderItem(_labelForGroup(group)));
    for (final conversation in bucket) {
      items.add(_ConversationItem(conversation));
    }
  }
  return items;
}

/// One entry in the flattened list: either a date header or a conversation.
abstract class _SidebarItem {
  const _SidebarItem();
}

class _SectionHeaderItem extends _SidebarItem {
  const _SectionHeaderItem(this.label);

  final String label;
}

class _ConversationItem extends _SidebarItem {
  const _ConversationItem(this.conversation);

  final ConversationSummary conversation;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: AppText.caption2(context).copyWith(
          letterSpacing: 0.5,
          color: AppColors.tertiaryLabel(context),
        ),
      ),
    );
  }
}

/// SwiftUI's `ContentUnavailableView`, in its two flavours.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyConversations});

  final bool hasAnyConversations;

  @override
  Widget build(BuildContext context) {
    final title = hasAnyConversations ? 'No Matches' : 'No Conversations Yet';
    final description =
        hasAnyConversations ? 'Try a different search.' : 'Start a new chat to begin.';
    final icon = hasAnyConversations
        ? AppIcons.magnifyingglass
        : AppIcons.bubbleLeftAndBubbleRight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.tertiaryLabel(context)),
            const SizedBox(height: 12),
            Text(title, style: AppText.title2(context), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppText.subheadline(context).copyWith(
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A conversation, as a rounded pill inset from the pane's edge.
///
/// Title only: the date header above the row already carries the recency the timestamp line
/// used to, and a single line of title is what makes a long list scannable.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onLongPress,
  });

  final ConversationSummary conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final void Function(Offset globalPosition) onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Semantics(
        selected: isSelected,
        container: true,
        child: Dismissible(
          key: ValueKey('dismiss-${conversation.id}'),
          direction: DismissDirection.endToStart,
          // Deleting a single conversation is not confirmed, matching the original — only
          // "Delete All History" asks first. `confirmDismiss` rather than `onDismissed`
          // because the row is removed by the list's own refresh, and letting `Dismissible`
          // also remove it would trip the "dismissed widget still in the tree" assertion in
          // the window before that refresh lands.
          confirmDismiss: (_) async {
            await onDelete();
            return false;
          },
          background: Container(
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.trash, color: scheme.onError, size: 20),
                const SizedBox(width: 6),
                Text('Delete', style: TextStyle(color: scheme.onError)),
              ],
            ),
          ),
          child: GestureDetector(
            // `InkWell.onLongPress` gives no position, and the context menu has to open
            // where the finger is.
            onLongPressStart: (details) => onLongPress(details.globalPosition),
            // Shape, selected fill and selected foreground all come from the theme's
            // `listTileTheme`, so a selected row is a pill without any local painting.
            child: ListTile(
              selected: isSelected,
              onTap: onTap,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
              minLeadingWidth: 0,
              title: Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// SwiftUI's `Text(date, style: .relative)`.
///
/// iOS renders a bare magnitude with no "ago" suffix — `"3 min"`, `"2 hr"`, `"5 days"` — and
/// re-renders it live as the clock moves. This is the static equivalent; the value refreshes
/// whenever the list rebuilds, which in practice is every time a conversation is written to.
/// `intl`'s `DateFormat` covers the fallback for anything older than a week.
String relativeTimestamp(DateTime timestamp) {
  final elapsed = DateTime.now().difference(timestamp);
  if (elapsed.inSeconds < 60) {
    return 'now';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes} min';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hr';
  }
  if (elapsed.inDays < 7) {
    return '${elapsed.inDays} ${elapsed.inDays == 1 ? 'day' : 'days'}';
  }
  return DateFormat.yMMMd().format(timestamp);
}
