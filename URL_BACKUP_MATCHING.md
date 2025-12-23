# URL to Backup File Matching

## Overview

This system matches asset URLs from the mod JSON to actual files in backup archives, and stores this mapping in Hive for quick lookup.

## Problem

When a mod is backed up, the asset URLs (like `https://steamusercontent.com/ugc/123/image.jpg`) are stored in the JSON, but the actual files in the backup have sanitized filenames (like `httpssteamusercontentcomugc123imagejpg.jpg`).

We need to:
1. Convert URLs to their expected filenames
2. Find those files in the backup
3. Mark which URLs are backed up

## Solution Components

### 1. BackupUrlMatcher (`backup_url_matcher.dart`)

Utility class that matches URLs to files in backups.

**Key Method:**
```dart
bool isUrlInBackup(String url, BackupFileMetadata backupMetadata)
```

**How it works:**
1. Converts URL using `getFileNameFromURL()` - removes all non-alphanumeric characters
2. Checks if any file in the backup starts with that converted filename
3. Returns true if found

**Example:**
```dart
final url = "https://steamusercontent.com/ugc/123/dragon.obj";
final urlFilename = getFileNameFromURL(url);
// Result: "httpssteamusercontentcomugc123dragonobj"

// Backup contains: "httpssteamusercontentcomugc123dragonobj.obj"
final isInBackup = BackupUrlMatcher.isUrlInBackup(url, backupMetadata);
// Result: true (because filename matches)
```

### 2. Storage Methods (`storage.dart`)

Added to the `Storage` class:

**New Hive Box:** `UrlBackupStatus`
- Key: URL string
- Value: JSON with backup info

**Methods:**
```dart
// Save backup status for a URL
Future<void> saveUrlBackupStatus(String url, Map<String, dynamic> status)

// Get backup status for a URL
Map<String, dynamic>? getUrlBackupStatus(String url)

// Check if URL is backed up
bool isUrlBackedUp(String url)

// Bulk operations
Future<void> saveUrlBackupStatusBulk(Map<String, Map<String, dynamic>> urlStatuses)
Map<String, Map<String, dynamic>> getUrlBackupStatusBulk(List<String> urls)
```

**Stored Data Format:**
```json
{
  "backupFilename": "MyMod.ttsmod",
  "fileSize": 2048000,
  "backedUpAt": "2025-12-23T10:30:00Z",
  "modJsonFileName": "123456789"
}
```

### 3. BackupUrlStatusService (`backup_url_status_service.dart`)

High-level service that orchestrates the matching and storage.

**Main Methods:**

#### Scan a single backup for a mod
```dart
await service.scanBackupForMod(
  mod: mod,
  backupFilename: 'MyMod.ttsmod',
  backupMetadata: backupMetadata,
);
```

#### Get backup status for all assets in a mod
```dart
final statusMap = await service.getBackupStatusForMod(mod);
// Returns: Map<String, Map<String, dynamic>> (URL -> backup info)
```

#### Rebuild entire database
```dart
await service.rebuildUrlBackupStatusDatabase(
  allMods: allMods,
  allBackups: allBackups,
);
```

## Usage Examples

### Example 1: Check if a mod's assets are backed up

```dart
import 'package:tts_mod_vault/src/state/backup/backup_url_status_service.dart';

// Initialize service
final service = BackupUrlStatusService(storage);

// Get backup status for a mod
final statusMap = await service.getBackupStatusForMod(mod);

// Check each asset
for (final asset in mod.getAllAssets()) {
  final backupInfo = statusMap[asset.url];

  if (backupInfo != null) {
    print('✓ ${asset.url} is backed up in ${backupInfo['backupFilename']}');
  } else {
    print('✗ ${asset.url} is NOT backed up');
  }
}
```

### Example 2: Populate backup status when loading backups

```dart
// In existing_backups.dart or similar

Future<void> loadExistingBackups() async {
  // ... existing code to load backups ...

  // After loading backups, populate URL backup status
  final service = BackupUrlStatusService(storage);

  for (final backup in state.backups) {
    final metadata = storage.getBackupFileMetadata(backup.filename);
    if (metadata != null) {
      // Find the mod that corresponds to this backup
      final mod = findModForBackup(backup);

      if (mod != null) {
        await service.scanBackupForMod(
          mod: mod,
          backupFilename: backup.filename,
          backupMetadata: metadata,
        );
      }
    }
  }
}
```

### Example 3: Update Asset model with backup status

