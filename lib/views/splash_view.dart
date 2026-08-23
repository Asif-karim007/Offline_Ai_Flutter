import 'package:flutter/material.dart';

import '../model_management/model_bootstrap_service.dart';
import 'error_banner.dart';
import 'theme.dart';

/// The launch screen, and the screen a failed launch stays on.
///
/// Two branches: an indeterminate spinner with the state's own status text, or — when the
/// state is `failed` — the message plus the three recovery actions.
class SplashView extends StatelessWidget {
  const SplashView({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onChooseAnotherModel,
    required this.onDeleteInvalidModel,
  });

  final AppLoadingState state;
  final VoidCallback onRetry;
  final VoidCallback onChooseAnotherModel;
  final VoidCallback onDeleteInvalidModel;

  @override
  Widget build(BuildContext context) {
    final failure = state;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              // `IntrinsicHeight` is what lets the flexible spacers below survive being
              // inside a scroll view: the column gets a definite height to divide up, and
              // the scroll view only engages when the content genuinely does not fit.
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // One spacer above, two below — content sits at roughly a third of the
                    // screen rather than dead centre, as in the original.
                    const Spacer(),
                    const ExcludeSemantics(child: _AppMark()),
                    const SizedBox(height: 20),
                    Text('Offline AI Chat', style: AppText.title2(context)),
                    const SizedBox(height: 28),
                    if (failure is FailedLoading)
                      _FailureBranch(
                        message: failure.message,
                        onRetry: onRetry,
                        onChooseAnotherModel: onChooseAnotherModel,
                        onDeleteInvalidModel: onDeleteInvalidModel,
                      )
                    else
                      _LoadingBranch(statusText: state.statusText),
                    const Spacer(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's mark: the glyph on a quiet raised tile rather than a large tinted icon.
///
/// A rounded square in [AppColors.thickMaterial] is the shape the rest of the restyle uses
/// for raised surfaces, so the launch screen reads as the same app before anything else has
/// been drawn.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.thickMaterial(context),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Icon(
        AppIcons.brainHeadProfile,
        size: 34,
        color: AppColors.primaryLabel(context),
      ),
    );
  }
}

class _LoadingBranch extends StatelessWidget {
  const _LoadingBranch({required this.statusText});

  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // No colour of its own: `progressIndicatorTheme` already paints this in
        // `onSurfaceVariant`, which is exactly `AppColors.secondaryLabel`.
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 16),
        Semantics(
          label: 'Status: $statusText',
          excludeSemantics: true,
          child: Text(
            statusText,
            style: AppText.subheadline(context).copyWith(
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _FailureBranch extends StatelessWidget {
  const _FailureBranch({
    required this.message,
    required this.onRetry,
    required this.onChooseAnotherModel,
    required this.onDeleteInvalidModel,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChooseAnotherModel;
  final VoidCallback onDeleteInvalidModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          ErrorBanner(message: message),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              children: [
                // Shapes come from `filledButtonTheme` / `outlinedButtonTheme`: capsules,
                // 48pt minimum. Nothing here overrides them.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onChooseAnotherModel,
                    child: const Text('Choose Another Model'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onDeleteInvalidModel,
                    style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                    child: const Text('Delete Invalid Model'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
