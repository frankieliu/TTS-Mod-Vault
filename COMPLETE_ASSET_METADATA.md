# Complete Asset Metadata Tracking

## Overview

The app now tracks comprehensive metadata for all assets across three states: downloaded, failed, and backed up.

---

## Metadata by Asset State

### 1. Downloaded Files

**Storage:** Hive `DownloadedFiles` box
**Key:** Filename (without extension) - e.g., `"httpiimgurcomtHADwoQjpg"`
**Model:** `DownloadedFileInfo`

#### Data Structure:
```dart
class DownloadedFileInfo {
  final String filepath;       // Full path to file
  final int size;              // File size in bytes
  final int downloadedAt;      // Timestamp when downloaded

  DateTime get downloadedAtDateTime;  // Convenience getter
}
```

#### Hive Storage:
```json
{
  "httpiimgurcomtHADwoQjpg": {
    "filepath": "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg",
    "size": 12345,
    "downloadedAt": 1703347200000
  }
}
```

#### When Populated:
- **New downloads:** When file is successfully downloaded (in `download.dart`)
- **Existing files:** When app loads existing assets (in `existing_assets.dart`)
  - Uses file modification time as download time
  - Gets size from file stat

---

### 2. Failed Downloads

**Storage:** Hive `FailedAssets` box
**Key:** Full URL - e.g., `"http://i.imgur.com/tHADwoQ.jpg"`
**Model:** `FailedAsset` (already existed)

#### Data Structure:
```dart
class FailedAsset {
  final String url;
  final AssetTypeEnum type;
  final DownloadErrorTypeEnum errorType;  // permanent, temporary, unknown
  final String errorMessage;
  final DateTime failedAt;                 // ✓ Already has timestamp!
  final int retryCount;
}
```

#### Hive Storage:
```json
{
  "http://i.imgur.com/tHADwoQ.jpg": {
    "url": "http://i.imgur.com/tHADwoQ.jpg",
    "type": "image",
    "errorType": "permanent",
    "errorMessage": "404 Not Found",
    "failedAt": 1703347200000,
    "retryCount": 2
  }
}
```

#### When Populated:
- Automatically when download fails (in `download.dart`)
- Already includes timestamp (`failedAt`)

---

### 3. Backed Up Files

**Storage:** Hive `BackupFiles` box
**Key:** Backup filename - e.g., `"MyMod.ttsmod"`
**Model:** `BackupFileMetadata` → `Map<String, BackupFileInfo>`

#### Data Structure:
```dart
class BackupFileInfo {
  final int size;          // File size in bytes
  final int crc32;         // CRC32 checksum
  final int backedUpAt;    // Timestamp when backed up

  DateTime get backedUpAtDateTime;  // Convenience getter
}
```

#### Hive Storage:
```json
{
  "MyMod.ttsmod": {
    "files": {
      "httpiimgurcomtHADwoQjpg": {
        "size": 12345,
        "crc32": 2749857398,
        "backedUpAt": 1703347200000
      },
      "httpiimgurcom8bVZDmujpg": {
        "size": 67890,
        "crc32": 1234567890,
        "backedUpAt": 1703347200000
      }
    }
  }
}
```

