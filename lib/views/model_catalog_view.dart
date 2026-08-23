import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model_management/model_catalog.dart';
import '../model_management/model_store.dart';
import '../utilities/file_size_formatter.dart';
import '../utilities/memory_reporter.dart';
import '../viewmodels/app_view_model.dart';
import '../viewmodels/model_download_view_model.dart';
import 'error_banner.dart';
import 'theme.dart';

/// The download catalog: every chat model in [ModelCatalog], with one transfer at a time.
///
/// **Why this screen exists at all.** Importing a `.gguf` by hand is gone, so downloading is
/// now the only way a model reaches the device. That makes this list the single funnel for
/// getting the app into a usable state, which is why it is a reusable widget rather than a
/// screen: the first-run setup view embeds it under its own title, and the model manager can
/// embed the same rows inside its settings sheet.
///
/// **Composition contract.** No [Scaffold] and no [AppBar] — the host supplies those. It
/// does scroll, though: the body is a [ListView], so a host only has to give it a bounded
/// height (a `Scaffold` body does) and never has to remember a scroll view of its own. That
/// matters because the list grows with the catalog, and at a large text scale three entries
/// plus a header already overflow a small phone.
///
/// One [ModelDownloadViewModel] is owned here for the whole list — not one per row. The view
/// model refuses a second concurrent transfer, and a single instance is what lets the list
/// tell which row that transfer belongs to (through `activeModel`) and grey the other rows'
/// buttons out.
class ModelCatalogView extends StatefulWidget {
  const ModelCatalogView({
    super.key,
    required this.installedFileNames,
    required this.onModelDownloaded,
    this.header,
  });

  /// File names already present in the model store. Those rows read "Installed"
  /// instead of offering a download.
  final Set<String> installedFileNames;

  /// Called with the finished file's NAME (not path) once a download completes.
  final Future<void> Function(String fileName) onModelDownloaded;

  /// Optional content rendered above the list — the first-run screen puts its
  /// title and explanation here.
  final Widget? header;

  @override
  State<ModelCatalogView> createState() => _ModelCatalogViewState();
}

class _ModelCatalogViewState extends State<ModelCatalogView> {
  /// Captured once rather than read per use: the completion callback can fire while this
  /// widget is on its way out, and `context.read` on a deactivated element throws.
  late final ModelStore _modelStore;

  late ModelDownloadViewModel _downloadViewModel;

  /// Total physical RAM, or `null` where the platform cannot report it without native code
  /// (iOS and macOS — see [MemoryReporter]). Read once here because
  /// `totalPhysicalMemoryBytes` is a synchronous `/proc/meminfo` parse, so there is nothing
  /// to await and nothing to rebuild for.
  int? _totalMemoryBytes;

  @override
  void initState() {
    super.initState();
    _modelStore = context.read<AppViewModel>().modelStore;
    _downloadViewModel = ModelDownloadViewModel(modelStore: _modelStore);
    _totalMemoryBytes = MemoryReporter.totalPhysicalMemoryBytes();
  }

  @override
  void dispose() {
    _downloadViewModel.dispose();
    super.dispose();
  }

  void _startDownload(CatalogModel model) {
    // `onComplete` is handed a path; every caller upstream of here works in file names.
    _downloadViewModel.startDownload(
      model: model,
      onComplete: (filePath) => widget.onModelDownloaded(
        ModelDownloadViewModel.fileNameFromPath(filePath),
      ),
    );
  }

