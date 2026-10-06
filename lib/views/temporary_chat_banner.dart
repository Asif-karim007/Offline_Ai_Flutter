import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'theme.dart';

/// The notice that sits above a temporary chat.
///
/// A small centred capsule rather than a full-bleed tinted strip. The state it reports is
/// persistent — it is true for the whole conversation — and a saturated bar pinned above the
/// transcript for that long reads as chrome and competes with the prose. A quiet pill in
/// [AppColors.thickMaterial] states the same fact once and then gets out of the way, which is
/// the convention the mainstream assistant apps settled on for the same mode.
class TemporaryChatBanner extends StatelessWidget {
  const TemporaryChatBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.secondaryLabel(context);

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.thickMaterial(context),
              borderRadius: const BorderRadius.all(Radius.circular(100)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(AppIcons.eyeSlash, size: 14, color: muted),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    AppStrings.of(context).temporaryChatBanner,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context).copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
