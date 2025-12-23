# Phase 1: Backup State Tracking - Complete Walkthrough

## What Phase 1 Does

**Goal:** Track which assets are backed up (by filename only, no checksums yet)

**End Result:**
- Assets in UI show visual indicator if they're backed up
- App knows which files exist in at least one backup
- Foundation for future checksum-based comparison

---

## Current State: What's Already Done ✅

### 1. Asset Model Has `isBackedUp` Field

**File:** `lib/src/state/asset/models/asset_model.dart`

```dart
class Asset {
  final String url;
  final bool fileExists;      // Downloaded to disk?
  final String? filePath;
  final bool hasFailed;       // Download failed?
  final DownloadErrorTypeEnum? errorType;
  final bool isBackedUp;      // 🆕 NEW FIELD

  Asset({
    required this.url,
    required this.fileExists,
    this.filePath,
    this.hasFailed = false,
    this.errorType,
    this.isBackedUp = false,   // Defaults to false
  });
}
```

**What this enables:**
```dart
// Now we can check if an asset is backed up
if (asset.isBackedUp) {
  showBlueBorder(); // Visual indicator
}

// Asset states are now richer:
// - fileExists=true,  isBackedUp=true  → Downloaded AND backed up
// - fileExists=false, isBackedUp=true  → Backed up but not downloaded
// - fileExists=true,  isBackedUp=false → Downloaded but not backed up
// - fileExists=false, isBackedUp=false → Missing entirely
```

### 2. Storage Layer for Backup Metadata

**File:** `lib/src/state/storage/storage.dart`

**New Hive Box:**
```dart
late Box<String> _backupFilesBox;
static const String backupFilesBox = 'BackupFiles';
```

**Storage Schema:**
```
Hive Box: BackupFiles
├── "CoolMap (123456789).ttsmod" → { files: { "dragon.obj": 2048000, "texture.png": 1024000 } }
├── "Adventure.ttsmod"           → { files: { "map.png": 512000, "token.png": 256000 } }
└── "Dungeon.ttsmod"            → { files: { "dragon.obj": 2048000, "floor.png": 768000 } }
```

**Key insight:** Notice "dragon.obj" appears in multiple backups! That's fine - if a file is in ANY backup, it's considered backed up.

**Storage Methods:**
```dart
// Save backup metadata when creating backup
Future<void> saveBackupFileMetadata(String backupFilename, BackupFileMetadata metadata);

// Get metadata for specific backup
BackupFileMetadata? getBackupFileMetadata(String backupFilename);

// Get ALL backup metadata (used by provider)
Map<String, BackupFileMetadata> getAllBackupFileMetadata();

// Delete when backup is deleted
Future<void> deleteBackupFileMetadata(String backupFilename);
```

### 3. Backup Creation Captures File Metadata

**File:** `lib/src/state/backup/backup.dart`

**What happens when user clicks "Backup":**

```dart
void _backupIsolate(BackupIsolateData data) async {
  final encoder = ZipFileEncoder();
  encoder.create('CoolMap.ttsmod');

  // 📝 Track files as we add them
  final Map<String, int> fileMetadata = {};

  for (final filePath in filePaths) {
    final file = File(filePath);

    // Add to ZIP
    await encoder.addFile(file, relativePath);

    // 📝 Record: filename → size
    final stat = await file.stat();
    final filename = basename(filePath);
    fileMetadata[filename] = stat.size;
  }

  await encoder.close();

  // ✅ Send metadata back to main thread
  sendPort.send(BackupCompleteMessage(
    true,
    'Backup created',
    fileMetadata,  // Contains: { "dragon.obj": 2048000, ... }
  ));
}
```

**Then in main thread:**
```dart
if (message.success) {
  // Add backup to state
  ref.read(existingBackupsProvider.notifier).addBackup(newBackup);

  // 💾 Save metadata to Hive
  if (message.fileMetadata != null) {
    final metadata = BackupFileMetadata(files: message.fileMetadata!);
    await ref.read(storageProvider).saveBackupFileMetadata(
      backupFileName,
      metadata,
    );
  }
}
```

### 4. Loading Existing Backups Extracts Metadata

**File:** `lib/src/state/backup/existing_backups.dart`

**What happens at app startup:**

