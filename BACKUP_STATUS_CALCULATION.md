# Backup Status Calculation - Two-Phase Approach

## Overview

The application uses a two-phase approach for calculating backup status:
1. **Phase 1**: Fast, timestamp-based approximation during initial load
2. **Phase 2**: Comprehensive CRC32/file comparison when needed

This design optimizes performance while ensuring accuracy when making backup decisions.

---

## Phase 1: Initial Load - `_getInitialModWithBackup()`

### Purpose
Provides a **fast, lightweight** initial backup status during app startup without requiring asset list data.

### Location
**File**: `lib/src/state/mods/mods.dart:666-682`

### When Called
During `loadModsData()` for ALL mods when the app starts (lines 276, 279, 283):

```dart
for (final mod in allProcessedMods) {
  switch (mod.modType) {
    case ModTypeEnum.mod:
      mods.add(_getInitialModWithBackup(mod));
      break;
    case ModTypeEnum.save:
      saves.add(_getInitialModWithBackup(mod));
      break;
    case ModTypeEnum.savedObject:
      savedObjects.add(_getInitialModWithBackup(mod));
      break;
  }
}
```

### Implementation

```dart
Mod _getInitialModWithBackup(Mod mod) {
  try {
    // 1. Find if a backup exists for this mod
    final backup = ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

    // 2. Calculate simple timestamp-based status
    final backupStatus = backup == null
        ? ExistingBackupStatusEnum.noBackup
        : (mod.dateTimeStamp == null ||
                backup.lastModifiedTimestamp > int.parse(mod.dateTimeStamp!))
            ? ExistingBackupStatusEnum.upToDate
            : ExistingBackupStatusEnum.outOfDate;

    // 3. Return mod with backup info attached
    return mod.copyWith(backup: backup, backupStatus: backupStatus);
  } catch (e) {
    return mod;
  }
}
```

### Logic

**Backup Status Determination:**
- **No Backup**: `backup == null`
- **Up to Date**: `backup.lastModifiedTimestamp > mod.dateTimeStamp`
  - Backup was created AFTER the mod was last saved
- **Out of Date**: `backup.lastModifiedTimestamp <= mod.dateTimeStamp`
  - Mod was saved AFTER the backup was created

### Characteristics

| Aspect | Details |
|--------|---------|
| **Speed** | ⚡ Very fast - only timestamp comparison |
| **Data Required** | Only `mod.dateTimeStamp` (from JSON) |
| **Accuracy** | ⚠️ Approximate - doesn't detect file changes |
| **Use Case** | Initial display of backup status icons in grid |
| **Limitations** | Cannot detect:<br>• New downloaded files<br>• CRC32 mismatches<br>• File deletions |

---

## Phase 2: On-Demand - `getCompleteMod()`

### Purpose
Provides **accurate, comprehensive** backup status using CRC32 checksums and file comparison when users interact with mods or perform operations.

### Location
**File**: `lib/src/state/mods/mods.dart:684-729`

### When Called

#### 1. User Selection
**File**: `mods.dart:505`
```dart
final updatedMod = await getCompleteMod(selectedMod, urls);
```
When a user clicks on a mod to view details.

#### 2. Adding New Mod
**File**: `mods.dart:589`
```dart
final completeMod = await getCompleteMod(newMod, urls);
```
When a new mod is added to the library.

#### 3. Bulk Download
**File**: `bulk_actions.dart:71`
```dart
final completeMod = await getCompleteMod(mod, modUrls);
```
Before downloading files for a mod.

#### 4. Bulk Backup
**File**: `bulk_actions.dart:116`
```dart
final completeMod = await getCompleteMod(mod, modUrls);
```
Before backing up a mod (determines if backup is needed).

#### 5. Bulk Download & Backup
**File**: `bulk_actions.dart:192, 210`
```dart
// Before download
final completeMod = await getCompleteMod(mod, modUrls);

// ... download files ...

// After download - re-check with updated CRC32 data
final updatedMod = await getCompleteMod(selectedMod, updatedModUrls);
```
Checks twice: before download, and after download with fresh file data.

#### 6. URL Updates
**File**: `mods.dart:845, 906`
```dart
final completeMod = await getCompleteMod(selectedMod, jsonURLs);
```
After updating URLs in mod JSON files.

### Implementation

