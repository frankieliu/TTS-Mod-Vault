# Asset Metadata Tracking Implementation Plan

## Overview

Build a comprehensive asset tracking system that:
1. Tracks which assets are backed up (by filename)
2. Captures metadata for downloaded assets (size + checksum)
3. Creates incremental backups with manifest files
4. Reconciles backed up assets vs source of truth
5. Enables intelligent decisions about downloads and backups

## Architecture Decisions

### Metadata Storage Strategy

We need to store metadata for assets in **two contexts**:

#### Context 1: Downloaded Assets (Source of Truth)
**Location:** TTS cache folders (`Mods/Images/`, `Mods/Models/`, etc.)
**Metadata:** Filename, size, checksum, download date, URL
**Purpose:** Track what we've successfully downloaded

#### Context 2: Backed Up Assets
**Location:** Inside `.ttsmod` backup files
**Metadata:** Filename, size, checksum, backup date
**Purpose:** Track what's preserved in backups

**Key Insight:** These are separate! A file can be:
- Downloaded but not backed up
- Backed up but not currently downloaded
- Both downloaded and backed up (may have different checksums if file changed)
- Neither (missing)

### Checksum Algorithm Choice

**Recommendation: Use CRC32**

**Rationale:**
1. **Already available** - ZIP files store CRC32 for every file
2. **Fast computation** - CRC32 is very fast for large files
3. **Sufficient for integrity** - Detects accidental corruption
4. **Compatible** - Standard in ZIP archives
5. **Small storage** - Only 4 bytes (8 hex characters)

**Alternative (future enhancement):**
- SHA256 for cryptographic verification
- Can be added alongside CRC32 later

**Trade-off:**
- CRC32 is NOT collision-resistant for malicious changes
- But TTS assets aren't a security concern
- Focus is on detecting accidental corruption/changes

### Data Model Design

```dart
// Downloaded asset metadata
class DownloadedAsset {
  final String url;                    // Asset URL
  final String filename;               // Derived from URL
  final int size;                      // File size in bytes
  final String crc32;                  // CRC32 checksum (hex)
  final DateTime downloadedAt;         // When downloaded
  final AssetTypeEnum type;            // Asset type

  // Optional: full file path on disk
  final String? filePath;
}

// Backed up asset metadata (in manifest)
class BackedUpAsset {
  final String filename;               // File basename
  final int size;                      // Size in backup
  final String crc32;                  // CRC32 from zip
  final DateTime backedUpAt;           // Backup timestamp
  final String backupFilename;         // Which backup contains it

  // Optional: relative path in backup
  final String? relativePath;
}

// Backup manifest (stored in each .ttsmod file)
class BackupManifest {
  final String backupFilename;         // Name of this backup
  final DateTime createdAt;            // When backup was created
  final String modName;                // Mod name
  final String? modDateTimeStamp;      // Mod's "Date" field
  final Map<String, BackedUpAsset> assets;  // filename -> metadata
  final String manifestVersion;        // For future compatibility

  // Computed field
  int get totalSize => assets.values.fold(0, (sum, a) => sum + a.size);
}
```

---

## Phase 1: Track Backed Up Files (Filename Only)

### Current State ✅ COMPLETED

We've already implemented:
- `BackupFileMetadata` model (filename → size)
- Hive storage for backup metadata
- Extraction from existing backups
- Aggregation via `backedUpFilesProvider`

### What We Have

```dart
// In storage
Map<String, BackupFileMetadata> getAllBackupFileMetadata()
// Returns: Map<backupFilename, BackupFileMetadata>

class BackupFileMetadata {
  final Map<String, int> files;  // filename -> size
}

// In provider
final backedUpFilesProvider = Provider<Set<String>>((ref) {
  // Returns Set of all filenames that exist in ANY backup
});
```

### Phase 1 Completion: Integration ⚠️ TODO

**Remaining work from BACKUP_STATE_TRACKING.md:**

1. Pass backed up files to isolate
2. Check backup state when building assets
3. Update UI to show backed up indicator

**Status:** See `BACKUP_STATE_TRACKING.md` for detailed implementation steps

---

