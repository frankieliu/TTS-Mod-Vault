import 'package:flutter/material.dart' show debugPrint;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart';
import 'package:tts_mod_vault/src/state/backup/models/backup_file_metadata.dart';
import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL;
import 'package:path/path.dart' as p;

/// Service for matching asset URLs to files in backups
class BackupUrlMatcher {
  /// Checks if a URL's corresponding file exists in a backup
  ///
  /// Converts the URL to a filename using [getFileNameFromURL] and checks
  /// if any file in the backup metadata starts with that converted filename
  ///
  /// Returns true if the file exists in the backup, false otherwise
  static bool isUrlInBackup(String url, BackupFileMetadata backupMetadata) {
    // Convert URL to filename (removes all non-alphanumeric characters)
    final urlAsFilename = getFileNameFromURL(url);

    debugPrint(
        'Checking if URL is in backup: url=$url, converted=$urlAsFilename');

    // Check if any file in the backup starts with this filename
    // We use startsWith because the file may have an extension
    for (final backupFilename in backupMetadata.files.keys) {
      final backupFilenameWithoutExt =
          p.basenameWithoutExtension(backupFilename);

      if (backupFilenameWithoutExt.startsWith(urlAsFilename)) {
        debugPrint(
            '  ✓ Found match: $backupFilename (without ext: $backupFilenameWithoutExt)');
        return true;
      }
    }

    debugPrint('  ✗ No match found in backup');
    return false;
  }

  /// Gets the actual filename in the backup that corresponds to a URL
  ///
  /// Returns the full filename (with extension) if found, null otherwise
  static String? getBackupFilenameForUrl(
      String url, BackupFileMetadata backupMetadata) {
    final urlAsFilename = getFileNameFromURL(url);

    for (final backupFilename in backupMetadata.files.keys) {
      final backupFilenameWithoutExt =
          p.basenameWithoutExtension(backupFilename);

      if (backupFilenameWithoutExt.startsWith(urlAsFilename)) {
        return backupFilename;
      }
    }

    return null;
  }

  /// Checks multiple URLs against a backup and returns a map of URL -> isInBackup
  ///
  /// This is more efficient than calling [isUrlInBackup] multiple times
  /// as it only iterates through the backup files once
  static Map<String, bool> checkUrlsInBackup(
      List<String> urls, BackupFileMetadata backupMetadata) {
    final result = <String, bool>{};

    // Convert all URLs to filenames once
    final urlToFilename = <String, String>{};
    for (final url in urls) {
      urlToFilename[url] = getFileNameFromURL(url);
    }

    // Check each backup file against all URLs
    final backupFilenamesWithoutExt = <String>{};
    for (final backupFilename in backupMetadata.files.keys) {
      backupFilenamesWithoutExt
          .add(p.basenameWithoutExtension(backupFilename));
    }

    // Mark URLs as backed up if their filename exists in backup
    for (final entry in urlToFilename.entries) {
      final url = entry.key;
      final urlFilename = entry.value;

      // Check if any backup filename starts with this URL's filename
      final isInBackup = backupFilenamesWithoutExt
          .any((backupFile) => backupFile.startsWith(urlFilename));

      result[url] = isInBackup;
    }

    return result;
  }

  /// Checks all assets in a list and returns updated Asset objects with isBackedUp set
  ///
  /// This is useful for updating asset states based on backup metadata
  static List<Asset> markAssetsAsBackedUp(
      List<Asset> assets, BackupFileMetadata backupMetadata) {
    final urls = assets.map((a) => a.url).toList();
    final backupStatus = checkUrlsInBackup(urls, backupMetadata);

    return assets.map((asset) {
      final isBackedUp = backupStatus[asset.url] ?? false;
      return Asset(
        url: asset.url,
        fileExists: asset.fileExists,
        filePath: asset.filePath,
        hasFailed: asset.hasFailed,
        errorType: asset.errorType,
        isBackedUp: isBackedUp,
      );
    }).toList();
  }

  /// Debug helper to print detailed matching information
  static void debugPrintUrlMatching(
      String url, BackupFileMetadata backupMetadata) {
    final urlAsFilename = getFileNameFromURL(url);

    debugPrint('\n=== URL Matching Debug ===');
    debugPrint('Original URL: $url');
    debugPrint('Converted filename: $urlAsFilename');
    debugPrint('\nBackup files:');

    for (final backupFilename in backupMetadata.files.keys) {
      final backupFilenameWithoutExt =
          p.basenameWithoutExtension(backupFilename);
      final matches = backupFilenameWithoutExt.startsWith(urlAsFilename);

      debugPrint(
          '  ${matches ? "✓" : "✗"} $backupFilename (without ext: $backupFilenameWithoutExt)');
    }

    debugPrint('========================\n');
  }
}