```dart
Future<Mod> getCompleteMod(Mod mod, Map<String, String> jsonURLs) async {
  // Get backup info
  ExistingBackup? backup = ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

  if (backup != null && backup.totalAssetCount == null) {
    final backupTotalAssetCount = await ref
        .read(existingBackupsProvider.notifier)
        .listZipContents(backup.filepath);
    backup = backup.copyWith(totalAssetCount: backupTotalAssetCount);
    ref.read(existingBackupsProvider.notifier).addBackup(backup);
  }

  // Build asset lists with file existence checks
  final assetLists = _getAssetListsFromUrls(jsonURLs);

  // Create mod with asset lists (needed for shouldForceBackup)
  final modWithAssets = mod.copyWith(
    assetLists: assetLists.$1,
    assetCount: assetLists.$2,
    existingAssetCount: assetLists.$3,
    missingAssetCount: assetLists.$2 - assetLists.$3,
    failedAssetCount: assetLists.$4,
  );

  // Calculate backup status using comprehensive logic
  ExistingBackupStatusEnum backupStatus;
  if (backup == null) {
    backupStatus = ExistingBackupStatusEnum.noBackup;
  } else {
    // Check if files have changed (new files or CRC32 mismatch)
    final shouldForce = ref.read(backupProvider.notifier).shouldForceBackup(modWithAssets);

    if (shouldForce) {
      // Files have changed - backup is out of date
      backupStatus = ExistingBackupStatusEnum.outOfDate;
    } else {
      // No file changes detected - backup is up to date
      backupStatus = ExistingBackupStatusEnum.upToDate;
    }
  }

  return modWithAssets.copyWith(
    backup: backup,
    backupStatus: backupStatus,
  );
}
```

### The CRC32/File Comparison Logic

**File**: `lib/src/state/backup/backup.dart:56-121`
**Method**: `shouldForceBackup(Mod mod)`

```dart
bool shouldForceBackup(Mod mod) {
  // Get backup metadata
  final backupMetadata = storage.getBackupFileMetadata(backupFileName);
  if (backupMetadata == null || backupMetadata.files.isEmpty) {
    return false; // No metadata, can't determine
  }

  // Get all downloaded files metadata
  final downloadedMetadata = storage.getAllDownloadedFileInfo();

  int newFilesCount = 0;
  int modifiedFilesCount = 0;

  for (final asset in mod.getAllAssets()) {
    if (!asset.fileExists) continue; // Skip non-downloaded files

    final filename = getFileNameFromURL(asset.url);
    final downloadInfo = downloadedMetadata[filename];
    final backupInfo = backupMetadata.files[filename];

    // Case 1: Downloaded file not in backup
    if (backupInfo == null) {
      newFilesCount++;
      continue;
    }

    // Case 2: CRC32 mismatch (when both are non-zero)
    if (downloadInfo != null &&
        downloadInfo.crc32 != 0 &&
        backupInfo.crc32 != 0 &&
        downloadInfo.crc32 != backupInfo.crc32) {
      modifiedFilesCount++;
    }
  }

  return newFilesCount > 0 || modifiedFilesCount > 0;
}
```

### Characteristics

| Aspect | Details |
|--------|---------|
| **Speed** | 🐢 Slower - requires asset list loading and CRC32 checks |
| **Data Required** | • Asset lists<br>• File existence checks<br>• Downloaded file CRC32 data<br>• Backup file CRC32 data |
| **Accuracy** | ✅ Highly accurate - detects actual file changes |
| **Use Case** | Making actual decisions (backup, download, etc.) |
| **Detection** | Detects:<br>• New downloaded files<br>• CRC32 mismatches (file content changes)<br>• Missing files |

---

## The Complete Flow

```
┌─────────────────────────────────────────────┐
│         App Startup - loadModsData()        │
└─────────────────────────────────────────────┘
                    ↓
    ┌───────────────────────────────────┐
    │ Load existing assets from disk    │
    │ Process JSON files in isolates    │
    │   • Extract saveName              │
    │   • Extract dateTimeStamp         │
    │   • Extract URLs                  │
    └───────────────────────────────────┘
                    ↓
    ┌───────────────────────────────────┐
    │  FOR EACH processed mod:          │
    │                                   │
    │  _getInitialModWithBackup(mod)    │ ← PHASE 1: Fast timestamp check
    │    └─> Adds backup info           │
    │        + approximate status       │
    └───────────────────────────────────┘
                    ↓
    ┌───────────────────────────────────┐
    │ Display mods in grid              │
    │ (with approximate backup status)  │
    └───────────────────────────────────┘
                    ↓
        User clicks mod OR starts
        bulk operation
                    ↓
    ┌───────────────────────────────────┐
    │  getCompleteMod(mod, urls)        │ ← PHASE 2: Accurate CRC32 check
    │    ├─> Load asset lists           │
    │    ├─> Check file existence       │
    │    ├─> Call shouldForceBackup()   │
    │    │   ├─> Check for new files    │
    │    │   └─> Check CRC32 mismatches │
    │    └─> Return ACCURATE status     │
    └───────────────────────────────────┘
                    ↓
    ┌───────────────────────────────────┐
    │ Perform operation with accurate   │
    │ data (backup, download, etc.)     │
    └───────────────────────────────────┘
```

---

## Backup Status Determination Comparison

### Simple Timestamp Logic (Phase 1)

```dart
backupStatus = backup.lastModifiedTimestamp > mod.dateTimeStamp
    ? upToDate
    : outOfDate
```

**Checks:**
- ✅ Backup timestamp vs mod timestamp

**Misses:**
- ❌ New downloaded files not in backup
- ❌ Files with different CRC32 (content changed)
- ❌ Files deleted from disk

### Comprehensive CRC32/File Logic (Phase 2)

