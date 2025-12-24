import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show showUpdateUrlsDialog;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        directoriesProvider,
        downloadProvider,
        modsProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showConfirmDialog;

class SelectedModActionButtons extends HookConsumerWidget {
  final Mod selectedMod;

  const SelectedModActionButtons({super.key, required this.selectedMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forceBackup = useState(false);
    final hasMissingFiles = useMemoized(() {
      if (selectedMod.assetLists == null) return false;

      return selectedMod.getAllAssets().any((asset) => !asset.fileExists);
    }, [selectedMod]);

    final modsNotifier = ref.watch(modsProvider.notifier);
    final backupNotifier = ref.watch(backupProvider.notifier);
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final actionInProgress = ref.watch(actionInProgressProvider);
    final enableTtsModdersFeatures =
        ref.watch(settingsProvider).enableTtsModdersFeatures;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 8,
      children: [
        ElevatedButton(
          onPressed: hasMissingFiles
              ? () async {
                  if (actionInProgress) {
                    return;
                  }

                  await downloadNotifier.downloadAllFiles(selectedMod);
                  await modsNotifier.updateSelectedMod(selectedMod);
                }
              : null,
          child: const Text('Download'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (actionInProgress) {
              return;
            }

            final showWarningMessage =
                ref.read(settingsProvider).showBackupState &&
                    ref.read(directoriesProvider).backupsDir.isEmpty;

            final setBackupFolderMessage =
                "Set a backup folder in Settings to show backup state after a restart or data refresh\nOr disable backup state feature in Settings to hide this warning";

            if (selectedMod.backupStatus == ExistingBackupStatusEnum.noBackup ||
                forceBackup.value) {
              // No existing backup OR force is checked → Create new backup
              if (showWarningMessage) {
                showConfirmDialog(
                  context,
                  "$setBackupFolderMessage\n\nContinue with creating a backup?",
                  () async {
                    await backupNotifier.createBackup(selectedMod);
                    await modsNotifier.updateSelectedMod(selectedMod);
                  },
                  () {},
                );
              } else {
                await backupNotifier.createBackup(selectedMod);
                await modsNotifier.updateSelectedMod(selectedMod);
              }
              return;
            }

            // Backup exists and force not checked → Check if backup should be forced
            final shouldForce = backupNotifier.shouldForceBackup(selectedMod);

            if (shouldForce) {
              // Downloaded files have changed → Auto-force backup creation
              String forceMessage =
                  'Downloaded files have changed (new files or CRC32 mismatch).\n\nCreating new backup with updated files.';
              String message = showWarningMessage
                  ? '$setBackupFolderMessage\n\n$forceMessage'
                  : forceMessage;

              showConfirmDialog(
                context,
                message,
                () async {
                  final backupFolder = p.dirname(selectedMod.backup!.filepath);
                  await backupNotifier.createBackup(selectedMod, backupFolder);
                  await modsNotifier.updateSelectedMod(selectedMod);
                },
                () {},
              );
              return;
            }

            // Backup exists, no changes detected → Ask what to do
            String backupMessage =
                'Backup already exists. Replace existing file?';
            String message = showWarningMessage
                ? '$setBackupFolderMessage\n\n$backupMessage'
                : backupMessage;

            showConfirmDialog(
              context,
              message,
              () async {
                final backupFolder = p.dirname(selectedMod.backup!.filepath);

                await backupNotifier.createBackup(selectedMod, backupFolder);
                await modsNotifier.updateSelectedMod(selectedMod);
              },
              () async {
                // Just update metadata without creating new backup
                await backupNotifier.updateExistingBackupMetadata(selectedMod);
                await modsNotifier.updateSelectedMod(selectedMod);
              },
            );
          },
          child: const Text('Backup'),
        ),
        SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: forceBackup.value,
                onChanged: (value) => forceBackup.value = value ?? false,
              ),
              const Text('Force', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        if (enableTtsModdersFeatures)
          ElevatedButton(
            onPressed: () async {
              if (actionInProgress) {
                return;
              }

              showUpdateUrlsDialog(context, ref, selectedMod);
            },
            child: const Text('Update URLs'),
          ),
      ],
    );
  }
}
