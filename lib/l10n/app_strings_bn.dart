import 'app_strings.dart';

/// Bangla (বাংলা).
///
/// The register is the polite "আপনি" throughout the interface. The starter suggestions are
/// the exception: they are what a student types to the assistant, so they use "তুমি" forms
/// ("বুঝিয়ে দাও"), the way students actually phrase a request. Technical names with no
/// settled Bangla term — GGUF, RAM, GPU, API, Hugging Face — stay in Latin script, as they do
/// in Bangladeshi apps generally.
class AppStringsBn extends AppStrings {
  const AppStringsBn();

  @override
  String get intlLocale => 'bn';

  // --- common ------------------------------------------------------------------------------

  @override
  String get appTitle => 'অফলাইন এআই চ্যাট';
  @override
  String get ok => 'ঠিক আছে';
  @override
  String get cancel => 'বাতিল';
  @override
  String get done => 'সম্পন্ন';
  @override
  String get delete => 'মুছুন';
  @override
  String get error => 'ত্রুটি';
  @override
  String get retry => 'আবার চেষ্টা করুন';
  @override
  String get unknown => 'অজানা';
  @override
  String get none => 'নেই';

  // --- language ----------------------------------------------------------------------------

  @override
  String get languageSection => 'ভাষা';
  @override
  String get languageSystem => 'ডিভাইসের ভাষা';
  @override
  String get languageFooter =>
      'এটি শুধু অ্যাপের ভাষা। আপনি যে ভাষায় লিখবেন — বাংলা বা ইংরেজি — সহকারী সবসময় সেই '
      'ভাষাতেই উত্তর দেবে।';

  // --- settings & models -------------------------------------------------------------------

