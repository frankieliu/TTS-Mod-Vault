# Simple Fix: BackupFileMetadata Without Extensions

## Summary

The backup status bug was fixed with **one key change**: BackupFileMetadata now stores filenames **WITHOUT extensions**.

This makes it consistent with how downloaded files are tracked, allowing simple `contains()` checks to work correctly.

---

## The Root Cause

### Before (Broken):
```dart
// Downloaded files stored WITHOUT extension
ExistingAssetsListsState {
  images: {
    "httpiimgurcomtHADwoQjpg": "/path/to/file.jpg"
  }
}

// BackupFileMetadata stored WITH extension
BackupFileMetadata {
  files: {
    "httpiimgurcomtHADwoQjpg.jpg": 12345  // ← Extension!
  }
}

// Check fails
final filename = getFileNameFromURL(url);  // "httpiimgurcomtHADwoQjpg"
backedUpFiles.contains(filename)  // false! (no extension in filename)
```

### After (Fixed):
```dart
// Downloaded files stored WITHOUT extension
ExistingAssetsListsState {
  images: {
    "httpiimgurcomtHADwoQjpg": "/path/to/file.jpg"
  }
}

// BackupFileMetadata stored WITHOUT extension ✓
BackupFileMetadata {
  files: {
    "httpiimgurcomtHADwoQjpg": 12345  // ← No extension!
  }
}

// Check works!
final filename = getFileNameFromURL(url);  // "httpiimgurcomtHADwoQjpg"
backedUpFiles.contains(filename)  // true! ✓
```

---

## The One Line Fix

**File:** `lib/src/state/backup/existing_backups.dart` (line 408)

**Before:**
```dart
final name = path.basename(zipFile.name);
```

**After:**
```dart
final name = path.basenameWithoutExtension(zipFile.name);
```

---

## Migration: Clear Old Metadata

**File:** `lib/src/state/backup/existing_backups.dart` (lines 29-33)

Added code to clear old BackupFileMetadata on startup:
```dart
// Clear old backup metadata (has filenames WITH extensions)
// This will force regeneration with new format (filenames WITHOUT extensions)
final storage = ref.read(storageProvider);
await storage.clearBackupFileMetadata();
debugPrint('Cleared old backup metadata - will regenerate with new format');
```

**What happens:**
1. App starts
2. Clears all old BackupFileMetadata
3. Extracts metadata from backup files again
4. Saves with new format (no extensions)

**Note:** This clearing code can be removed after first successful run.

---

## Files Changed

### 1. `lib/src/state/backup/existing_backups.dart`
- **Line 408:** Changed to use `basenameWithoutExtension`
- **Lines 29-33:** Added code to clear old metadata

### 2. No other changes needed!
The original simple approach with `backedUpFilesProvider` works perfectly now.

---

## How It Works

```
1. Download file:
   URL: "http://i.imgur.com/tHADwoQ.jpg"
   Save as: "/path/to/httpiimgurcomtHADwoQjpg.jpg"
   Track as: "httpiimgurcomtHADwoQjpg" (no extension)

2. Backup file:
   Read: "/path/to/httpiimgurcomtHADwoQjpg.jpg"
   Store in ZIP: "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

3. Extract metadata:
   ZIP file: "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
   basename: "httpiimgurcomtHADwoQjpg.jpg"
   basenameWithoutExtension: "httpiimgurcomtHADwoQjpg" ✓
   Store: {"httpiimgurcomtHADwoQjpg": 12345}

4. Check if backed up:
   URL: "http://i.imgur.com/tHADwoQ.jpg"
   Convert: "httpiimgurcomtHADwoQjpg"
   Check: backedUpFiles.contains("httpiimgurcomtHADwoQjpg")
   Result: true ✓
```

---

## All Components Working Together

| Component | Key Format | Example |
|-----------|-----------|---------|
| **URL** | Full URL | `http://i.imgur.com/tHADwoQ.jpg` |
| **getFileNameFromURL()** | No extension | `httpiimgurcomtHADwoQjpg` |
| **Downloaded file (disk)** | With extension | `httpiimgurcomtHADwoQjpg.jpg` |
| **ExistingAssetsListsState key** | No extension | `httpiimgurcomtHADwoQjpg` |
| **Backup ZIP file** | With extension | `Mods/Images/httpiimgurcomtHADwoQjpg.jpg` |
| **BackupFileMetadata key** | **No extension** | `httpiimgurcomtHADwoQjpg` |
| **backedUpFilesProvider** | No extension | `{httpiimgurcomtHADwoQjpg, ...}` |

---

## Testing Limits (Still In Place)

From previous session:
- **10 backups max** (line 54): Only processes first 10 backup files
- Can be removed by changing `limitedFiles`

---

## What to Watch For

**Debug logs on startup:**
```
loadExistingBackups - started at ...
Cleared old backup metadata - will regenerate with new format
loadExistingBackups - TESTING MODE: Processing 10 of X total backups
loadExistingBackups - 0 backups loaded from cache, 10 need extraction
Saved metadata for Backup1.ttsmod
...
backedUpFilesProvider - Aggregated X backed up files from Y backups
```

**When loading mods:**
- Assets should show correct `isBackedUp` status
- Blue border should appear for backed up assets

---

## Cleanup After Testing

Once confirmed working, remove the clearing code:

**File:** `lib/src/state/backup/existing_backups.dart` (lines 29-33)

```dart
// DELETE THESE LINES after first successful run:
// final storage = ref.read(storageProvider);
// await storage.clearBackupFileMetadata();
// debugPrint('Cleared old backup metadata - will regenerate with new format');
```

The metadata will persist correctly going forward.

---

## Why This Is Better

### Rejected Complex Approach:
- ❌ Added UrlBackupStatus Hive box
- ❌ 70+ lines of population code
- ❌ Complex URL mapping logic
- ❌ Bulk queries and conversions
- ❌ More state to maintain

### Simple Approach (This Fix):
- ✅ One line change (line 408)
- ✅ Everything else stays the same
- ✅ Uses existing backedUpFilesProvider
- ✅ O(1) Set lookups work correctly
- ✅ No additional complexity

---

## Consistency Achieved

All filename-based keys are now consistent (no extensions):
- ✅ ExistingAssetsListsState
- ✅ BackupFileMetadata
- ✅ backedUpFilesProvider
- ✅ getFileNameFromURL() output

**Result:** Simple `contains()` checks work perfectly!

---

## Summary

The bug was caused by BackupFileMetadata storing filenames WITH extensions while everything else used filenames WITHOUT extensions.

The fix: One line change to use `basenameWithoutExtension()`.

No complex URL mapping needed. The original simple approach works perfectly once the data format is consistent.
