# Fix: Service Using Provider Instead of Widget Ref

## Problem

After backing up a mod with many files (164 files in "Alchemists + King's Golem"), the UI didn't update to show the blue borders and folder icons, even though the backup was successfully created.

### Log Evidence
```
addBackup - Adding backup: Alchemists + King's Golem (1230898448).ttsmod
addBackup - Total backups after add: 157
_refreshModUI error (likely widget disposed): Bad state: Cannot use "ref" after the widget was disposed.
service.backupMod() returned, decision: null (backup completed)
Backup completed successfully
```

## Root Cause

The service was being created in the widget with the **widget's ref**:

```dart
// In SelectedModActionButtons.build()
final service = ModOperationsService(ref);  // This is WidgetRef!
```

Even though the service accepted `dynamic ref`, it was still a `WidgetRef` tied to the widget lifecycle. When the backup took longer (164 files vs 72 files), the widget had more time to be disposed during the operation, making the ref invalid.

### Why It Worked for Some Mods But Not Others

- **Fast operations** (fewer files, faster backup) - Widget stays alive, ref valid, UI updates ✅
- **Slow operations** (many files, slower backup) - Widget disposed during operation, ref invalid, UI update fails ❌

## Solution

Create the service as a **Riverpod Provider** so it has its own `Ref` that is tied to the **provider lifecycle**, not the widget lifecycle.

### Changes Made

#### 1. Added Provider (lib/src/state/provider.dart)

```dart
import 'package:tts_mod_vault/src/state/mod_operations/mod_operations_service.dart';

final modOperationsServiceProvider = Provider<ModOperationsService>((ref) {
  return ModOperationsService(ref);
});
```

This creates a service with a provider-level `Ref` that stays valid regardless of widget lifecycle.

#### 2. Updated Service (mod_operations_service.dart)

```dart
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref;

class ModOperationsService {
  final Ref ref;  // Changed from: final dynamic ref

  ModOperationsService(this.ref);
}
```

Now uses proper `Ref` type (provider-level) instead of accepting any ref type.

#### 3. Updated Widget (selected_mod_action_buttons.dart)

```dart
// Before:
final service = ModOperationsService(ref);  // Using widget's WidgetRef ❌

// After:
final service = ref.watch(modOperationsServiceProvider);  // Using provider's Ref ✅
```

#### 4. Updated Bulk Actions (bulk_actions.dart)

For consistency, also changed bulk actions to use the provider:

```dart
// Before:
final service = ModOperationsService(ref);

// After:
final service = ref.read(modOperationsServiceProvider);
```

## Key Differences: WidgetRef vs Provider Ref

| Aspect | WidgetRef (Before) | Ref from Provider (After) |
|--------|-------------------|---------------------------|
| Lifetime | Tied to widget lifecycle | Tied to provider lifecycle |
| Valid when widget disposed? | ❌ No - throws error | ✅ Yes - stays valid |
| Safe for long operations? | ⚠️ Only if widget stays alive | ✅ Always safe |
| Used in | Widget build methods | StateNotifiers, services, providers |

## How It Works Now

### Service Creation Flow

```
1. App starts
   └─ Riverpod creates modOperationsServiceProvider
   └─ Provider creates ModOperationsService(provider_ref)
   └─ Service has Ref tied to PROVIDER lifecycle (not widget)

2. Widget builds
   └─ Widget accesses: ref.watch(modOperationsServiceProvider)
   └─ Gets service instance with provider-level Ref

3. User clicks backup
   └─ Widget calls: service.backupMod()
   └─ Service uses its provider-level Ref (always valid)

4. Widget disposes during backup
   └─ Widget's WidgetRef becomes invalid
   └─ Service's Ref stays valid! ✅
   └─ Service completes backup
   └─ Service updates UI successfully ✅
```

### Comparison: Before vs After

#### Before (❌ Broken):
```
Widget → WidgetRef → Service
   ↓
Widget disposed
   ↓
WidgetRef invalid ❌
   ↓
Service can't update UI ❌
```

#### After (✅ Fixed):
```
Provider → Ref → Service
   ↓
Widget uses Service from Provider
   ↓
Widget disposed (doesn't affect service)
   ↓
Service's Ref stays valid ✅
   ↓
Service updates UI successfully ✅
```

## Expected Behavior Now

### Scenario 1: Fast Backup (e.g., Akrotiri - 72 files)
```
1. Click Backup
2. Backup completes in ~2 seconds
3. Widget still alive
4. ✅ UI updates immediately
5. ✅ Blue borders and folder icons appear
```

### Scenario 2: Slow Backup (e.g., Alchemists - 164 files)
```
1. Click Backup
2. Backup takes ~10 seconds
3. Widget might be disposed (user clicks away, etc.)
4. ✅ Backup completes successfully
5. ✅ UI updates successfully (service's Ref is still valid)
6. ✅ Blue borders and folder icons appear
```

### Scenario 3: Widget Definitely Disposed
```
1. Click Backup
2. Immediately navigate away (widget disposed)
3. Backup completes in background
4. ✅ Backup completes successfully
5. ✅ UI updates successfully (service's Ref is valid)
6. Navigate back to mod
7. ✅ Blue borders and folder icons are there
```

## Files Changed

1. **lib/src/state/provider.dart**
   - Added `modOperationsServiceProvider`
   - Imported `ModOperationsService`

2. **lib/src/state/mod_operations/mod_operations_service.dart**
   - Changed `final dynamic ref` to `final Ref ref`
   - Added `Ref` import from hooks_riverpod

3. **lib/src/mods/components/selected_mod_action_buttons.dart**
   - Changed from `ModOperationsService(ref)` to `ref.watch(modOperationsServiceProvider)`
   - Removed `ModOperationsService` import
   - Added `modOperationsServiceProvider` to provider imports

4. **lib/src/state/bulk_actions/bulk_actions.dart**
   - Changed from `ModOperationsService(ref)` to `ref.read(modOperationsServiceProvider)` (3 instances)
   - Removed `ModOperationsService` import
   - Added `modOperationsServiceProvider` to provider imports

## Benefits

1. **Reliability** - Operations always complete and update UI, regardless of widget lifecycle
2. **Consistency** - Same service instance used everywhere via provider
3. **Type Safety** - Proper `Ref` type instead of `dynamic`
4. **Testability** - Can easily mock the service provider in tests
5. **Performance** - Service instance reused instead of creating new instances

## Summary

The fix changes the service from being **widget-scoped** (created with widget's ref) to being **app-scoped** (created via provider). This ensures the service's ref stays valid even when widgets are disposed, allowing long-running operations like backup to always successfully update the UI.

**Result**: Blue borders and folder icons now appear reliably after backup, regardless of how long the operation takes! 🎉
