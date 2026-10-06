import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_strings_bn.dart';
import 'app_strings_en.dart';

/// The language the user picked in Settings. [system] follows the device.
enum AppLanguage {
  system('system'),
  english('en'),
  bangla('bn');

  const AppLanguage(this.wireValue);

  /// What `AppSettings` stores. Stable across releases — never rename.
  final String wireValue;

  /// The locale to force on `MaterialApp`, or null to follow the device.
  Locale? get locale => switch (this) {
        AppLanguage.system => null,
        AppLanguage.english => const Locale('en'),
        AppLanguage.bangla => const Locale('bn'),
      };

  static AppLanguage fromWireValue(String? value) {
    for (final language in values) {
      if (language.wireValue == value) {
        return language;
      }
    }
    return AppLanguage.system;
  }
}

/// Every user-visible string in the app, in English ([AppStringsEn]) and Bangla
/// ([AppStringsBn]).
///
/// Hand-written rather than generated from ARB files, for the same reason the project has no
/// `build_runner`: a fresh clone builds with no generation step. Making this an abstract class
/// keeps the one property generation would have given — a string added here and missing from
/// either language is a compile error, not a blank label at runtime.
///
/// Widgets read strings with [AppStrings.of]. Code with no `BuildContext` — error types, the
/// loading states, view models — reads [AppStrings.current], which [delegate] keeps equal to
/// the language the UI is showing. Text the *assistant* says on its own (date answers, the
/// "can't verify" replies) instead follows the language of the user's message, via
/// [AppStrings.forText].
abstract class AppStrings {
  const AppStrings();

  static const List<Locale> supportedLocales = [Locale('en'), Locale('bn')];

  static const LocalizationsDelegate<AppStrings> delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? current;

  /// The language the UI is currently in. Before the first frame — and in tests that never
  /// build a `MaterialApp` — this follows the device locale.
  static AppStrings get current => _current ??= forLocale(ui.PlatformDispatcher.instance.locale);
  static AppStrings? _current;

  @visibleForTesting
  static set current(AppStrings value) => _current = value;

  static AppStrings forLocale(Locale locale) =>
      locale.languageCode == 'bn' ? const AppStringsBn() : const AppStringsEn();

  /// Bangla if [text] is written in Bengali script, English otherwise. For replies the app
  /// writes on the assistant's behalf, which should match the language of the question rather
  /// than the language of the buttons.
  static AppStrings forText(String text) =>
      containsBengaliScript(text) ? const AppStringsBn() : const AppStringsEn();

  static bool containsBengaliScript(String text) {
    for (final unit in text.codeUnits) {
      if (unit >= 0x0980 && unit <= 0x09FF) {
        return true;
      }
    }
    return false;
  }

  /// The locale `intl` should format dates and times with for this language.
  String get intlLocale;

  // --- common ------------------------------------------------------------------------------

  String get appTitle;
  String get ok;
  String get cancel;
  String get done;
  String get delete;
  String get error;
  String get retry;
  String get unknown;
  String get none;

  // --- language ----------------------------------------------------------------------------

  String get languageSection;
  String get languageSystem;
  String get languageFooter;

  // --- settings & models -------------------------------------------------------------------

  String get settingsAndModels;
  String get downloadAModel;
  String get switchModelTitle;
  String get switchModelBody;
  String get switchAction;
  String get deleteModelTitle;
  String get deleteModelBody;
  String get activeModel;
  String get name;
  String get size;
  String get architecture;
  String get quantization;
  String get nativeContext;
  String get chatTemplate;
  String get present;
  String get missing;
  String get status;
  String get loading;
  String get ready;
  String get reloadCurrentModel;
  String get installedModels;
  String get noModelsInstalled;
  String get generationSettings;
  String get contextLength;
  String maxResponseTokens(int count);
  String temperature(String value);
  String get deterministicSeed;
  String get debugMetrics;
  String get generationFooter;
  String get webSearch;
  String get webSearchOff;
  String get webSearchAsk;
  String get webSearchAutomatic;
  String get braveApiKey;
  String get configured;
  String get removeKey;
  String get saveKey;
  String get webSearchFooter;
  String get device;
  String get gpuOffload;
  String get gpuDisabledSimulator;
  String get enabled;
  String get benchmarkDebug;
  String get runningBenchmark;
  String get runBenchmarkSuite;
  String tokensPerSecond(String value);
  String firstTokenSeconds(String value);
  String get benchmarkFooter;
  String get decrease;
  String get increase;
  String get cannotDeleteActiveModel;

  // --- model catalog -----------------------------------------------------------------------

  String get availableModels;
  String get catalogFooter;
  String get download;
  String needsRam(String amount);
  String get recommended;
  String get installed;
  String downloadProgress(String written, String total);
  String contextTokens(String amount);

  /// The one-line note under a catalog entry. [fallback] is the English note the catalog
  /// itself carries.
  String catalogNote(String modelId, String fallback);

  // --- first launch ------------------------------------------------------------------------

