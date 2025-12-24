# Changes Made - December 23, 2025

## 1. Multi-Select Feature Completion

### Overview
Completed the multi-select feature that allows users to select multiple mods using Shift+Click and Ctrl+Click, and then perform bulk operations on the selected mods.

### Files Modified

#### `lib/src/mods/components/mods_grid_card.dart` (Already Implemented)
- **Shift+Click**: Selects a range from the last selected mod to the clicked mod
- **Ctrl+Click (Cmd+Click on Mac)**: Toggles individual mods in/out of multi-selection
- **Normal Click**: Selects a single mod (clears multi-selection)
- **Visual Feedback**:
  - Single selection: White border
  - Multi-selection: Cyan border

#### `lib/src/mods/components/bulk_actions_menu.dart`
**Changes:**
- Added logic to use multi-selected mods when performing bulk operations
- All bulk action handlers now use `targetMods` which contains:
  - Multi-selected mods (if any are selected)
  - All filtered mods (if no multi-selection exists)
- Updated button labels to dynamically show selection count:
  - "Download all", "Backup all", etc. when no mods are selected
  - "Download 5 selected", "Backup 5 selected", etc. when mods are multi-selected

**Specific Updates (lines 80-245):**
- Added `targetMods` calculation in `_BulkActionsDropDownButton`
- Added `actionLabel` variable for dynamic button text
- Updated all menu items to use `targetMods`:
  - Download (line 121)
  - Backup (line 143)
  - Update URLs (line 168)
  - Download & Backup (line 197)

---

## 2. Backup Status Logic Refactoring

### Problem Identified
Two different backup status determination logics existed:

1. **Simple timestamp comparison** (in `mods.dart`):
   - Only checked if backup timestamp > mod timestamp
   - **Ignored**: New downloaded files, CRC32 mismatches

2. **Complete logic** (in `backup.dart` - `shouldForceBackup()`):
   - Checked for downloaded files not in backup
   - Checked CRC32 mismatches (when both non-zero)
   - Only used by the single-mod Backup button

This inconsistency meant "Replace if out of date" in bulk operations didn't properly detect file changes.

### Solution Implemented
Unified all backup status calculations to use the comprehensive CRC32/file comparison logic.

### Files Modified

#### `lib/src/state/mods/mods.dart`

**Line 38-51**: Added `backupProvider` to imports
```dart
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backedUpFilesProvider,
        backupProvider,  // Added
        directoriesProvider,
        // ... rest
```

**Lines 684-729**: Refactored `getCompleteMod()` method
```dart
Future<Mod> getCompleteMod(Mod mod, Map<String, String> jsonURLs) async {
  // ... get backup and asset lists ...

  // Create mod with asset lists so shouldForceBackup can check files
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
      backupStatus = ExistingBackupStatusEnum.outOfDate;
    } else {
      backupStatus = ExistingBackupStatusEnum.upToDate;
    }
  }

  return modWithAssets.copyWith(
    backup: backup,
    backupStatus: backupStatus,
  );
}
```

**Key Changes:**
- Moved backup status calculation to AFTER creating `modWithAssets` (so `shouldForceBackup` has access to asset lists)
- Now uses `shouldForceBackup()` from `BackupNotifier` for comprehensive file/CRC32 checking
- Removed simple timestamp-only comparison

#### `lib/src/state/bulk_actions/bulk_actions.dart`

**Lines 101-154**: Refactored `backupAllMods()` method

**Key Changes:**
- Moved `getCompleteMod()` call BEFORE backup status check (line 114-116)
- Changed from using `mod.backupStatus` to `completeMod.backupStatus` (line 121, 135)
- Now properly uses backup status with CRC32/file comparison
- Added debug logging for transparency

**Before:**
```dart
// Check backup status FIRST (using old timestamp-only logic)
if (mod.backupStatus != ExistingBackupStatusEnum.noBackup) {
  // Make decision...
}
// Then get complete mod later
final completeMod = await getCompleteMod(mod, modUrls);
```

**After:**
```dart
// Get complete mod FIRST (with CRC32/file checks)
final completeMod = await getCompleteMod(mod, modUrls);

// Then check backup status using comprehensive logic
if (completeMod.backupStatus != ExistingBackupStatusEnum.noBackup) {
  // Make decision with accurate status...
}
```

