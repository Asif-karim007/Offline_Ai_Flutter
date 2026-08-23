import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model_management/model_bootstrap_service.dart';
import '../viewmodels/app_view_model.dart';
import 'main_split_view.dart';
import 'model_setup_view.dart';
import 'splash_view.dart';

/// The router. Switches on `AppViewModel.loadingState` and nothing else.
///
/// `ready` gets the shell, `needsModel` gets the setup screen, and every other state — the
/// four loading phases and `failed` — gets the splash.
class RootView extends StatefulWidget {
  const RootView({super.key});

  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> {
  bool _bootstrapStarted = false;

  @override
  void initState() {
    super.initState();
    // The Swift `.task { await appViewModel.bootstrap() }` on `RootView` — once, when the
    // root appears. The guard is what makes it once rather than once per rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bootstrapStarted) {
        return;
      }
      _bootstrapStarted = true;
      unawaited(context.read<AppViewModel>().bootstrap());
    });
  }

  @override
  Widget build(BuildContext context) {
    final appViewModel = context.watch<AppViewModel>();
    final state = appViewModel.loadingState;

    if (state.isReady) {
      return const MainSplitView();
    }
    if (state == AppLoadingState.needsModel) {
      // No callback: the setup screen reaches `AppViewModel` through the provider itself,
      // now that downloading is the only route in and the import callback is gone.
      return const ModelSetupView();
    }
    return SplashView(
      state: state,
      onRetry: () => unawaited(appViewModel.retry()),
      onChooseAnotherModel: appViewModel.chooseAnotherModel,
      onDeleteInvalidModel: () => unawaited(appViewModel.deleteInvalidModelAndRetry()),
    );
  }
}
