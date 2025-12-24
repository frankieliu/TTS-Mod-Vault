import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mod_operations/backup_decision.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        directoriesProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider;

/// Unified service for all mod operations (download, backup, combined)
/// Consolidates logic previously duplicated between single-mod and bulk operations
class ModOperationsService {
  final Ref ref;

  ModOperationsService(this.ref);

  // ============ Download Operations ============

  /// Download all files for a single mod
  Future<void> downloadMod(Mod mod, {bool updateUI = true}) async {
    debugPrint('Downloading: ${mod.saveName}');

    await ref.read(downloadProvider.notifier).downloadAllFiles(mod);

    if (updateUI) {
      await _refreshModUI(mod);
    }
  }

  /// Download all files for multiple mods with progress callback
  Future<void> downloadMods(
    List<Mod> mods, {
    void Function(int current, int total, Mod mod)? onProgress,
  }) async {
    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (onProgress != null) {
        onProgress(i + 1, mods.length, mod);
      }

      await downloadMod(mod, updateUI: true);
    }
  }

  // ============ Backup Operations ============

  /// Backup a single mod using the provided configuration
  /// Returns the BackupDecision if interactive confirmation is needed, null if completed
  Future<BackupDecision?> backupMod(
    Mod mod,
    BackupConfig config, {
    bool updateUI = true,
  }) async {
    final decision = await _determineBackupAction(mod, config);

    debugPrint('Backup decision for ${mod.saveName}: ${decision.reason}');

    if (!decision.shouldBackup) {
      debugPrint('  Skipping backup: ${decision.reason}');
      return decision;
    }

    // If interactive and needs confirmation, return decision for caller to handle
    if (config.showDialogs && decision.needsConfirmation) {
      return decision;
    }

    // Perform backup
    await ref.read(backupProvider.notifier).createBackup(
          mod,
          decision.targetFolder,
        );

    if (updateUI) {
      await _refreshModUI(mod);
    }

    // Return null to indicate backup completed successfully
    return null;
  }

  /// Backup multiple mods with progress callback
  Future<void> backupMods(
    List<Mod> mods,
    BackupConfig config, {
    void Function(int current, int total, Mod mod)? onProgress,
  }) async {
    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (onProgress != null) {
        onProgress(i + 1, mods.length, mod);
      }

      // Get complete mod with CRC32 checks for accurate decision making
      final urls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final completeMod =
          await ref.read(modsProvider.notifier).getCompleteMod(mod, urls);

      await backupMod(completeMod, config);
    }
  }

  // ============ Combined Operations ============

  /// Download and backup multiple mods with phase-specific progress
  Future<void> downloadAndBackupMods(
    List<Mod> mods,
    BackupConfig config, {
    void Function(int current, int total, Mod mod, String phase)? onProgress,
  }) async {
    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      // Download phase
      if (onProgress != null) {
        onProgress(i + 1, mods.length, mod, 'Downloading');
      }
      await downloadMod(mod, updateUI: true);

      // Backup phase
      if (onProgress != null) {
        onProgress(i + 1, mods.length, mod, 'Backing up');
      }

      // Get fresh mod data after download for backup decision
      final urls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final updatedMod =
          await ref.read(modsProvider.notifier).getCompleteMod(mod, urls);

      await backupMod(updatedMod, config);
    }
  }

  // ============ Helper Methods ============

  /// Refresh UI for a single mod (asset counts, backup status)
  Future<void> _refreshModUI(Mod mod) async {
    try {
      await ref.read(modsProvider.notifier).refreshModsInfo([mod]);

      // Also update the selected mod to ensure UI reflects the change
      final selectedMod = ref.read(selectedModProvider);
      if (selectedMod?.jsonFilePath == mod.jsonFilePath) {
        await ref.read(modsProvider.notifier).updateSelectedMod(mod);
      }
    } catch (e) {
      // Ignore errors if widget was disposed during async operation
      debugPrint('_refreshModUI error (likely widget disposed): $e');
      // Even if update fails, the state in existingBackupsProvider is correct
      // UI will update on next natural rebuild
    }
  }

  /// Determine what backup action to take based on mod state and config
  Future<BackupDecision> _determineBackupAction(
    Mod mod,
    BackupConfig config,
  ) async {
    // No existing backup → Always backup
    if (mod.backup == null ||
        mod.backupStatus == ExistingBackupStatusEnum.noBackup) {
      return BackupDecision.backup(
        folder: config.targetFolder ?? await _getDefaultBackupFolder(),
        reason: 'No backup exists',
      );
    }

    // Force flag set → Always replace
    if (config.force) {
      return BackupDecision.backup(
        folder: config.targetFolder ?? p.dirname(mod.backup!.filepath),
        reason: 'Force flag set',
      );
    }

    // Apply behavior-based logic
    switch (config.behavior) {
      case BackupBehavior.skip:
        return BackupDecision.skip('Backup exists (skip behavior)');

      case BackupBehavior.replace:
        return BackupDecision.backup(
          folder: config.targetFolder ?? p.dirname(mod.backup!.filepath),
          reason: 'Replace existing backup',
        );

      case BackupBehavior.replaceIfNecessary:
        if (mod.backupStatus == ExistingBackupStatusEnum.outOfDate) {
          return BackupDecision.backup(
            folder: config.targetFolder ?? p.dirname(mod.backup!.filepath),
            reason: 'Files changed (CRC32 mismatch or new files)',
          );
        } else {
          return BackupDecision.skip('Backup is up to date');
        }

      case BackupBehavior.interactive:
        // For interactive mode, check if backup should be forced
        final shouldForce =
            ref.read(backupProvider.notifier).shouldForceBackup(mod);

        return BackupDecision.backup(
          folder: p.dirname(mod.backup!.filepath),
          reason: shouldForce
              ? 'Files changed - needs confirmation'
              : 'Backup exists - needs user choice',
          needsConfirmation: true,
        );
    }
  }

  /// Get default backup folder (from settings or prompt user)
  Future<String> _getDefaultBackupFolder() async {
    final backupsDir = ref.read(directoriesProvider).backupsDir;
    if (backupsDir.isNotEmpty) {
      return backupsDir;
    }

    // Prompt user for folder
    final folder = await FilePicker.platform
        .getDirectoryPath(lockParentWindow: true);
    return folder ?? backupsDir;
  }
}