**Lines 178-245**: Refactored `downloadAndBackupAllMods()` method

**Key Changes:**
- Re-calculates backup status AFTER downloading files (lines 208-210)
- Uses `updatedMod` with fresh CRC32 data for backup decisions (line 215)
- Ensures "Replace if out of date" works correctly with newly downloaded files
- Added debug logging

**Logic Flow:**
1. Download all files for the mod
2. Re-fetch the mod to get updated CRC32 data from downloaded files
3. Check backup status using the updated mod
4. Make backup decision based on comprehensive file comparison

### How "Replace if out of date" Now Works

The option now properly checks:

1. **New Files**: Are there downloaded files missing from the backup?
2. **CRC32 Mismatch**: Do any files have different checksums (when both non-zero)?

**Determination Logic (from `BackupNotifier.shouldForceBackup()`):**

```dart
// For each downloaded file:
// 1. Check if file exists in backup
if (backupInfo == null) {
  // File is new - not in backup
  return true; // Out of date
}

// 2. Check CRC32 mismatch
if (downloadInfo.crc32 != 0 &&
    backupInfo.crc32 != 0 &&
    downloadInfo.crc32 != backupInfo.crc32) {
  // File has changed
  return true; // Out of date
}
```

**Result:**
- `outOfDate` → Backup will be replaced
- `upToDate` → Backup will be skipped

### File Preservation (Already Working)

The existing file preservation logic in `createBackup()` continues to work correctly:
- Extracts files from old backup that aren't in the current downloaded set
- Preserves their directory structure
- Includes them in the new backup

This ensures backups contain:
- ✅ All newly downloaded files
- ✅ Files from the old backup that weren't re-downloaded
- ✅ Proper CRC32 metadata for all files

---

## Benefits of These Changes

### Multi-Select Feature
1. More efficient bulk operations on specific mods
2. Ability to select non-contiguous mods (Ctrl+Click)
3. Ability to select ranges (Shift+Click)
4. Clear visual feedback with cyan borders
5. Dynamic button labels showing selection count

### Backup Status Logic
1. **Accurate backup detection**: No longer relies solely on timestamps
2. **Content-aware decisions**: Detects actual file changes via CRC32
3. **Consistent behavior**: Single-mod and bulk operations use same logic
4. **Better efficiency**: "Replace if out of date" only backs up what actually changed
5. **File preservation**: Old backup files are retained in new backups

---

## Testing Recommendations

### Multi-Select Feature
1. Test Shift+Click range selection
2. Test Ctrl+Click toggle selection
3. Verify bulk download works with selection
4. Verify bulk backup works with selection
5. Check that button labels update correctly

### Backup Status Logic
1. Create a backup of a mod
2. Download one new file for that mod
3. Use "Replace if out of date" bulk backup
4. Verify it replaces the backup (because new file was added)
5. Run "Replace if out of date" again
6. Verify it skips (because backup is now current)
7. Verify old files are preserved in new backup

---

## 3. UI Wording Improvement - Bulk Backup Dialog

### Change Made
Updated the bulk backup dialog option from "Replace if out of date" to "Replace if necessary" to better reflect the comprehensive CRC32/file comparison logic.

### File Modified

#### `lib/src/state/bulk_actions/bulk_actions_state.dart`
**Line 12**: Changed enum label
```dart
enum BulkBackupBehaviorEnum {
  skip('Skip'),
  replace('Replace'),
  replaceIfOutOfDate('Replace if necessary');  // Changed from 'Replace if out of date'
  
  final String label;
  const BulkBackupBehaviorEnum(this.label);
}
```

### Rationale

The previous wording "Replace if out of date" implied only a timestamp comparison, which was misleading after implementing the comprehensive backup status logic.

The new wording "Replace if necessary" better describes that the system:
- ✅ Checks for new downloaded files not in backup
- ✅ Detects CRC32 mismatches (file content changes)
- ✅ Makes an intelligent decision about whether replacement is needed

This change provides clearer communication to users about what the option actually does.

### Dialog Options Summary

| Option | Behavior |
|--------|----------|
| **Skip** | Don't backup if a backup already exists |
| **Replace** | Always replace existing backups |
| **Replace if necessary** | Only replace if files have changed (new files or CRC32 mismatch) |
