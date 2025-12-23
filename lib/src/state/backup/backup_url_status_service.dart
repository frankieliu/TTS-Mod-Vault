import 'package:flutter/material.dart' show debugPrint;
import 'package:tts_mod_vault/src/state/backup/backup_url_matcher.dart';
import 'package:tts_mod_vault/src/state/backup/models/backup_file_metadata.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart';
import 'package:tts_mod_vault/src/state/storage/storage.dart';

/// Service to populate and manage URL backup status in Hive
class BackupUrlStatusService {
  final Storage storage;

  BackupUrlStatusService(this.storage);

  /// Scans a backup and marks all URLs from a mod as backed up
  ///
  /// This is the main method to call when you want to update the backup status
  /// for all assets in a mod based on what's in a backup file
  Future<void> scanBackupForMod({
    required Mod mod,
    required String backupFilename,
    required BackupFileMetadata backupMetadata,
  }) async {
    debugPrint(
        'Scanning backup $backupFilename for mod ${mod.saveName}...');

    // Get all assets from the mod
    final assets = mod.getAllAssets();
    final urls = assets.map((a) => a.url).toList();

    debugPrint('  Found ${urls.length} asset URLs in mod');

    // Check which URLs are in the backup
    final backupStatus =
        BackupUrlMatcher.checkUrlsInBackup(urls, backupMetadata);

    // Prepare bulk save data
    final urlStatuses = <String, Map<String, dynamic>>{};

    for (final entry in backupStatus.entries) {
      final url = entry.key;
      final isInBackup = entry.value;

      if (isInBackup) {
        // Get the actual filename in the backup
        final backupFilenameForUrl =
            BackupUrlMatcher.getBackupFilenameForUrl(url, backupMetadata);
        final fileSize = backupFilenameForUrl != null
            ? backupMetadata.getFileSize(backupFilenameForUrl)
            : null;

        urlStatuses[url] = {
          'backupFilename': backupFilename,
          'fileSize': fileSize,
          'backedUpAt': DateTime.now().toIso8601String(),
          'modJsonFileName': mod.jsonFileName,
        };

        debugPrint('  ✓ URL backed up: $url -> $backupFilenameForUrl');
      } else {
        debugPrint('  ✗ URL not in backup: $url');
      }
    }

    // Save all backup statuses at once (bulk operation)
    if (urlStatuses.isNotEmpty) {
      await storage.saveUrlBackupStatusBulk(urlStatuses);
      debugPrint(
          '  Saved backup status for ${urlStatuses.length} URLs to Hive');
    }
  }

  /// Scans all backups for a specific mod and updates URL backup status
  ///
  /// Useful when you have multiple backups and want to mark all URLs that
  /// exist in ANY backup
  Future<void> scanAllBackupsForMod({
    required Mod mod,
    required Map<String, BackupFileMetadata> allBackups,
  }) async {
    debugPrint(
        'Scanning all ${allBackups.length} backups for mod ${mod.saveName}...');

    for (final entry in allBackups.entries) {
      final backupFilename = entry.key;
      final backupMetadata = entry.value;

      await scanBackupForMod(
        mod: mod,
        backupFilename: backupFilename,
        backupMetadata: backupMetadata,
      );
    }

    debugPrint('Finished scanning all backups for mod ${mod.saveName}');
  }

  /// Gets backup status for all assets in a mod
  ///
  /// Returns a map of URL -> backup status info
  Future<Map<String, Map<String, dynamic>>> getBackupStatusForMod(
      Mod mod) async {
    final assets = mod.getAllAssets();
    final urls = assets.map((a) => a.url).toList();

    return storage.getUrlBackupStatusBulk(urls);
  }

  /// Checks if a specific URL is backed up
  Future<bool> isUrlBackedUp(String url) async {
    return storage.isUrlBackedUp(url);
  }

  /// Gets detailed backup info for a URL
  Future<Map<String, dynamic>?> getUrlBackupInfo(String url) async {
    return storage.getUrlBackupStatus(url);
  }

  /// Clears backup status for URLs that are no longer in any backup
  ///
  /// This is a cleanup method to remove stale data
  Future<void> cleanupStaleUrlStatuses({
    required Map<String, BackupFileMetadata> allBackups,
  }) async {
    debugPrint('Cleaning up stale URL backup statuses...');

    // Get all URLs that are currently marked as backed up
    final backedUpUrls = storage.getAllBackedUpUrls();

    debugPrint('  Found ${backedUpUrls.length} URLs marked as backed up');

    // For each backed up URL, check if it still exists in any backup
    final urlsToDelete = <String>[];

    for (final url in backedUpUrls) {
      bool foundInAnyBackup = false;

      for (final backupMetadata in allBackups.values) {
        if (BackupUrlMatcher.isUrlInBackup(url, backupMetadata)) {
          foundInAnyBackup = true;
          break;
        }
      }

      if (!foundInAnyBackup) {
        urlsToDelete.add(url);
      }
    }

    // Delete stale URLs
    if (urlsToDelete.isNotEmpty) {
      debugPrint('  Deleting ${urlsToDelete.length} stale URL statuses');
      for (final url in urlsToDelete) {
        await storage.deleteUrlBackupStatus(url);
      }
    } else {
      debugPrint('  No stale URL statuses found');
    }
  }

  /// Rescans all backups and rebuilds the URL backup status database
  ///
  /// This is useful for initial population or full refresh
  Future<void> rebuildUrlBackupStatusDatabase({
    required List<Mod> allMods,
    required Map<String, BackupFileMetadata> allBackups,
  }) async {
    debugPrint('Rebuilding URL backup status database...');
    debugPrint('  Mods: ${allMods.length}, Backups: ${allBackups.length}');

    // Clear existing data
    await storage.clearUrlBackupStatus();

    // Scan each mod against all backups
    for (final mod in allMods) {
      await scanAllBackupsForMod(
        mod: mod,
        allBackups: allBackups,
      );
    }

    debugPrint('Finished rebuilding URL backup status database');

    // Print summary
    final totalBackedUpUrls = storage.getAllBackedUpUrls().length;
    debugPrint('  Total URLs marked as backed up: $totalBackedUpUrls');
  }

  /// Debug method to print backup status for a mod
  Future<void> debugPrintBackupStatusForMod(Mod mod) async {
    debugPrint('\n=== Backup Status for Mod: ${mod.saveName} ===');

    final assets = mod.getAllAssets();
    debugPrint('Total assets: ${assets.length}');

    final backupStatusMap = await getBackupStatusForMod(mod);
    final backedUpCount =
        backupStatusMap.values.where((v) => v.isNotEmpty).length;

    debugPrint('Backed up: $backedUpCount');
    debugPrint('Not backed up: ${assets.length - backedUpCount}');

    for (final asset in assets) {
      final status = backupStatusMap[asset.url];
      if (status != null) {
        debugPrint('  ✓ ${asset.url}');
        debugPrint('    -> ${status['backupFilename']} (${status['fileSize']} bytes)');
      } else {
        debugPrint('  ✗ ${asset.url}');
      }
    }

    debugPrint('======================================\n');
  }
}
