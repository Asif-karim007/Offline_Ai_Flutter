import 'package:flutter/material.dart';

import '../domain/generation_metrics.dart';
import '../utilities/file_size_formatter.dart';
import 'theme.dart';

/// The debug metrics sheet.
///
/// A value snapshot with no view model behind it, exactly as in the original: it renders
/// whatever `ChatViewModel.lastMetrics` held at the moment the sheet opened, and does not
/// update while it is on screen.
///
/// Presented as grouped cards rather than a full-bleed list: every row here is a key and a
/// figure, and figures are set in a monospace face so the digits line up column-wise down a
/// card instead of drifting with the proportional face's varying digit widths.
class GenerationDebugView extends StatelessWidget {
  const GenerationDebugView({super.key, required this.metrics, this.onDone});

  final GenerationMetrics metrics;
  final VoidCallback? onDone;

  bool get _hasAgentMetrics =>
      metrics.plannerDuration != null ||
      metrics.searchDuration != null ||
      metrics.documentRetrievalDuration != null ||
      metrics.ragTokenCount != null ||
      metrics.memoryTokenCount != null;

  @override
  Widget build(BuildContext context) {
    final done = onDone;

    // No `backgroundColor` here: `scaffoldBackgroundColor` is already `AppColors.page`.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Metrics'),
        leading: done == null
            ? null
            : TextButton(onPressed: done, child: const Text('Done')),
        leadingWidth: 88,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const _SectionHeader('Model'),
          _MetricCard(
            rows: [
              _MetricRow('Name', metrics.modelName),
              _MetricRow(
                'File size',
                FileSizeFormatter.string(bytes: metrics.modelFileSizeBytes),
              ),
              _MetricRow('Native context', '${metrics.nativeContextLength}'),
              _MetricRow('Allocated context', '${metrics.allocatedContextLength}'),
            ],
          ),
          const _SectionHeader('Last generation'),
          _MetricCard(
            rows: [
              _MetricRow('Prompt tokens', '${metrics.promptTokenCount}'),
              _MetricRow('Reserved output tokens', '${metrics.reservedOutputTokens}'),
              _MetricRow('Generated tokens', '${metrics.generatedTokenCount}'),
              if (metrics.firstTokenLatency != null)
                _MetricRow(
                  'First-token latency',
                  _seconds(metrics.firstTokenLatency!),
                ),
              if (metrics.totalGenerationDuration != null)
                _MetricRow('Total duration', _seconds(metrics.totalGenerationDuration!)),
              if (metrics.tokensPerSecond != null)
                _MetricRow(
                  'Tokens / second',
                  metrics.tokensPerSecond!.toStringAsFixed(1),
                ),
            ],
          ),
          if (_hasAgentMetrics) ...[
            const _SectionHeader('Agent Pipeline'),
            _MetricCard(
              rows: [
                if (metrics.plannerDuration != null)
                  _MetricRow('Planner duration', _seconds(metrics.plannerDuration!)),
                if (metrics.searchDuration != null)
                  _MetricRow('Web search duration', _seconds(metrics.searchDuration!)),
                if (metrics.documentRetrievalDuration != null)
                  _MetricRow(
                    'Document retrieval duration',
                    _seconds(metrics.documentRetrievalDuration!),
                  ),
                if (metrics.ragTokenCount != null)
                  _MetricRow('RAG evidence tokens (est.)', '${metrics.ragTokenCount}'),
                if (metrics.memoryTokenCount != null)
                  _MetricRow(
                    'Session memory tokens (est.)',
                    '${metrics.memoryTokenCount}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// `String(format: "%.2fs", duration)` — Swift formatted a `TimeInterval`, which is
  /// seconds as a double.
  static String _seconds(Duration duration) {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    return '${seconds.toStringAsFixed(2)}s';
  }
}

/// The grouped-list section header a SwiftUI `Section("…")` renders.
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

/// One grouped card: a raised fill, a 14pt radius, and hairlines between rows instead of
/// full-bleed dividers.
class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index += 1) {
      if (index > 0) {
        // Colour and thickness come from `dividerTheme`.
        children.add(const Divider(indent: 14));
      }
      children.add(rows[index]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.thickMaterial(context),
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// SwiftUI's `LabeledContent`: label leading and primary, value trailing, secondary and
/// monospaced so the figures align down the card.
class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppText.subheadline(context))),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.subheadline(context).copyWith(
                color: AppColors.secondaryLabel(context),
                fontFamily: 'monospace',
                fontFamilyFallback: const <String>['Menlo', 'Courier New'],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