  String statusLabel(String status);
  String get chooseAnotherModel;
  String get deleteInvalidModel;
  String get chooseAModel;
  String get modelSetupBody;
  String get checkingModel;
  String get copyingModel;
  String get validatingModel;
  String get loadingModel;
  String get preparingEngine;
  String get noModelInstalled;
  String conversationStoreFailed(String detail);

  // --- chat --------------------------------------------------------------------------------

  String get showConversations;
  String get newChat;
  String get startTemporaryChat;
  String get temporaryChat;
  String get temporaryChatBanner;
  String modelTitle(String name);
  String get emptyStateTitle;
  String get emptyStateSubtitle;
  List<String> get suggestions;
  String get modelNotReady;
  String searchWebFor(String query);
  String get notNow;
  String get search;
  String removeDocument(String name);
  String get thinking;
  String get searchingWeb;
  String get searchingDocuments;
  String get searchingTextbooks;
  String get endTemporaryChatTitle;
  String get endTemporaryChatBody;
  String get discard;
  String get dismissError;

  // --- textbooks (curriculum packs) --------------------------------------------------------

  String get textbooks;
  String get answersUse;
  String get chooseTextbooks;
  String get textbooksFooter;
  String get textbooksIntro;

  /// "Class 9–10 · Bangla version". [classes] is e.g. `[9, 10]`; [stream] is `general` or
  /// `hsc`.
  String packTitle(List<int> classes, String stream, {required bool banglaVersion});
  String packDetails(int books, String size);
  String get usePack;
  String get inUse;
  String get preparingPack;
  String get packListUnavailable;
  String get addTextbooks;
  String answersFromTextbooks(String packTitle);
  String get deletePackTitle;
  String get deletePackBody;

  // --- composer ----------------------------------------------------------------------------

  String get addFile;
  String get messageHint;
  String get stop;
  String get send;

  // --- message bubble ----------------------------------------------------------------------

  String get you;
  String get assistant;
  String get failedToSend;
  String get stopped;
  String get generationFailed;
  String get copy;
  String get thinkingLabel;
  String get sources;
  String sourceWithPage(String source, int page);

  // --- sidebar -----------------------------------------------------------------------------

  String get deleteAllTitle;
  String get deleteAllBody;
  String get deleteAll;
  String get renameConversation;
  String get titleHint;
  String get rename;
  String get more;
  String get deleteAllHistory;
  String get newChatRow;
  String get today;
  String get yesterday;
  String get previous7Days;
  String get previous30Days;
  String get older;
  String get noMatches;
  String get noConversationsYet;
  String get tryDifferentSearch;
  String get startNewChatToBegin;

  // --- debug metrics -----------------------------------------------------------------------

  String get model;
  String get fileSize;
  String get allocatedContext;
  String get lastGeneration;
  String get promptTokens;
  String get reservedOutputTokens;
  String get generatedTokens;
  String get firstTokenLatency;
  String get totalDuration;
  String get tokensPerSecondLabel;
  String get agentPipeline;
  String get plannerDuration;
  String get webSearchDuration;
  String get documentRetrievalDuration;
  String get ragEvidenceTokens;
  String get sessionMemoryTokens;
  String seconds(String value);

  // --- errors ------------------------------------------------------------------------------

  String get errorModelFileMissing;
  String get errorInvalidFileExtension;
  String get errorFileAccessDenied;
  String get errorModelCopyFailed;
  String get errorModelLoadFailed;
  String get errorUnsupportedGguf;
  String get errorMissingChatTemplate;
  String get errorContextCreationFailed;
  String get errorSamplerCreationFailed;
  String get errorTokenizationFailed;
  String errorPromptTooLarge(int? required, int? available);
  String get errorDecodeFailed;
  String get errorGenerationCancelled;
  String get errorOutputDecodingFailed;
  String get errorDatabaseSaveFailed;
  String get errorInsufficientStorage;
  String get errorModelNotLoaded;
  String get errorGenerationAlreadyInProgress;
  String get errorNativeException;
  String get errorUnknownNative;
  String errorUnsupportedDocument(String fileName);
  String get errorPdfHasNoText;
  String get errorDocumentAccessLost;
  String get errorDownloadInvalidResponse;
  String errorDownloadServer(int? statusCode);

  // --- the assistant's own replies (chosen by the language of the question) ----------------

  String get replyWebNotAllowed;
  String get replyWebRetrievalFailed;
  String replyTimeAndDate(String time, String date);
  String replyDate(String date);
  String replyTime(String time);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  // Every locale is "supported": anything that is not Bangla gets English rather than no
  // strings at all. `MaterialApp.supportedLocales` is what actually narrows the choice.
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppStrings> load(Locale locale) {
    final strings = AppStrings.forLocale(locale);
    // The single writer of `current`: whatever the widgets are about to show, the
    // context-free code shows too.
    AppStrings._current = strings;
    return SynchronousFuture<AppStrings>(strings);
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