  @override
  String get settingsAndModels => 'সেটিংস ও মডেল';
  @override
  String get downloadAModel => 'মডেল ডাউনলোড করুন';
  @override
  String get switchModelTitle => 'মডেল পরিবর্তন করবেন?';
  @override
  String get switchModelBody =>
      'চলমান উত্তরটি বাতিল হবে এবং মডেলটি আবার লোড হবে। আপনার সংরক্ষিত চ্যাটগুলো থেকে যাবে।';
  @override
  String get switchAction => 'পরিবর্তন করুন';
  @override
  String get deleteModelTitle => 'মডেল মুছবেন?';
  @override
  String get deleteModelBody =>
      'মডেল ফাইলটি আপনার ডিভাইস থেকে মুছে যাবে। পরে চাইলে আবার ডাউনলোড করতে পারবেন।';
  @override
  String get activeModel => 'চালু মডেল';
  @override
  String get name => 'নাম';
  @override
  String get size => 'আকার';
  @override
  String get architecture => 'আর্কিটেকচার';
  @override
  String get quantization => 'কোয়ান্টাইজেশন';
  @override
  String get nativeContext => 'নিজস্ব কনটেক্সট';
  @override
  String get chatTemplate => 'চ্যাট টেমপ্লেট';
  @override
  String get present => 'আছে';
  @override
  String get missing => 'নেই';
  @override
  String get status => 'অবস্থা';
  @override
  String get loading => 'লোড হচ্ছে…';
  @override
  String get ready => 'প্রস্তুত';
  @override
  String get reloadCurrentModel => 'বর্তমান মডেল আবার লোড করুন';
  @override
  String get installedModels => 'ইনস্টল করা মডেল';
  @override
  String get noModelsInstalled => 'এখনো কোনো মডেল ইনস্টল করা হয়নি।';
  @override
  String get generationSettings => 'উত্তর তৈরির সেটিংস';
  @override
  String get contextLength => 'কনটেক্সট দৈর্ঘ্য';
  @override
  String maxResponseTokens(int count) => 'উত্তরের সর্বোচ্চ টোকেন: $count';
  @override
  String temperature(String value) => 'টেম্পারেচার: $value';
  @override
  String get deterministicSeed => 'নির্দিষ্ট সিড';
  @override
  String get debugMetrics => 'ডিবাগ মেট্রিক্স';
  @override
  String get generationFooter =>
      'কনটেক্সট উইন্ডো যত বড়, তত বেশি মেমরি লাগে, প্রথম উত্তর আসতে তত দেরি হয়, ডিভাইস তত '
      'গরম হয় ও ব্যাটারি তত বেশি খরচ হয়। মেমরি কম পড়লে অ্যাপটি বন্ধ হয়ে যাওয়ার ঝুঁকিও বাড়ে।';
  @override
  String get webSearch => 'ওয়েব সার্চ';
  @override
  String get webSearchOff => 'বন্ধ';
  @override
  String get webSearchAsk => 'আগে জিজ্ঞেস করবে';
  @override
  String get webSearchAutomatic => 'সাম্প্রতিক তথ্যের জন্য স্বয়ংক্রিয়';
  @override
  String get braveApiKey => 'Brave Search API কী';
  @override
  String get configured => 'যুক্ত করা আছে';
  @override
  String get removeKey => 'কী সরান';
  @override
  String get saveKey => 'কী সংরক্ষণ করুন';
  @override
  String get webSearchFooter =>
      'চালু থাকলে একটি ছোট সার্চ কোয়েরি (কখনোই আপনার পুরো কথোপকথন বা ফাইল নয়) সার্চ '
      'সেবাদাতার কাছে পাঠানো হতে পারে, এবং আপনি যে পাবলিক ওয়েবপেজ খুঁজছেন তা ডাউনলোড হতে '
      'পারে। মডেলের চিন্তা ও চূড়ান্ত উত্তর সবসময় এই ডিভাইসেই তৈরি হয়। Brave Search API কী না '
      'থাকলে বিনামূল্যের, কী-ছাড়া DuckDuckGo সার্চ ব্যবহার হয়। পরিবর্তনগুলো আপনার পরের '
      'বার্তা থেকেই কার্যকর হবে — অ্যাপ আবার চালু করতে হবে না।';
  @override
  String get device => 'ডিভাইস';
  @override
  String get gpuOffload => 'GPU অফলোড';
  @override
  String get gpuDisabledSimulator => 'বন্ধ (সিমুলেটর)';
  @override
  String get enabled => 'চালু';
  @override
  String get benchmarkDebug => 'বেঞ্চমার্ক (ডিবাগ)';
  @override
  String get runningBenchmark => 'বেঞ্চমার্ক চলছে…';
  @override
  String get runBenchmarkSuite => 'বেঞ্চমার্ক চালান';
  @override
  String tokensPerSecond(String value) => '$value টোকেন/সে.';
  @override
  String firstTokenSeconds(String value) => 'প্রথম টোকেন $value সে.';
  @override
  String get benchmarkFooter =>
      'পারফরম্যান্স যাচাই করুন আসল ডিভাইসে, সিমুলেটরে নয় — সিমুলেটর শুধু CPU ব্যবহার করে, '
      'তাই ফলাফল বাস্তবসম্মত হয় না। ফলাফল কোথাও সংরক্ষিত হয় না — শুধু এই সেশনেই থাকে।';
  @override
  String get decrease => 'কমান';
  @override
  String get increase => 'বাড়ান';
  @override
  String get cannotDeleteActiveModel =>
      'যে মডেলটি এখন লোড করা আছে সেটি মোছা যাবে না। আগে অন্য একটি মডেলে পরিবর্তন করুন।';

  // --- model catalog -----------------------------------------------------------------------

  @override
  String get availableModels => 'যেসব মডেল পাওয়া যায়';
  @override
  String get catalogFooter =>
      'মডেলগুলো Hugging Face থেকে নামানো হয়, তাই ডাউনলোডের সময় ইন্টারনেট সংযোগ লাগবে। '
      'মডেল একবার ডিভাইসে চলে এলে চ্যাট পুরোপুরি অফলাইনে চলে।';
  @override
  String get download => 'ডাউনলোড';
  @override
  String needsRam(String amount) => '$amount RAM প্রয়োজন';
  @override
  String get recommended => 'প্রস্তাবিত';
  @override
  String get installed => 'ইনস্টল করা আছে';
  @override
  String downloadProgress(String written, String total) => '$total-এর মধ্যে $written';
  @override
  String contextTokens(String amount) => '$amount কনটেক্সট';