```dart
// When building assets for a mod

List<Asset> buildAssetsWithBackupStatus(Mod mod) {
  final assets = mod.getAllAssets();

  // Get backup status from Hive
  final backupStatusMap = storage.getUrlBackupStatusBulk(
    assets.map((a) => a.url).toList()
  );

  // Create new Asset objects with isBackedUp set
  return assets.map((asset) {
    final isBackedUp = backupStatusMap.containsKey(asset.url);

    return Asset(
      url: asset.url,
      fileExists: asset.fileExists,
      filePath: asset.filePath,
      hasFailed: asset.hasFailed,
      errorType: asset.errorType,
      isBackedUp: isBackedUp, // Set from Hive data
    );
  }).toList();
}
```

### Example 4: Debug a specific URL matching

```dart
final url = "https://steamusercontent.com/ugc/123/image.jpg";

// Check what filename it converts to
final filename = getFileNameFromURL(url);
print('URL converts to: $filename');

// Check if it's in a specific backup
final backupMetadata = storage.getBackupFileMetadata('MyMod.ttsmod');
if (backupMetadata != null) {
  BackupUrlMatcher.debugPrintUrlMatching(url, backupMetadata);
}

// Check Hive storage
final backupInfo = storage.getUrlBackupStatus(url);
if (backupInfo != null) {
  print('Stored in Hive: $backupInfo');
} else {
  print('Not found in Hive');
}
```

## Integration Points

### 1. When backups are loaded
Call `scanBackupForMod()` to populate Hive with URL backup status.

### 2. When mods are loaded
Query Hive using `getUrlBackupStatusBulk()` to get backup status for all asset URLs.

### 3. In UI
Use the `isBackedUp` field in Asset model to show backup indicators.

### 4. When backups are created/deleted
Update Hive storage to reflect the new backup state.

## Data Flow

```
1. User loads backup list
   ↓
2. For each backup:
   - Extract file metadata (filename → size)
   - Get associated mod
   - Call scanBackupForMod()
   ↓
3. scanBackupForMod:
   - Gets all asset URLs from mod
   - Converts each URL to filename
   - Checks if filename exists in backup
   - Saves results to Hive
   ↓
4. Later, when displaying mod assets:
   - Query Hive for URL backup status
   - Update Asset.isBackedUp field
   - Display backup indicator in UI
```

## URL to Filename Conversion

The key function is `getFileNameFromURL()` in `utils.dart`:

```dart
String getFileNameFromURL(String url) {
  // Keep only letters and numbers, remove everything else
  return url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
}
```

**Examples:**
```
https://example.com/image.jpg
→ httpsexamplecomimagejpg

http://cloud-3.steamusercontent.com/ugc/12345/dragon.obj
→ httpcloud3steamusercontentcomugc12345dragonobj

https://steamusercontent-a.akamaihd.net/ugc/789/texture.png
→ httpssteamusercontentaakamaihd789texturepng
```

## Performance Considerations

1. **Bulk operations** - Use `saveUrlBackupStatusBulk()` instead of saving one at a time
2. **Lazy loading** - Only scan backups when needed
3. **Caching** - Hive provides fast in-memory access after initial load
4. **Background processing** - Run `rebuildUrlBackupStatusDatabase()` in background/isolate

## Maintenance

### Clean up stale data
```dart
await service.cleanupStaleUrlStatuses(allBackups: allBackups);
```

### Rebuild from scratch
```dart
await service.rebuildUrlBackupStatusDatabase(
  allMods: allMods,
  allBackups: allBackups,
);
```

## Testing

### Test URL matching
```dart
test('URL converts to correct filename', () {
  final url = "https://example.com/image.jpg";
  final filename = getFileNameFromURL(url);
  expect(filename, equals("httpsexamplecomimagejpg"));
});

test('URL is found in backup', () {
  final metadata = BackupFileMetadata(files: {
    'httpsexamplecomimagejpg.jpg': 12345,
  });

  final isInBackup = BackupUrlMatcher.isUrlInBackup(
    "https://example.com/image.jpg",
    metadata,
  );

  expect(isInBackup, isTrue);
});
```

## Summary

This system provides a way to:
- ✅ Convert URLs to their sanitized filenames
- ✅ Match URLs to files in backups
- ✅ Store URL backup status in Hive for quick lookup
- ✅ Update Asset models with backup status
- ✅ Efficiently handle bulk operations
- ✅ Debug and maintain the backup status data
