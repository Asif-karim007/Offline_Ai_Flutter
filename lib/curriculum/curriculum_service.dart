import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../agent/curriculum/textbook_retriever.dart';
import '../model_management/app_settings.dart';
import '../model_management/model_downloader.dart';
import '../utilities/logger.dart';
import '../viewmodels/error_text.dart';
import 'curriculum_index.dart';
import 'curriculum_pack.dart';

/// Where a pack is in its life on this device.
enum CurriculumPackStatus { notInstalled, downloading, preparing, installed }

/// The student's textbook library: which packs exist, which are on the device, which one
/// answers questions — and the search itself.
///
/// Packs are downloaded once, over the network, from the public Hugging Face dataset, and
/// everything after that is offline. One pack is *active* at a time (a student studies one
/// class in one version); its full-text index is opened at launch and searched on every
/// question by the agent through [TextbookRetriever].
class CurriculumService extends ChangeNotifier implements TextbookRetriever {
  CurriculumService({
    required Directory directory,
    required AppSettings settings,
    http.Client? httpClient,
    DatabaseFactory? databaseFactory,
  })  : _directory = directory,
        _settings = settings,
        _httpClient = httpClient,
        _databaseFactory = databaseFactory;

  /// `<application support>/Curriculum` — private to the app, removed on uninstall, never
  /// scanned by the media store.
  static Future<CurriculumService> open(AppSettings settings) async {
    final support = await getApplicationSupportDirectory();
    return CurriculumService(
      directory: Directory(p.join(support.path, 'Curriculum')),
      settings: settings,
    );
  }

  final Directory _directory;
  final AppSettings _settings;
  final http.Client? _httpClient;
  final DatabaseFactory? _databaseFactory;

  CurriculumManifest? _manifest;
  bool _isLoadingManifest = false;
  bool _manifestFailed = false;
  final Set<String> _installedFiles = {};

  String? _downloadingPackId;
  ModelDownloadProgress? _downloadProgress;
  ModelDownloader? _downloader;
  String? _preparingPackId;
  String? _errorMessage;

  CurriculumIndex? _index;
  String? _indexPackId;
  Future<void>? _indexOpening;

  // --- state --------------------------------------------------------------------------------

  CurriculumManifest? get manifest => _manifest;
  bool get isLoadingManifest => _isLoadingManifest;

  /// The pack list could not be fetched and there is no cached copy — i.e. never online yet.
  bool get manifestUnavailable => _manifestFailed && _manifest == null;

  ModelDownloadProgress? get downloadProgress => _downloadProgress;
  bool get isDownloading => _downloadingPackId != null;

  String? get errorMessage => _errorMessage;
  set errorMessage(String? value) {
    _errorMessage = value;
    notifyListeners();
  }

  String? get activePackId => _settings.activeCurriculumPackId;

  CurriculumPack? get activePack {
    final id = activePackId;
    return id == null ? null : _manifest?.byId(id);
  }

  CurriculumPackStatus statusOf(CurriculumPack pack) {
    if (_downloadingPackId == pack.id) return CurriculumPackStatus.downloading;
    if (_preparingPackId == pack.id) return CurriculumPackStatus.preparing;
    if (_installedFiles.contains(pack.fileName)) return CurriculumPackStatus.installed;
    return CurriculumPackStatus.notInstalled;
  }

  // --- lifecycle ----------------------------------------------------------------------------

  /// Called once at launch. Works offline: the cached pack list and the installed files are
  /// enough to open the active pack; the network refresh happens in the background.
  Future<void> start() async {
    await _directory.create(recursive: true);
    await _loadCachedManifest();
    await _scanInstalled();
    notifyListeners();
    unawaited(_openActiveIndex());
    unawaited(refreshManifest());
  }

  /// Fetches the pack list. A call while a fetch is already running waits for that fetch
  /// rather than returning early with nothing loaded.
  Future<void> refreshManifest() => _manifestRefresh ??=
      _fetchManifest().whenComplete(() => _manifestRefresh = null);

  Future<void>? _manifestRefresh;

  Future<void> _fetchManifest() async {
    _isLoadingManifest = true;
    notifyListeners();
    final client = _httpClient ?? http.Client();
    try {
      final response =
          await client.get(CurriculumManifest.url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('manifest status ${response.statusCode}');
      }
      final body = utf8.decode(response.bodyBytes);
      _manifest = CurriculumManifest.fromJson(jsonDecode(body) as Map<String, Object?>);
      _manifestFailed = false;
      await File(_manifestCachePath).writeAsString(body);
    } catch (_) {
      // Offline is the normal case for this app, not an error worth a banner: the cached list
      // (if any) stays on screen and the list view says it could not refresh.
      _manifestFailed = true;
      AppLog.ui('curriculum.manifestFetchFailed');
    } finally {
      if (_httpClient == null) client.close();
      _isLoadingManifest = false;
      notifyListeners();
    }
  }

  // --- actions ------------------------------------------------------------------------------