## Phase 2: Bulk Download with Metadata Capture

### Objective

When downloading assets:
1. Download missing assets
2. Compute CRC32 checksum as we download
3. Store metadata in Hive: `url → DownloadedAsset`
4. Use this metadata for future comparisons

### Storage Structure

**New Hive Box:**
```dart
class Storage {
  late Box<String> _downloadedAssetsBox;
  static const String downloadedAssetsBox = 'DownloadedAssets';
}
```

**Key:** Asset URL (unique identifier)
**Value:** JSON-encoded `DownloadedAsset`

**Why URL as key?**
- URLs are unique per asset
- Allows O(1) lookup by URL
- Supports multiple files with same name but different URLs

### Download Flow with Metadata

**File:** `lib/src/state/download/download.dart`

```dart
Future<void> _downloadAsset(Asset asset) async {
  try {
    // Download to temp location first
    final tempFile = File('${targetPath}.tmp');

    await dio.download(
      asset.url,
      tempFile.path,
      onReceiveProgress: (received, total) {
        // Update progress
      },
    );

    // Compute CRC32
    final crc32 = await _computeCrc32(tempFile);

    // Get file size
    final stat = await tempFile.stat();
    final size = stat.size;

    // Move to final location
    await tempFile.rename(targetPath);

    // Save metadata
    final downloadedAsset = DownloadedAsset(
      url: asset.url,
      filename: getFileNameFromURL(asset.url),
      size: size,
      crc32: crc32,
      downloadedAt: DateTime.now(),
      type: assetType,
      filePath: targetPath,
    );

    await ref.read(storageProvider).saveDownloadedAsset(
      asset.url,
      downloadedAsset,
    );

  } catch (e) {
    // Handle download failure
    // Save to failed assets as before
  }
}

// CRC32 computation
Future<String> _computeCrc32(File file) async {
  final bytes = await file.readAsBytes();
  final crc = Crc32();
  crc.add(bytes);
  return crc.value.toRadixString(16).padLeft(8, '0');
}
```

**Dependencies:**
```dart
// Add to pubspec.yaml
dependencies:
  archive: ^4.0.5  # Already included, has CRC32
```

### Bulk Download Strategy

**Scenario:** User clicks "Download All" for multiple mods

**Current behavior:** Downloads all missing assets
**New behavior:** Downloads AND captures metadata

**Implementation:**
1. Existing download logic remains unchanged
2. Add metadata capture step after each successful download
3. Store in `downloadedAssetsBox`
4. No UI changes needed initially

**Optimization:**
- CRC32 computation is fast (hundreds of MB/s)
- Minimal overhead vs current downloads
- Can be done in isolate if needed

### Metadata Usage

**Use cases:**
1. **Compare downloaded vs backed up:** Same CRC32 = identical
2. **Verify downloads:** Re-compute CRC32, compare with stored
3. **Detect changes:** Different CRC32 = file changed
4. **Skip re-downloads:** Check metadata before downloading
5. **Smart backups:** Only backup files not already backed up (same CRC32)

---

## Phase 3: Incremental Backup with Manifest

### Objective

Create backups that:
1. Include manifest file with checksums
2. Support incremental backups (skip unchanged files)
3. Preserve previously backed up files
4. Enable fast comparison without extracting backup

### Manifest File Structure

**File:** `manifest.json` (included in every `.ttsmod` backup)

```json
{
  "manifestVersion": "1.0",
  "backupFilename": "CoolMap (123456789).ttsmod",
  "createdAt": "2025-12-23T10:30:00Z",
  "modName": "Cool Map",
  "modDateTimeStamp": "1735034600",
  "jsonFile": {
    "filename": "123456789.json",
    "size": 1024000,
    "crc32": "a1b2c3d4"
  },
  "imageFile": {
    "filename": "123456789.png",
    "size": 512000,
    "crc32": "e5f6g7h8"
  },
  "assets": {
    "dragon.obj": {
      "filename": "dragon.obj",
      "size": 2048000,
      "crc32": "12345678",
      "relativePath": "Mods/Models/dragon.obj",
      "type": "model"
    },
    "texture.png": {
      "filename": "texture.png",
      "size": 1024000,
      "crc32": "abcdef01",
      "relativePath": "Mods/Images/texture.png",
      "type": "image"
    }
  },
  "stats": {
    "totalFiles": 10,
    "totalSize": 52428800
  }
}
```

