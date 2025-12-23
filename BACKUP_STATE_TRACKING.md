# Backup State Tracking Feature

## Overview

This feature adds the ability to track which assets have been backed up, independent of whether they're currently downloaded or their download URLs are still valid. This is critical because:

1. **URLs are ephemeral** - Workshop URLs can go stale over time
2. **Preserve backup information** - We don't want to lose knowledge of backed up data
3. **Smart backup decisions** - Know which assets need backing up vs which are already safe

## Asset States

Assets can now be in one of several states:

- **Downloaded** (`fileExists=true`) - File exists on disk (Green ✓)
- **Backed Up** (`isBackedUp=true`) - File is in at least one backup (new state)
- **Failed** (`hasFailed=true`, `fileExists=false`) - Download failed, not on disk
  - Permanent failure (Red ✗)
  - Temporary failure (Orange ⚠)
- **Missing** (`fileExists=false`, `hasFailed=false`, `isBackedUp=false`) - Not downloaded, not failed, not backed up (White ○)

**Important:** These states are NOT mutually exclusive:
- An asset can be both downloaded AND backed up
- An asset can be backed up but NOT downloaded (file was deleted but we have backup)
- An asset can have failed but still be backed up (URL went bad after backup was made)

## Implementation Plan

### Phase 1: Data Models ✅ COMPLETED

#### 1.1 Asset Model Update
**File:** `lib/src/state/asset/models/asset_model.dart`

```dart
class Asset {
  final String url;
  final bool fileExists;
  final String? filePath;
  final bool hasFailed;
  final DownloadErrorTypeEnum? errorType;
  final bool isBackedUp;  // NEW FIELD

  Asset({
    required this.url,
    required this.fileExists,
    this.filePath,
    this.hasFailed = false,
    this.errorType,
    this.isBackedUp = false,  // DEFAULT FALSE
  });
}
```

#### 1.2 Backup File Metadata Model
**File:** `lib/src/state/backup/models/backup_file_metadata.dart` (NEW FILE)

```dart
class BackupFileMetadata {
  // Map of filename (basename) -> size in bytes
  final Map<String, int> files;

  BackupFileMetadata({required this.files});
  BackupFileMetadata.empty() : files = {};

  Map<String, dynamic> toJson();
  factory BackupFileMetadata.fromJson(Map<String, dynamic> json);

  bool containsFile(String filename);
  int? getFileSize(String filename);
  int get totalFiles => files.length;
}
```

**Why filename → size?**
- Simple and lightweight
- Enables quick lookups: O(1) to check if file is backed up
- Size can be used for future comparison/validation

### Phase 2: Storage Layer ✅ COMPLETED

#### 2.1 Hive Storage Setup
**File:** `lib/src/state/storage/storage.dart`

Added new Hive box for backup file metadata:

```dart
class Storage {
  late Box<String> _backupFilesBox;
  static const String backupFilesBox = 'BackupFiles';

  Future<void> initializeStorage() async {
    _backupFilesBox = await Hive.openBox<String>(backupFilesBox);
  }

  // Storage methods
  Future<void> saveBackupFileMetadata(String backupFilename, BackupFileMetadata metadata);
  BackupFileMetadata? getBackupFileMetadata(String backupFilename);
  Future<void> deleteBackupFileMetadata(String backupFilename);
  Map<String, BackupFileMetadata> getAllBackupFileMetadata();
  Future<void> clearBackupFileMetadata();
}
```

**Storage structure:**
- Key: Backup filename (e.g., "Cool Map (123456789).ttsmod")
- Value: JSON-encoded BackupFileMetadata

### Phase 3: Backup Creation ✅ COMPLETED

#### 3.1 Capture Metadata During Backup
**File:** `lib/src/state/backup/backup_state.dart`

Updated `BackupCompleteMessage` to carry file metadata:

```dart
class BackupCompleteMessage extends BackupMessage {
  final bool success;
  final String message;
  final Map<String, int>? fileMetadata; // filename -> size

  BackupCompleteMessage(this.success, this.message, [this.fileMetadata]);
}
```

#### 3.2 Extract Metadata in Backup Isolate
**File:** `lib/src/state/backup/backup.dart`

