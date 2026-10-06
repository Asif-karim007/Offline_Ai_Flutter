import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_request.dart';
import '../curriculum/curriculum_service.dart';
import '../domain/local_model_info.dart';
import '../l10n/app_strings.dart';
import '../model_management/app_settings.dart';
import '../utilities/file_size_formatter.dart';
import '../viewmodels/model_manager_view_model.dart';
import 'curriculum_packs_view.dart';
import 'model_catalog_view.dart';
import 'theme.dart';

/// Settings and the installed-model list, presented as a sheet.
///
/// [onWillSwitchModel] runs — and is awaited — before every path that loads, reloads,
/// downloads or switches a model. It is `ChatViewModel.startNewPersistentChat()`, and it is
/// what satisfies `ModelManagerViewModel.switchToModel`'s caller contract that generation has
/// already been stopped.
class ModelManagerView extends StatefulWidget {
  const ModelManagerView({super.key, required this.onWillSwitchModel});

  final Future<void> Function() onWillSwitchModel;

  @override
  State<ModelManagerView> createState() => _ModelManagerViewState();
}

class _ModelManagerViewState extends State<ModelManagerView> {
  final TextEditingController _braveApiKeyController = TextEditingController();
  String? _shownErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(context.read<ModelManagerViewModel>().refresh());
    });
  }

  @override
  void dispose() {
    _braveApiKeyController.dispose();
    super.dispose();
  }

  /// The Swift "Error" alert, whose only button clears `errorMessage`.
  void _surfaceError(ModelManagerViewModel viewModel) {
    final message = viewModel.errorMessage;
    if (message == null || message == _shownErrorMessage) {
      return;
    }
    _shownErrorMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppStrings.of(context).error),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppStrings.of(context).ok),
            ),
          ],
        ),
      );
      viewModel.errorMessage = null;
      _shownErrorMessage = null;
    });
  }

  /// Pushes the built-in catalog as a full page over this sheet.
  ///
  /// Downloading is now the only way a model reaches the device — hand-importing a `.gguf`
  /// is gone — so this is the screen's sole "add a model" affordance.
  ///
  /// [viewModel] is captured from the closure rather than read out of the pushed route's
  /// context on purpose: `MainSplitView` provides `ModelManagerViewModel` *inside* the sheet,
  /// which is below the navigator this route goes onto, so a `read` in there would throw.
  ///
  /// Nothing is refreshed when the route pops. `useDownloadedModel` already calls `refresh()`
  /// and notifies, and `build` watches the view model, so the installed list is current the
  /// moment a download finishes — before the user pops, not after.
  Future<void> _openModelCatalog(ModelManagerViewModel viewModel) async {
    final installedFileNames = <String>{
      for (final model in viewModel.installedModels) model.fileName,
    };
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        // `ModelCatalogView` deliberately carries no chrome of its own, so the route supplies
        // the scaffold and the bar it needs.
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(AppStrings.of(context).downloadAModel)),
          body: ModelCatalogView(
            installedFileNames: installedFileNames,
            onModelDownloaded: (fileName) async {
              // `useDownloadedModel` switches to the model it just adopted, so it inherits
              // `switchToModel`'s caller contract — the same one `_confirmSwitch` and
              // `_reload` satisfy by awaiting this first.
              await widget.onWillSwitchModel();
              await viewModel.useDownloadedModel(fileName);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSwitch(
    ModelManagerViewModel viewModel,
    String fileName,
  ) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.switchModelTitle),
        content: Text(strings.switchModelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.switchAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.onWillSwitchModel();
    await viewModel.switchToModel(fileName);
  }

  Future<void> _confirmDelete(
    ModelManagerViewModel viewModel,
    String fileName,
  ) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteModelTitle),
        content: Text(strings.deleteModelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.deleteModel(fileName);
    }
  }

  Future<void> _reload(ModelManagerViewModel viewModel) async {
    await widget.onWillSwitchModel();
    await viewModel.reloadCurrentModel();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ModelManagerViewModel>();
    final settings = context.watch<AppSettings>();
    final strings = AppStrings.of(context);
    _surfaceError(viewModel);

    // No `backgroundColor` here: `scaffoldBackgroundColor` is already `AppColors.page`.
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settingsAndModels),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.done),
        ),
        leadingWidth: 88,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // First, so a user who opened the app in the wrong language finds the way out
          // without having to read past anything else.
          ..._languageSection(context, settings),
          ..._textbooksSection(context),
          ..._activeModelSection(context, viewModel),
          ..._installedModelsSection(context, viewModel),
          ..._generationSettingsSection(context, settings),
          ..._webSearchSection(context, settings),
          ..._deviceSection(context),
          if (settings.debugMetricsEnabled)
            ..._benchmarkSection(context, viewModel),
        ],
      ),
    );
  }

  // --- section 0 ------------------------------------------------------------------------

  List<Widget> _languageSection(BuildContext context, AppSettings settings) {
    final strings = AppStrings.of(context);
    return [
      _SectionHeader(strings.languageSection),
      _SettingsCard(
        children: [
          _RowShell(
            child: Row(
              children: [
                Text(strings.languageSection, style: AppText.body(context)),
                const SizedBox(width: 16),
                Flexible(
                  child: _Dropdown<AppLanguage>(
                    isExpanded: true,
                    value: settings.appLanguage,
                    items: [
                      DropdownMenuItem<AppLanguage>(
                        value: AppLanguage.system,
                        child: Text(strings.languageSystem, overflow: TextOverflow.ellipsis),
                      ),
                      // Each language is named in itself, never translated: someone who
                      // cannot read the current language must still recognise their own.
                      const DropdownMenuItem<AppLanguage>(
                        value: AppLanguage.bangla,
                        child: Text('বাংলা', overflow: TextOverflow.ellipsis),
                      ),
                      const DropdownMenuItem<AppLanguage>(
                        value: AppLanguage.english,
                        child: Text('English', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.appLanguage = value;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      _SectionFooter(strings.languageFooter),
    ];
  }

  // --- section 0b -----------------------------------------------------------------------

  List<Widget> _textbooksSection(BuildContext context) {
    final strings = AppStrings.of(context);
    final curriculum = context.watch<CurriculumService>();
    final active = curriculum.activePack;
    return [
      _SectionHeader(strings.textbooks),
      _SettingsCard(
        children: [
          _LabeledRow(
            strings.answersUse,
            active == null ? strings.none : curriculumPackTitle(strings, active),
          ),
          _ActionRow(
            icon: AppIcons.books,
            label: strings.chooseTextbooks,
            onTap: () => unawaited(showCurriculumPacks(context)),
          ),
        ],
      ),
      _SectionFooter(strings.textbooksFooter),
    ];
  }

  // --- section 1 ------------------------------------------------------------------------

  List<Widget> _activeModelSection(
    BuildContext context,
    ModelManagerViewModel viewModel,
  ) {
    final strings = AppStrings.of(context);
    final metadata = viewModel.loadedModelMetadata;
    final canReload = viewModel.selectedFileName != null && !viewModel.isSwitchingModel;

    return [
      _SectionHeader(strings.activeModel),
      _SettingsCard(
        children: [
          _LabeledRow(strings.name, viewModel.selectedFileName ?? strings.none),
          if (metadata != null) ...[
            _LabeledRow(
              strings.size,
              FileSizeFormatter.string(bytes: metadata.fileSizeBytes),
            ),
            _LabeledRow(strings.architecture, metadata.architecture ?? strings.unknown),
            _LabeledRow(strings.quantization, metadata.quantization ?? strings.unknown),
            _LabeledRow(
              strings.nativeContext,
              metadata.nativeContextLength?.toString() ?? strings.unknown,
            ),
            _LabeledRow(
              strings.chatTemplate,
              metadata.hasChatTemplate ? strings.present : strings.missing,
            ),
          ],
          _LabeledRow(
            strings.status,
            viewModel.isSwitchingModel ? strings.loading : strings.ready,
          ),
          _ActionRow(
            icon: AppIcons.arrowClockwise,
            label: strings.reloadCurrentModel,
            onTap: canReload ? () => unawaited(_reload(viewModel)) : null,
          ),
        ],
      ),
    ];
  }

  // --- section 2 ------------------------------------------------------------------------

  List<Widget> _installedModelsSection(
    BuildContext context,
    ModelManagerViewModel viewModel,
  ) {
    final strings = AppStrings.of(context);
    return [
      _SectionHeader(strings.installedModels),
      _SettingsCard(
        children: [
          if (viewModel.installedModels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text(
                strings.noModelsInstalled,
                style: AppText.body(context).copyWith(
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            )
          else
            for (final model in viewModel.installedModels)
              _InstalledModelRow(
                key: ValueKey(model.fileName),
                model: model,
                isActive: model.fileName == viewModel.selectedFileName,
                onTap: model.fileName == viewModel.selectedFileName
                    ? null
                    : () => unawaited(_confirmSwitch(viewModel, model.fileName)),
                onDelete: () => _confirmDelete(viewModel, model.fileName),
              ),
          _ActionRow(
            icon: AppIcons.arrowDownCircle,
            label: strings.downloadAModel,
            onTap: () => unawaited(_openModelCatalog(viewModel)),
          ),
        ],
      ),
    ];
  }

  // --- section 3 ------------------------------------------------------------------------

  List<Widget> _generationSettingsSection(BuildContext context, AppSettings settings) {
    final strings = AppStrings.of(context);
    return [
      _SectionHeader(strings.generationSettings),
      _SettingsCard(
        children: [
          _RowShell(
            child: Row(
              children: [
                Expanded(child: Text(strings.contextLength, style: AppText.body(context))),
                _Dropdown<int>(
                  // A stored value outside the three offered presets would assert rather
                  // than render, and `AppSettings` will happily hand back whatever
                  // preferences hold.
                  value: AppSettings.availableContextLengths
                          .contains(settings.contextLengthPreset)
                      ? settings.contextLengthPreset
                      : null,
                  items: [
                    for (final length in AppSettings.availableContextLengths)
                      DropdownMenuItem<int>(value: length, child: Text('$length')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settings.contextLengthPreset = value;
                    }
                  },
                ),
              ],
            ),
          ),
          _StepperRow(
            label: strings.maxResponseTokens(settings.maxResponseTokens),
            onDecrement: settings.maxResponseTokens > AppSettings.minResponseTokens
                ? () => settings.maxResponseTokens =
                    settings.maxResponseTokens - AppSettings.responseTokensStep
                : null,
            onIncrement: settings.maxResponseTokens < AppSettings.maxResponseTokensLimit
                ? () => settings.maxResponseTokens =
                    settings.maxResponseTokens + AppSettings.responseTokensStep
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.temperature(settings.temperature.toStringAsFixed(2)),
                  style: AppText.body(context),
                ),
                // Track, thumb and overlay are all monochrome by way of `sliderTheme`.
                Slider(
                  value: settings.temperature.clamp(
                    AppSettings.minTemperature,
                    AppSettings.maxTemperature,
                  ),
                  min: AppSettings.minTemperature,
                  max: AppSettings.maxTemperature,
                  // 0…1.5 in steps of 0.05 is 30 intervals.
                  divisions: 30,
                  onChanged: (value) => settings.temperature = value,
                ),
              ],
            ),
          ),
          _SwitchRow(
            label: strings.deterministicSeed,
            value: settings.useDeterministicSeed,
            onChanged: (value) => settings.useDeterministicSeed = value,
          ),
          _SwitchRow(
            label: strings.debugMetrics,
            value: settings.debugMetricsEnabled,
            onChanged: (value) => settings.debugMetricsEnabled = value,
          ),
        ],
      ),
      _SectionFooter(strings.generationFooter),
    ];
  }

  // --- section 4 ------------------------------------------------------------------------

  List<Widget> _webSearchSection(BuildContext context, AppSettings settings) {
    final strings = AppStrings.of(context);
    return [
      _SectionHeader(strings.webSearch),
      _SettingsCard(
        children: [
          _RowShell(
            child: Row(
              children: [
                Text(strings.webSearch, style: AppText.body(context)),
                const SizedBox(width: 16),
                // Flexible + isExpanded, because 'Automatic for Current Info' is wider than
                // the row has to spare on a small phone at large text scale.
                Flexible(
                  child: _Dropdown<WebSearchMode>(
                    isExpanded: true,
                    value: settings.webSearchMode,
                    items: [
                      DropdownMenuItem<WebSearchMode>(
                        value: WebSearchMode.off,
                        child: Text(strings.webSearchOff, overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem<WebSearchMode>(
                        value: WebSearchMode.ask,
                        child: Text(strings.webSearchAsk, overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem<WebSearchMode>(
                        value: WebSearchMode.automatic,
                        child: Text(
                          strings.webSearchAutomatic,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.webSearchMode = value;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (settings.hasBraveApiKey) ...[
            _LabeledRow(strings.braveApiKey, strings.configured),
            _ActionRow(
              label: strings.removeKey,
              destructive: true,
              onTap: () => unawaited(settings.setBraveApiKey(null)),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: TextField(
                controller: _braveApiKeyController,
                obscureText: true,
                style: AppText.body(context),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: strings.braveApiKey,
                  filled: true,
                  // The page colour, not `thickMaterial`: the field now sits *inside* a
                  // `thickMaterial` card, and a fill matching its own ground would vanish.
                  fillColor: AppColors.page(context),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _ActionRow(
              label: strings.saveKey,
              onTap: _braveApiKeyController.text.trim().isEmpty
                  ? null
                  : () {
                      unawaited(
                          context.read<AppSettings>().setBraveApiKey(
                                _braveApiKeyController.text,
                              ));
                      _braveApiKeyController.clear();
                      setState(() {});
                    },
            ),
          ],
        ],
      ),
      _SectionFooter(strings.webSearchFooter),
    ];
  }

  // --- section 5a -----------------------------------------------------------------------

  List<Widget> _deviceSection(BuildContext context) {
    // The same signal `AppSettings._gpuLayers()` uses, replicated because that method is
    // private and there is no public accessor for the decision it makes.
    final isIosSimulator =
        Platform.isIOS && Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
    final strings = AppStrings.of(context);
    return [
      _SectionHeader(strings.device),
      _SettingsCard(
        children: [
          _LabeledRow(
            strings.gpuOffload,
            isIosSimulator ? strings.gpuDisabledSimulator : strings.enabled,
          ),
        ],
      ),
    ];
  }

  // --- section 5b -----------------------------------------------------------------------

  List<Widget> _benchmarkSection(
    BuildContext context,
    ModelManagerViewModel viewModel,
  ) {
    final canRun = !viewModel.isBenchmarking && viewModel.selectedFileName != null;
    final strings = AppStrings.of(context);

    return [
      _SectionHeader(strings.benchmarkDebug),
      _SettingsCard(
        children: [
          _ActionRow(
            icon: viewModel.isBenchmarking ? AppIcons.hourglass : AppIcons.speedometer,
            label: viewModel.isBenchmarking
                ? strings.runningBenchmark
                : strings.runBenchmarkSuite,
            onTap: canRun ? () => unawaited(viewModel.runBenchmark()) : null,
          ),
          for (final result in viewModel.benchmarkResults)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.promptLabel,
                    style: AppText.caption(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Figures in a monospace face so successive runs line up column-wise.
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (result.tokensPerSecond != null)
                        _BenchmarkFigure(
                          strings.tokensPerSecond(result.tokensPerSecond!.toStringAsFixed(1)),
                        ),
                      if (result.firstTokenLatency != null)
                        _BenchmarkFigure(
                          strings.firstTokenSeconds(
                            (result.firstTokenLatency!.inMicroseconds /
                                    Duration.microsecondsPerSecond)
                                .toStringAsFixed(2),
                          ),
                        ),
                      if (result.residentMemoryBytesAfter != null)
                        _BenchmarkFigure(
                          FileSizeFormatter.string(
                            bytes: result.residentMemoryBytesAfter!,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      _SectionFooter(strings.benchmarkFooter),
    ];
  }
}

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

class _SectionFooter extends StatelessWidget {
  const _SectionFooter(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Indented to sit under the card's own inset rather than at the screen edge.
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
      child: Text(
        text,
        style: AppText.caption(context).copyWith(
          color: AppColors.tertiaryLabel(context),
        ),
      ),
    );
  }
}

/// One grouped card: rows on a raised fill, a 14pt radius, and hairlines between them.
///
/// This replaces the full-bleed dividers the screen used to draw. A rule that runs edge to
/// edge reads as a seam in the page itself; a rule inset inside a card reads as a boundary
/// between two rows of the same group, which is the actual relationship.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        // Colour and thickness come from `dividerTheme`.
        rows.add(const Divider(indent: 14));
      }
      rows.add(children[index]);
    }

    // A `Material` rather than a plain `ColoredBox`: the rows inside are `InkWell`s, and ink
    // paints onto the nearest `Material` ancestor — a bare fill drawn over the scaffold's
    // would swallow every ripple. `clipBehavior` is what keeps the ink inside the radius.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.thickMaterial(context),
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// The padding every card row shares, for the handful of rows built inline.
class _RowShell extends StatelessWidget {
  const _RowShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: child,
    );
  }
}

/// A `DropdownButton` with the app's chevron and the same menu geometry as the popup menus
/// the theme already restyles.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Fill the width handed down instead of sizing to the widest item.
  ///
  /// A `DropdownButton` measures itself against its longest entry, so a long option makes
  /// the button wide enough to squeeze the label beside it to nothing — and at large text
  /// scales, wide enough to overflow the row outright. Set this wherever the options are
  /// prose rather than numerals, and give the button a `Flexible` parent.
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      isExpanded: isExpanded,
      value: value,
      items: items,
      onChanged: onChanged,
      style: AppText.body(context),
      underline: const SizedBox.shrink(),
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      dropdownColor: AppColors.thickMaterial(context),
      icon: Icon(
        AppIcons.chevronDown,
        size: 20,
        color: AppColors.secondaryLabel(context),
      ),
    );
  }
}

/// One benchmark figure, monospaced so the numbers align between runs.
class _BenchmarkFigure extends StatelessWidget {
  const _BenchmarkFigure(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppText.caption2(context).copyWith(
        color: AppColors.secondaryLabel(context),
        fontFamily: 'monospace',
        fontFamilyFallback: const <String>['Menlo', 'Courier New'],
      ),
    );
  }
}

/// SwiftUI's `LabeledContent`.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppText.body(context))),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.body(context).copyWith(
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : (enabled ? AppColors.primaryLabel(context) : AppColors.tertiaryLabel(context));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(label, style: AppText.body(context).copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// SwiftUI's `Stepper`: a live label with a minus and a plus.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body(context))),
          IconButton(
            onPressed: onDecrement,
            icon: const Icon(Icons.remove, size: 20),
            tooltip: AppStrings.of(context).decrease,
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add, size: 20),
            tooltip: AppStrings.of(context).increase,
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body(context))),
          // Thumb and track are monochrome by way of `switchTheme`.
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _InstalledModelRow extends StatelessWidget {
  const _InstalledModelRow({
    super.key,
    required this.model,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  final LocalModelInfo model;
  final bool isActive;
  final VoidCallback? onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.fileName, style: AppText.body(context)),
                  const SizedBox(height: 2),
                  Text(
                    FileSizeFormatter.string(bytes: model.fileSizeBytes),
                    style: AppText.caption(context).copyWith(
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Icon(AppIcons.checkmarkCircleFill, color: scheme.primary, size: 20),
          ],
        ),
      ),
    );

    // The active model cannot be swiped away — deleting the weights out from under a loaded
    // context is the one thing this screen must not allow.
    if (isActive) {
      return row;
    }

    return Dismissible(
      key: ValueKey('dismiss-${model.fileName}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onDelete();
        return false;
      },
      background: Container(
        color: scheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.trash, color: scheme.onError, size: 20),
            const SizedBox(width: 6),
            Text(AppStrings.of(context).delete, style: TextStyle(color: scheme.onError)),
          ],
        ),
      ),
      child: row,
    );
  }
}