  /// Downloads [pack], prepares its search index and — when no pack is active yet — makes it
  /// the active one, so the first download "just works".
  Future<void> download(CurriculumPack pack) async {
    if (isDownloading) return;
    _downloadingPackId = pack.id;
    _downloadProgress = null;
    _errorMessage = null;
    notifyListeners();

    final destination = _packPath(pack);
    final downloader = ModelDownloader(client: _httpClient);
    _downloader = downloader;
    var finished = false;
    try {
      await for (final event in downloader.download(url: pack.downloadUrl, destinationPath: destination)) {
        switch (event) {
          case ModelDownloadProgress():
            _downloadProgress = event;
            notifyListeners();
          case ModelDownloadFinished():
            finished = true;
        }
      }
      if (!finished) {
        return; // cancelled — the partial file is kept for a later resume
      }
      final size = await File(destination).length();
      if (pack.sizeBytes > 0 && size != pack.sizeBytes) {
        await File(destination).delete();
        throw const ModelDownloadException(ModelDownloadErrorKind.invalidResponse);
      }
      _installedFiles.add(pack.fileName);
    } catch (error) {
      _errorMessage = describeError(error);
      return;
    } finally {
      _downloader = null;
      _downloadingPackId = null;
      _downloadProgress = null;
      notifyListeners();
    }

    if (activePackId == null || activePackId == pack.id) {
      await activate(pack);
    } else {
      // Build the index now, while the student is still looking at the progress, rather than
      // on the first question after they switch to it.
      await _withPreparing(pack, () async {
        final index = await CurriculumIndex.open(destination, factory: _databaseFactory);
        await index.close();
      });
    }
  }

  Future<void> cancelDownload() async {
    await _downloader?.cancel();
  }

  Future<void> activate(CurriculumPack pack) async {
    if (!_installedFiles.contains(pack.fileName)) return;
    _settings.activeCurriculumPackId = pack.id;
    notifyListeners();
    await _openActiveIndex();
  }

  Future<void> delete(CurriculumPack pack) async {
    if (pack.id == activePackId) {
      _settings.activeCurriculumPackId = null;
    }
    if (_indexPackId == pack.id) {
      await _closeIndex();
    }
    for (final path in [_packPath(pack), '${_packPath(pack)}${ModelDownloader.partialSuffix}']) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _installedFiles.remove(pack.fileName);
    notifyListeners();
  }

  // --- TextbookRetriever --------------------------------------------------------------------

  @override
  Future<List<TextbookExcerpt>> search(String query, {int limit = 2}) async {
    try {
      // The first question after launch may arrive while the index is still opening.
      await _indexOpening;
      final index = _index;
      if (index == null || _indexPackId != activePackId) return const [];
      return await index.search(query, limit: limit);
    } catch (error, stackTrace) {
      // Still never thrown at the agent — but no longer invisible either. A failure here
      // once made every search come back empty on Android with nothing in any log.
      AppLog.ui('curriculum.searchFailed');
      debugPrint('curriculum search failed: $error\n$stackTrace');
      return const [];
    }
  }

  // --- internals ----------------------------------------------------------------------------

  String get _manifestCachePath => p.join(_directory.path, 'manifest.json');

  String _packPath(CurriculumPack pack) => p.join(_directory.path, pack.fileName);

  Future<void> _loadCachedManifest() async {
    final file = File(_manifestCachePath);
    if (!await file.exists()) return;
    try {
      _manifest = CurriculumManifest.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, Object?>);
    } catch (_) {
      // A corrupt cache is replaced by the next successful refresh.
    }
  }

  Future<void> _scanInstalled() async {
    _installedFiles.clear();
    await for (final entity in _directory.list()) {
      final name = p.basename(entity.path);
      if (entity is File && name.endsWith('.db')) {
        _installedFiles.add(name);
      }
    }
  }

  /// The active pack's file name, from the manifest or — offline, before any manifest was
  /// cached — from the id, which the pipeline always names `<id>.db`.
  String? get _activeFileName {
    final id = activePackId;
    if (id == null) return null;
    return _manifest?.byId(id)?.fileName ?? '$id.db';
  }

  Future<void> _openActiveIndex() {
    final opening = _doOpenActiveIndex();
    _indexOpening = opening;
    return opening.whenComplete(() {
      if (identical(_indexOpening, opening)) _indexOpening = null;
    });
  }

  Future<void> _doOpenActiveIndex() async {
    final id = activePackId;
    final fileName = _activeFileName;
    if (id == _indexPackId && _index != null) return;
    await _closeIndex();
    if (id == null || fileName == null || !_installedFiles.contains(fileName)) return;

    final pack = _manifest?.byId(id);
    Future<void> openIt() async {
      _index = await CurriculumIndex.open(p.join(_directory.path, fileName), factory: _databaseFactory);
      _indexPackId = id;
    }

    try {
      if (pack != null) {
        await _withPreparing(pack, openIt);
      } else {
        await openIt();
      }
    } catch (error) {
      _errorMessage = describeError(error);
      notifyListeners();
    }
  }

  Future<void> _withPreparing(CurriculumPack pack, Future<void> Function() work) async {
    _preparingPackId = pack.id;
    notifyListeners();
    try {
      await work();
    } finally {
      _preparingPackId = null;
      notifyListeners();
    }
  }

  Future<void> _closeIndex() async {
    final index = _index;
    _index = null;
    _indexPackId = null;
    await index?.close();
  }

  @override
  void dispose() {
    unawaited(_downloader?.cancel());
    unawaited(_closeIndex());
    super.dispose();
  }
}