Modified `_backupIsolate` to track files as they're added:

```dart
void _backupIsolate(BackupIsolateData data) async {
  final encoder = ZipFileEncoder();
  encoder.create(data.targetBackupFilePath);

  final Map<String, int> fileMetadata = {}; // Track files

  for (final filePath in data.filePaths) {
    // ... add file to zip ...

    // Record metadata
    final stat = await file.stat();
    final filename = p.basename(filePath);
    fileMetadata[filename] = stat.size;
  }

  await encoder.close();

  // Send metadata back
  data.sendPort.send(BackupCompleteMessage(
    true,
    'Backup created',
    fileMetadata, // INCLUDE METADATA
  ));
}
```

#### 3.3 Save Metadata to Storage
**File:** `lib/src/state/backup/backup.dart` in `createBackup` method

```dart
if (message.success) {
  // Add backup to state
  ref.read(existingBackupsProvider.notifier).addBackup(newBackup);

  // Save file metadata to Hive
  if (message.fileMetadata != null) {
    final metadata = BackupFileMetadata(files: message.fileMetadata!);
    await ref.read(storageProvider).saveBackupFileMetadata(backupFileName, metadata);
  }
}
```

### Phase 4: Backup Loading ✅ COMPLETED

#### 4.1 Extract Metadata from Existing Backups
**File:** `lib/src/state/backup/existing_backups.dart`

Modified `_processBackupFiles` to extract file lists from zip archives:

```dart
Future<List<(ExistingBackup, BackupFileMetadata?)>> _processBackupFiles(
    List<File> files) async {
  final results = <(ExistingBackup, BackupFileMetadata?)>[];

  for (final file in files) {
    // Extract metadata from zip
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final Map<String, int> filesMap = {};
    for (final zipFile in archive.files) {
      if (!zipFile.isFile) continue;
      final name = path.basename(zipFile.name);
      filesMap[name] = zipFile.size;
    }

    final metadata = BackupFileMetadata(files: filesMap);
    final backup = ExistingBackup(/* ... */);

    results.add((backup, metadata));
  }

  return results;
}
```

#### 4.2 Save Metadata During Load
**File:** `lib/src/state/backup/existing_backups.dart` in `loadExistingBackups`

```dart
final results = await Future.wait(futures);
final backups = results.expand((list) => list.map((r) => r.$1)).toList();

// Save file metadata to storage
for (final result in results) {
  for (final (backup, metadata) in result) {
    if (metadata != null) {
      await ref.read(storageProvider).saveBackupFileMetadata(
        backup.filename,
        metadata
      );
    }
  }
}
```

#### 4.3 Aggregate Provider
**File:** `lib/src/state/provider.dart`

Created provider to aggregate all backed up files across all backups:

```dart
final backedUpFilesProvider = Provider<Set<String>>((ref) {
  final storage = ref.watch(storageProvider);
  final allBackupMetadata = storage.getAllBackupFileMetadata();

  final Set<String> backedUpFiles = {};
  for (final metadata in allBackupMetadata.values) {
    backedUpFiles.addAll(metadata.files.keys);
  }

  return backedUpFiles;
});
```

**How it works:**
- Watches storage for all backup metadata
- Aggregates filenames from ALL backups into one Set
- If a file appears in ANY backup, it's considered backed up
- Returns Set<String> for O(1) lookup

---

## REMAINING WORK

### Phase 5: Asset Building Integration ⚠️ TODO

#### 5.1 Update IsolateWorkData
**File:** `lib/src/state/mods/mods_isolates.dart`

Add backed up files to isolate data:

```dart
class IsolateWorkData {
  final List<List<Mod>> batches;
  final Map<String, String?> cachedDateTimeStamps;
  final Map<String, Map<String, String>?> cachedAssetLists;
  final bool ignoreAudioAssets;
  // Existing asset maps
  final Map<String, String> existingAssetBundles;
  final Map<String, String> existingAudio;
  final Map<String, String> existingImages;
  final Map<String, String> existingModels;
  final Map<String, String> existingPdf;
  // Failed assets map
  final Map<String, String> failedAssets;
  // NEW: Backed up files set
  final Set<String> backedUpFiles;  // ADD THIS

  IsolateWorkData({
    required this.batches,
    required this.cachedDateTimeStamps,
    required this.cachedAssetLists,
    required this.ignoreAudioAssets,
    required this.existingAssetBundles,
    required this.existingAudio,
    required this.existingImages,
    required this.existingModels,
    required this.existingPdf,
    required this.failedAssets,
    required this.backedUpFiles,  // ADD THIS
  });
}
```