  /// Dismissing a failure replaces the view model rather than mutating it.
  ///
  /// This is the pattern the setup screen already used, and it is the only way to clear
  /// `DownloadFailed`: the view model exposes no reset, and reusing a failed instance would
  /// leave the next press starting from a state the user thinks they dismissed. Disposing
  /// the old one after the `setState` is safe — `ChangeNotifier.removeListener` is
  /// explicitly callable on a disposed instance, which is what the rebuilt
  /// `ListenableBuilder` does to it.
  void _dismissFailure() {
    final previous = _downloadViewModel;
    setState(() {
      _downloadViewModel = ModelDownloadViewModel(modelStore: _modelStore);
    });
    previous.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _downloadViewModel,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final viewModel = _downloadViewModel;
    final state = viewModel.state;
    final activeModel = viewModel.activeModel;
    final header = widget.header;
    final failure = state is DownloadFailed ? state : null;
    final downloading = state is Downloading ? state : null;

    return ListView(
      // Bottom inset only: the header owns the top spacing, and hosts that add an app bar
      // get theirs from the bar.
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        if (header != null) header,
        if (failure != null) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorBanner(
              message: failure.message,
              onDismiss: _dismissFailure,
            ),
          ),
        ],
        const _SectionHeader('Available Models'),
        for (final model in ModelCatalog.chatModels)
          Padding(
            // The key goes here, on the widget the list actually sees. On `_CatalogRow` it
            // would identify a grandchild and do nothing for element reuse.
            key: ValueKey<String>(model.id),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _CatalogRow(
              model: model,
              isInstalled: widget.installedFileNames.contains(model.fileName),
              // Progress belongs to exactly one row: the one the view model is working on.
              downloadState:
                  activeModel?.id == model.id ? downloading : null,
              // One transfer at a time. The view model already drops a second
              // `startDownload`; the button says so instead of silently doing nothing.
              isDownloadDisabled:
                  viewModel.isDownloading && activeModel?.id != model.id,
              fitsInMemory: model.fitsInMemory(_totalMemoryBytes),
              onDownload: () => _startDownload(model),
              onCancel: viewModel.cancelDownload,
            ),
          ),
        const _CatalogFooter(
          'Models are fetched from Hugging Face, so the download itself needs a connection. '
          'Once a model is on the device, chatting works fully offline.',
        ),
      ],
    );
  }
}

