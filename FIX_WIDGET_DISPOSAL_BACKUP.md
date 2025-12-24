# Fix: Widget Disposal During Backup Operations

## Problem
After backing up a mod:
1. Blue border doesn't appear on AssetURL
2. Folder icon doesn't appear in mods selector
3. Pressing backup button again re-triggers backup (says "No backup exists")

## Root Cause Analysis

### Issue 1: Service Returning Wrong Value
The service was returning a `BackupDecision` object even when backup completed successfully, instead of returning `null`. The widget checked `if (decision == null)` to know when to update UI, so it never entered the update block.

### Issue 2: Widget Disposed During Long-Running Backup
The `createBackup()` operation runs in an isolate and takes time. During this operation, the widget could be disposed (user navigating away, widget rebuild, etc.). When the backup completes and tries to update UI using the widget's `ref`, it throws "Cannot use ref after widget was disposed".

### Issue 3: Stale Mod Object on Second Press
Even though the backup was successfully created and added to `existingBackupsProvider`, the mod object in memory still had `backup: null` because the UI update failed. On the second button press, the stale mod object was used, causing the backup to be re-triggered.

## Solution

### Fix 1: Service Returns Null on Success
**File:** `mod_operations_service.dart:85`
```dart
// Return null to indicate backup completed successfully
return null;
```

### Fix 2: Let Service Handle UI Updates
**File:** `selected_mod_action_buttons.dart`
- Changed all operations to use `updateUI: true`
- Service catches disposal errors gracefully in `_refreshModUI()`
- Errors are logged but don't crash the app

### Fix 3: Enhanced `_refreshModUI`
**File:** `mod_operations_service.dart:144-159`
```dart
Future<void> _refreshModUI(Mod mod) async {
  try {
    await ref.read(modsProvider.notifier).refreshModsInfo([mod]);

    // Also update the selected mod to ensure UI reflects the change
    final selectedMod = ref.read(selectedModProvider);
    if (selectedMod?.jsonFilePath == mod.jsonFilePath) {
      await ref.read(modsProvider.notifier).updateSelectedMod(mod);
    }
  } catch (e) {
    debugPrint('_refreshModUI error (likely widget disposed): $e');
    // Even if update fails, the state in existingBackupsProvider is correct
    // UI will update on next natural rebuild
  }
}
```

### Fix 4: Refresh Mod Before Making Decisions
**File:** `selected_mod_action_buttons.dart:64-69`
```dart
// Get fresh mod with latest backup info before making decisions
final urls = await ref.read(modsProvider.notifier).getUrlsByMod(selectedMod);
final freshMod = await ref.read(modsProvider.notifier).getCompleteMod(selectedMod, urls);

debugPrint('After refresh - backup: ${freshMod.backup?.filepath ?? "null"}');
debugPrint('After refresh - backup status: ${freshMod.backupStatus}');
```

This ensures that even if the previous UI update failed due to disposal, we always get the latest backup info from `existingBackupsProvider` before making backup decisions.

## Expected Behavior Now

### First Backup Press:
```
=== BACKUP BUTTON PRESSED ===
Selected mod: Akrotiri
Current backup: null
After refresh - backup: null (no backup in provider yet)
Calling service.backupMod()...
Backup decision for Akrotiri: No backup exists
[Backup creation happens in isolate]
addBackup - Adding backup: Akrotiri (923364917).ttsmod
service.backupMod() returned, decision: null (backup completed)
Backup completed successfully
```

If widget is disposed during backup:
```
_refreshModUI error (likely widget disposed): Bad state: Cannot use "ref"
```
This is handled gracefully - state is correct, UI updates on next interaction.

### Second Backup Press:
```
=== BACKUP BUTTON PRESSED ===
Selected mod: Akrotiri
Current backup: null (old prop)
After refresh - backup: /path/to/backup.ttsmod (fresh from provider!)
Calling service.backupMod()...
Backup decision for Akrotiri: Backup exists - needs user choice
[Shows confirmation dialog]
```

## Key Points

1. **Backup always succeeds** - Even if UI update fails, backup is in `existingBackupsProvider`
2. **Fresh mod on every press** - Button handler refreshes mod to get latest backup info
3. **Graceful disposal handling** - Errors are caught and logged, app doesn't crash
4. **UI updates when possible** - If widget is still mounted, UI updates immediately
5. **UI updates eventually** - If widget is disposed, UI updates on next rebuild/interaction

## Files Changed

1. `mod_operations_service.dart`:
   - Return `null` on successful backup completion
   - Enhanced `_refreshModUI` to update selected mod
   - Added `selectedModProvider` import

2. `selected_mod_action_buttons.dart`:
   - Changed to `updateUI: true` for all operations
   - Refresh mod at start of backup handler
   - Use `freshMod` for all backup operations
   - Simplified error handling (let service handle it)

3. Added comprehensive debug logging throughout the flow