#### 5.2 Pass Backed Up Files to Isolate
**File:** `lib/src/state/mods/mods.dart` in mod loading

Around line 178, where `IsolateWorkData` is created:

```dart
// Get backed up files
final backedUpFiles = ref.read(backedUpFilesProvider);

final List<IsolateWorkData> isolateWorkData =
    batchesPerIsolate.map((batches) {
  final allModsForIsolate = batches.expand((batch) => batch).toList();

  return IsolateWorkData(
    batches: batches,
    cachedDateTimeStamps: /* ... */,
    cachedAssetLists: /* ... */,
    ignoreAudioAssets: ignoreAudio,
    existingAssetBundles: existingAssets.assetBundles,
    existingAudio: existingAssets.audio,
    existingImages: existingAssets.images,
    existingModels: existingAssets.models,
    existingPdf: existingAssets.pdf,
    failedAssets: failedAssetsMap,
    backedUpFiles: backedUpFiles,  // ADD THIS
  );
}).toList();
```

#### 5.3 Update Asset Building Function
**File:** `lib/src/state/mods/mods_isolates.dart`

Update `_buildAssetListsFromUrls` signature:

```dart
(AssetLists, int, int, int) _buildAssetListsFromUrls(
  Map<String, String> urlsData,
  Map<String, String> assetBundles,
  Map<String, String> audio,
  Map<String, String> images,
  Map<String, String> models,
  Map<String, String> pdf,
  bool ignoreAudio,
  Map<String, String> failedAssets,
  Set<String> backedUpFiles,  // ADD THIS PARAMETER
) {
  // ... existing code ...
}
```

Update call site in `processMultipleBatchesInIsolate`:

```dart
final assetLists = _buildAssetListsFromUrls(
  jsonURLs,
  workData.existingAssetBundles,
  workData.existingAudio,
  workData.existingImages,
  workData.existingModels,
  workData.existingPdf,
  workData.ignoreAudioAssets,
  workData.failedAssets,
  workData.backedUpFiles,  // ADD THIS
);
```

#### 5.4 Check Backup State When Creating Assets
**File:** `lib/src/state/mods/mods_isolates.dart`

In the asset creation loop (around line 295):

```dart
final assets = urlsByType[type]!.map((url) {
  final filename = getFileNameFromURL(url);
  final filepath = assetMap[filename]; // O(1) lookup

  // Check if this asset has failed
  final errorTypeString = failedAssets[url];
  final hasFailed = errorTypeString != null;
  DownloadErrorTypeEnum? errorType;

  if (hasFailed) {
    errorType = DownloadErrorTypeEnum.values.firstWhere(
      (e) => e.name == errorTypeString,
      orElse: () => DownloadErrorTypeEnum.unknown,
    );
  }

  // NEW: Check if this asset is backed up
  final isBackedUp = backedUpFiles.contains(filename);  // ADD THIS

  return Asset(
    url: url,
    fileExists: filepath != null,
    filePath: filepath,
    hasFailed: hasFailed,
    errorType: errorType,
    isBackedUp: isBackedUp,  // ADD THIS
  );
}).toList();
```

### Phase 6: UI Updates ⚠️ TODO

#### 6.1 Update Assets Tooltip
**File:** `lib/src/mods/components/assets_tooltip.dart`

Add backed up state to the help dialog:

```dart
// After the downloaded/failed/missing states, add:
WidgetSpan(
  child: Icon(Icons.backup, size: 16, color: Colors.blue),
),
TextSpan(
  text: ' Blue Border',
  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
),
TextSpan(text: ' - Asset is backed up\n'),
```

Add explanation note:

