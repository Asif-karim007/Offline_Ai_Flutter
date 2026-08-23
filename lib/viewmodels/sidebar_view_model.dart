import 'package:flutter/foundation.dart';

import '../persistence/conversation.dart';
import '../persistence/conversation_repository.dart';
import 'error_text.dart';

/// The conversation list: the query, the filter, and the three destructive operations.
///
/// **The list itself is new here.** The Swift `SidebarViewModel` held no conversations at all
/// — `SidebarView` used SwiftData's `@Query`, which is a live, self-sorting, auto-updating
/// collection. `ConversationRepository` offers `fetchAllSummaries()` and no change stream, so
/// the list has to be held and refreshed explicitly. [refresh] is called on first appearance,
/// after every mutation here, and by `MainSplitView` whenever `ChatViewModel` reports that it
/// has written to the store.
class SidebarViewModel extends ChangeNotifier {
  SidebarViewModel({required ConversationRepository repository})
      : _repository = repository;

  final ConversationRepository _repository;

  String _searchText = '';
  String? _errorMessage;
  List<ConversationSummary> _conversations = const [];
  bool _isLoading = false;

  /// Two-way bound to the search field.
  String get searchText => _searchText;

  set searchText(String value) {
    if (_searchText == value) {
      return;
    }
    _searchText = value;
    _notify();
  }

  /// Written by all three async methods below.
  ///
  /// In the Swift app nothing rendered this — a failed rename or delete was silent. The port
  /// surfaces it as a `SnackBar` in `SidebarView`, which is the one deliberate behavioural
  /// improvement in this class.
  String? get errorMessage => _errorMessage;

  set errorMessage(String? value) {
    if (_errorMessage == value) {
      return;
    }
    _errorMessage = value;
    _notify();
  }

  /// Newest activity first, as the repository returns them.
  List<ConversationSummary> get conversations => List.unmodifiable(_conversations);

  bool get isLoading => _isLoading;

  /// The list after the search filter, which is what the sidebar actually renders.
  List<ConversationSummary> get filteredConversations => _conversations
      .where((conversation) =>
          matches(title: conversation.title, preview: conversation.lastMessagePreview))
      .toList(growable: false);

  Future<void> refresh() async {
    _isLoading = true;
    _notify();
    try {
      _conversations = await _repository.fetchAllSummaries();
    } on Object catch (error) {
      _errorMessage = describeError(error);
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Silently does nothing when the trimmed title is empty — the alert just closes, with no
  /// error and no write.
  Future<void> rename({required String conversationId, required String title}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      await _repository.renameConversation(id: conversationId, title: trimmed);
    } on Object catch (error) {
      _errorMessage = describeError(error);
    }
    await refresh();
  }

  /// No confirmation, matching the original: a swipe or a context-menu tap deletes the
  /// conversation immediately. Only "Delete All History" asks first.
  Future<void> delete(String conversationId) async {
    try {
      await _repository.deleteConversation(conversationId);
    } on Object catch (error) {
      _errorMessage = describeError(error);
    }
    await refresh();
  }

  Future<void> deleteAll() async {
    try {
      await _repository.deleteAllConversations();
    } on Object catch (error) {
      _errorMessage = describeError(error);
    }
    await refresh();
  }

  /// An empty query matches everything. Otherwise the query has to appear in the title or the
  /// preview, case-insensitively.
  ///
  /// Swift used `localizedCaseInsensitiveContains`, which folds case per the current locale.
  /// Dart's `toLowerCase()` is Unicode's default case folding and is locale-independent — the
  /// two differ only for Turkish dotless I and a handful of similar cases, and Dart offers no
  /// locale-sensitive equivalent without adding a dependency.
  bool matches({required String title, required String preview}) {
    final query = _searchText.trim();
    if (query.isEmpty) {
      return true;
    }
    final needle = query.toLowerCase();
    return title.toLowerCase().contains(needle) ||
        preview.toLowerCase().contains(needle);
  }

  bool _disposed = false;

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
