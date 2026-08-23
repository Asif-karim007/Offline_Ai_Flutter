import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// `WebSearchMode` is owned by the agent layer (`AgentRequest.swift` in the original) and is
// only mirrored here. The direction of the dependency is deliberate and one-way: the
// orchestrator never reads AppSettings, the caller resolves permissions and passes them in.
import 'package:offline_ai_chat/agent/agent_request.dart';
import 'package:offline_ai_chat/agent/web/api_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/generation_configuration.dart';

/// User-configurable generation settings and the selected model file name.
///
/// The Swift original was an `@Observable` class whose every property had a `didSet` that
/// wrote through to `UserDefaults` immediately; there was no `save()`. That is reproduced
/// here: each setter writes to `SharedPreferences` and notifies, and nothing batches.
///
/// **Every key string below is copied verbatim from `AppSettings.Keys`**, including
/// `settings.bundledModelCopied`, whose name does not match its property
/// (`hasBundledModelBeenCopied`). Renaming it would be tidier and would also silently
/// abandon the flag on any device migrated from the iOS build, re-copying a bundled model
/// that is already installed.
///
/// Nothing stored here is chat content. The one secret — the Brave Search API key — lives in
/// the platform keychain, and only a non-secret "is one configured" boolean is kept here so
/// the settings screen can render without awaiting secure storage.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._preferences, this._apiKeyStore)
      : _selectedModelFileName =
            _preferences.getString(_Keys.selectedModelFileName),
        _contextLengthPreset =
            _readIntWithZeroAsUnset(_preferences, _Keys.contextLengthPreset, 4096),
        _maxResponseTokens =
            _readIntWithZeroAsUnset(_preferences, _Keys.maxResponseTokens, 384),
        _temperature = _preferences.getDouble(_Keys.temperature) ?? 0.7,
        _useDeterministicSeed =
            _preferences.getBool(_Keys.useDeterministicSeed) ?? false,
        _debugMetricsEnabled = _preferences.getBool(_Keys.debugMetricsEnabled) ?? false,
        _hasBundledModelBeenCopied =
            _preferences.getBool(_Keys.bundledModelCopied) ?? false,
        _webSearchMode =
            _webSearchModeFromStored(_preferences.getString(_Keys.webSearchMode)),
        _hasBraveApiKey = _preferences.getBool(_Keys.hasBraveApiKey) ?? false;

  /// Reads every value once, up front.
  ///
  /// `UserDefaults` reads synchronously, so the Swift initialiser could populate every
  /// property inline. `SharedPreferences` cannot, which is why construction is a static
  /// future: the alternative — a settings object whose values arrive later — would make
  /// every reader handle a pre-load state that has no counterpart in the original.
  static Future<AppSettings> load({
    SharedPreferences? preferences,
    FlutterSecureStorage? secureStorage,
  }) async {
    final resolved = preferences ?? await SharedPreferences.getInstance();
    return AppSettings._(resolved, ApiKeyStore(storage: secureStorage));
  }

  final SharedPreferences _preferences;

  /// Secure storage goes through [ApiKeyStore] rather than being reimplemented here. It is the
  /// single place that sets the platform options the key needs — Android's
  /// `encryptedSharedPreferences`, iOS's `first_unlock_this_device` accessibility — and a second
  /// copy of that configuration is exactly how one of them ends up missing an option and writing
  /// the key in the clear.
  final ApiKeyStore _apiKeyStore;

  // --- constants carried over verbatim -------------------------------------------------

  /// Keychain account name for the Brave Search API key. The key material itself never
  /// touches `SharedPreferences`.
  static const String braveApiKeyAccount = 'brave-search-api-key';

  /// `kSecAttrService` from the Swift `KeychainStore`. `flutter_secure_storage` maps
  /// `IOSOptions.accountName` onto `kSecAttrService` and the entry key onto
  /// `kSecAttrAccount`, so this pair reads and writes the same keychain item the iOS build
  /// did — an app updated in place keeps its configured key.
  static const String keychainService = ApiKeyStore.service;

  /// The only values the context-length picker offers. Not a range: each one is a KV-cache
  /// size that was checked against the memory budget of a mid-range device.
  static const List<int> availableContextLengths = [2048, 4096, 8192];

  static const int minResponseTokens = 64;
  static const int maxResponseTokensLimit = 1024;
  static const int responseTokensStep = 64;

  static const double minTemperature = 0.0;
  static const double maxTemperature = 1.5;
  static const double temperatureStep = 0.05;

  /// The fixed seed used when "Deterministic Seed" is on. A constant, not a stored value —
  /// the point is that two runs of the same prompt produce the same tokens.
  static const int deterministicSeedValue = 1234;

  // --- stored settings ------------------------------------------------------------------

  String? _selectedModelFileName;
  int _contextLengthPreset;
  int _maxResponseTokens;
  double _temperature;
  bool _useDeterministicSeed;
  bool _debugMetricsEnabled;
  bool _hasBundledModelBeenCopied;
  WebSearchMode _webSearchMode;
  bool _hasBraveApiKey;

  String? get selectedModelFileName => _selectedModelFileName;

  set selectedModelFileName(String? value) {
    if (_selectedModelFileName == value) {
      return;
    }
    _selectedModelFileName = value;
    // `SharedPreferences` has no "set to null"; removing the key is what makes a later read
    // return null, matching `defaults.set(nil, forKey:)`.
    if (value == null) {
      _preferences.remove(_Keys.selectedModelFileName).ignore();
    } else {
      _preferences.setString(_Keys.selectedModelFileName, value).ignore();
    }
    notifyListeners();
  }

  int get contextLengthPreset => _contextLengthPreset;

  set contextLengthPreset(int value) {
    if (_contextLengthPreset == value) {
      return;
    }
    _contextLengthPreset = value;
    _preferences.setInt(_Keys.contextLengthPreset, value).ignore();
    notifyListeners();
  }

  int get maxResponseTokens => _maxResponseTokens;

  set maxResponseTokens(int value) {
    if (_maxResponseTokens == value) {
      return;
    }
    _maxResponseTokens = value;
    _preferences.setInt(_Keys.maxResponseTokens, value).ignore();
    notifyListeners();
  }

  double get temperature => _temperature;

  set temperature(double value) {
    if (_temperature == value) {
      return;
    }
    _temperature = value;
    _preferences.setDouble(_Keys.temperature, value).ignore();
    notifyListeners();
  }

  bool get useDeterministicSeed => _useDeterministicSeed;

  set useDeterministicSeed(bool value) {
    if (_useDeterministicSeed == value) {
      return;
    }
    _useDeterministicSeed = value;
    _preferences.setBool(_Keys.useDeterministicSeed, value).ignore();
    notifyListeners();
  }

  bool get debugMetricsEnabled => _debugMetricsEnabled;

  set debugMetricsEnabled(bool value) {
    if (_debugMetricsEnabled == value) {
      return;
    }
    _debugMetricsEnabled = value;
    _preferences.setBool(_Keys.debugMetricsEnabled, value).ignore();
    notifyListeners();
  }

  /// Guards the bundled-model copy so it only ever runs once, even if the copied file is
  /// later deleted by the user.
  bool get hasBundledModelBeenCopied => _hasBundledModelBeenCopied;

  set hasBundledModelBeenCopied(bool value) {
    if (_hasBundledModelBeenCopied == value) {
      return;
    }
    _hasBundledModelBeenCopied = value;
    _preferences.setBool(_Keys.bundledModelCopied, value).ignore();
    notifyListeners();
  }

  /// Off / Ask / Automatic. `ask` is the default: automatic web lookups are opt-in, because
  /// the entire premise of the app is that nothing leaves the device unless asked.
  WebSearchMode get webSearchMode => _webSearchMode;

  set webSearchMode(WebSearchMode value) {
    if (_webSearchMode == value) {
      return;
    }
    _webSearchMode = value;
    _preferences.setString(_Keys.webSearchMode, value.wireValue).ignore();
    notifyListeners();
  }

  /// Whether a Brave Search API key is configured. Read-only from outside — the only way to
  /// change it is [setBraveApiKey], which keeps it in step with the keychain.
  bool get hasBraveApiKey => _hasBraveApiKey;

  // --- secrets --------------------------------------------------------------------------

  /// Stores (or clears) the Brave Search API key.
  ///
  /// A key that is `null`, or blank once trimmed, clears the entry — which drops web search
  /// back to the zero-configuration provider rather than leaving it half-configured with an
  /// empty string that every request would then send and get rejected for.
  Future<void> setBraveApiKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await _apiKeyStore.set(trimmed, key: braveApiKeyAccount);
      _setHasBraveApiKey(true);
    } else {
      await _apiKeyStore.remove(key: braveApiKeyAccount);
      _setHasBraveApiKey(false);
    }
  }

  /// Returns the configured key, or `null`.
  ///
  /// Short-circuits on the plain flag before touching secure storage, so the common case —
  /// no key configured — never pays for a keychain round trip. That matters because this is
  /// consulted once per agent request, not once per launch.
  Future<String?> currentBraveApiKey() async {
    if (!_hasBraveApiKey) {
      return null;
    }
    return _apiKeyStore.get(key: braveApiKeyAccount);
  }

  void _setHasBraveApiKey(bool value) {
    if (_hasBraveApiKey == value) {
      return;
    }
    _hasBraveApiKey = value;
    _preferences.setBool(_Keys.hasBraveApiKey, value).ignore();
    notifyListeners();
  }

  // --- derived --------------------------------------------------------------------------

  /// Builds a [GenerationConfiguration] from the current settings plus the defaults that are
  /// not user-exposed.
  ///
  /// `batchSize`, `safetyMargin`, `minP`, `topP` and `systemPrompt` are deliberately never
  /// overridden from settings — they are tuned values, not preferences.
  GenerationConfiguration currentGenerationConfiguration() {
    return GenerationConfiguration.standard(gpuLayers: _gpuLayers()).copyWith(
      contextLength: contextLengthPreset,
      maxNewTokens: maxResponseTokens,
      temperature: temperature,
      deterministicSeed: useDeterministicSeed ? deterministicSeedValue : null,
      clearDeterministicSeed: !useDeterministicSeed,
    );
  }

  /// `-1` offloads every layer to the GPU; `0` disables offload.
  ///
  /// The Swift version used `#if targetEnvironment(simulator)`, a compile-time check with no
  /// Dart equivalent. `device_info_plus` would give a runtime `isPhysicalDevice`, but it is
  /// not a dependency of this project, so this reads the environment variable the iOS
  /// Simulator sets in every process it hosts. It is a real signal rather than a heuristic:
  /// `SIMULATOR_DEVICE_NAME` is absent on device and present in the simulator regardless of
  /// build configuration, which is exactly the distinction the `#if` drew.
  ///
  /// The simulator has no usable Metal path for llama.cpp, so offloading there fails slowly
  /// instead of failing fast.
  static int _gpuLayers() {
    final isIosSimulator =
        Platform.isIOS && Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
    return isIosSimulator ? 0 : -1;
  }

  // --- reading semantics ----------------------------------------------------------------

  /// Reproduces `UserDefaults.integer(forKey:)`, which returns `0` for an unset key.
  ///
  /// This is bug-compatible on purpose: a genuinely stored `0` is indistinguishable from
  /// "never set" and is coerced to the default. `SharedPreferences.getInt` returns `null`
  /// for unset and would have let a stored `0` through, which would then be handed to
  /// llama.cpp as a context length of zero.
  static int _readIntWithZeroAsUnset(
    SharedPreferences preferences,
    String key,
    int fallback,
  ) {
    final stored = preferences.getInt(key) ?? 0;
    return stored == 0 ? fallback : stored;
  }

  /// An unrecognised stored value falls back to `ask` rather than throwing, matching
  /// `WebSearchMode.init(rawValue:) ?? .ask`. A downgrade that removes a mode must not
  /// leave the app unable to read its own settings.
  static WebSearchMode _webSearchModeFromStored(String? stored) {
    if (stored == null) {
      return WebSearchMode.ask;
    }
    for (final mode in WebSearchMode.values) {
      if (mode.wireValue == stored) {
        return mode;
      }
    }
    return WebSearchMode.ask;
  }
}

/// The `UserDefaults` key strings, unchanged from the Swift original so a future migration
/// path stays open.
abstract final class _Keys {
  static const String selectedModelFileName = 'settings.selectedModelFileName';
  static const String contextLengthPreset = 'settings.contextLengthPreset';
  static const String maxResponseTokens = 'settings.maxResponseTokens';
  static const String temperature = 'settings.temperature';
  static const String useDeterministicSeed = 'settings.useDeterministicSeed';
  static const String debugMetricsEnabled = 'settings.debugMetricsEnabled';
  static const String bundledModelCopied = 'settings.bundledModelCopied';
  static const String webSearchMode = 'settings.webSearchMode';
  static const String hasBraveApiKey = 'settings.hasBraveAPIKey';
}
