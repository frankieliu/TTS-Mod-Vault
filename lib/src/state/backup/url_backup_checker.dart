import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL;

/// Simple utility to check if a URL's file exists in a set of backed up filenames
class UrlBackupChecker {
  /// Checks if a URL is backed up by seeing if any backed up file starts with the URL's filename
  ///
  /// [url] - The asset URL to check
  /// [backedUpFiles] - Set of filenames (without extensions) from the backup
  ///
  /// Returns true if any backed up file starts with the converted URL filename
  static bool isUrlBackedUp(String url, Set<String> backedUpFiles) {
    // Convert URL to filename (removes all non-alphanumeric chars)
    final urlFilename = getFileNameFromURL(url);

    // Check if any backed up file starts with this URL's filename
    for (final backedUpFile in backedUpFiles) {
      if (backedUpFile.startsWith(urlFilename)) {
        return true;
      }
    }

    return false;
  }

  /// Batch version - checks multiple URLs at once
  ///
  /// Returns a Map of URL -> isBackedUp
  static Map<String, bool> checkUrlsBatch(
      List<String> urls, Set<String> backedUpFiles) {
    final result = <String, bool>{};

    for (final url in urls) {
      result[url] = isUrlBackedUp(url, backedUpFiles);
    }

    return result;
  }

  /// Gets the actual backed up filename that matches a URL
  ///
  /// Returns the matching filename if found, null otherwise
  static String? getMatchingBackupFilename(
      String url, Set<String> backedUpFiles) {
    final urlFilename = getFileNameFromURL(url);

    for (final backedUpFile in backedUpFiles) {
      if (backedUpFile.startsWith(urlFilename)) {
        return backedUpFile;
      }
    }

    return null;
  }

  /// Debug helper - prints why a URL might not be matching
  static void debugUrlMatching(String url, Set<String> backedUpFiles,
      {int sampleSize = 5}) {
    final urlFilename = getFileNameFromURL(url);

    print('\n=== URL Backup Matching Debug ===');
    print('Original URL: $url');
    print('Converted filename: $urlFilename');
    print('Total backed up files: ${backedUpFiles.length}');

    // Check for any matches
    final matches = backedUpFiles
        .where((file) => file.startsWith(urlFilename))
        .toList();

    if (matches.isNotEmpty) {
      print('✓ MATCHES FOUND: ${matches.length}');
      for (final match in matches) {
        print('  - $match');
      }
    } else {
      print('✗ NO MATCHES FOUND');

      // Show some samples
      print('\nSample backed up files:');
      final samples = backedUpFiles.take(sampleSize).toList();
      for (final sample in samples) {
        print('  - $sample');
      }

      // Check for partial matches (files that contain part of the URL filename)
      print('\nPartial matches (backed up files containing any part):');
      final partialMatches = backedUpFiles
          .where((file) =>
              file.contains(urlFilename.substring(
                  0, urlFilename.length > 10 ? 10 : urlFilename.length)) ||
              urlFilename.contains(
                  file.substring(0, file.length > 10 ? 10 : file.length)))
          .take(5)
          .toList();

      if (partialMatches.isEmpty) {
        print('  (none found)');
      } else {
        for (final partial in partialMatches) {
          print('  - $partial');
        }
      }
    }

    print('================================\n');
  }
}