```dart
Future<void> loadExistingBackups() async {
  // Find all .ttsmod files
  final backupFiles = directory.list()
    .where((f) => f.path.endsWith('.ttsmod'));

  // Process in parallel using isolates
  final results = await Future.wait(
    backupFiles.map((file) =>
      Isolate.run(() => _processBackupFiles([file]))
    )
  );

  // Each result contains: (ExistingBackup, BackupFileMetadata?)
  for (final (backup, metadata) in results) {
    if (metadata != null) {
      // 💾 Save to Hive for fast access
      await storage.saveBackupFileMetadata(backup.filename, metadata);
    }
  }
}
```

**What happens in isolate:**
```dart
Future<(ExistingBackup, BackupFileMetadata?)> _processBackupFiles(File file) async {
  // Read ZIP file
  final bytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  // 📝 Extract file list
  final Map<String, int> filesMap = {};
  for (final zipFile in archive.files) {
    if (!zipFile.isFile) continue;
    final name = basename(zipFile.name);
    filesMap[name] = zipFile.size;
  }

  final metadata = BackupFileMetadata(files: filesMap);
  final backup = ExistingBackup(/* ... */);

  return (backup, metadata);
}
```

**Result:** After app loads, Hive contains metadata for ALL backups!

### 5. Provider Aggregates All Backed Up Files

**File:** `lib/src/state/provider.dart`

```dart
final backedUpFilesProvider = Provider<Set<String>>((ref) {
  // Get all backup metadata from storage
  final storage = ref.watch(storageProvider);
  final allBackupMetadata = storage.getAllBackupFileMetadata();

  // Returns: {
  //   "CoolMap.ttsmod": { files: { "dragon.obj": 2048000, ... } },
  //   "Adventure.ttsmod": { files: { "map.png": 512000, ... } },
  // }

  // Aggregate ALL filenames across ALL backups
  final Set<String> backedUpFiles = {};
  for (final metadata in allBackupMetadata.values) {
    backedUpFiles.addAll(metadata.files.keys);
  }

  // Returns: {"dragon.obj", "map.png", "texture.png", ...}
  return backedUpFiles;
});
```

**What this gives us:**
```dart
// In any widget or provider:
final backedUpFiles = ref.watch(backedUpFilesProvider);

// Fast O(1) lookup
if (backedUpFiles.contains("dragon.obj")) {
  print("Dragon is backed up!");
}
```

---

## Remaining Work: What Needs to be Done 🚧

### Step 1: Pass Backed Up Files to Isolate

**File:** `lib/src/state/mods/mods_isolates.dart`

**Current state:**
```dart
class IsolateWorkData {
  final List<List<Mod>> batches;
  final Map<String, String?> cachedDateTimeStamps;
  final Map<String, Map<String, String>?> cachedAssetLists;
  final bool ignoreAudioAssets;
  final Map<String, String> existingAssetBundles;
  final Map<String, String> existingAudio;
  final Map<String, String> existingImages;
  final Map<String, String> existingModels;
  final Map<String, String> existingPdf;
  final Map<String, String> failedAssets;
  // ❌ Missing: backedUpFiles
}
```

**What to add:**
```dart
class IsolateWorkData {
  // ... existing fields ...
  final Set<String> backedUpFiles;  // 🆕 ADD THIS

  IsolateWorkData({
    // ... existing parameters ...
    required this.backedUpFiles,    // 🆕 ADD THIS
  });
}
```

**Why:** Isolates can't access Riverpod providers, so we must pass the data explicitly.

### Step 2: Pass Data When Creating Isolates

**File:** `lib/src/state/mods/mods.dart`

**Find this code (around line 174-210):**
```dart
// Create work data for each isolate
final ignoreAudio = ref.read(settingsProvider).ignoreAudioAssets;
final existingAssets = ref.read(existingAssetListsProvider);

// Get failed assets
final failedAssetsState = ref.read(failedAssetsProvider);
final failedAssetsMap = failedAssetsState.failedAssets.map(
  (url, failedAsset) => MapEntry(url, failedAsset.errorType.name),
);

final List<IsolateWorkData> isolateWorkData = batchesPerIsolate.map((batches) {
  // ... code ...

  return IsolateWorkData(
    batches: batches,
    // ... other fields ...
    existingPdf: existingAssets.pdf,
    failedAssets: failedAssetsMap,
    // ❌ Missing: backedUpFiles
  );
}).toList();
```

