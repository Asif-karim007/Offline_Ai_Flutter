import 'app_strings.dart';

/// English. The wording is the app's original copy, unchanged.
class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  String get intlLocale => 'en_US';

  // --- common ------------------------------------------------------------------------------

  @override
  String get appTitle => 'Offline AI Chat';
  @override
  String get ok => 'OK';
  @override
  String get cancel => 'Cancel';
  @override
  String get done => 'Done';
  @override
  String get delete => 'Delete';
  @override
  String get error => 'Error';
  @override
  String get retry => 'Retry';
  @override
  String get unknown => 'Unknown';
  @override
  String get none => 'None';

  // --- language ----------------------------------------------------------------------------

  @override
  String get languageSection => 'Language';
  @override
  String get languageSystem => 'Device language';
  @override
  String get languageFooter =>
      'The language of the app itself. The assistant always replies in the language you '
      'write in — Bangla or English.';

  // --- settings & models -------------------------------------------------------------------

  @override
  String get settingsAndModels => 'Settings & Models';
  @override
  String get downloadAModel => 'Download a Model';
  @override
  String get switchModelTitle => 'Switch Model?';
  @override
  String get switchModelBody =>
      'This cancels any response in progress and reloads the model. Your saved chat '
      'history is kept.';
  @override
  String get switchAction => 'Switch';
  @override
  String get deleteModelTitle => 'Delete Model?';
  @override
  String get deleteModelBody =>
      'This removes the model file from your device. You can download it again later.';
  @override
  String get activeModel => 'Active Model';
  @override
  String get name => 'Name';
  @override
  String get size => 'Size';
  @override
  String get architecture => 'Architecture';
  @override
  String get quantization => 'Quantization';
  @override
  String get nativeContext => 'Native context';
  @override
  String get chatTemplate => 'Chat template';
  @override
  String get present => 'Present';
  @override
  String get missing => 'Missing';
  @override
  String get status => 'Status';
  @override
  String get loading => 'Loading…';
  @override
  String get ready => 'Ready';
  @override
  String get reloadCurrentModel => 'Reload Current Model';
  @override
  String get installedModels => 'Installed Models';
  @override
  String get noModelsInstalled => 'No models installed yet.';
  @override
  String get generationSettings => 'Generation Settings';
  @override
  String get contextLength => 'Context Length';
  @override
  String maxResponseTokens(int count) => 'Max Response Tokens: $count';
  @override
  String temperature(String value) => 'Temperature: $value';
  @override
  String get deterministicSeed => 'Deterministic Seed';
  @override
  String get debugMetrics => 'Debug Metrics';
  @override
  String get generationFooter =>
      'Larger context windows increase memory use, first-response latency, device heat, '
      'and battery consumption, and raise the risk of the app being terminated under '
      'memory pressure.';
  @override
  String get webSearch => 'Web Search';
  @override
  String get webSearchOff => 'Off';
  @override
  String get webSearchAsk => 'Ask';
  @override
  String get webSearchAutomatic => 'Automatic for Current Info';
  @override
  String get braveApiKey => 'Brave Search API Key';
  @override
  String get configured => 'Configured';
  @override
  String get removeKey => 'Remove Key';
  @override
  String get saveKey => 'Save Key';
  @override
  String get webSearchFooter =>
      'When enabled, a short search query (never your full conversation or files) may be '
      'sent to a search provider, and public web pages you search for may be downloaded. '
      'Model reasoning and the final answer always happen on-device. Without a Brave '
      'Search API key, search falls back automatically to a free, no-key DuckDuckGo '
      'search. Changes take effect on your next message -- no restart needed.';
  @override
  String get device => 'Device';
  @override
  String get gpuOffload => 'GPU Offload';
  @override
  String get gpuDisabledSimulator => 'Disabled (Simulator)';
  @override
  String get enabled => 'Enabled';
  @override
  String get benchmarkDebug => 'Benchmark (Debug)';
  @override
  String get runningBenchmark => 'Running Benchmark…';
  @override
  String get runBenchmarkSuite => 'Run Benchmark Suite';
  @override
  String tokensPerSecond(String value) => '$value tok/s';
  @override
  String firstTokenSeconds(String value) => '${value}s first token';
  @override
  String get benchmarkFooter =>
      'Test performance on a physical device, not the Simulator, which is CPU-only and '
      'not representative. Results are not stored anywhere -- they exist only for this '
      'session.';
  @override
  String get decrease => 'Decrease';
  @override
  String get increase => 'Increase';
  @override
  String get cannotDeleteActiveModel =>
      "Can't delete the model that's currently loaded. Switch to another model first.";

  // --- model catalog -----------------------------------------------------------------------

  @override
  String get availableModels => 'Available Models';
  @override
  String get catalogFooter =>
      'Models are fetched from Hugging Face, so the download itself needs a connection. '
      'Once a model is on the device, chatting works fully offline.';
  @override
  String get download => 'Download';
  @override
  String needsRam(String amount) => 'Needs $amount RAM';
  @override
  String get recommended => 'Recommended';
  @override
  String get installed => 'Installed';
  @override
  String downloadProgress(String written, String total) => '$written of $total';
  @override
  String contextTokens(String amount) => '$amount context';
  @override
  String catalogNote(String modelId, String fallback) => fallback;

  // --- first launch ------------------------------------------------------------------------

  @override
  String statusLabel(String status) => 'Status: $status';
  @override
  String get chooseAnotherModel => 'Choose Another Model';
  @override
  String get deleteInvalidModel => 'Delete Invalid Model';
  @override
  String get chooseAModel => 'Choose a Model';
  @override
  String get modelSetupBody =>
      'Download one to start chatting — it is stored on this device and runs entirely on it.';
  @override
  String get checkingModel => 'Checking model…';
  @override
  String get copyingModel => 'Copying model…';
  @override
  String get validatingModel => 'Validating model…';
  @override
  String get loadingModel => 'Loading model…';
  @override
  String get preparingEngine => 'Preparing inference engine…';
  @override
  String get noModelInstalled => 'No model installed';
  @override
  String conversationStoreFailed(String detail) =>
      'Failed to open the conversation store: $detail';

  // --- chat --------------------------------------------------------------------------------

  @override
  String get showConversations => 'Show Conversations';
  @override
  String get newChat => 'New Chat';
  @override
  String get startTemporaryChat => 'Start Temporary Chat';
  @override
  String get temporaryChat => 'Temporary Chat';
  @override
  String get temporaryChatBanner => 'Temporary chat — messages will not be saved';
  @override
  String modelTitle(String name) => 'Model: $name';
  @override
  String get emptyStateTitle => 'How can I help?';
  @override
  String get emptyStateSubtitle => 'Everything you ask is answered by a model on this device.';
  @override
  List<String> get suggestions => const [
        'Explain photosynthesis simply',
        'Make a study plan for my exams',
        'Help me solve a math problem step by step',
      ];
  @override
  String get modelNotReady => 'Model is not ready yet.';
  @override
  String searchWebFor(String query) => 'Search the web for “$query”?';
  @override
  String get notNow => 'Not Now';
  @override
  String get search => 'Search';
  @override
  String removeDocument(String name) => 'Remove $name';
  @override
  String get thinking => 'Thinking…';
  @override
  String get searchingWeb => 'Searching the web…';
  @override
  String get searchingDocuments => 'Searching documents…';
  @override
  String get searchingTextbooks => 'Searching your textbooks…';
  @override
  String get endTemporaryChatTitle => 'End Temporary Chat?';
  @override
  String get endTemporaryChatBody =>
      'This conversation is not saved and will be permanently discarded.';
  @override
  String get discard => 'Discard';
  @override
  String get dismissError => 'Dismiss error';

  // --- textbooks (curriculum packs) --------------------------------------------------------

  @override
  String get textbooks => 'Textbooks';
  @override
  String get answersUse => 'Answers use';
  @override
  String get chooseTextbooks => 'Choose Class & Textbooks';
  @override
  String get textbooksFooter =>
      "Download your class's NCTB textbooks once. After that, study questions are looked up "
      'in them on this device — no internet needed.';
  @override
  String get textbooksIntro =>
      'Pick your class and version. The textbooks download once; after that, answers are '
      'looked up in them offline and cite the book and page.';
  @override
  String packTitle(List<int> classes, String stream, {required bool banglaVersion}) {
    final version = banglaVersion ? 'Bangla version' : 'English version';
    final grade = stream == 'hsc'
        ? 'HSC (Class 11–12)'
        : 'Class ${classes.join('–')}';
    return '$grade · $version';
  }

  @override
  String packDetails(int books, String size) => '$books ${books == 1 ? 'book' : 'books'} · $size';
  @override
  String get usePack => 'Use';
  @override
  String get inUse => 'In use';
  @override
  String get preparingPack => 'Preparing…';
  @override
  String get packListUnavailable =>
      'Connect to the internet once to load the list of textbooks.';
  @override
  String get addTextbooks => 'Add your class textbooks';
  @override
  String answersFromTextbooks(String packTitle) => 'Answers use your textbooks: $packTitle';
  @override
  String get deletePackTitle => 'Delete these textbooks?';
  @override
  String get deletePackBody => 'They are removed from this device. You can download them again later.';

  // --- composer ----------------------------------------------------------------------------

  @override
  String get addFile => 'Add File';
  @override
  String get messageHint => 'Message';
  @override
  String get stop => 'Stop';
  @override
  String get send => 'Send';

  // --- message bubble ----------------------------------------------------------------------

  @override
  String get you => 'You';
  @override
  String get assistant => 'Assistant';
  @override
  String get failedToSend => 'Failed to send';
  @override
  String get stopped => 'Stopped';
  @override
  String get generationFailed => 'Generation failed';
  @override
  String get copy => 'Copy';
  @override
  String get thinkingLabel => 'Thinking';
  @override
  String get sources => 'Sources';
  @override
  String sourceWithPage(String source, int page) => '$source — page $page';

  // --- sidebar -----------------------------------------------------------------------------

  @override
  String get deleteAllTitle => 'Delete all conversations?';
  @override
  String get deleteAllBody =>
      "This permanently deletes every saved conversation. This can't be undone.";
  @override
  String get deleteAll => 'Delete All';
  @override
  String get renameConversation => 'Rename Conversation';
  @override
  String get titleHint => 'Title';
  @override
  String get rename => 'Rename';
  @override
  String get more => 'More';
  @override
  String get deleteAllHistory => 'Delete All History';
  @override
  String get newChatRow => 'New chat';
  @override
  String get today => 'Today';
  @override
  String get yesterday => 'Yesterday';
  @override
  String get previous7Days => 'Previous 7 Days';
  @override
  String get previous30Days => 'Previous 30 Days';
  @override
  String get older => 'Older';
  @override
  String get noMatches => 'No Matches';
  @override
  String get noConversationsYet => 'No Conversations Yet';
  @override
  String get tryDifferentSearch => 'Try a different search.';
  @override
  String get startNewChatToBegin => 'Start a new chat to begin.';

  // --- debug metrics -----------------------------------------------------------------------

  @override
  String get model => 'Model';
  @override
  String get fileSize => 'File size';
  @override
  String get allocatedContext => 'Allocated context';
  @override
  String get lastGeneration => 'Last generation';
  @override
  String get promptTokens => 'Prompt tokens';
  @override
  String get reservedOutputTokens => 'Reserved output tokens';
  @override
  String get generatedTokens => 'Generated tokens';
  @override
  String get firstTokenLatency => 'First-token latency';
  @override
  String get totalDuration => 'Total duration';
  @override
  String get tokensPerSecondLabel => 'Tokens / second';
  @override
  String get agentPipeline => 'Agent Pipeline';
  @override
  String get plannerDuration => 'Planner duration';
  @override
  String get webSearchDuration => 'Web search duration';
  @override
  String get documentRetrievalDuration => 'Document retrieval duration';
  @override
  String get ragEvidenceTokens => 'RAG evidence tokens (est.)';
  @override
  String get sessionMemoryTokens => 'Session memory tokens (est.)';
  @override
  String seconds(String value) => '${value}s';

  // --- errors ------------------------------------------------------------------------------

  @override
  String get errorModelFileMissing =>
      'The selected model file could not be found. It may have been deleted or moved.';
  @override
  String get errorInvalidFileExtension =>
      "That file isn't a GGUF model. Please choose a file ending in .gguf.";
  @override
  String get errorFileAccessDenied => "The app doesn't have permission to read that file.";
  @override
  String get errorModelCopyFailed => "The model file couldn't be copied into the app's storage.";
  @override
  String get errorModelLoadFailed =>
      'The model failed to load. It may be corrupted or incompatible with this device.';
  @override
  String get errorUnsupportedGguf => "This GGUF file isn't a supported model format.";
  @override
  String get errorMissingChatTemplate =>
      "This model doesn't include a usable chat template, so it can't be used for chat yet.";
  @override
  String get errorContextCreationFailed =>
      "The app couldn't allocate memory to run this model. Try a smaller context length.";
  @override
  String get errorSamplerCreationFailed =>
      "The app couldn't set up text generation for this model.";
  @override
  String get errorTokenizationFailed => "The app couldn't process this text for the model.";
  @override
  String errorPromptTooLarge(int? required, int? available) =>
      "This message is too long for the model's context window "
      '($required tokens needed, $available available).';
  @override
  String get errorDecodeFailed =>
      'The model encountered an internal error while generating a response.';
  @override
  String get errorGenerationCancelled => 'Generation was stopped.';
  @override
  String get errorOutputDecodingFailed =>
      "The model produced output that couldn't be decoded as text.";
  @override
  String get errorDatabaseSaveFailed => "Your conversation couldn't be saved.";
  @override
  String get errorInsufficientStorage =>
      "There isn't enough free storage to complete this operation.";
  @override
  String get errorModelNotLoaded => 'No model is currently loaded.';
  @override
  String get errorGenerationAlreadyInProgress => 'A response is already being generated.';
  @override
  String get errorNativeException =>
      'The model engine hit an internal error and recovered safely. Please try again.';
  @override
  String get errorUnknownNative => 'An unexpected error occurred in the model engine.';
  @override
  String errorUnsupportedDocument(String fileName) => '"$fileName" isn\'t a supported file type.';
  @override
  String get errorPdfHasNoText => 'This PDF does not contain extractable text.';
  @override
  String get errorDocumentAccessLost =>
      'I no longer have access to this file. Please select it again.';
  @override
  String get errorDownloadInvalidResponse =>
      'The download server returned an unexpected response.';
  @override
  String errorDownloadServer(int? statusCode) =>
      'The download failed (server returned status $statusCode).';

  // --- the assistant's own replies ---------------------------------------------------------

  @override
  String get replyWebNotAllowed =>
      "I can't verify this because it needs current information and web access isn't "
      "available for this message. I won't guess at an answer that could be outdated.";
  @override
  String get replyWebRetrievalFailed =>
      "I couldn't retrieve reliable current information for this request, so I can't "
      'answer accurately. Please try again in a moment.';
  @override
  String replyTimeAndDate(String time, String date) => "It's $time on $date.";
  @override
  String replyDate(String date) => 'Today is $date.';
  @override
  String replyTime(String time) => "It's $time.";
}
