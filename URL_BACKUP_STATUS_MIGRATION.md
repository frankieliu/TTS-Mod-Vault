# Migration to UrlBackupStatus - Changes Summary

## Overview

Migrated from using `backedUpFilesProvider` (Set of filenames with extensions) to `UrlBackupStatus` Hive box (Map of URLs → backup info) for checking if assets are backed up.

## Why the Change?

### Old Approach Problem:
- **backedUpFiles**: Set of filenames WITH extensions (e.g., `"httpiimgurcomtHADwoQjpg.jpg"`)
- **URL conversion**: Creates filename WITHOUT extension (e.g., `"httpiimgurcomtHADwoQjpg"`)
- **Matching logic**: Used `contains()` for exact match
- **Result**: Always returned `false` (extension mismatch)

### New Approach Solution:
- **UrlBackupStatus**: Maps URL → backup status info directly
- **No conversion needed**: Direct URL lookup
- **Matching logic**: O(1) HashMap lookup
- **Result**: Correct backup status + faster performance

---

## Files Modified

### 1. `lib/src/state/provider.dart`
**Removed:**
- `backedUpFilesProvider` (lines 67-80)

**Before:**
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

**After:**
```dart
// Provider removed - using UrlBackupStatus Hive box instead
```

---

### 2. `lib/src/state/mods/mods_isolates.dart`

#### Change 1: IsolateWorkData class (lines 26-55)
**Before:**
```dart
class IsolateWorkData {
  final Set<String> backedUpFiles;
  // ...
  IsolateWorkData({
    required this.backedUpFiles,
    // ...
  });
}
```

**After:**
```dart
class IsolateWorkData {
  // URL backup status map for O(1) lookups (url -> isBackedUp)
  final Map<String, bool> urlBackupStatusMap;
  // ...
  IsolateWorkData({
    required this.urlBackupStatusMap,
    // ...
  });
}
```

#### Change 2: Function call (line 151)
**Before:**
```dart
workData.backedUpFiles,
```

**After:**
```dart
workData.urlBackupStatusMap,
```

#### Change 3: Function signature (line 270)
**Before:**
```dart
Set<String> backedUpFiles,
```

**After:**
```dart
Map<String, bool> urlBackupStatusMap,
```

#### Change 4: Backup check logic (lines 320-322)
**Before:**
```dart
final isBackedUp = backedUpFiles.contains(filename); // Wrong!

// Debug logging removed
```

**After:**
```dart
// Check if this asset is backed up using direct URL lookup
final isBackedUp = urlBackupStatusMap[url] ?? false; // O(1) lookup!
```

#### Change 5: Removed debug logging
Removed lines 292, 324-333 (debug asset count and logging)

---

### 3. `lib/src/state/mods/mods.dart`

#### Change 1: Removed import (line 40)
**Before:**
```dart
show
    backedUpFilesProvider,
    directoriesProvider,
    // ...
```

**After:**
```dart
show
    directoriesProvider,
    // ...
```

#### Change 2: Build urlBackupStatusMap (lines 184-206)
**Before:**
```dart
// Get backed up files for O(1) lookups in isolate
final backedUpFiles = ref.read(backedUpFilesProvider);
```

**After:**
```dart
// Get URL backup status map for O(1) lookups in isolate
// Get all URLs from all mods
final allUrls = <String>[];
for (final batch in batchesPerIsolate) {
  for (final modBatch in batch) {
    for (final mod in modBatch) {
      final urls = cachedUrls[mod.jsonFileName];
      if (urls != null) {
        allUrls.addAll(urls.keys);
      }
    }
  }
}

// Query backup status for all URLs at once
final storage = ref.read(storageProvider);
final urlBackupStatusData = storage.getUrlBackupStatusBulk(allUrls);

// Convert to simple bool map for isolate
final urlBackupStatusMap = <String, bool>{};
for (final url in allUrls) {
  urlBackupStatusMap[url] = urlBackupStatusData.containsKey(url);
}
```

#### Change 3: Pass to isolate (line 233)
**Before:**
```dart
backedUpFiles: backedUpFiles,
```

**After:**
```dart
urlBackupStatusMap: urlBackupStatusMap,
```

---

### 4. `lib/src/state/backup/existing_backups.dart`

#### Change 1: Added imports (lines 18-19)
**Before:**
```dart
show directoriesProvider, loadingMessageProvider, settingsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart' show getBackupFilenameByMod;
```

**After:**
```dart
show directoriesProvider, loadingMessageProvider, modsProvider, settingsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart' show getBackupFilenameByMod, getFileNameFromURL;
```

#### Change 2: Added population call (line 145)
**After line 142:**
```dart
// Populate URL backup status for mods (limited to 5 mods for testing)
await _populateUrlBackupStatus();
```