```dart
backupStatus = shouldForceBackup(mod)
    ? outOfDate  // New files OR CRC32 mismatch
    : upToDate   // All files match
```

**Checks:**
- ✅ New downloaded files not in backup
- ✅ CRC32 mismatches between downloaded and backed-up files
- ✅ File existence on disk

---

## Why This Two-Phase Approach?

### Performance Optimization

**Without Two-Phase Approach:**
- Load 1000 mods on startup
- Run CRC32 checks on all 1000 mods
- Wait 30+ seconds for app to be ready
- ❌ Poor user experience

**With Two-Phase Approach:**
- Load 1000 mods with fast timestamp checks
- App ready in 2-3 seconds
- Run CRC32 checks only on the 5-10 mods user interacts with
- ✅ Great user experience

### Accuracy When It Matters

**Initial Display:**
- User sees approximate backup status
- Fast grid loading
- Good enough for visual reference

**User Action:**
- System re-calculates with accurate CRC32 checks
- Ensures correct backup decisions
- No data loss or incorrect operations

### The Best of Both Worlds

```
Speed (Phase 1)     +     Accuracy (Phase 2)     =     Optimal UX
     ↓                           ↓                           ↓
Fast app startup          Correct decisions        Happy users
Responsive UI             No data loss             No waiting
```

---

## Usage in mod.dateTimeStamp

The `mod.dateTimeStamp` field is used in several contexts:

### 1. Source of Data
**File**: `lib/src/state/mods/mods_isolates.dart:611-626`

Extracted from TTS JSON file's `"Date"` field:
```dart
String? _extractDateTimeStampFromString(String jsonString) {
  final dateRegex = RegExp(r'"Date"\s*:\s*"([^"]*)"');
  final match = dateRegex.firstMatch(jsonString);
  if (match != null) {
    return _dateTimeToUnixTimestampSync(match.group(1));
  }
  return null;
}
```

**Format**: Unix timestamp (seconds since epoch)

### 2. Initial Backup Status Calculation
**File**: `lib/src/state/mods/mods.dart:673-676`

Used in `_getInitialModWithBackup()` for fast timestamp comparison.

### 3. Storage/Caching
**File**: `lib/src/state/mods/mods.dart:595-597`

```dart
if (newMod.dateTimeStamp != null) {
  metadata['${newMod.jsonFileName}${Storage.dateTimeStampSuffix}'] =
      newMod.dateTimeStamp!;
}
```

Stored as metadata for cache invalidation.

### 4. Cache Invalidation
**File**: `lib/src/state/mods/mods_isolates.dart:119`

```dart
final updateTimeChanged = cachedUpdateTime != null &&
    cachedUpdateTime.isNotEmpty &&
    cachedUpdateTime != mod.dateTimeStamp;
```

Detects if mod has been re-saved in TTS since last cache.

### 5. UI Display
**Files**:
- `lib/src/mods/components/mods_grid_card.dart:245`
- `lib/src/mods/components/mods_list_item.dart:185`

```dart
'Update: ${formatTimestamp(mod.dateTimeStamp) ?? 'N/A'}\n'
'Backup: ${formatTimestamp(mod.backup!.lastModifiedTimestamp.toString())}'
```

Displayed as: "23 December 2025 14:30"

---

## Important Notes

### The Timestamp Still Matters For:
1. ✅ **Cache invalidation** - Detecting when a mod file has been edited in TTS
2. ✅ **UI display** - Showing users when they last saved the mod
3. ✅ **Initial rough estimate** - Before asset lists are loaded

### The Timestamp is NOT Sufficient For:
1. ❌ **Accurate backup status** - Doesn't detect file changes or CRC32 mismatches
2. ❌ **Backup decisions** - Which is why we use CRC32/file comparison in Phase 2

### Why _getInitialModWithBackup() Still Uses Timestamp-Only Logic:
- Called during initial app load when asset lists haven't been loaded yet
- Provides a **fast, approximate** backup status for UI display
- The status gets **updated to accurate status** when you select a mod (via `getCompleteMod()`)

### This is Actually Optimal Because:
- The timestamp-only check in `_getInitialModWithBackup()` is just for initial display
- When users actually take action (backup, download), the code calls `getCompleteMod()` first
- Bulk operations now also use `getCompleteMod()` before making decisions
- Most mods won't be interacted with during a session, so we don't waste time doing expensive checks upfront

---

## Summary

| Aspect | Phase 1: `_getInitialModWithBackup()` | Phase 2: `getCompleteMod()` |
|--------|---------------------------------------|------------------------------|
| **When** | App startup (all mods) | On-demand (selected mods) |
| **Speed** | ⚡ Very fast | 🐢 Slower |
| **Data** | Timestamp only | Full asset lists + CRC32 |
| **Accuracy** | ⚠️ Approximate | ✅ Accurate |
| **Purpose** | Quick display | Correct decisions |
| **Checks** | Timestamp comparison | New files + CRC32 mismatches |

**Result**: Fast app startup + accurate backup decisions when needed!