  static const Map<String, String> _catalogNotes = {
    'qwen3.5-0.8b-q4_k_m': 'শুরু করার জন্য সবচেয়ে উপযুক্ত। বাংলাসহ ২০১টি ভাষা জানে।',
    'qwen3.5-2b-q4_k_m': 'A19 Pro-তে মাপা গতি ৩৯ টোকেন/সেকেন্ড, সর্বোচ্চ ১.৪৮ GB মেমরি।',
    'qwen3.5-4b-q4_k_m': 'KV ক্যাশ ছাড়াই শুধু মডেলের ওজন ২.৭৪ GB।',
    'gemma-3n-e2b-it-q4_k_m':
        'মাল্টিমোডাল মডেল, এখানে শুধু লেখার জন্য ব্যবহার হয়। আরও ভালো মানের জন্য E4B বেছে নিন।',
    'gemma-3n-e4b-it-q4_k_m':
        'মাল্টিমোডাল মডেল, এখানে শুধু লেখার জন্য ব্যবহার হয়। KV ক্যাশ ছাড়াই শুধু ওজন ৪.৫৪ GB।',
    'multilingual-e5-small-q8_0': 'হাইব্রিড খোঁজার জন্য এমবেডিং মডেল। চ্যাটে ব্যবহার করা যায় না।',
    'gemma-4-e2b-it-qat-q4_0': 'বাংলা ও ইংরেজিতে পড়াশোনার উত্তরে সবচেয়ে ভালো। প্রস্তাবিত।',
  };

  @override
  String catalogNote(String modelId, String fallback) => _catalogNotes[modelId] ?? fallback;

  // --- first launch ------------------------------------------------------------------------

  @override
  String statusLabel(String status) => 'অবস্থা: $status';
  @override
  String get chooseAnotherModel => 'অন্য মডেল বেছে নিন';
  @override
  String get deleteInvalidModel => 'অকার্যকর মডেলটি মুছুন';
  @override
  String get chooseAModel => 'একটি মডেল বেছে নিন';
  @override
  String get modelSetupBody =>
      'চ্যাট শুরু করতে একটি মডেল ডাউনলোড করুন — এটি এই ডিভাইসেই থাকে এবং পুরোপুরি এখানেই চলে।';
  @override
  String get checkingModel => 'মডেল খোঁজা হচ্ছে…';
  @override
  String get copyingModel => 'মডেল কপি করা হচ্ছে…';
  @override
  String get validatingModel => 'মডেল যাচাই করা হচ্ছে…';
  @override
  String get loadingModel => 'মডেল লোড হচ্ছে…';
  @override
  String get preparingEngine => 'ইনফারেন্স ইঞ্জিন প্রস্তুত হচ্ছে…';
  @override
  String get noModelInstalled => 'কোনো মডেল ইনস্টল করা নেই';
  @override
  String conversationStoreFailed(String detail) => 'কথোপকথনের ডেটাবেস খোলা যায়নি: $detail';

  // --- chat --------------------------------------------------------------------------------

  @override
  String get showConversations => 'কথোপকথনগুলো দেখান';
  @override
  String get newChat => 'নতুন চ্যাট';
  @override
  String get startTemporaryChat => 'অস্থায়ী চ্যাট শুরু করুন';
  @override
  String get temporaryChat => 'অস্থায়ী চ্যাট';
  @override
  String get temporaryChatBanner => 'অস্থায়ী চ্যাট — বার্তাগুলো সংরক্ষণ করা হবে না';
  @override
  String modelTitle(String name) => 'মডেল: $name';
  @override
  String get emptyStateTitle => 'কীভাবে সাহায্য করতে পারি?';
  @override
  String get emptyStateSubtitle => 'আপনার প্রতিটি প্রশ্নের উত্তর দেয় এই ডিভাইসেই চলা একটি মডেল।';
  @override
  List<String> get suggestions => const [
        'সালোকসংশ্লেষণ সহজভাবে বুঝিয়ে দাও',
        'পরীক্ষার জন্য একটি পড়ার রুটিন বানিয়ে দাও',
        'একটি গণিত সমস্যা ধাপে ধাপে সমাধান করতে সাহায্য করো',
      ];
  @override
  String get modelNotReady => 'মডেল এখনো প্রস্তুত হয়নি।';
  @override
  String searchWebFor(String query) => '“$query” ওয়েবে খুঁজবেন?';
  @override
  String get notNow => 'এখন না';
  @override
  String get search => 'খুঁজুন';
  @override
  String removeDocument(String name) => '$name সরান';
  @override
  String get thinking => 'ভাবছে…';
  @override
  String get searchingWeb => 'ওয়েবে খুঁজছে…';
  @override
  String get searchingDocuments => 'ডকুমেন্টে খুঁজছে…';
  @override
  String get searchingTextbooks => 'পাঠ্যবইয়ে খুঁজছে…';
  @override
  String get endTemporaryChatTitle => 'অস্থায়ী চ্যাট শেষ করবেন?';
  @override
  String get endTemporaryChatBody => 'এই কথোপকথনটি সংরক্ষিত নয়, তাই এটি স্থায়ীভাবে মুছে যাবে।';
  @override
  String get discard => 'মুছে ফেলুন';
  @override
  String get dismissError => 'ত্রুটির বার্তা বন্ধ করুন';