#### Change 3: Added _populateUrlBackupStatus method (lines 150-222)
```dart
Future<void> _populateUrlBackupStatus() async {
  debugPrint('_populateUrlBackupStatus - started');

  // Get storage and mods provider
  final storage = ref.read(storageProvider);

  // We'll limit to first 5 mods for testing
  final modsState = ref.read(modsProvider).valueOrNull;
  if (modsState == null) {
    debugPrint('_populateUrlBackupStatus - no mods loaded yet, skipping');
    return;
  }

  // Get first 5 mods for testing
  final allMods = [...modsState.mods, ...modsState.saves, ...modsState.savedObjects];
  final testMods = allMods.take(5).toList();

  debugPrint('_populateUrlBackupStatus - processing ${testMods.length} mods');

  // Get all backup metadata
  final allBackupMetadata = storage.getAllBackupFileMetadata();

  int totalUrlsProcessed = 0;
  int totalUrlsBackedUp = 0;

  for (final mod in testMods) {
    // Get all asset URLs from this mod
    final assets = mod.getAllAssets();
    if (assets.isEmpty) continue;

    debugPrint('  Mod ${mod.saveName}: ${assets.length} assets');

    // Check each backup to see if it contains files for this mod's assets
    for (final backupEntry in allBackupMetadata.entries) {
      final backupFilename = backupEntry.key;
      final backupMetadata = backupEntry.value;

      // Check each asset URL against this backup
      for (final asset in assets) {
        final url = asset.url;
        totalUrlsProcessed++;

        // Convert URL to filename (without extension)
        final urlFilename = getFileNameFromURL(url);

        // Check if any file in backup starts with this filename
        bool found = false;
        for (final backupFile in backupMetadata.files.keys) {
          if (backupFile.startsWith(urlFilename)) {
            found = true;
            break;
          }
        }

        if (found) {
          // Save URL backup status to Hive
          final status = {
            'backupFilename': backupFilename,
            'fileSize': backupMetadata.getFileSize(backupFilename),
            'backedUpAt': DateTime.now().toIso8601String(),
            'modJsonFileName': mod.jsonFileName,
          };

          await storage.saveUrlBackupStatus(url, status);
          totalUrlsBackedUp++;
        }
      }
    }
  }

  debugPrint('_populateUrlBackupStatus - finished: $totalUrlsProcessed URLs processed, $totalUrlsBackedUp URLs backed up');
}
```

---

## How It Works Now

### 1. App Startup

```
User starts app
  ↓
loadExistingBackups() is called
  ↓
Backups are loaded and metadata extracted
  ↓
_populateUrlBackupStatus() is called
  ↓
For first 5 mods:
  - Get all asset URLs
  - For each URL, check all backups
  - If URL's file exists in backup:
    → Save to UrlBackupStatus Hive box
```

### 2. Loading Mods

```
loadModsData() is called
  ↓
Get all asset URLs from mods
  ↓
Query UrlBackupStatus Hive box for all URLs (bulk)
  ↓
Build urlBackupStatusMap: Map<String, bool>
  ↓
Pass to isolate
  ↓
For each asset:
  isBackedUp = urlBackupStatusMap[url] ?? false
```

---

## Performance Comparison

### Old Approach:
```dart
// O(n) where n = number of files in all backups
for (final backedUpFile in backedUpFiles) {  // ~1000+ files
  if (backedUpFile.startsWith(filename)) {
    return true;
  }
}
```

### New Approach:
```dart
// O(1) HashMap lookup
final isBackedUp = urlBackupStatusMap[url] ?? false;
```

---

## Testing Limits

### Current Limits (for testing):
- **Backups loaded:** Limited to first 10 (in existing_backups.dart line 54)
- **UrlBackupStatus population:** Limited to first 5 mods (in _populateUrlBackupStatus line 166)

### To Remove Limits:
1. **Remove backup limit:**
   ```dart
   // In existing_backups.dart line 53-56
   // Change from:
   final limitedFiles = files.take(10).toList();

   // To:
   final limitedFiles = files.toList();
   ```

2. **Remove mod limit:**
   ```dart
   // In existing_backups.dart line 166
   // Change from:
   final testMods = allMods.take(5).toList();

   // To:
   final testMods = allMods;
   ```

---

## Hive Storage Structure

### UrlBackupStatus Box
**Key:** URL (String)
**Value:** JSON String

```json
{
  "backupFilename": "MyMod.ttsmod",
  "fileSize": 12345,
  "backedUpAt": "2025-12-23T10:30:00Z",
  "modJsonFileName": "123456789"
}
```

### Example:
```dart
// Key
"http://i.imgur.com/tHADwoQ.jpg"

// Value
{
  "backupFilename": "MyMod (123456789).ttsmod",
  "fileSize": 12345,
  "backedUpAt": "2025-12-23T10:30:00Z",
  "modJsonFileName": "123456789"
}
```

---

## What to Test

1. **Startup:**
   - Check debug logs for "_populateUrlBackupStatus - started"
   - Should process 5 mods
   - Check log: "X URLs processed, Y URLs backed up"

2. **Loading Mods:**
   - Mods should load normally
   - Assets should show correct `isBackedUp` status
   - Check if blue border appears for backed up assets

3. **Performance:**
   - Mod loading should be fast (no O(n) searches)
   - No debug logging in console about backedUpFiles

4. **Hive Data:**
   - Check that UrlBackupStatus box is populated
   - Can use Hive browser or debug tools to inspect

---

## Rollback (if needed)

If issues occur, you can rollback by:
1. Revert all 4 files to previous versions
2. The old backedUpFilesProvider will work again
3. UrlBackupStatus box will be ignored (no harm)

---

## Next Steps

After testing with 5 mods:
1. Remove the testing limits
2. Add population for new mods when they're created
3. Update UrlBackupStatus when backups are created/deleted
4. Add UI to show which backup contains each asset
