import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model_management/model_importer.dart';
import '../utilities/file_size_formatter.dart';
import '../viewmodels/app_view_model.dart';
import '../viewmodels/error_text.dart';
import '../viewmodels/model_download_view_model.dart';
import 'error_banner.dart';
import 'theme.dart';

/// First run, and every later run where no model is installed.
///
/// Owns a lazily-created [ModelDownloadViewModel]: it does not exist until the user presses
/// the download button, and it is thrown away when they dismiss a download error, which is
/// what makes the next press start from a clean state.
class ModelSetupView extends StatefulWidget {
  const ModelSetupView({super.key, required this.onImport});

  /// Receives the picked file's path. A path rather than a `URL`: `file_picker` returns
  /// paths, and `ModelImporter` takes one.
  final void Function(String pickedPath) onImport;

  @override
  State<ModelSetupView> createState() => _ModelSetupViewState();
}

class _ModelSetupViewState extends State<ModelSetupView> {
  ModelDownloadViewModel? _downloadViewModel;
  String? _importError;

  @override
  void dispose() {
    _downloadViewModel?.dispose();
    super.dispose();
  }

  Future<void> _pickModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ModelImporter.allowedExtensions,
      );
      final path = result?.files.single.path;
      if (path == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() => _importError = null);
      widget.onImport(path);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _importError = describeError(error));
    }
  }

  void _startDownload() {
    final appViewModel = context.read<AppViewModel>();
    // The field can already hold a view model — after a cancel, and in the window between
    // a finished download and `useDownloadedModel` returning. Overwriting it without
    // disposing strands a ChangeNotifier that still owns a live download subscription.
    final previous = _downloadViewModel;
    final viewModel = ModelDownloadViewModel(modelStore: appViewModel.modelStore);
    setState(() => _downloadViewModel = viewModel);
    previous?.dispose();
    viewModel.startDownload(
      onComplete: (filePath) => appViewModel.useDownloadedModel(
        ModelDownloadViewModel.fileNameFromPath(filePath),
      ),
    );
  }

  void _dismissDownloadError() {
    final viewModel = _downloadViewModel;
    setState(() => _downloadViewModel = null);
    viewModel?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadViewModel = _downloadViewModel;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: downloadViewModel == null
                    ? _buildBody(context, null)
                    : ListenableBuilder(
                        listenable: downloadViewModel,
                        builder: (context, _) => _buildBody(context, downloadViewModel),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ModelDownloadViewModel? downloadViewModel) {
    final downloadState = downloadViewModel?.state;
    final importError = _importError;

    return Column(
      children: [
        const Spacer(),
        ExcludeSemantics(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.thickMaterial(context),
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            child: Icon(
              AppIcons.shippingBox,
              size: 32,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('No Model Installed', style: AppText.title2(context)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Get a GGUF language model to start chatting offline. The recommended starter '
            'model is Qwen3-0.6B.',
            textAlign: TextAlign.center,
            style: AppText.subheadline(context).copyWith(
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        if (importError != null) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ErrorBanner(
              message: importError,
              onDismiss: () => setState(() => _importError = null),
            ),
          ),
        ],
        if (downloadState is DownloadFailed) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ErrorBanner(
              message: downloadState.message,
              onDismiss: _dismissDownloadError,
            ),
          ),
        ],
        const SizedBox(height: 32),
        // Both buttons take their capsule shape and 48pt minimum height straight from
        // `filledButtonTheme` / `outlinedButtonTheme` — no local shape or height override.
        if (downloadState is Downloading)
          _DownloadProgress(
            state: downloadState,
            onCancel: downloadViewModel!.cancelDownload,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startDownload,
                icon: const Icon(AppIcons.arrowDownCircle, size: 20),
                label: Text(
                  'Download Recommended Model '
                  '(${FileSizeFormatter.string(bytes: ModelDownloadViewModel.recommendedModelSizeBytes)})',
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: downloadViewModel?.isDownloading == true ? null : _pickModel,
              icon: const Icon(AppIcons.squareAndArrowDown, size: 20),
              label: const Text('Import GGUF Model'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Downloading requires an internet connection once. After that, chatting works '
            'fully offline.',
            textAlign: TextAlign.center,
            style: AppText.caption(context).copyWith(
              color: AppColors.tertiaryLabel(context),
            ),
          ),
        ),
        const Spacer(),
        const Spacer(),
      ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // A server that sent no length gets an indeterminate bar rather than a bar frozen
          // at zero. Colours come from `progressIndicatorTheme`; the clip is what rounds the
          // ends, since `LinearProgressIndicator` draws square ones.
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: LinearProgressIndicator(value: state.fraction, minHeight: 6),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: AppText.caption(context).copyWith(
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              textStyle: AppText.footnote(context),
            ),
            child: const Text('Cancel Download'),
          ),
        ],
      ),
    );
  }
}
