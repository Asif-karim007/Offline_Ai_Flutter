import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_request.dart';
import '../domain/local_model_info.dart';
import '../model_management/app_settings.dart';
import '../model_management/model_importer.dart';
import '../utilities/file_size_formatter.dart';
import '../viewmodels/model_manager_view_model.dart';
import 'theme.dart';

/// Settings and the installed-model list, presented as a sheet.
///
/// [onWillSwitchModel] runs — and is awaited — before every path that loads, reloads, imports
/// or switches a model. It is `ChatViewModel.startNewPersistentChat()`, and it is what
/// satisfies `ModelManagerViewModel.switchToModel`'s caller contract that generation has
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
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      viewModel.errorMessage = null;
      _shownErrorMessage = null;
    });
  }

  Future<void> _importModel(ModelManagerViewModel viewModel) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ModelImporter.allowedExtensions,
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await widget.onWillSwitchModel();
    await viewModel.importModel(path);
  }

  Future<void> _confirmSwitch(
    ModelManagerViewModel viewModel,
    String fileName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Model?'),
        content: const Text(
          'This cancels any response in progress and reloads the model. Your saved chat '
          'history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model?'),
        content: const Text(
          'This removes the model file from your device. You can re-import it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
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
    _surfaceError(viewModel);

    // No `backgroundColor` here: `scaffoldBackgroundColor` is already `AppColors.page`.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Models'),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        leadingWidth: 88,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
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

  // --- section 1 ------------------------------------------------------------------------

  List<Widget> _activeModelSection(
    BuildContext context,
    ModelManagerViewModel viewModel,
  ) {
    final metadata = viewModel.loadedModelMetadata;
    final canReload = viewModel.selectedFileName != null && !viewModel.isSwitchingModel;

    return [
      const _SectionHeader('Active Model'),
      _SettingsCard(
        children: [
          _LabeledRow('Name', viewModel.selectedFileName ?? 'None'),
          if (metadata != null) ...[
            _LabeledRow(
              'Size',
              FileSizeFormatter.string(bytes: metadata.fileSizeBytes),
            ),
            _LabeledRow('Architecture', metadata.architecture ?? 'Unknown'),
            _LabeledRow('Quantization', metadata.quantization ?? 'Unknown'),
            _LabeledRow(
              'Native context',
              metadata.nativeContextLength?.toString() ?? 'Unknown',
            ),
            _LabeledRow(
              'Chat template',
              metadata.hasChatTemplate ? 'Present' : 'Missing',
            ),
          ],
          _LabeledRow('Status', viewModel.isSwitchingModel ? 'Loading…' : 'Ready'),
          _ActionRow(
            icon: AppIcons.arrowClockwise,
            label: 'Reload Current Model',
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
    return [
      const _SectionHeader('Installed Models'),
      _SettingsCard(
        children: [
          if (viewModel.installedModels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text(
                'No models installed yet.',
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
            icon: AppIcons.squareAndArrowDown,
            label: 'Import Another GGUF',
            onTap: () => unawaited(_importModel(viewModel)),
          ),
        ],
      ),
    ];
  }

  // --- section 3 ------------------------------------------------------------------------

  List<Widget> _generationSettingsSection(BuildContext context, AppSettings settings) {
    return [
      const _SectionHeader('Generation Settings'),
      _SettingsCard(
        children: [
          _RowShell(
            child: Row(
              children: [
                Expanded(child: Text('Context Length', style: AppText.body(context))),
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
            label: 'Max Response Tokens: ${settings.maxResponseTokens}',
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
                  'Temperature: ${settings.temperature.toStringAsFixed(2)}',
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
            label: 'Deterministic Seed',
            value: settings.useDeterministicSeed,
            onChanged: (value) => settings.useDeterministicSeed = value,
          ),
          _SwitchRow(
            label: 'Debug Metrics',
            value: settings.debugMetricsEnabled,
            onChanged: (value) => settings.debugMetricsEnabled = value,
          ),
        ],
      ),
      const _SectionFooter(
        'Larger context windows increase memory use, first-response latency, device heat, '
        'and battery consumption, and raise the risk of the app being terminated under '
        'memory pressure.',
      ),
    ];
  }

  // --- section 4 ------------------------------------------------------------------------

  List<Widget> _webSearchSection(BuildContext context, AppSettings settings) {
    return [
      const _SectionHeader('Web Search'),
      _SettingsCard(
        children: [
          _RowShell(
            child: Row(
              children: [
                Text('Web Search', style: AppText.body(context)),
                const SizedBox(width: 16),
                // Flexible + isExpanded, because 'Automatic for Current Info' is wider than
                // the row has to spare on a small phone at large text scale.
                Flexible(
                  child: _Dropdown<WebSearchMode>(
                    isExpanded: true,
                    value: settings.webSearchMode,
                    items: const [
                      DropdownMenuItem<WebSearchMode>(
                        value: WebSearchMode.off,
                        child: Text('Off', overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem<WebSearchMode>(
                        value: WebSearchMode.ask,
                        child: Text('Ask', overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem<WebSearchMode>(
                        value: WebSearchMode.automatic,
                        child: Text(
                          'Automatic for Current Info',
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
            const _LabeledRow('Brave Search API Key', 'Configured'),
            _ActionRow(
              label: 'Remove Key',
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
                  hintText: 'Brave Search API Key',
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
              label: 'Save Key',
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
      const _SectionFooter(
        'When enabled, a short search query (never your full conversation or files) may be '
        'sent to a search provider, and public web pages you search for may be downloaded. '
        'Model reasoning and the final answer always happen on-device. Without a Brave '
        'Search API key, search falls back automatically to a free, no-key DuckDuckGo '
        'search. Changes take effect on your next message -- no restart needed.',
      ),
    ];
  }

  // --- section 5a -----------------------------------------------------------------------

  List<Widget> _deviceSection(BuildContext context) {
    // The same signal `AppSettings._gpuLayers()` uses, replicated because that method is
    // private and there is no public accessor for the decision it makes.
    final isIosSimulator =
        Platform.isIOS && Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
    return [
      const _SectionHeader('Device'),
      _SettingsCard(
        children: [
          _LabeledRow(
            'GPU Offload',
            isIosSimulator ? 'Disabled (Simulator)' : 'Enabled',
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

    return [
      const _SectionHeader('Benchmark (Debug)'),
      _SettingsCard(
        children: [
          _ActionRow(
            icon: viewModel.isBenchmarking ? AppIcons.hourglass : AppIcons.speedometer,
            label: viewModel.isBenchmarking
                ? 'Running Benchmark…'
                : 'Run Benchmark Suite',
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
                          '${result.tokensPerSecond!.toStringAsFixed(1)} tok/s',
                        ),
                      if (result.firstTokenLatency != null)
                        _BenchmarkFigure(
                          '${(result.firstTokenLatency!.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)}s first token',
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
      const _SectionFooter(
        'Test performance on a physical device, not the Simulator, which is CPU-only and '
        'not representative. Results are not stored anywhere -- they exist only for this '
        'session.',
      ),
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
            tooltip: 'Decrease',
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Increase',
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
            Text('Delete', style: TextStyle(color: scheme.onError)),
          ],
        ),
      ),
      child: row,
    );
  }
}
