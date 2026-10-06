import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../viewmodels/app_view_model.dart';
import '../viewmodels/error_text.dart';
import 'error_banner.dart';
import 'model_catalog_view.dart';
import 'theme.dart';

/// First run, and every later run where no model is installed.
///
/// **The import half is gone.** This screen used to offer two routes — a file picker feeding
/// an importer, and one hardcoded "download the recommended model" button. Hand-importing a
/// `.gguf` has been removed outright, so downloading is now the only way a model reaches the
/// device, and the one-model button would have capped the app at exactly one choice. Both are replaced by an
/// embedded [ModelCatalogView], which is the same list the settings sheet can show.
///
/// What is left here is the framing: a [Scaffold], a title and one line of explanation
/// passed down as the catalog's `header`, and the error banner for the load that follows a
/// finished download. **Do not wrap the catalog in a scroll view** — its body is a
/// `ListView` and it scrolls itself; giving it unbounded height throws at runtime.
/// Download failures are the catalog's own business and it shows them itself.
class ModelSetupView extends StatefulWidget {
  const ModelSetupView({super.key});

  @override
  State<ModelSetupView> createState() => _ModelSetupViewState();
}

class _ModelSetupViewState extends State<ModelSetupView> {
  /// Captured once. `onModelDownloaded` fires from the download stream, and the load it
  /// starts moves `AppViewModel` off `needsModel`, which unmounts this screen — reading the
  /// provider out of a deactivated element at that point would throw.
  late final AppViewModel _appViewModel;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _appViewModel = context.read<AppViewModel>();
  }

  /// The file is already at its final path in the model store; this only loads it.
  ///
  /// `useDownloadedModel` reports its own failures through `AppLoadingState.failed`, so the
  /// banner here is for anything that escapes it — the guard exists so a throw cannot leave
  /// the user on a screen that silently did nothing after a multi-gigabyte download.
  Future<void> _handleDownloaded(String fileName) async {
    try {
      await _appViewModel.useDownloadedModel(fileName);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    // No `backgroundColor` here: `scaffoldBackgroundColor` is already `AppColors.page`.
    return Scaffold(
      body: SafeArea(
        // No scroll view of its own: `ModelCatalogView` is a `ListView`, and all it needs
        // from a host is the bounded height a `Scaffold` body already gives it.
        child: ModelCatalogView(
          // Nothing can be installed: this screen only exists because discovery found no
          // model at all.
          installedFileNames: const <String>{},
          onModelDownloaded: _handleDownloaded,
          header: _SetupHeader(
            errorMessage: _errorMessage,
            onDismissError: () => setState(() => _errorMessage = null),
          ),
        ),
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({required this.errorMessage, required this.onDismissError});

  final String? errorMessage;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Padding(
          // 28, not 16: prose sits under the cards' own inner inset rather than at the
          // screen edge, which is the same measure the settings sheet's headers use.
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // `Align` rather than a bare `Container`: the surrounding column stretches its
              // children, which would override the badge's own 56pt width.
              Align(
                alignment: Alignment.centerLeft,
                child: ExcludeSemantics(
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.thickMaterial(context),
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Icon(
                      AppIcons.shippingBox,
                      size: 26,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(AppStrings.of(context).chooseAModel, style: AppText.title(context)),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(context).modelSetupBody,
                style: AppText.subheadline(context).copyWith(
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorBanner(message: message, onDismiss: onDismissError),
          ),
        ],
      ],
    );
  }
}