/// One catalog entry: the metadata on the left, its current state on the right.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.model,
    required this.isInstalled,
    required this.downloadState,
    required this.isDownloadDisabled,
    required this.fitsInMemory,
    required this.onDownload,
    required this.onCancel,
  });

  final CatalogModel model;
  final bool isInstalled;

  /// Non-null only while *this* row's transfer is running.
  final Downloading? downloadState;

  /// Some other row is downloading, so this row's button is greyed out.
  final bool isDownloadDisabled;

  /// False only when the device's RAM was actually readable and falls short. An unknown
  /// memory figure reads as "fits" — see [CatalogModel.fitsInMemory].
  final bool fitsInMemory;

  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final downloading = downloadState;

    // A `Material` rather than a decorated `Container`: the trailing controls are buttons,
    // and ink paints into the nearest `Material` ancestor — a bare fill drawn over the
    // scaffold's own Material would swallow every ripple under this card's colour.
    return Material(
      color: AppColors.thickMaterial(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Details(model: model, fitsInMemory: fitsInMemory)),
                // While this row is downloading, the whole width below is the progress
                // block, so the trailing slot stands empty rather than showing a dead
                // button beside its own progress bar.
                if (downloading == null) ...[
                  const SizedBox(width: 12),
                  if (isInstalled)
                    const _InstalledLabel()
                  else
                    // Capsule shape and the 48pt minimum height come from
                    // `filledButtonTheme` — no local override.
                    FilledButton(
                      onPressed: isDownloadDisabled ? null : onDownload,
                      child: const Text('Download'),
                    ),
                ],
              ],
            ),
            if (downloading != null) ...[
              const SizedBox(height: 12),
              _DownloadProgress(state: downloading, onCancel: onCancel),
            ],
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.model, required this.fitsInMemory});

  final CatalogModel model;
  final bool fitsInMemory;

  @override
  Widget build(BuildContext context) {
    final contextLength = model.contextLength;
    final metadata = <String>[
      FileSizeFormatter.string(bytes: model.downloadSizeBytes),
      if (contextLength != null) _contextLengthLabel(contextLength),
      model.license,
    ].join(' · ');

    final mutedCaption = AppText.caption2(context).copyWith(
      color: AppColors.tertiaryLabel(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                model.displayName,
                style: AppText.headline(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Choosing is now mandatory — there is no bundled fallback and no import — so
            // the list has to say which one to pick. `ModelTier` already records it, which
            // is why this reads the tier rather than a second "recommended" constant.
            if (model.tier == ModelTier.bundledDefault) ...[
              const SizedBox(width: 8),
              const _RecommendedBadge(),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          metadata,
          style: AppText.caption(context).copyWith(
            color: AppColors.secondaryLabel(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(model.note, style: mutedCaption),
        // Deliberately a caption and not a filter: a model that will not fit is still
        // offered, because the RAM figure is a floor from the model card rather than a
        // measurement of what this device can actually load.
        if (!fitsInMemory) ...[
          const SizedBox(height: 4),
          Text(
            'Needs ${_memoryRequirementLabel(model.minimumDeviceMemoryBytes)} RAM',
            style: mutedCaption,
          ),
        ],
      ],
    );
  }
}

/// A small capsule marking the entry a first-time user should take.
class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: ShapeDecoration(
        // The page colour, not an accent: inside a `thickMaterial` card this reads as a
        // punched-out chip and keeps the row monochrome.
        color: AppColors.page(context),
        shape: const StadiumBorder(),
      ),
      child: Text(
        'Recommended',
        style: AppText.caption2(context).copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}

class _InstalledLabel extends StatelessWidget {
  const _InstalledLabel();

  @override
  Widget build(BuildContext context) {
    final color = AppColors.secondaryLabel(context);

    // Not a disabled button: there is no action here, and a greyed-out control invites a
    // press that can never do anything.
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(AppIcons.checkmarkCircleFill, size: 18, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              'Installed',
              style: AppText.footnote(context).copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.state, required this.onCancel});

  final Downloading state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final label = state.isDeterminate
        ? '${FileSizeFormatter.string(bytes: state.bytesWritten)} of '
            '${FileSizeFormatter.string(bytes: state.totalBytes)}'
        : FileSizeFormatter.string(bytes: state.bytesWritten);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A server that sent no length gets a spinner rather than a bar frozen at zero or a
        // bar that lies about how far along it is. Colours come from
        // `progressIndicatorTheme`; the clip is what rounds the bar's ends, since
        // `LinearProgressIndicator` draws square ones.
        if (state.isDeterminate)
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: LinearProgressIndicator(value: state.fraction, minHeight: 6),
          )
        else
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.caption(context).copyWith(
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                textStyle: AppText.footnote(context),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The same uppercase caption the settings sheet uses for its groups. Duplicated rather than
/// shared because that one is private to `model_manager_view.dart`, and a two-line widget is
/// a smaller cost than a third file to hold it.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
      child: Text(
        title.toUpperCase(),
        style: AppText.caption2(context).copyWith(
          color: AppColors.tertiaryLabel(context),
          letterSpacing: 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CatalogFooter extends StatelessWidget {
  const _CatalogFooter(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Indented to sit under the cards' own inset rather than at the screen edge.
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
      child: Text(
        text,
        style: AppText.caption(context).copyWith(
          color: AppColors.tertiaryLabel(context),
        ),
      ),
    );
  }
}

/// `262144` → `"262K context"`.
///
/// Thousands, not kibi-anything: context lengths are quoted in round decimal thousands on
/// every model card, and "256K" for 262144 would be a different number than the one the
/// catalog records.
String _contextLengthLabel(int tokens) {
  if (tokens < 1000) {
    return '$tokens context';
  }
  final thousands = tokens / 1000;
  final rendered = thousands >= 100 || thousands == thousands.roundToDouble()
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1);
  return '${rendered}K context';
}

/// `8589934592` → `"8 GB"`.
///
/// Not [FileSizeFormatter]: that renders base-1000 file sizes, and the catalog's memory
/// floors are whole gibibytes, so 8 GiB would come back as "8.59 GB" — a number no device
/// spec sheet prints.
String _memoryRequirementLabel(int bytes) {
  const int gibibyte = 1024 * 1024 * 1024;
  final gigabytes = bytes / gibibyte;
  final rendered = gigabytes >= 10 || gigabytes == gigabytes.roundToDouble()
      ? gigabytes.round().toString()
      : gigabytes.toStringAsFixed(1);
  return '$rendered GB';
}