**Location in backup:**
```
CoolMap.ttsmod (ZIP)
├── manifest.json              # NEW: Metadata manifest
├── Mods/
│   ├── Workshop/
│   │   ├── 123456789.json
│   │   └── 123456789.png
│   ├── Images/
│   │   └── texture.png
│   └── Models/
│       └── dragon.obj
```

### Backup Creation with Manifest

**File:** `lib/src/state/backup/backup.dart`

**Modified `_backupIsolate`:**

```dart
void _backupIsolate(BackupIsolateData data) async {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(data.targetBackupFilePath);

    // Track metadata as we add files
    final Map<String, BackedUpAsset> assetsMetadata = {};

    for (int i = 0; i < data.filePaths.length; i++) {
      final filePath = data.filePaths[i];
      final file = File(filePath);

      if (!await file.exists()) continue;

      // Add file to zip
      final relativePath = /* ... compute relative path ... */;
      await encoder.addFile(file, relativePath);

      // Compute CRC32 from file
      final bytes = await file.readAsBytes();
      final crc = Crc32();
      crc.add(bytes);
      final crc32Hex = crc.value.toRadixString(16).padLeft(8, '0');

      // Store metadata
      final filename = p.basename(filePath);
      final stat = await file.stat();

      assetsMetadata[filename] = BackedUpAsset(
        filename: filename,
        size: stat.size,
        crc32: crc32Hex,
        backedUpAt: DateTime.now(),
        backupFilename: data.backupFilename,
        relativePath: relativePath,
      );

      data.sendPort.send(BackupProgressMessage(i + 1, data.filePaths.length));
    }

    // Create manifest
    final manifest = BackupManifest(
      backupFilename: data.backupFilename,
      createdAt: DateTime.now(),
      modName: data.modName,
      modDateTimeStamp: data.modDateTimeStamp,
      assets: assetsMetadata,
      manifestVersion: '1.0',
    );

    // Add manifest to backup
    final manifestJson = jsonEncode(manifest.toJson());
    final manifestBytes = utf8.encode(manifestJson);
    encoder.addArchiveFile(ArchiveFile(
      'manifest.json',
      manifestBytes.length,
      manifestBytes,
    ));

    await encoder.close();

    // Send complete message with metadata
    data.sendPort.send(BackupCompleteMessage(
      true,
      'Backup created with manifest',
      assetsMetadata.map((k, v) => MapEntry(k, v.size)),
    ));
  } catch (e) {
    data.sendPort.send(BackupCompleteMessage(false, e.toString()));
  }
}
```

### Loading Backups with Manifest

**File:** `lib/src/state/backup/existing_backups.dart`

**Modified `_processBackupFiles`:**

```dart
Future<List<(ExistingBackup, BackupFileMetadata?)>> _processBackupFiles(
    List<File> files) async {

  for (final file in files) {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    BackupFileMetadata? metadata;

    // Look for manifest.json first
    final manifestFile = archive.files.firstWhere(
      (f) => f.name == 'manifest.json',
      orElse: () => null,
    );

    if (manifestFile != null) {
      // Parse manifest (fast, contains all metadata)
      final manifestJson = utf8.decode(manifestFile.content);
      final manifest = BackupManifest.fromJson(jsonDecode(manifestJson));

      metadata = BackupFileMetadata(
        files: manifest.assets.map((k, v) => MapEntry(k, v.size)),
      );
    } else {
      // Fallback: Extract from zip files (slower)
      final Map<String, int> filesMap = {};
      for (final zipFile in archive.files) {
        if (!zipFile.isFile) continue;
        final name = path.basename(zipFile.name);
        if (name.isNotEmpty) {
          filesMap[name] = zipFile.size;
        }
      }
      metadata = BackupFileMetadata(files: filesMap);
    }

    // ... create ExistingBackup and return ...
  }
}
```

### Incremental Backup Strategy

