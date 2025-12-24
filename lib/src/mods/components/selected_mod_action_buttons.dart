import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show showUpdateUrlsDialog;
import 'package:tts_mod_vault/src/state/mod_operations/backup_decision.dart';
import 'package:tts_mod_vault/src/state/mod_operations/mod_operations_service.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        directoriesProvider,
        modsProvider,
        selectedModProvider,
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

    final actionInProgress = ref.watch(actionInProgressProvider);
    final enableTtsModdersFeatures =
        ref.watch(settingsProvider).enableTtsModdersFeatures;
    final service = ModOperationsService(ref);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 8,
      children: [
        ElevatedButton(
          onPressed: hasMissingFiles
              ? () async {
                  if (actionInProgress) return;

                  await service.downloadMod(selectedMod, updateUI: false);

                  // Explicitly update UI from widget context
                  await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
                }
              : null,
          child: const Text('Download'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (actionInProgress) return;

            debugPrint('\n=== BACKUP BUTTON PRESSED ===');
            debugPrint('Selected mod: ${selectedMod.saveName}');
            debugPrint('Current backup: ${selectedMod.backup?.filepath ?? "null"}');
            debugPrint('Current backup status: ${selectedMod.backupStatus}');

            final showWarningMessage =
                ref.read(settingsProvider).showBackupState &&
                    ref.read(directoriesProvider).backupsDir.isEmpty;

            final setBackupFolderMessage =
                "Set a backup folder in Settings to show backup state after a restart or data refresh\nOr disable backup state feature in Settings to hide this warning";

            final config = BackupConfig.interactive(force: forceBackup.value);
            debugPrint('Calling service.backupMod()...');

            final decision = await service.backupMod(
              selectedMod,
              config,
              updateUI: false, // Don't update from service (widget context)
            );

            debugPrint('service.backupMod() returned, decision: ${decision?.reason ?? "null (backup completed)"}');

            if (decision == null) {
              // Backup completed - update UI from widget context
              debugPrint('Backup completed, calling updateSelectedMod()...');
              try {
                await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
                debugPrint('updateSelectedMod() completed successfully');

                // Re-read the updated mod to verify backup was set
                final updatedMod = ref.read(selectedModProvider);
                debugPrint('After update - backup: ${updatedMod?.backup?.filepath ?? "null"}');
                debugPrint('After update - backup status: ${updatedMod?.backupStatus}');
              } catch (e) {
                debugPrint('ERROR in updateSelectedMod(): $e');
              }
              return;
            }

            if (!decision.needsConfirmation) {
              // Backup skipped or completed - update UI from widget context
              debugPrint('Backup skipped/completed (no confirmation), calling updateSelectedMod()...');
              try {
                await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
                debugPrint('updateSelectedMod() completed successfully');
              } catch (e) {
                debugPrint('ERROR in updateSelectedMod(): $e');
              }
              return;
            }

            // Check if widget is still mounted before showing dialogs
            if (!context.mounted) {
              debugPrint('Widget not mounted, cannot show dialog');
              return;
            }

            // Interactive mode - show confirmation dialog
            if (decision.reason.contains('Files changed')) {
              // Files have changed - auto-force backup
              String message = showWarningMessage
                  ? '$setBackupFolderMessage\n\n${decision.reason}\n\nCreating new backup with updated files.'
                  : '${decision.reason}\n\nCreating new backup with updated files.';

              showConfirmDialog(
                context,
                message,
                () async {
                  final backupConfig = BackupConfig(
                    behavior: BackupBehavior.replace,
                    targetFolder: decision.targetFolder,
                    force: true,
                  );
                  await service.backupMod(selectedMod, backupConfig, updateUI: false);
                  await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
                },
                () {},
              );
            } else {
              // Backup exists, no changes - ask user
              String message = showWarningMessage
                  ? '$setBackupFolderMessage\n\nBackup already exists. Replace existing file?'
                  : 'Backup already exists. Replace existing file?';

              showConfirmDialog(
                context,
                message,
                () async {
                  final backupConfig = BackupConfig(
                    behavior: BackupBehavior.replace,
                    targetFolder: decision.targetFolder,
                    force: true,
                  );
                  await service.backupMod(selectedMod, backupConfig, updateUI: false);
                  await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
                },
                () async {
                  // Just update metadata without creating new backup
                  await ref
                      .read(backupProvider.notifier)
                      .updateExistingBackupMetadata(selectedMod);
                  await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
                },
              );
            }
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
              if (actionInProgress) return;

              showUpdateUrlsDialog(context, ref, selectedMod);
            },
            child: const Text('Update URLs'),
          ),
      ],
    );
  }
}