**What to add:**
```dart
// Get failed assets
final failedAssetsState = ref.read(failedAssetsProvider);
final failedAssetsMap = failedAssetsState.failedAssets.map(
  (url, failedAsset) => MapEntry(url, failedAsset.errorType.name),
);

// 🆕 ADD THIS: Get backed up files
final backedUpFiles = ref.read(backedUpFilesProvider);

final List<IsolateWorkData> isolateWorkData = batchesPerIsolate.map((batches) {
  // ... code ...

  return IsolateWorkData(
    batches: batches,
    // ... other fields ...
    existingPdf: existingAssets.pdf,
    failedAssets: failedAssetsMap,
    backedUpFiles: backedUpFiles,  // 🆕 ADD THIS
  );
}).toList();
```

### Step 3: Update Asset Building Function Signature

**File:** `lib/src/state/mods/mods_isolates.dart`

**Find this function (around line 254):**
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
  // ❌ Missing: backedUpFiles parameter
) {
```

**What to add:**
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
  Set<String> backedUpFiles,  // 🆕 ADD THIS PARAMETER
) {
```

### Step 4: Pass Parameter When Calling Function

**File:** `lib/src/state/mods/mods_isolates.dart`

**Find this code (around line 139-148):**
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
  // ❌ Missing: workData.backedUpFiles
);
```

**What to add:**
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
  workData.backedUpFiles,  // 🆕 ADD THIS
);
```

### Step 5: Check Backup State When Creating Assets

**File:** `lib/src/state/mods/mods_isolates.dart`

**Find this code (around line 295-320):**
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

  // ❌ Missing: Check if backed up

  return Asset(
    url: url,
    fileExists: filepath != null,
    filePath: filepath,
    hasFailed: hasFailed,
    errorType: errorType,
    // ❌ Missing: isBackedUp
  );
}).toList();
```

**What to add:**
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

  // 🆕 ADD THIS: Check if this asset is backed up
  final isBackedUp = backedUpFiles.contains(filename);

  return Asset(
    url: url,
    fileExists: filepath != null,
    filePath: filepath,
    hasFailed: hasFailed,
    errorType: errorType,
    isBackedUp: isBackedUp,  // 🆕 ADD THIS
  );
}).toList();
```

**That's it for the backend! Now assets know if they're backed up.**

### Step 6: Update UI Tooltip (Optional but Recommended)

**File:** `lib/src/mods/components/assets_tooltip.dart`

**Current tooltip shows:**
- ✓ Green - Downloaded
- ○ White - Not downloaded
- ⚠ Orange - Temporary failure
- ✗ Red - Permanent failure
- • Blue - Last selected URL

**What to add:**
```dart
// After the existing states, add:
WidgetSpan(
  child: Icon(Icons.backup, size: 16, color: Colors.blue),
),
TextSpan(
  text: ' Blue Border',
  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
),
TextSpan(text: ' - Asset is backed up\n'),

// Add explanation
TextSpan(
  text: '\nNote:\n',
  style: TextStyle(fontWeight: FontWeight.bold),
),
TextSpan(
  text: '• Assets can be backed up even if not currently downloaded\n'
       '• Backup state is preserved even if URLs become invalid\n'
       '• Blue border indicates the asset exists in at least one backup\n',
),
```

### Step 7: Update Asset Visual Display (Optional)

**File:** `lib/src/mods/components/assets_url.dart`

**Add visual indicator for backed up assets:**

Find the asset display widget (around line 245-265) and add a border:

```dart
Container(
  decoration: BoxDecoration(
    // 🆕 ADD THIS: Blue border if backed up
    border: asset.isBackedUp
      ? Border.all(color: Colors.blue, width: 2)
      : null,
    borderRadius: BorderRadius.circular(4),
  ),
  child: Row(
    children: [
      // Existing asset icon and text
      Icon(
        asset.fileExists ? Icons.check_circle :
        asset.hasFailed ? (asset.errorType == permanent ? Icons.error : Icons.warning) :
        Icons.circle_outlined,
        // ... colors ...
      ),
      Text(asset.url),
    ],
  ),
)
```

---

## Data Flow Diagram

Here's how data flows through the system:

