import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../curriculum/curriculum_pack.dart';
import '../curriculum/curriculum_service.dart';
import '../l10n/app_strings.dart';
import '../utilities/file_size_formatter.dart';
import 'error_banner.dart';
import 'theme.dart';

/// Short display name for a pack: "Class 9–10 · Bangla version" / "নবম–দশম শ্রেণি · বাংলা ভার্সন".
String curriculumPackTitle(AppStrings strings, CurriculumPack pack) => strings.packTitle(
      pack.classNumbers,
      pack.stream,
      banglaVersion: pack.isBanglaVersion,
    );

/// Opens the textbook picker as a full page. Usable from anywhere under the app's providers.
Future<void> showCurriculumPacks(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context).textbooks)),
        body: const CurriculumPacksView(),
      ),
    ),
  );
}

/// Every pack in the published manifest, one row each, with its download / use / delete
/// controls. A student picks their class and version here; the first download also becomes
/// the active pack, so for most students this screen is one tap.
class CurriculumPacksView extends StatelessWidget {
  const CurriculumPacksView({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CurriculumService>();
    final strings = AppStrings.of(context);
    final manifest = service.manifest;

    return RefreshIndicator(
      onRefresh: service.refreshManifest,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              strings.textbooksIntro,
              style: AppText.subheadline(context).copyWith(
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          if (service.errorMessage case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ErrorBanner(
                message: message,
                onDismiss: () => service.errorMessage = null,
              ),
            ),
          if (manifest == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: service.isLoadingManifest
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          Text(
                            strings.packListUnavailable,
                            textAlign: TextAlign.center,
                            style: AppText.body(context),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => unawaited(service.refreshManifest()),
                            child: Text(strings.retry),
                          ),
                        ],
                      ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (final pack in manifest.packs)
              Padding(
                key: ValueKey<String>(pack.id),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _PackRow(pack: pack),
              ),
          ],
        ],
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.pack});

  final CurriculumPack pack;

  Future<void> _confirmDelete(BuildContext context, CurriculumService service) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deletePackTitle),
        content: Text(strings.deletePackBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.delete(pack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CurriculumService>();
    final strings = AppStrings.of(context);
    final status = service.statusOf(pack);
    final isActive = service.activePackId == pack.id;
    final progress = status == CurriculumPackStatus.downloading ? service.downloadProgress : null;

    final Widget trailing = switch (status) {
      CurriculumPackStatus.notInstalled => FilledButton(
          onPressed: service.isDownloading ? null : () => unawaited(service.download(pack)),
          child: Text(strings.download),
        ),
      CurriculumPackStatus.downloading => TextButton(
          onPressed: () => unawaited(service.cancelDownload()),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: Text(strings.cancel),
        ),
      CurriculumPackStatus.preparing => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(strings.preparingPack, style: AppText.footnote(context)),
          ],
        ),
      CurriculumPackStatus.installed when isActive => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.checkmarkCircleFill,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(strings.inUse, style: AppText.footnote(context)),
          ],
        ),
      CurriculumPackStatus.installed => OutlinedButton(
          onPressed: () => unawaited(service.activate(pack)),
          child: Text(strings.usePack),
        ),
    };

    return Material(
      color: AppColors.thickMaterial(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(AppIcons.books, size: 22, color: AppColors.secondaryLabel(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(curriculumPackTitle(strings, pack), style: AppText.headline(context)),
                      const SizedBox(height: 2),
                      Text(
                        strings.packDetails(
                          pack.bookCount,
                          FileSizeFormatter.string(bytes: pack.sizeBytes),
                        ),
                        style: AppText.caption(context).copyWith(
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
                if (status == CurriculumPackStatus.installed)
                  IconButton(
                    onPressed: () => unawaited(_confirmDelete(context, service)),
                    icon: const Icon(AppIcons.trash, size: 20),
                    tooltip: strings.delete,
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
            if (status == CurriculumPackStatus.downloading) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                  child: LinearProgressIndicator(value: progress?.fraction, minHeight: 6),
                ),
              ),
              if (progress != null && progress.isDeterminate) ...[
                const SizedBox(height: 6),
                Text(
                  strings.downloadProgress(
                    FileSizeFormatter.string(bytes: progress.bytesWritten),
                    FileSizeFormatter.string(bytes: progress.totalBytes),
                  ),
                  style: AppText.caption(context).copyWith(
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