  // --- textbooks (curriculum packs) --------------------------------------------------------

  @override
  String get textbooks => 'পাঠ্যবই';
  @override
  String get answersUse => 'উত্তরের উৎস';
  @override
  String get chooseTextbooks => 'শ্রেণি ও পাঠ্যবই বেছে নিন';
  @override
  String get textbooksFooter =>
      'আপনার শ্রেণির NCTB পাঠ্যবই একবার ডাউনলোড করুন। এরপর পড়াশোনার প্রশ্নের উত্তর এই '
      'ডিভাইসেই সেই বইগুলো থেকে খোঁজা হবে — ইন্টারনেট লাগবে না।';
  @override
  String get textbooksIntro =>
      'আপনার শ্রেণি ও ভার্সন বেছে নিন। বইগুলো একবারই ডাউনলোড হবে; এরপর অফলাইনেই উত্তর সেই '
      'বই থেকে খোঁজা হবে এবং কোন বইয়ের কোন পৃষ্ঠা, তা-ও দেখানো হবে।';

  static const List<String> _ordinals = [
    'প্রথম', 'দ্বিতীয়', 'তৃতীয়', 'চতুর্থ', 'পঞ্চম', 'ষষ্ঠ',
    'সপ্তম', 'অষ্টম', 'নবম', 'দশম', 'একাদশ', 'দ্বাদশ',
  ];

  static String _ordinal(int number) =>
      number >= 1 && number <= _ordinals.length ? _ordinals[number - 1] : _digits('$number');

  /// Western digits to Bengali digits: "33" → "৩৩".
  static String _digits(String text) => text.replaceAllMapped(
        RegExp(r'[0-9]'),
        (match) => '০১২৩৪৫৬৭৮৯'[int.parse(match.group(0)!)],
      );

  @override
  String packTitle(List<int> classes, String stream, {required bool banglaVersion}) {
    final version = banglaVersion ? 'বাংলা ভার্সন' : 'ইংলিশ ভার্সন';
    final grade = stream == 'hsc'
        ? 'এইচএসসি (একাদশ–দ্বাদশ শ্রেণি)'
        : '${classes.map(_ordinal).join('–')} শ্রেণি';
    return '$grade · $version';
  }

  @override
  String packDetails(int books, String size) => '${_digits('$books')}টি বই · $size';
  @override
  String get usePack => 'ব্যবহার করুন';
  @override
  String get inUse => 'চালু আছে';
  @override
  String get preparingPack => 'প্রস্তুত হচ্ছে…';
  @override
  String get packListUnavailable =>
      'পাঠ্যবইয়ের তালিকা দেখতে একবার ইন্টারনেটে সংযুক্ত হোন।';
  @override
  String get addTextbooks => 'আপনার শ্রেণির পাঠ্যবই যোগ করুন';
  @override
  String answersFromTextbooks(String packTitle) => 'উত্তরে ব্যবহার হচ্ছে: $packTitle';
  @override
  String get deletePackTitle => 'এই পাঠ্যবইগুলো মুছবেন?';
  @override
  String get deletePackBody =>
      'বইগুলো এই ডিভাইস থেকে মুছে যাবে। পরে চাইলে আবার ডাউনলোড করতে পারবেন।';

  // --- composer ----------------------------------------------------------------------------

  @override
  String get addFile => 'ফাইল যোগ করুন';
  @override
  String get messageHint => 'বার্তা লিখুন';
  @override
  String get stop => 'থামান';
  @override
  String get send => 'পাঠান';

  // --- message bubble ----------------------------------------------------------------------

  @override
  String get you => 'আপনি';
  @override
  String get assistant => 'সহকারী';
  @override
  String get failedToSend => 'পাঠানো যায়নি';
  @override
  String get stopped => 'থামানো হয়েছে';
  @override
  String get generationFailed => 'উত্তর তৈরি করা যায়নি';
  @override
  String get copy => 'কপি করুন';
  @override
  String get thinkingLabel => 'চিন্তা';
  @override
  String get sources => 'সূত্র';
  @override
  String sourceWithPage(String source, int page) => '$source — পৃষ্ঠা $page';

