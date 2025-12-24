import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show showUpdateUrlsDialog;
import 'package:tts_mod_vault/src/state/mod_operations/backup_decision.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        directoriesProvider,
        modOperationsServiceProvider,
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
    final service = ref.watch(modOperationsServiceProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 8,
      children: [
        ElevatedButton(
          onPressed: hasMissingFiles
              ? () async {
                  if (actionInProgress) return;

                  await service.downloadMod(selectedMod, updateUI: true);
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

            // Get fresh mod with latest backup info before making decisions
            final urls = await ref.read(modsProvider.notifier).getUrlsByMod(selectedMod);
            final freshMod = await ref.read(modsProvider.notifier).getCompleteMod(selectedMod, urls);

            debugPrint('After refresh - backup: ${freshMod.backup?.filepath ?? "null"}');
            debugPrint('After refresh - backup status: ${freshMod.backupStatus}');

            final showWarningMessage =
                ref.read(settingsProvider).showBackupState &&
                    ref.read(directoriesProvider).backupsDir.isEmpty;

            final setBackupFolderMessage =
                "Set a backup folder in Settings to show backup state after a restart or data refresh\nOr disable backup state feature in Settings to hide this warning";

            final config = BackupConfig.interactive(force: forceBackup.value);
            debugPrint('Calling service.backupMod()...');

            final decision = await service.backupMod(
              freshMod, // Use fresh mod with updated backup info
              config,
              updateUI: true, // Let service handle UI update (will catch disposal errors)
            );

            debugPrint('service.backupMod() returned, decision: ${decision?.reason ?? "null (backup completed)"}');

            if (decision == null) {
              // Backup completed - service already updated UI
              debugPrint('Backup completed successfully');
              return;
            }

            if (!decision.needsConfirmation) {
              // Backup skipped - no UI update needed
              debugPrint('Backup skipped or completed (no confirmation needed)');
              return;
            }

            // Check if widget is still mounted before showing dialogs
            if (!context.mounted) {
              debugPrint('Widget not mounted, cannot show dialog');
              return;
            }

            // Interactive mode - only show dialog for file changes
            if (decision.reason.contains('Files changed')) {
              // Files have changed - inform user and create backup
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
                  await service.backupMod(freshMod, backupConfig, updateUI: true);
                },
                () {},
              );
            } else {
              // Backup exists, no changes, Force not checked
              // Don't show dialog - user should use Force checkbox if they want to replace
              debugPrint('Backup exists and up to date. Use Force checkbox to replace.');
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