**Goal:** Don't re-backup files that haven't changed

**Approach 1: Compare with Last Backup (Simple)**

```dart
// Before creating backup, check if files changed
Future<bool> shouldCreateBackup(Mod mod) async {
  final existingBackup = ref.read(existingBackupsProvider).getBackupByMod(mod);

  if (existingBackup == null) {
    return true; // No backup exists
  }

  // Check if mod was saved after backup
  if (mod.dateTimeStamp != null) {
    final modTimestamp = int.parse(mod.dateTimeStamp!);
    if (modTimestamp > existingBackup.lastModifiedTimestamp) {
      return true; // Mod updated
    }
  }

  // Check if asset count changed
  if (mod.existingAssetCount != existingBackup.totalAssetCount) {
    return true; // Assets added/removed
  }

  return false; // Backup is up to date
}
```

**Approach 2: Compare CRC32 (Thorough)**

```dart
// Compare current files vs backup manifest
Future<BackupComparison> compareWithBackup(Mod mod, ExistingBackup backup) async {
  // Extract manifest from backup
  final manifest = await extractManifest(backup.filepath);

  // Get current file CRCs from downloaded assets metadata
  final currentAssets = await getDownloadedAssetsForMod(mod);

  final added = <String>[];
  final removed = <String>[];
  final changed = <String>[];
  final unchanged = <String>[];

  for (final asset in currentAssets) {
    final filename = asset.filename;
    final currentCrc = asset.crc32;

    final backedUpAsset = manifest.assets[filename];

    if (backedUpAsset == null) {
      added.add(filename); // New file
    } else if (backedUpAsset.crc32 != currentCrc) {
      changed.add(filename); // File changed
    } else {
      unchanged.add(filename); // Identical
    }
  }

  // Check for removed files
  for (final backedUpFile in manifest.assets.keys) {
    if (!currentAssets.any((a) => a.filename == backedUpFile)) {
      removed.add(backedUpFile);
    }
  }

  return BackupComparison(
    added: added,
    removed: removed,
    changed: changed,
    unchanged: unchanged,
  );
}
```

**Smart Backup Decision:**

```dart
if (comparison.added.isEmpty &&
    comparison.removed.isEmpty &&
    comparison.changed.isEmpty) {
  // Nothing changed - skip backup
  showMessage('Backup is up to date');
} else {
  // Show summary and ask user
  showDialog(
    title: 'Backup Changes',
    message: '''
      Added: ${comparison.added.length} files
      Changed: ${comparison.changed.length} files
      Removed: ${comparison.removed.length} files

      Create new backup?
    ''',
  );
}
```

---

## Phase 4: Bulk Operations with Intelligence

### Bulk Download Strategy

**Enhanced "Download All" that:**
1. Checks if files already downloaded (metadata exists)
2. Verifies checksums for existing files
3. Only downloads missing/corrupted files
4. Captures metadata for new downloads

```dart
Future<void> bulkDownloadWithVerification(List<Mod> mods) async {
  for (final mod in mods) {
    final assets = mod.getAllAssets();

    for (final asset in assets) {
      // Check if we have metadata for this URL
      final metadata = await ref.read(storageProvider).getDownloadedAsset(asset.url);

      if (metadata != null && asset.fileExists) {
        // File exists and we have metadata - verify checksum
        final currentCrc = await _computeCrc32(File(asset.filePath!));

        if (currentCrc == metadata.crc32) {
          // File is valid, skip download
          continue;
        } else {
          // File corrupted, re-download
          debugPrint('File corrupted: ${asset.filePath}, re-downloading');
        }
      }

      // Download and capture metadata
      await downloadWithMetadata(asset);
    }
  }
}
```

### Bulk Backup Strategy

**Enhanced "Backup All" that:**
1. Compares each mod with existing backup
2. Skips mods with no changes
3. Creates incremental backups when needed
4. Shows summary before proceeding

