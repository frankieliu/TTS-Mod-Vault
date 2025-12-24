# Widget Disposal Issue - Detailed Explanation

## What Widget Are We Talking About?

The widget is **`SelectedModActionButtons`** - this is the UI component that displays the Download, Backup, and Update URLs buttons when you select a mod.

```dart
class SelectedModActionButtons extends HookConsumerWidget {
  final Mod selectedMod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Button handlers are defined here
    return Row(
      children: [
        ElevatedButton(onPressed: downloadHandler, ...),
        ElevatedButton(onPressed: backupHandler, ...),
        ...
      ]
    );
  }
}
```

## Why Is It Being Disposed?

In Flutter, widgets are **rebuilt and disposed constantly** as part of the normal UI lifecycle. Here's when this specific widget gets disposed:

### Common Scenarios:

1. **User selects a different mod** - When you click on a different mod in the list, Flutter disposes the old `SelectedModActionButtons` widget (for Mod A) and creates a new one (for Mod B)

2. **User navigates away** - If you switch tabs, close the mod details panel, or navigate to a different screen

3. **UI rebuild** - Flutter may rebuild the widget tree for various reasons (state changes, layout changes, etc.)

4. **Parent widget rebuilds** - If any parent widget rebuilds, child widgets may be disposed and recreated

## The Problem: Timing Issue

Here's the sequence that was causing the bug:

```
1. User clicks "Backup" button
   └─ Backup button handler starts

2. Handler calls service.backupMod()
   └─ Service starts createBackup()

3. createBackup() spawns an ISOLATE (separate thread)
   └─ This takes 5-10 seconds to zip all files

4. [MEANWHILE] User clicks on a different mod
   └─ Flutter disposes SelectedModActionButtons widget
   └─ The WidgetRef becomes INVALID

5. Backup completes in the isolate
   └─ Tries to call: ref.read(modsProvider.notifier).updateSelectedMod()
   └─ ❌ ERROR: "Cannot use ref after widget was disposed"
   └─ UI never updates!
```

## Visual Timeline

```
TIME →
═══════════════════════════════════════════════════════════════════

User:    [Click Backup]         [Click Different Mod]
           │                            │
Widget:    │                            ├──── Widget DISPOSED
           │                            │
           │                            │
Backup:    ├──[Start]──────────────────┼──[Complete]──X (Ref invalid!)
           │   Isolate running...       │
           │                            │
           5 seconds                    │
                                        └── New widget created for other mod
```

## The WidgetRef Problem

`WidgetRef` is a Flutter/Riverpod concept that provides access to providers **only while the widget is alive**:

```dart
class SelectedModActionButtons extends HookConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    // 'ref' is valid ONLY while this widget instance exists

    onPressed: () async {
      await longRunningOperation();  // Takes 10 seconds

      // If widget was disposed during longRunningOperation(),
      // using 'ref' here will throw an error!
      await ref.read(modsProvider.notifier).updateSelectedMod();  // ❌
    }
  }
}
```

## Why Doesn't This Happen for Download?

The download operation **also** runs in an isolate and takes time, but we probably don't see the error because:
1. Download is usually faster (fewer files)
2. Users are less likely to switch mods during download
3. The error might be happening but UI updates on next rebuild anyway
4. **NOW FIXED**: Download now uses `updateUI: true` so service handles the update safely

## The Solution Explained

### Before (❌ Broken):
```dart
// In widget - using WidgetRef
onPressed: () async {
  await service.backupMod(mod, config, updateUI: false);

  // Widget might be disposed here!
  await ref.read(modsProvider.notifier).updateSelectedMod(mod);  // ❌ Crash
}
```

### After (✅ Fixed):
```dart
// In widget - delegate to service
onPressed: () async {
  // Let service handle updates with its own Ref (not tied to widget lifecycle)
  await service.backupMod(mod, config, updateUI: true);
}

// In service (mod_operations_service.dart)
class ModOperationsService {
  final dynamic ref;  // This is Ref, not WidgetRef - stays valid!

  Future<void> _refreshModUI(Mod mod) async {
    try {
      // This ref is not tied to widget lifecycle
      await ref.read(modsProvider.notifier).updateSelectedMod(mod);
    } catch (e) {
      // If it fails, no crash - just log and continue
      debugPrint('Update failed: $e');
    }
  }
}
```

### Plus: Refresh on Every Button Press (Backup)
```dart
// Get FRESH mod data from existingBackupsProvider before making decisions
final urls = await ref.read(modsProvider.notifier).getUrlsByMod(selectedMod);
final freshMod = await ref.read(modsProvider.notifier).getCompleteMod(selectedMod, urls);
```

This ensures that even if the previous update failed, the second button press will see the correct backup state.

## Why Does `existingBackupsProvider` Stay Valid?

The backup IS successfully added to `existingBackupsProvider` state because that happens in `backup.dart:391`:

```dart
ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
```

This uses the **BackupNotifier's** ref (which is a service-level `Ref`, not a widget's `WidgetRef`), so it always succeeds regardless of which widgets are alive.

The problem was only with updating the **mod object** to reference that backup.

## Key Differences: WidgetRef vs Ref

| Aspect | WidgetRef | Ref (in Notifier/Service) |
|--------|-----------|---------------------------|
| Lifetime | Tied to widget lifecycle | Tied to provider lifecycle |
| Valid when widget disposed? | ❌ No | ✅ Yes |
| Used in | Widget build methods | StateNotifiers, services |
| Safe for async operations? | ⚠️ Only if widget stays alive | ✅ Yes |

## Summary

- **Widget**: `SelectedModActionButtons` (the buttons you see when a mod is selected)
- **Why disposed**: Normal Flutter lifecycle - user switches mods, navigates away, etc.
- **Problem**: Long-running backup/download completes after widget disposal, can't update UI with invalid WidgetRef
- **Solution**:
  1. Let service handle updates (service's Ref is valid)
  2. Wrap updates in try-catch to gracefully handle any failures
  3. Refresh mod state on button press to ensure latest data
- **Result**: Operations always complete successfully, UI updates when possible, no crashes

## Files Protected From Widget Disposal

### ✅ Download Button (selected_mod_action_buttons.dart:45-53)
```dart
ElevatedButton(
  onPressed: hasMissingFiles
      ? () async {
          if (actionInProgress) return;
          await service.downloadMod(selectedMod, updateUI: true);  // Safe!
        }
      : null,
  child: const Text('Download'),
)
```

### ✅ Backup Button (selected_mod_action_buttons.dart:55-159)
```dart
ElevatedButton(
  onPressed: () async {
    if (actionInProgress) return;

    // Refresh mod first to get latest backup state
    final freshMod = await ref.read(modsProvider.notifier).getCompleteMod(...);

    // Let service handle updates
    await service.backupMod(freshMod, config, updateUI: true);  // Safe!
  },
  child: const Text('Backup'),
)
```

### ✅ Service Methods (mod_operations_service.dart)
All service methods use try-catch in `_refreshModUI()` to gracefully handle disposal:

```dart
Future<void> _refreshModUI(Mod mod) async {
  try {
    await ref.read(modsProvider.notifier).refreshModsInfo([mod]);

    final selectedMod = ref.read(selectedModProvider);
    if (selectedMod?.jsonFilePath == mod.jsonFilePath) {
      await ref.read(modsProvider.notifier).updateSelectedMod(mod);
    }
  } catch (e) {
    debugPrint('_refreshModUI error (likely widget disposed): $e');
    // Even if update fails, the state in providers is correct
    // UI will update on next natural rebuild
  }
}
```

This ensures no crashes even if widgets are disposed during long-running operations.
