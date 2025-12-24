# Code Consolidation Refactoring Plan

## Goal
Consolidate duplicate download/backup logic between single-mod and bulk operations into a unified architecture.

## Current State Analysis

### Code Duplication

**Download Logic:**
- Single mod: `selected_mod_action_buttons.dart:54-56`
- Bulk download: `bulk_actions.dart:70-72`
- Bulk download+backup: `bulk_actions.dart:192-193`

**Backup Logic:**
- Single mod: `selected_mod_action_buttons.dart:61-139` (complex interactive)
- Bulk backup: `bulk_actions.dart:112-151` (behavior-based)
- Bulk download+backup: `bulk_actions.dart:199-234` (behavior-based)

**State Update Logic:**
- Single mod: `updateSelectedMod()` after each operation
- Bulk: `_refreshBackupInfo()` at end (we'll change to per-mod)

### Total Duplication: ~250 lines

---

## Refactoring Plan

### Phase 1: Create Core Service (New File)
**File:** `lib/src/state/mod_operations/mod_operations_service.dart`

**Purpose:** Unified service for all mod operations

**Methods:**
```dart
class ModOperationsService {
  final Ref ref;

  // Download operations
  Future<void> downloadMod(Mod mod, {bool updateUI = true});
  Future<void> downloadMods(List<Mod> mods, {bool showProgress = false});

  // Backup operations
  Future<void> backupMod(Mod mod, {BackupConfig? config});
  Future<void> backupMods(List<Mod> mods, BackupConfig config);

  // Combined operation
  Future<void> downloadAndBackupMods(List<Mod> mods, BackupConfig config);

  // Helper methods
  Future<void> _refreshModUI(Mod mod);
  Future<BackupDecision> _determineBackupAction(Mod mod, BackupConfig config);
}
```

### Phase 2: Extract Backup Decision Logic (New File)
**File:** `lib/src/state/mod_operations/backup_decision.dart`

**Purpose:** Centralized backup decision-making

**Classes:**
```dart
class BackupConfig {
  final BackupBehavior behavior;
  final String? targetFolder;
  final bool force;
  final bool showDialogs;  // For single-mod interactive mode
}

enum BackupBehavior {
  skip,           // Don't backup if exists
  replace,        // Always replace
  replaceIfNecessary,  // Check files/CRC32
  interactive,    // Show dialogs (single-mod only)
}

class BackupDecision {
  final bool shouldBackup;
  final String? targetFolder;
  final String reason;
  final bool needsConfirmation;
}
```

### Phase 3: Update Bulk Actions to Use Service
**File:** `lib/src/state/bulk_actions/bulk_actions.dart`

**Changes:**
- Replace `downloadAllMods()` → Call `ModOperationsService.downloadMods()`
- Replace `backupAllMods()` → Call `ModOperationsService.backupMods()`
- Replace `downloadAndBackupAllMods()` → Call `ModOperationsService.downloadAndBackupMods()`
- Remove duplicate logic (~150 lines removed)

### Phase 4: Update Single Mod Actions to Use Service
**File:** `lib/src/mods/components/selected_mod_action_buttons.dart`

**Changes:**
- Replace download button logic → Call `ModOperationsService.downloadMod()`
- Replace backup button logic → Call `ModOperationsService.backupMod()`
- Keep Force checkbox, pass to config
- Simplify from ~170 lines to ~50 lines

### Phase 5: Per-Mod UI Updates (Fix)
- Change bulk operations to update UI after each mod completes
- Remove batch refresh at end
- Use unified `_refreshModUI()` method

---

## Implementation Steps

### Step 1: Create mod_operations directory
```
mkdir -p lib/src/state/mod_operations
```

### Step 2: Create backup_decision.dart
Define `BackupConfig`, `BackupBehavior`, `BackupDecision` classes

### Step 3: Create mod_operations_service.dart
Implement unified service with all methods

### Step 4: Update bulk_actions.dart
Replace implementations with service calls

### Step 5: Update selected_mod_action_buttons.dart
Replace implementations with service calls

### Step 6: Add to provider.dart
Export `modOperationsServiceProvider`

### Step 7: Test
- Test single mod download
- Test single mod backup
- Test bulk download
- Test bulk backup
- Test bulk download+backup
- Verify UI updates correctly

---

## Detailed Implementation

### File 1: backup_decision.dart

```dart
enum BackupBehavior {
  skip,
  replace,
  replaceIfNecessary,
  interactive,
}

class BackupConfig {
  final BackupBehavior behavior;
  final String? targetFolder;
  final bool force;
  final bool showDialogs;

  const BackupConfig({
    required this.behavior,
    this.targetFolder,
    this.force = false,
    this.showDialogs = false,
  });

  // Factory for single-mod interactive
  factory BackupConfig.interactive({bool force = false}) {
    return BackupConfig(
      behavior: force ? BackupBehavior.replace : BackupBehavior.interactive,
      showDialogs: true,
      force: force,
    );
  }

  // Factory for bulk operations
  factory BackupConfig.bulk({
    required BackupBehavior behavior,
    String? folder,
  }) {
    return BackupConfig(
      behavior: behavior,
      targetFolder: folder,
      showDialogs: false,
    );
  }
}

class BackupDecision {
  final bool shouldBackup;
  final String? targetFolder;
  final String reason;
  final bool needsConfirmation;

  const BackupDecision({
    required this.shouldBackup,
    this.targetFolder,
    required this.reason,
    this.needsConfirmation = false,
  });

  factory BackupDecision.skip(String reason) {
    return BackupDecision(
      shouldBackup: false,
      reason: reason,
    );
  }

  factory BackupDecision.backup({
    required String folder,
    required String reason,
    bool needsConfirmation = false,
  }) {
    return BackupDecision(
      shouldBackup: true,
      targetFolder: folder,
      reason: reason,
      needsConfirmation: needsConfirmation,
    );
  }
}
```

### File 2: mod_operations_service.dart

```dart
class ModOperationsService {
  final Ref ref;

  ModOperationsService(this.ref);

  // ============ Download Operations ============

  Future<void> downloadMod(Mod mod, {bool updateUI = true}) async {
    await ref.read(downloadProvider.notifier).downloadAllFiles(mod);

    if (updateUI) {
      await _refreshModUI(mod);
    }
  }

  Future<void> downloadMods(
    List<Mod> mods, {
    void Function(int current, int total)? onProgress,
  }) async {
    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (onProgress != null) {
        onProgress(i + 1, mods.length);
      }

      await downloadMod(mod, updateUI: true);
    }
  }

  // ============ Backup Operations ============

  Future<void> backupMod(
    Mod mod,
    BackupConfig config,
  ) async {
    final decision = await _determineBackupAction(mod, config);

    if (!decision.shouldBackup) {
      debugPrint('Skipping backup: ${decision.reason}');
      return;
    }

    // If interactive and needs confirmation, caller should handle dialog
    // For bulk operations, no confirmation needed

    await ref.read(backupProvider.notifier).createBackup(
      mod,
      decision.targetFolder,
    );

    await _refreshModUI(mod);
  }

  Future<void> backupMods(
    List<Mod> mods,
    BackupConfig config,
    {
      void Function(int current, int total)? onProgress,
    }
  ) async {
    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (onProgress != null) {
        onProgress(i + 1, mods.length);
      }

      // Get complete mod with CRC32 checks for decision making
      final urls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final completeMod = await ref.read(modsProvider.notifier).getCompleteMod(mod, urls);

      await backupMod(completeMod, config);
    }
  }

  // ============ Combined Operations ============

  Future<void> downloadAndBackupMods(
    List<Mod> mods,
    BackupConfig config,
    {
      void Function(int current, int total, String phase)? onProgress,
    }
  ) async {
    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      // Download phase
      if (onProgress != null) {
        onProgress(i + 1, mods.length, 'Downloading');
      }
      await downloadMod(mod, updateUI: true);

      // Backup phase
      if (onProgress != null) {
        onProgress(i + 1, mods.length, 'Backing up');
      }

      // Get fresh mod data after download
      final urls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final updatedMod = await ref.read(modsProvider.notifier).getCompleteMod(mod, urls);

      await backupMod(updatedMod, config);
    }
  }

  // ============ Helper Methods ============

  Future<void> _refreshModUI(Mod mod) async {
    await ref.read(modsProvider.notifier).refreshModsInfo([mod]);
  }

  Future<BackupDecision> _determineBackupAction(
    Mod mod,
    BackupConfig config,
  ) async {
    // No existing backup → Always backup
    if (mod.backup == null) {
      return BackupDecision.backup(
        folder: config.targetFolder ?? await _getDefaultBackupFolder(),
        reason: 'No backup exists',
      );
    }

    // Force flag set → Always replace
    if (config.force) {
      return BackupDecision.backup(
        folder: config.targetFolder ?? p.dirname(mod.backup!.filepath),
        reason: 'Force flag set',
      );
    }

    // Apply behavior
    switch (config.behavior) {
      case BackupBehavior.skip:
        return BackupDecision.skip('Backup exists (skip behavior)');

      case BackupBehavior.replace:
        return BackupDecision.backup(
          folder: config.targetFolder ?? p.dirname(mod.backup!.filepath),
          reason: 'Replace existing backup',
        );

      case BackupBehavior.replaceIfNecessary:
        final shouldForce = ref.read(backupProvider.notifier).shouldForceBackup(mod);
        if (shouldForce) {
          return BackupDecision.backup(
            folder: config.targetFolder ?? p.dirname(mod.backup!.filepath),
            reason: 'Files changed (CRC32 mismatch or new files)',
          );
        } else {
          return BackupDecision.skip('Backup is up to date');
        }

      case BackupBehavior.interactive:
        // For interactive mode, return decision with needsConfirmation flag
        // The UI layer will show dialogs and call backupMod again
        final shouldForce = ref.read(backupProvider.notifier).shouldForceBackup(mod);
        return BackupDecision.backup(
          folder: p.dirname(mod.backup!.filepath),
          reason: shouldForce
            ? 'Files changed - needs confirmation'
            : 'Backup exists - needs user choice',
          needsConfirmation: true,
        );
    }
  }

  Future<String> _getDefaultBackupFolder() async {
    final backupsDir = ref.read(directoriesProvider).backupsDir;
    if (backupsDir.isNotEmpty) {
      return backupsDir;
    }

    // Prompt user for folder
    final folder = await FilePicker.platform.getDirectoryPath(lockParentWindow: true);
    return folder ?? backupsDir;
  }
}
```

---

## Migration Guide

### Before (Single Mod):
```dart
ElevatedButton(
  onPressed: () async {
    await downloadNotifier.downloadAllFiles(selectedMod);
    await modsNotifier.updateSelectedMod(selectedMod);
  },
  child: Text('Download'),
)
```

### After (Single Mod):
```dart
ElevatedButton(
  onPressed: () async {
    final service = ModOperationsService(ref);
    await service.downloadMod(selectedMod);
  },
  child: Text('Download'),
)
```

### Before (Bulk):
```dart
Future<void> downloadAllMods(List<Mod> mods) async {
  // 40 lines of implementation
  for (final mod in mods) {
    // progress tracking
    await downloadProvider.downloadAllFiles(mod);
  }
  await _refreshBackupInfo(mods);
}
```

### After (Bulk):
```dart
Future<void> downloadAllMods(List<Mod> mods) async {
  final service = ModOperationsService(ref);

  await service.downloadMods(
    mods,
    onProgress: (current, total) {
      state = state.copyWith(
        currentModNumber: current,
        statusMessage: 'Downloading ($current/$total)',
      );
    },
  );
}
```

---

## Benefits

1. **Single Source of Truth**
   - All download/backup logic in one place
   - Easy to maintain and test

2. **Reduced Code**
   - ~250 lines of duplication removed
   - Simpler button implementations
   - Clearer bulk actions

3. **Consistent Behavior**
   - Same logic for single and bulk
   - Predictable outcomes

4. **Easier Testing**
   - Test service independently
   - Mock for UI tests

5. **Future Extensibility**
   - Easy to add new operations
   - Easy to modify behavior

---

## Files Changed Summary

**New Files (3):**
- `lib/src/state/mod_operations/mod_operations_service.dart` (~200 lines)
- `lib/src/state/mod_operations/backup_decision.dart` (~100 lines)
- `lib/src/state/mod_operations/mod_operations_provider.dart` (~20 lines)

**Modified Files (3):**
- `lib/src/state/bulk_actions/bulk_actions.dart` (-150 lines, +50 lines)
- `lib/src/mods/components/selected_mod_action_buttons.dart` (-120 lines, +30 lines)
- `lib/src/state/provider.dart` (+5 lines)

**Net Change:**
- +320 new lines (service + models)
- -270 duplicate lines removed
- **+50 total lines** (but much cleaner!)

---

## Testing Plan

1. ✅ Test single mod download
2. ✅ Test single mod backup (interactive)
3. ✅ Test single mod backup (force)
4. ✅ Test bulk download (5 mods)
5. ✅ Test bulk backup (skip behavior)
6. ✅ Test bulk backup (replace behavior)
7. ✅ Test bulk backup (replaceIfNecessary behavior)
8. ✅ Test bulk download+backup
9. ✅ Verify UI updates after each mod
10. ✅ Test cancellation

---

## Timeline

- **Step 1-2:** Create models and enums (30 min)
- **Step 3:** Create service (1 hour)
- **Step 4:** Update bulk actions (30 min)
- **Step 5:** Update single mod buttons (30 min)
- **Step 6:** Add provider (15 min)
- **Step 7:** Testing (1 hour)

**Total:** ~3.5 hours

---

## Risk Mitigation

1. **Backup existing files** before changes
2. **Incremental testing** after each step
3. **Git commits** at each phase
4. **Keep old code commented** until fully tested

---

## Success Criteria

✅ Single mod operations work identically to before
✅ Bulk operations work identically to before
✅ UI updates correctly after each operation
✅ No regression in functionality
✅ Code is cleaner and more maintainable
✅ All tests pass

---

## Next: Implementation

Ready to proceed with implementation!