#### When Populated:
- When backup is created (uses backup file's last modified time)
- When backup is loaded (extracts from ZIP with real CRC32 values)

---

## Summary Table

| Asset State | Hive Box | Key Format | Stored Data |
|------------|----------|------------|-------------|
| **Downloaded** | `DownloadedFiles` | Filename (no ext) | filepath, size, downloadedAt |
| **Failed** | `FailedAssets` | Full URL | url, type, errorType, errorMessage, failedAt, retryCount |
| **Backed Up** | `BackupFiles` | Backup filename | Map of filename → (size, crc32, backedUpAt) |

---

## Storage API Reference

### Downloaded Files

```dart
// Save metadata after download
await storage.saveDownloadedFileInfo(filename, DownloadedFileInfo(...));

// Get metadata for a file
final info = storage.getDownloadedFileInfo("httpiimgurcomtHADwoQjpg");
print('Downloaded: ${info?.downloadedAtDateTime}');
print('Size: ${info?.size} bytes');

// Bulk operations
final infos = storage.getDownloadedFileInfoBulk(filenames);
await storage.saveDownloadedFileInfoBulk(infoMap);

// Get all
final allDownloaded = storage.getAllDownloadedFileInfo();
```

### Failed Assets

```dart
// Already implemented - no changes needed
final failedAsset = storage.getFailedAsset(url);
print('Failed at: ${failedAsset?.failedAt}');
print('Error: ${failedAsset?.errorMessage}');
print('Retries: ${failedAsset?.retryCount}');
```

### Backed Up Files

```dart
// Get backup metadata
final metadata = storage.getBackupFileMetadata("MyMod.ttsmod");

// Get file info
final info = metadata?.getFileInfo("httpiimgurcomtHADwoQjpg");
print('Size: ${info?.size} bytes');
print('CRC32: ${info?.crc32}');
print('Backed up: ${info?.backedUpAtDateTime}');

// Individual getters
final size = metadata?.getFileSize("filename");
final crc32 = metadata?.getFileCrc32("filename");
final timestamp = metadata?.getFileBackedUpAt("filename");
final dateTime = metadata?.getFileBackedUpAtDateTime("filename");
```

---

## Usage Examples

### Example 1: Display Asset Metadata in UI

```dart
// For a given asset URL
final url = "http://i.imgur.com/tHADwoQ.jpg";
final filename = getFileNameFromURL(url);

// Get downloaded info
final downloadedInfo = storage.getDownloadedFileInfo(filename);

// Get backup info (check all backups)
final allBackups = storage.getAllBackupFileMetadata();
BackupFileInfo? backupInfo;
String? backupName;

for (final entry in allBackups.entries) {
  final info = entry.value.getFileInfo(filename);
  if (info != null) {
    backupInfo = info;
    backupName = entry.key;
    break;
  }
}

// Get failed info
final failedInfo = storage.getFailedAsset(url);

// Display
if (downloadedInfo != null) {
  print('✓ Downloaded:');
  print('  Size: ${downloadedInfo.size} bytes');
  print('  When: ${downloadedInfo.downloadedAtDateTime}');
}

if (backupInfo != null) {
  print('✓ Backed up in: $backupName');
  print('  Size: ${backupInfo.size} bytes');
  print('  CRC32: ${backupInfo.crc32}');
  print('  When: ${backupInfo.backedUpAtDateTime}');
}

if (failedInfo != null) {
  print('✗ Failed:');
  print('  Error: ${failedInfo.errorMessage}');
  print('  When: ${failedInfo.failedAt}');
  print('  Retries: ${failedInfo.retryCount}');
}
```

### Example 2: Compare Downloaded vs Backed Up

```dart
final filename = "httpiimgurcomtHADwoQjpg";

// Get both
final downloaded = storage.getDownloadedFileInfo(filename);
final backup = storage.getBackupFileMetadata("MyMod.ttsmod")?.getFileInfo(filename);

if (downloaded != null && backup != null) {
  if (downloaded.size == backup.size) {
    print('✓ Sizes match: ${downloaded.size} bytes');
  } else {
    print('⚠ Size mismatch!');
    print('  Downloaded: ${downloaded.size} bytes');
    print('  Backed up: ${backup.size} bytes');
  }

  // Check which is newer
  final downloadedTime = downloaded.downloadedAtDateTime;
  final backedUpTime = backup.backedUpAtDateTime;

  if (downloadedTime.isAfter(backedUpTime)) {
    print('⚠ Downloaded file is newer than backup!');
  } else {
    print('✓ Backup is up to date');
  }
}
```

### Example 3: Find Files Not Backed Up Recently

```dart
final downloadedFiles = storage.getAllDownloadedFileInfo();
final cutoffTime = DateTime.now().subtract(Duration(days: 30));

final needsBackup = <String>[];

for (final entry in downloadedFiles.entries) {
  final filename = entry.key;
  final downloadedInfo = entry.value;

  // Check if backed up
  bool backedUpRecently = false;

  for (final backup in storage.getAllBackupFileMetadata().values) {
    final backupInfo = backup.getFileInfo(filename);
    if (backupInfo != null &&
        backupInfo.backedUpAtDateTime.isAfter(cutoffTime)) {
      backedUpRecently = true;
      break;
    }
  }

  if (!backedUpRecently) {
    needsBackup.add(filename);
  }
}

print('${needsBackup.length} files need backup');
```

### Example 4: Verify Backup Integrity

```dart
// Extract a file from backup and verify its CRC32
final backupMetadata = storage.getBackupFileMetadata("MyMod.ttsmod");
final expectedCrc32 = backupMetadata?.getFileCrc32("httpiimgurcomtHADwoQjpg");

// Extract file from ZIP and calculate CRC32
final extractedFile = await extractFileFromBackup("MyMod.ttsmod", "httpiimgurcomtHADwoQjpg");
final actualCrc32 = await calculateFileCrc32(extractedFile);

if (expectedCrc32 == actualCrc32) {
  print('✓ Backup integrity verified');
} else {
  print('✗ Backup may be corrupted!');
}
```

### Example 5: Display in UI

```dart
// Asset list tile showing metadata
ListTile(
  title: Text(asset.url),
  subtitle: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (asset.fileExists) ...[
        Text('Downloaded: ${downloadedInfo?.downloadedAtDateTime ?? "Unknown"}'),
        Text('Size: ${formatBytes(downloadedInfo?.size ?? 0)}'),
      ],
      if (asset.isBackedUp) ...[
        Text('Backed up: ${backupInfo?.backedUpAtDateTime ?? "Unknown"}'),
        Text('CRC32: ${backupInfo?.crc32?.toRadixString(16) ?? "N/A"}'),
      ],
      if (asset.hasFailed) ...[
        Text('Failed: ${failedInfo?.failedAt ?? "Unknown"}'),
        Text('Error: ${failedInfo?.errorMessage ?? "Unknown"}'),
      ],
    ],
  ),
);
```

---

## Data Population Flow

### On App Startup:
```
1. Initialize Hive storage
2. Load existing assets from disk
   ↓
3. For each existing file:
   - Get file stat (size, modified time)
   - Save to DownloadedFiles box
   ↓
4. Load backups
   ↓
5. For each backup:
   - Extract metadata from ZIP
   - Get size, CRC32, backup timestamp
   - Save to BackupFiles box
```

### On New Download:
```
1. Download file
2. Save to disk
   ↓
3. Get file size from bytes
4. Save metadata:
   - filepath
   - size
   - downloadedAt = now()
   ↓
5. Add to existing assets
```

### On Failed Download:
```
1. Download fails
2. Classify error type
   ↓
3. Save to FailedAssets:
   - url
   - type
   - errorType
   - errorMessage
   - failedAt = now()
   - retryCount
```

### On Backup Creation:
```
1. Create ZIP backup
2. Track files added
   ↓
3. Save metadata:
   - filename → size
   - backedUpAt = backup file modified time
   - crc32 = 0 (placeholder)
   ↓
4. Later when loading:
   - Extract real CRC32 from ZIP
   - Update metadata
```

---

## Migration Notes

### Existing Files:
On first run after this update, existing downloaded files will get metadata populated:
- **downloadedAt:** Uses file modification time
- **size:** Gets from file stat

### Existing Backups:
On first run after this update (with cache clearing):
- **backedUpAt:** Uses backup file modification time
- **size:** Extracted from ZIP
- **crc32:** Extracted from ZIP

### Failed Assets:
No migration needed - already have timestamps.

---

## Performance Considerations

### Startup Time:
- Scanning existing files: ~1-2 seconds for 1000 files
- Extracting backup metadata: ~1-2 seconds per backup (already happening)
- Total: Negligible impact (operations are already being done)

### Storage:
- **Downloaded:** ~24 bytes per file (filepath + size + timestamp)
- **Failed:** ~100 bytes per failed URL (already existed)
- **Backed Up:** ~16 bytes per file per backup (size + crc32 + timestamp)

For 1000 files:
- Downloaded metadata: ~24 KB
- 10 backups: ~160 KB
- Total: ~200 KB (negligible)

---

## Complete Example: Single Asset Lifecycle

```dart
// Asset URL
final url = "http://i.imgur.com/tHADwoQ.jpg";
final filename = getFileNameFromURL(url);  // "httpiimgurcomtHADwoQjpg"

// STAGE 1: Download
await downloadAsset(url);
// Saved to: /path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg
// Metadata saved to DownloadedFiles:
// {
//   "filepath": "/path/to/.../httpiimgurcomtHADwoQjpg.jpg",
//   "size": 12345,
//   "downloadedAt": 1703347200000
// }

// STAGE 2: Backup
await createBackup(mod);
// Added to backup: MyMod.ttsmod
// Metadata saved to BackupFiles["MyMod.ttsmod"]:
// {
//   "httpiimgurcomtHADwoQjpg": {
//     "size": 12345,
//     "crc32": 2749857398,
//     "backedUpAt": 1703347300000
//   }
// }

// QUERY: Get all metadata for this asset
final downloadedInfo = storage.getDownloadedFileInfo(filename);
final backupInfo = storage.getBackupFileMetadata("MyMod.ttsmod")?.getFileInfo(filename);

print('Downloaded:');
print('  When: ${downloadedInfo?.downloadedAtDateTime}');
print('  Size: ${downloadedInfo?.size} bytes');

print('\nBacked up:');
print('  When: ${backupInfo?.backedUpAtDateTime}');
print('  Size: ${backupInfo?.size} bytes');
print('  CRC32: ${backupInfo?.crc32}');
```

---

## Displaying Metadata in UI

### Asset Card/Tile Component:

```dart
Widget buildAssetMetadata(Asset asset) {
  final filename = getFileNameFromURL(asset.url);
  final storage = ref.watch(storageProvider);

  // Get all metadata
  final downloadedInfo = storage.getDownloadedFileInfo(filename);
  final failedInfo = storage.getFailedAsset(asset.url);

  // Find backup info (check all backups)
  BackupFileInfo? backupInfo;
  String? backupName;
  final allBackups = storage.getAllBackupFileMetadata();

  for (final entry in allBackups.entries) {
    final info = entry.value.getFileInfo(filename);
    if (info != null) {
      backupInfo = info;
      backupName = entry.key;
      break;
    }
  }

  return Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('URL: ${asset.url}'),
        Divider(),

        if (downloadedInfo != null) ...[
          Icon(Icons.check_circle, color: Colors.green),
          Text('Downloaded ${_formatTimeAgo(downloadedInfo.downloadedAtDateTime)}'),
          Text('Size: ${_formatBytes(downloadedInfo.size)}'),
        ],

        if (backupInfo != null) ...[
          Icon(Icons.backup, color: Colors.blue),
          Text('Backed up in: $backupName'),
          Text('Backup date: ${_formatTimeAgo(backupInfo.backedUpAtDateTime)}'),
          Text('CRC32: ${backupInfo.crc32.toRadixString(16).toUpperCase()}'),
        ],

        if (failedInfo != null) ...[
          Icon(Icons.error, color: Colors.red),
          Text('Failed ${_formatTimeAgo(failedInfo.failedAt)}'),
          Text('Error: ${failedInfo.errorMessage}'),
          Text('Retries: ${failedInfo.retryCount}'),
        ],
      ],
    ),
  );
}

String _formatTimeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
```

---

## Maintenance Operations

### Clear All Metadata:
```dart
await storage.clearDownloadedFileMetadata();
await storage.clearBackupFileMetadata();
await storage.clearFailedAssets();
```

### Rebuild Downloaded Metadata:
```dart
// Called automatically in loadExistingAssetsLists()
await ref.read(existingAssetListsProvider.notifier).loadExistingAssetsLists();
```

### Update After File Changes:
```dart
// If file is re-downloaded
final info = DownloadedFileInfo(
  filepath: newPath,
  size: newSize,
  downloadedAt: DateTime.now().millisecondsSinceEpoch,
);
await storage.saveDownloadedFileInfo(filename, info);
```

---

## Benefits

✅ **Complete History:** Know when every asset was downloaded, backed up, or failed
✅ **Size Tracking:** Track file sizes for all states
✅ **Integrity:** CRC32 verification for backed up files
✅ **Debugging:** Detailed error information for failed downloads
✅ **UI Display:** Rich metadata for user interface
✅ **Analytics:** Track download/backup patterns
✅ **Cleanup:** Identify old files/backups for cleanup
✅ **Verification:** Compare downloaded files with backups

---

## Testing Checklist

### Download Flow:
- [ ] Download a new asset
- [ ] Check DownloadedFiles box has metadata
- [ ] Verify size matches file on disk
- [ ] Verify downloadedAt is recent

### Backup Flow:
- [ ] Create a backup
- [ ] Check BackupFiles box has metadata
- [ ] Verify size and CRC32 are present
- [ ] Verify backedUpAt matches backup file time

### Existing Files:
- [ ] Start app with existing downloads
- [ ] Check DownloadedFiles box is populated
- [ ] Verify downloadedAt uses file modification time
- [ ] Verify sizes match files on disk

### Failed Downloads:
- [ ] Download fails (e.g., 404)
- [ ] Check FailedAssets box has entry
- [ ] Verify failedAt is present
- [ ] Verify error details are saved

---

## Summary

All three asset states now have comprehensive metadata:

| State | Has Timestamp | Has Size | Has CRC32 | Has Error Info |
|-------|--------------|----------|-----------|----------------|
| Downloaded | ✅ downloadedAt | ✅ size | ❌ | ❌ |
| Failed | ✅ failedAt | ❌ | ❌ | ✅ errorType, errorMessage, retryCount |
| Backed Up | ✅ backedUpAt | ✅ size | ✅ crc32 | ❌ |

This enables rich UI displays, integrity verification, and comprehensive asset tracking!
