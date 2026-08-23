import 'package:flutter/material.dart';

import 'theme.dart';

/// The inline error strip. Ported from `Views/ErrorView.swift`, whose type is `ErrorBanner`.
///
/// The dismiss button is present only when [onDismiss] is given — the splash screen's failure
/// banner has nothing to dismiss to.
///
/// A rounded, inset card rather than a full-bleed red bar: error is the one saturated hue the
/// palette allows besides the send affordance, so it appears as a tint plus a hairline and
/// leaves the message itself in the ordinary label colour. Every call site already insets it,
/// so the banner carries no margin of its own.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dismiss = onDismiss;

    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: scheme.error.withAlpha(26), // 0.10
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: scheme.error.withAlpha(71)), // 0.28
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                AppIcons.exclamationmarkTriangleFill,
                color: scheme.error,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppText.footnote(context).copyWith(
                  color: AppColors.primaryLabel(context),
                ),
              ),
            ),
            if (dismiss != null) ...[
              const SizedBox(width: 10),
              Semantics(
                label: 'Dismiss error',
                button: true,
                // Its own transparent Material: the nearest one otherwise is the
                // Scaffold, and ink paints *into* that Material — i.e. underneath this
                // banner's tint and border, where the ripple is invisible.
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: dismiss,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        AppIcons.xmark,
                        size: 16,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
