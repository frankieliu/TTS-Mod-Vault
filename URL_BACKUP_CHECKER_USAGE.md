# Using UrlBackupChecker

## Quick Example

```dart
import 'package:tts_mod_vault/src/state/backup/url_backup_checker.dart';

// You already have:
Set<String> backedUpFiles; // Your set of 1488 filenames from backup
List<Asset> assets; // Your list of assets

// Check each asset individually
for (final asset in assets) {
  final isBackedUp = UrlBackupChecker.isUrlBackedUp(asset.url, backedUpFiles);

  print('Asset URL: ${asset.url}');
  print('  Converted filename: ${getFileNameFromURL(asset.url)}');
  print('  Is backed up: $isBackedUp');

  if (isBackedUp) {
    // Get the actual matching filename
    final matchingFile = UrlBackupChecker.getMatchingBackupFilename(
      asset.url,
      backedUpFiles
    );
    print('  Matches backup file: $matchingFile');
  }
}

// OR: Batch check all URLs at once (more efficient)
final urls = assets.map((a) => a.url).toList();
final backupStatus = UrlBackupChecker.checkUrlsBatch(urls, backedUpFiles);

for (final asset in assets) {
  final isBackedUp = backupStatus[asset.url] ?? false;
  print('${asset.url}: ${isBackedUp ? "✓ Backed up" : "✗ Not backed up"}');
}
```

## Debug a specific URL

```dart
// If a URL is not matching, use the debug helper:
final url = "http://chryme.up.me/meflag5.unity3d";

UrlBackupChecker.debugUrlMatching(url, backedUpFiles, sampleSize: 10);
```

This will print:
- The original URL
- The converted filename
- Any matches found
- Sample files from the backup
- Partial matches to help diagnose issues

## Example based on your log

```dart
// Asset #1 from your log
final url1 = "http://chryme.up.me/meflag5.unity3d";
final isBackedUp1 = UrlBackupChecker.isUrlBackedUp(url1, backedUpFiles);
// Converted filename: "httpchrymeupmemeflag5unity3d"
// Checks if any file in backedUpFiles STARTS WITH "httpchrymeupmemeflag5unity3d"

// Asset #2 from your log
final url2 = "http://i.imgur.com/tHADwoQ.jpg";
final isBackedUp2 = UrlBackupChecker.isUrlBackedUp(url2, backedUpFiles);
// Converted filename: "httpiimgurcomtHADwoQjpg"
// Checks if any file in backedUpFiles STARTS WITH "httpiimgurcomtHADwoQjpg"

// Asset #3 from your log
final url3 = "http://i.imgur.com/8bVZDmu.jpg";
final isBackedUp3 = UrlBackupChecker.isUrlBackedUp(url3, backedUpFiles);
// Converted filename: "httpiimgurcom8bVZDmujpg"
// Checks if any file in backedUpFiles STARTS WITH "httpiimgurcom8bVZDmujpg"
```

## Important: The key is using `startsWith()`

The backed up files might have extensions or additional characters, so we check if any backed up file **starts with** the converted URL filename:

```dart
// Your converted URL filename
final urlFilename = "httpiimgurcomtHADwoQjpg";

// Backed up files might be:
// - "httpiimgurcomtHADwoQjpg.jpg"  ← Matches! (starts with the URL filename)
// - "httpiimgurcomtHADwoQjpgextra" ← Also matches!
// - "httpiimgurcomOTHERFILE.jpg"   ← Doesn't match

// Check:
for (final backedUpFile in backedUpFiles) {
  if (backedUpFile.startsWith(urlFilename)) {
    return true; // Found a match!
  }
}
```

## Replace your current code

If you have code like this:
```dart
// ❌ This won't work (exact match)
final isBackedUp = backedUpFiles.contains(filename);
```

Replace it with:
```dart
// ✓ This will work (starts with)
final isBackedUp = UrlBackupChecker.isUrlBackedUp(url, backedUpFiles);
```