```
📦 BACKUP CREATION
User clicks "Backup"
  ↓
Isolate creates ZIP
  ↓
Tracks: { "dragon.obj": 2048000, "texture.png": 1024000 }
  ↓
Sends to main thread
  ↓
Saves to Hive: BackupFiles["CoolMap.ttsmod"] = metadata
  ↓
✅ Metadata persisted


📱 APP STARTUP
App loads
  ↓
loadExistingBackups() runs
  ↓
Extracts file lists from all .ttsmod files
  ↓
Saves to Hive: BackupFiles[...] = metadata
  ↓
backedUpFilesProvider aggregates all filenames
  ↓
Returns: Set{"dragon.obj", "texture.png", ...}
  ↓
✅ Ready for use


🔄 MOD LOADING
User views mods
  ↓
modsProvider loads mods in isolate
  ↓
Main thread reads: backedUpFilesProvider
  ↓
Passes Set to isolate: backedUpFiles = {"dragon.obj", ...}
  ↓
For each asset URL:
  - Extract filename: "dragon.obj"
  - Check: backedUpFiles.contains("dragon.obj") → true
  - Create Asset with isBackedUp=true
  ↓
Assets returned to main thread
  ↓
UI displays with visual indicators
  ↓
✅ User sees backed up state
```

---

## Testing Phase 1

### Test 1: Create New Backup
1. Select a mod with downloaded assets
2. Click "Backup"
3. **Verify:**
   - Backup created successfully
   - Hive contains metadata: Open Hive box viewer, check BackupFiles
   - Metadata has correct filenames and sizes

### Test 2: Load Existing Backups
1. Close app
2. Reopen app
3. **Verify:**
   - App loads all backups
   - Hive contains metadata for all backups
   - Check backedUpFilesProvider contains expected filenames

### Test 3: Asset State Display
1. Open a mod that has:
   - Some assets downloaded AND backed up
   - Some assets backed up but NOT downloaded
   - Some assets downloaded but NOT backed up
2. **Verify:**
   - Downloaded+Backed up: Green icon + blue border
   - Backed up only: White/Red icon + blue border
   - Downloaded only: Green icon + no border
   - Neither: White/Red icon + no border

### Test 4: Delete Backup
1. Delete a .ttsmod file from filesystem
2. Refresh app data
3. **Verify:**
   - Backup no longer appears in list
   - Metadata removed from Hive (optional cleanup)
   - Assets that were ONLY in that backup now show isBackedUp=false

### Test 5: Large Backup
1. Create backup with 100+ assets
2. **Verify:**
   - Metadata extraction completes in reasonable time (< 5 seconds)
   - All filenames captured
   - No memory issues

---

## Performance Characteristics

### Memory Usage
- **Per backup:** ~50-100 bytes per file (filename + size)
- **1000 files:** ~50-100 KB
- **100 backups with 1000 files each:** ~5-10 MB
- **Conclusion:** Negligible memory impact

### CPU Usage
- **Creating backup:** O(n) where n = number of files
  - Just tracking filename + size, no checksums yet
  - Minimal overhead vs current backup creation
- **Loading backups:** O(n × m) where n = backups, m = files per backup
  - Done once at startup
  - Parallelized in isolates
  - Result cached in Hive
- **Checking backup state:** O(1) set lookup
  - Fast, no performance impact

### Storage Usage
- **Hive storage:** ~100 bytes per file
- **1000 files:** ~100 KB
- **Conclusion:** Negligible storage impact

---

## What Phase 1 DOES NOT Do

❌ **Does NOT compute checksums** - That's Phase 2
❌ **Does NOT verify integrity** - That's Phase 2
❌ **Does NOT compare backups** - That's Phase 3
❌ **Does NOT create manifests** - That's Phase 3
❌ **Does NOT do smart backups** - That's Phase 4

✅ **ONLY tracks:** Which filenames exist in which backups

---

## Summary

**Phase 1 Goal:** Track which assets are backed up by filename

**What's Done:**
- ✅ Storage layer
- ✅ Backup creation captures metadata
- ✅ Backup loading extracts metadata
- ✅ Provider aggregates data
- ✅ Asset model has field

**What Remains:**
- 🚧 Pass data to isolate (5 lines of code)
- 🚧 Check backup state in assets (2 lines of code)
- 🚧 UI indicators (optional, 10-20 lines)

**Estimated Time to Complete:** 30-60 minutes

**Risk Level:** Very low - simple data passing

**Next Phase:** Phase 2 - Add checksums to downloads
