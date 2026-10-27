import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../model_management/model_catalog.dart';
import '../utilities/file_size_formatter.dart';
import '../utilities/memory_reporter.dart';
import '../viewmodels/app_view_model.dart';
import '../viewmodels/error_text.dart';
import '../viewmodels/model_download_view_model.dart';
import 'error_banner.dart';
import 'theme.dart';

/// First run, and every later run where no model is installed.
///
/// **A welcome, not a picker.** This screen no longer lists models. It greets the user,
/// chooses the recommended model for this device on their behalf, and starts the download
/// immediately, showing calm progress. A partial download is resumed automatically (the
/// downloader keeps a `.part` file), so closing the app mid-way costs nothing.
///
/// The model list still exists in Settings for anyone who wants a different one.
class ModelSetupView extends StatefulWidget {
  const ModelSetupView({super.key});

  @override
  State<ModelSetupView> createState() => _ModelSetupViewState();
}

class _ModelSetupViewState extends State<ModelSetupView> with TickerProviderStateMixin {
  /// Captured once: the completion callback fires from the download stream and the load it
  /// starts unmounts this screen, after which `context.read` would throw.
  late final AppViewModel _appViewModel;
  late final ModelDownloadViewModel _download;
  late final CatalogModel _model;

  late final AnimationController _breath;
  late final AnimationController _entrance;

  Timer? _rotator;
  int _lineIndex = 0;

  bool _paused = false;
  bool _finishing = false;
  double _lastFraction = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _appViewModel = context.read<AppViewModel>();
    _download = ModelDownloadViewModel(modelStore: _appViewModel.modelStore);
    _model = _chooseModel();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _rotator = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted) {
        setState(() => _lineIndex++);
      }
    });

    // Start once the first frame is up, so the welcome is visible before any work begins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _start();
      }
    });
  }

  /// The first chat model, in catalog order, that this device has the RAM for. When the
  /// platform cannot report memory every model "fits", which yields the catalog's lead
  /// recommendation.
  CatalogModel _chooseModel() {
    final memory = MemoryReporter.totalPhysicalMemoryBytes();
    for (final model in ModelCatalog.chatModels) {
      if (model.fitsInMemory(memory)) {
        return model;
      }
    }
    return ModelCatalog.bundledDefault;
  }

  void _start() {
    setState(() {
      _paused = false;
      _loadError = null;
    });
    _download.startDownload(
      model: _model,
      onComplete: (filePath) => _handleDownloaded(
        ModelDownloadViewModel.fileNameFromPath(filePath),
      ),
    );
  }

  void _pause() {
    setState(() => _paused = true);
    _download.cancelDownload();
  }

  /// The file is at its final path; this only loads it. `useDownloadedModel` reports its own
  /// failures through the loading state, so the banner is for anything that escapes it.
  Future<void> _handleDownloaded(String fileName) async {
    if (mounted) {
      setState(() => _finishing = true);
    }
    try {
      await _appViewModel.useDownloadedModel(fileName);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _finishing = false;
        _loadError = describeError(error);
      });
    }
  }

  @override
  void dispose() {
    _rotator?.cancel();
    _breath.dispose();
    _entrance.dispose();
    _download.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);

    return Scaffold(
      body: Stack(
        children: [
          // A very soft glow behind the content; decoration only.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.45),
                    radius: 0.95,
                    colors: [
                      AppColors.accent(context).withAlpha(30),
                      AppColors.page(context).withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: FadeTransition(
                    opacity: fade,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(fade),
                      child: ListenableBuilder(
                        listenable: _download,
                        builder: (context, _) => _buildBody(context, strings, reduceMotion),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppStrings strings, bool reduceMotion) {
    final state = _download.state;
    final failure = state is DownloadFailed ? state : null;
    final downloading = state is Downloading ? state : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, child) => Transform.scale(
              scale: reduceMotion ? 1 : 1 + 0.045 * Curves.easeInOut.transform(_breath.value),
              child: child,
            ),
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.thickMaterial(context),
                borderRadius: const BorderRadius.all(Radius.circular(28)),
              ),
              child: Icon(
                AppIcons.brainHeadProfile,
                size: 42,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          strings.welcomeTitle,
          textAlign: TextAlign.center,
          style: AppText.title(context),
        ),
        const SizedBox(height: 10),
        Text(
          strings.welcomeBody,
          textAlign: TextAlign.center,
          style: AppText.subheadline(context).copyWith(
            color: AppColors.secondaryLabel(context),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 36),
        if (failure != null)
          _buildFailure(context, strings, failure.message)
        else
          _buildProgress(context, strings, downloading),
        if (_loadError != null) ...[
          const SizedBox(height: 20),
          ErrorBanner(
            message: _loadError!,
            onDismiss: () => setState(() => _loadError = null),
          ),
        ],
      ],
    );
  }

  Widget _buildProgress(BuildContext context, AppStrings strings, Downloading? state) {
    final secondary = AppColors.secondaryLabel(context);
    final muted = AppText.caption(context).copyWith(color: AppColors.tertiaryLabel(context));

    final String headline;
    final String? detail;
    final double? fraction;

    if (_finishing) {
      headline = strings.welcomeAlmostThere;
      detail = null;
      fraction = 1;
    } else if (_paused) {
      headline = strings.welcomePaused;
      detail = null;
      fraction = _lastFraction;
    } else if (state == null) {
      headline = strings.welcomePreparing;
      detail = null;
      fraction = null;
    } else {
      final done = state.bytesWritten;
      final total = state.totalBytes > 0 ? state.totalBytes : _model.downloadSizeBytes;
      final f = (done / total).clamp(0.0, 1.0);
      _lastFraction = f;
      headline = strings.welcomePreparing;
      detail = strings.welcomeProgress(
        FileSizeFormatter.string(bytes: done),
        FileSizeFormatter.string(bytes: total),
        (f * 100).floor(),
      );
      fraction = f;
    }

    final lines = strings.welcomeReassurances;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: AppText.headline(context),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: fraction ?? 0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              // Indeterminate (soft sweep) until there is a real number to show.
              value: fraction == null && !_paused ? null : value,
              minHeight: 6,
              backgroundColor: AppColors.thickMaterial(context),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 18,
          child: detail == null
              ? null
              : Text(detail, textAlign: TextAlign.center, style: muted),
        ),
        const SizedBox(height: 24),
        if (!_paused && !_finishing)
          SizedBox(
            height: 44,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              child: Text(
                lines[_lineIndex % lines.length],
                key: ValueKey<int>(_lineIndex % lines.length),
                textAlign: TextAlign.center,
                style: AppText.subheadline(context).copyWith(color: secondary),
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (_paused)
          Center(
            child: FilledButton(
              onPressed: _start,
              child: Text(strings.welcomeResume),
            ),
          )
        else if (!_finishing)
          Center(
            child: TextButton(
              onPressed: state == null ? null : _pause,
              child: Text(strings.welcomePause),
            ),
          ),
        const SizedBox(height: 20),
        Text(strings.welcomeWifiNote, textAlign: TextAlign.center, style: muted),
      ],
    );
  }

  Widget _buildFailure(BuildContext context, AppStrings strings, String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.welcomeFailedTitle,
          textAlign: TextAlign.center,
          style: AppText.headline(context),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.caption(context).copyWith(color: AppColors.secondaryLabel(context)),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton(
            onPressed: _start,
            child: Text(strings.retry),
          ),
        ),
      ],
    );
  }
}