```dart
TextSpan(
  text: '\nNote:\n',
  style: TextStyle(fontWeight: FontWeight.bold),
),
TextSpan(
  text: '• Assets can be backed up even if not currently downloaded\n'
       '• Backup state is preserved even if URLs become invalid\n'
       '• Blue border indicates the asset exists in at least one backup\n'
),
```

#### 6.2 Update Asset URL Display (Optional)
**File:** `lib/src/mods/components/assets_url.dart`

Consider adding visual indicator for backed up assets (e.g., blue border or badge).

Around the asset display widget (line 245-265):

```dart
Container(
  decoration: BoxDecoration(
    border: asset.isBackedUp
      ? Border.all(color: Colors.blue, width: 2)
      : null,
    borderRadius: BorderRadius.circular(4),
  ),
  child: // ... existing asset display ...
)
```

---

## Testing Checklist

### Backup Creation
- [ ] Create a new backup
- [ ] Verify metadata is saved to Hive (`BackupFiles` box)
- [ ] Check metadata contains correct filenames and sizes
- [ ] Verify existing backups get metadata extracted on app load

### Asset State
- [ ] Asset exists and is backed up → `fileExists=true`, `isBackedUp=true`
- [ ] Asset backed up but not downloaded → `fileExists=false`, `isBackedUp=true`
- [ ] Asset downloaded but not backed up → `fileExists=true`, `isBackedUp=false`
- [ ] Asset failed but backed up → `hasFailed=true`, `isBackedUp=true`

### Edge Cases
- [ ] Backup file deleted → metadata should be cleaned up
- [ ] Multiple backups with same file → file still marked as backed up
- [ ] File renamed after backup → original filename still tracked as backed up
- [ ] Large backups (1000+ files) → performance acceptable

### UI
- [ ] Backed up assets show visual indicator
- [ ] Tooltip shows backed up state explanation
- [ ] Asset counts reflect backed up state

---

## Data Migration

### On First Run After Update
1. App loads existing backups
2. `_processBackupFiles` extracts metadata from each backup
3. Metadata is saved to `BackupFiles` Hive box
4. Subsequent runs use cached metadata (faster)

### Cleanup
When a backup file is deleted, its metadata should also be removed:

```dart
// In ExistingBackupsStateNotifier or wherever backups are deleted
await ref.read(storageProvider).deleteBackupFileMetadata(backupFilename);
```

---

## Performance Considerations

1. **Backup Loading:** Extracting metadata from large backups may be slow
   - Mitigation: Done in isolates, cached in Hive
   - Only happens once per backup

2. **Asset Building:** Checking backup state is O(1) Set lookup
   - No performance impact on mod loading

3. **Memory:** `backedUpFilesProvider` keeps all filenames in memory
   - Acceptable: Even 10,000 files × 50 chars = ~500KB

---

## Future Enhancements

1. **Backup Comparison:** Compare current mod state vs backup to decide if new backup needed
2. **Incremental Backups:** Only back up changed/new files
3. **Backup Metadata UI:** Show which files are in which backups
4. **Smart Backup Suggestions:** "10 new assets since last backup"
5. **File Size Validation:** Compare current file size vs backed up size

---

## Summary

**Completed:**
- ✅ Asset model updated with `isBackedUp` field
- ✅ BackupFileMetadata model created
- ✅ Hive storage layer implemented
- ✅ Backup creation extracts and saves metadata
- ✅ Backup loading extracts metadata from existing backups
- ✅ Provider aggregates backed up files across all backups

**Remaining:**
- ⚠️ Pass backed up files to isolate during mod loading
- ⚠️ Update asset building to check backup state
- ⚠️ Update UI to show backed up state

**Files Modified:**
- `lib/src/state/asset/models/asset_model.dart`
- `lib/src/state/backup/models/backup_file_metadata.dart` (NEW)
- `lib/src/state/storage/storage.dart`
- `lib/src/state/backup/backup_state.dart`
- `lib/src/state/backup/backup.dart`
- `lib/src/state/backup/existing_backups.dart`
- `lib/src/state/provider.dart`

**Files To Modify:**
- `lib/src/state/mods/mods_isolates.dart`
- `lib/src/state/mods/mods.dart`
- `lib/src/mods/components/assets_tooltip.dart`
- (Optional) `lib/src/mods/components/assets_url.dart`