```dart
Future<void> bulkBackupIntelligent(List<Mod> mods) async {
  final needsBackup = <Mod>[];
  final upToDate = <Mod>[];
  final noBackup = <Mod>[];

  // Analyze each mod
  for (final mod in mods) {
    final backup = existingBackups.getBackupByMod(mod);

    if (backup == null) {
      noBackup.add(mod);
    } else {
      final comparison = await compareWithBackup(mod, backup);
      if (comparison.hasChanges) {
        needsBackup.add(mod);
      } else {
        upToDate.add(mod);
      }
    }
  }

  // Show summary
  final result = await showDialog(
    title: 'Bulk Backup Analysis',
    content: '''
      No backup: ${noBackup.length} mods
      Needs update: ${needsBackup.length} mods
      Up to date: ${upToDate.length} mods

      Create backups for ${noBackup.length + needsBackup.length} mods?
    ''',
  );

  if (result == true) {
    final toBackup = [...noBackup, ...needsBackup];
    for (final mod in toBackup) {
      await createBackupWithManifest(mod);
    }
  }
}
```

---

## Phase 5: Future - Source of Truth Reconciliation

### Objective

Compare backed up assets with "source of truth" (Steam's CDN) to detect:
1. Files that were modified on Steam
2. Files that are no longer available
3. Files that have newer versions

**Challenge:** Cannot get checksums from Steam URLs without downloading

**Approach:**
1. HTTP HEAD request to check if URL still exists
2. Get `Content-Length` and `Last-Modified` headers
3. Compare size and date with backup metadata
4. Optional: Partial download to verify checksum

```dart
Future<AssetStatus> verifyAgainstSourceOfTruth(BackedUpAsset asset, String url) async {
  try {
    final response = await dio.head(url);

    final remoteSize = int.parse(response.headers.value('content-length') ?? '0');
    final lastModified = response.headers.value('last-modified');

    if (remoteSize != asset.size) {
      return AssetStatus.sizeChanged;
    }

    if (lastModified != null) {
      // Compare dates
      final remoteDate = HttpDate.parse(lastModified);
      if (remoteDate.isAfter(asset.backedUpAt)) {
        return AssetStatus.possiblyUpdated;
      }
    }

    return AssetStatus.unchanged;

  } catch (e) {
    if (e is DioException && e.response?.statusCode == 404) {
      return AssetStatus.urlDead;
    }
    return AssetStatus.unknown;
  }
}
```

---

## Storage Schema Summary

### Hive Boxes

```dart
class Storage {
  // Existing
  late Box<String> _failedAssetsBox;      // url -> FailedAsset JSON
  late Box<String> _backupFilesBox;       // backupFilename -> BackupFileMetadata JSON

  // New
  late Box<String> _downloadedAssetsBox;  // url -> DownloadedAsset JSON
}
```

### Data Relationships

```
URL (unique identifier)
  ↓
Downloaded Asset (if downloaded)
  - filename
  - size
  - crc32
  - downloadedAt

Filename (may have multiple URLs!)
  ↓
Backed Up Assets (may be in multiple backups)
  - size
  - crc32
  - backupFilename
  - backedUpAt
```

**Important:** Multiple URLs can have same filename!

Example:
```
http://steam.../ugc/123/dragon.obj  → dragon.obj
http://steam.../ugc/456/dragon.obj  → dragon.obj (different file!)
```

This is why we key `DownloadedAssets` by URL, not filename.

---

## Implementation Phases

### ✅ Phase 1: Filename Tracking (MOSTLY COMPLETE)
- [x] BackupFileMetadata model
- [x] Hive storage for backup metadata
- [x] Extract metadata from backups
- [ ] Pass to isolate (see BACKUP_STATE_TRACKING.md)
- [ ] Check backup state in assets
- [ ] UI indicator

### ⚠️ Phase 2: Download Metadata (NEXT)
**Priority: HIGH**

**Tasks:**
1. Create `DownloadedAsset` model
2. Add `downloadedAssetsBox` to Storage
3. Add CRC32 computation to download flow
4. Save metadata after successful downloads
5. Test with manual downloads

**Estimated effort:** 2-4 hours
**Files to modify:** 2-3 files

### ⚠️ Phase 3: Backup Manifest (MEDIUM PRIORITY)
**Priority: MEDIUM**

**Tasks:**
1. Create `BackupManifest` model
2. Modify backup creation to compute CRC32
3. Add manifest.json to backups
4. Update backup loading to read manifest
5. Test with new backups

**Estimated effort:** 4-6 hours
**Files to modify:** 3-4 files

### ⚠️ Phase 4: Intelligent Bulk Operations (LOW PRIORITY)
**Priority: LOW (nice-to-have)**

**Tasks:**
1. Implement backup comparison logic
2. Add "should backup" checks
3. Add download verification
4. Create UI for comparison results
5. Test with large mod collections

**Estimated effort:** 6-8 hours
**Files to modify:** 5-6 files

---

## Testing Strategy

### Unit Tests

```dart
test('CRC32 computation is consistent', () async {
  final file = File('test_asset.png');
  final crc1 = await computeCrc32(file);
  final crc2 = await computeCrc32(file);
  expect(crc1, equals(crc2));
});

test('Backup manifest serialization', () {
  final manifest = BackupManifest(/* ... */);
  final json = manifest.toJson();
  final restored = BackupManifest.fromJson(json);
  expect(restored.backupFilename, manifest.backupFilename);
});
```

### Integration Tests

1. **Download → Metadata → Verify**
   - Download asset
   - Check metadata stored
   - Verify CRC32 matches

2. **Backup → Manifest → Load**
   - Create backup with manifest
   - Extract backup
   - Verify manifest contents

3. **Compare → Backup → Compare**
   - Create initial backup
   - Modify files
   - Compare with backup
   - Verify changes detected

### Performance Tests

1. **CRC32 Speed**
   - 100MB file should compute in < 1 second
   - 1GB file should compute in < 10 seconds

2. **Manifest Loading**
   - Loading 1000-file backup manifest should be < 100ms
   - Much faster than extracting entire zip

---

## Migration Strategy

### Existing Users

Users with existing backups will have:
- Old backups without manifests
- No downloaded asset metadata

**Solution:**
1. Gradually populate metadata as files are downloaded
2. Generate manifest when backup is extracted/loaded
3. Store generated manifest in Hive for future use
4. Next backup will include manifest

**No data loss:** System works with partial data

---

## Benefits

### Immediate Benefits (Phase 1-2)
1. Know which assets are backed up
2. Track downloaded asset integrity
3. Detect corrupted downloads

### Medium-term Benefits (Phase 3)
1. Fast backup comparison without extraction
2. Incremental backups (skip unchanged files)
3. Backup verification without full extraction

### Long-term Benefits (Phase 4)
1. Intelligent bulk operations
2. Minimize redundant downloads
3. Minimize redundant backups
4. Detect when Steam removes/changes content

---

## Open Questions & Decisions Needed

### 1. CRC32 vs SHA256?
**Recommendation:** Start with CRC32, add SHA256 later if needed
- CRC32: Fast, sufficient for integrity, standard in ZIP
- SHA256: Slower, cryptographically secure, not needed for TTS assets

### 2. Manifest Version Strategy?
**Recommendation:** Use semantic versioning
- `"1.0"` - Initial implementation
- `"1.1"` - Add SHA256 checksums
- `"2.0"` - Breaking changes to structure

### 3. Store Full File Paths or Just Filenames?
**Recommendation:** Both
- Filename: For cross-backup lookup
- Relative path: For proper extraction

### 4. Cleanup Old Metadata?
**Recommendation:** Periodic cleanup
- Remove downloaded asset metadata for deleted files
- Remove backup metadata for deleted backups
- Run on app startup or weekly

### 5. UI for Comparison Results?
**Recommendation:** Phase 4 feature
- Show detailed diff dialog
- List added/changed/removed files
- Allow user to decide whether to backup

---

## Summary

This plan creates a robust asset tracking system that:

✅ **Solves the core problem:** URLs are ephemeral, we need checksums
✅ **Incremental approach:** Each phase adds value independently
✅ **Efficient:** CRC32 is fast, manifests avoid extraction
✅ **Flexible:** Works with partial data, gradual migration
✅ **Future-proof:** Versioned manifests, extensible schema

**Next step:** Implement Phase 2 (Download Metadata Capture)