  // --- sidebar -----------------------------------------------------------------------------

  @override
  String get deleteAllTitle => 'সব কথোপকথন মুছবেন?';
  @override
  String get deleteAllBody =>
      'সংরক্ষিত সব কথোপকথন স্থায়ীভাবে মুছে যাবে। এটি আর ফিরিয়ে আনা যাবে না।';
  @override
  String get deleteAll => 'সব মুছুন';
  @override
  String get renameConversation => 'কথোপকথনের নাম বদলান';
  @override
  String get titleHint => 'শিরোনাম';
  @override
  String get rename => 'নাম বদলান';
  @override
  String get more => 'আরও';
  @override
  String get deleteAllHistory => 'সব ইতিহাস মুছুন';
  @override
  String get newChatRow => 'নতুন চ্যাট';
  @override
  String get today => 'আজ';
  @override
  String get yesterday => 'গতকাল';
  @override
  String get previous7Days => 'গত ৭ দিন';
  @override
  String get previous30Days => 'গত ৩০ দিন';
  @override
  String get older => 'আরও পুরোনো';
  @override
  String get noMatches => 'কিছু পাওয়া যায়নি';
  @override
  String get noConversationsYet => 'এখনো কোনো কথোপকথন নেই';
  @override
  String get tryDifferentSearch => 'অন্য কিছু লিখে খুঁজে দেখুন।';
  @override
  String get startNewChatToBegin => 'শুরু করতে একটি নতুন চ্যাট খুলুন।';

  // --- debug metrics -----------------------------------------------------------------------

  @override
  String get model => 'মডেল';
  @override
  String get fileSize => 'ফাইলের আকার';
  @override
  String get allocatedContext => 'বরাদ্দকৃত কনটেক্সট';
  @override
  String get lastGeneration => 'সর্বশেষ উত্তর';
  @override
  String get promptTokens => 'প্রম্পট টোকেন';
  @override
  String get reservedOutputTokens => 'উত্তরের জন্য রাখা টোকেন';
  @override
  String get generatedTokens => 'তৈরি হওয়া টোকেন';
  @override
  String get firstTokenLatency => 'প্রথম টোকেন আসার সময়';
  @override
  String get totalDuration => 'মোট সময়';
  @override
  String get tokensPerSecondLabel => 'টোকেন / সেকেন্ড';
  @override
  String get agentPipeline => 'এজেন্ট পাইপলাইন';
  @override
  String get plannerDuration => 'প্ল্যানারের সময়';
  @override
  String get webSearchDuration => 'ওয়েব সার্চের সময়';
  @override
  String get documentRetrievalDuration => 'ডকুমেন্ট খোঁজার সময়';
  @override
  String get ragEvidenceTokens => 'RAG তথ্যের টোকেন (আনুমানিক)';
  @override
  String get sessionMemoryTokens => 'সেশন মেমরির টোকেন (আনুমানিক)';
  @override
  String seconds(String value) => '$value সে.';

  // --- errors ------------------------------------------------------------------------------

  @override
  String get errorModelFileMissing =>
      'নির্বাচিত মডেল ফাইলটি পাওয়া যায়নি। এটি হয়তো মুছে ফেলা হয়েছে বা সরানো হয়েছে।';
  @override
  String get errorInvalidFileExtension =>
      'এটি GGUF মডেল ফাইল নয়। অনুগ্রহ করে .gguf দিয়ে শেষ হওয়া একটি ফাইল বেছে নিন।';
  @override
  String get errorFileAccessDenied => 'ফাইলটি পড়ার অনুমতি অ্যাপের নেই।';
  @override
  String get errorModelCopyFailed => 'মডেল ফাইলটি অ্যাপের স্টোরেজে কপি করা যায়নি।';
  @override
  String get errorModelLoadFailed =>
      'মডেলটি লোড হয়নি। ফাইলটি হয়তো নষ্ট, অথবা এই ডিভাইসের সাথে মানানসই নয়।';
  @override
  String get errorUnsupportedGguf => 'এই GGUF ফাইলের মডেল ফরম্যাটটি সমর্থিত নয়।';
  @override
  String get errorMissingChatTemplate =>
      'এই মডেলে ব্যবহারযোগ্য চ্যাট টেমপ্লেট নেই, তাই এটি এখনো চ্যাটের জন্য ব্যবহার করা যাবে না।';
  @override
  String get errorContextCreationFailed =>
      'এই মডেল চালানোর মতো মেমরি পাওয়া যায়নি। ছোট কনটেক্সট দৈর্ঘ্য দিয়ে চেষ্টা করুন।';
  @override
  String get errorSamplerCreationFailed => 'এই মডেলের জন্য উত্তর তৈরির ব্যবস্থা চালু করা যায়নি।';
  @override
  String get errorTokenizationFailed => 'লেখাটি মডেলের জন্য প্রস্তুত করা যায়নি।';
  @override
  String errorPromptTooLarge(int? required, int? available) =>
      'বার্তাটি মডেলের কনটেক্সট উইন্ডোর তুলনায় অনেক বড় '
      '($required টোকেন প্রয়োজন, পাওয়া যাচ্ছে $available)।';
  @override
  String get errorDecodeFailed => 'উত্তর তৈরির সময় মডেলে একটি অভ্যন্তরীণ ত্রুটি হয়েছে।';
  @override
  String get errorGenerationCancelled => 'উত্তর তৈরি থামানো হয়েছে।';
  @override
  String get errorOutputDecodingFailed => 'মডেলের তৈরি লেখাটি পড়া যায়নি।';
  @override
  String get errorDatabaseSaveFailed => 'আপনার কথোপকথনটি সংরক্ষণ করা যায়নি।';
  @override
  String get errorInsufficientStorage => 'কাজটি শেষ করার মতো যথেষ্ট ফাঁকা জায়গা ডিভাইসে নেই।';
  @override
  String get errorModelNotLoaded => 'এখন কোনো মডেল লোড করা নেই।';
  @override
  String get errorGenerationAlreadyInProgress => 'একটি উত্তর ইতিমধ্যে তৈরি হচ্ছে।';
  @override
  String get errorNativeException =>
      'মডেল ইঞ্জিনে একটি অভ্যন্তরীণ ত্রুটি হয়েছিল, তবে নিরাপদে সামলে নেওয়া হয়েছে। আবার চেষ্টা করুন।';
  @override
  String get errorUnknownNative => 'মডেল ইঞ্জিনে একটি অপ্রত্যাশিত ত্রুটি হয়েছে।';
  @override
  String errorUnsupportedDocument(String fileName) => '"$fileName" ধরনের ফাইল সমর্থিত নয়।';
  @override
  String get errorPdfHasNoText => 'এই PDF থেকে লেখা বের করা যায় না।';
  @override
  String get errorDocumentAccessLost =>
      'এই ফাইলটি পড়ার অনুমতি আর নেই। অনুগ্রহ করে ফাইলটি আবার নির্বাচন করুন।';
  @override
  String get errorDownloadInvalidResponse => 'ডাউনলোড সার্ভার একটি অপ্রত্যাশিত উত্তর দিয়েছে।';
  @override
  String errorDownloadServer(int? statusCode) =>
      'ডাউনলোড ব্যর্থ হয়েছে (সার্ভার স্ট্যাটাস $statusCode)।';

  // --- the assistant's own replies ---------------------------------------------------------

  @override
  String get replyWebNotAllowed =>
      'এই প্রশ্নের উত্তরের জন্য সাম্প্রতিক তথ্য দরকার, কিন্তু এই বার্তার জন্য ইন্টারনেট ব্যবহারের '
      'সুযোগ নেই, তাই আমি তথ্যটি যাচাই করতে পারছি না। পুরোনো হয়ে যেতে পারে এমন উত্তর আমি '
      'অনুমান করে দেব না।';
  @override
  String get replyWebRetrievalFailed =>
      'এই প্রশ্নের জন্য নির্ভরযোগ্য সাম্প্রতিক তথ্য পাওয়া যায়নি, তাই সঠিক উত্তর দিতে পারছি না। '
      'একটু পরে আবার চেষ্টা করুন।';
  @override
  String replyTimeAndDate(String time, String date) => 'এখন সময় $time, আজ $date।';
  @override
  String replyDate(String date) => 'আজ $date।';
  @override
  String replyTime(String time) => 'এখন সময় $time।';
}
