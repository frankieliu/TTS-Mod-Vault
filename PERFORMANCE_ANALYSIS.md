# Performance Analysis - Bulk Operations UI & Parallelization

## Current Issues

### 1. UI Updates Only at End
**Problem:** Bulk operations only refresh UI after ALL operations complete
```dart
// downloadAllMods
for (final mod in mods) {
  await downloadAllFiles(mod);  // Download
  // NO UI update here
}
await _refreshBackupInfo(mods);  // ← Only updates UI at the very end
```

**Impact:**
- User sees progress bar moving
- But grid shows stale data (old file counts, no blue borders)
- Only updates when operation completes
- Feels slow/unresponsive

### 2. Sequential Processing (No Parallelization)
**Problem:** Operations run one-at-a-time even though they're I/O bound
```dart
for (final mod in mods) {  // Sequential loop
  await downloadAllFiles(mod);  // Wait for network I/O
  // Could be downloading other mods while waiting...
}
```

**Impact:**
- 100 mods × 5 seconds each = 500 seconds total
- With parallelization (3 concurrent): ~170 seconds
- **3x faster!**

---

## Proposed Solution

### Solution 1: Update UI After Each Operation

**Change bulk operations to update each mod immediately:**

```dart
// Current (batch update at end)
Future<void> downloadAllMods(List<Mod> mods) async {
  for (final mod in mods) {
    await downloadAllFiles(mod);
  }
  await _refreshBackupInfo(mods);  // ← Batch update
}

// Proposed (update per-mod)
Future<void> downloadAllMods(List<Mod> mods) async {
  for (final mod in mods) {
    await downloadAllFiles(mod);
    await _refreshModInfo(mod);  // ← Update this mod's UI immediately
  }
}

// New helper method in bulk_actions.dart
Future<void> _refreshModInfo(Mod mod) async {
  final urls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
  final assetLists = ref.read(modsProvider.notifier).getAssetListsFromUrls(urls);
  final backup = ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

  final updatedMod = mod.copyWith(
    backup: backup,
    assetLists: assetLists.$1,
    assetCount: assetLists.$2,
    existingAssetCount: assetLists.$3,
    missingAssetCount: assetLists.$2 - assetLists.$3,
    failedAssetCount: assetLists.$4,
  );

  ref.read(modsProvider.notifier).updateMod(updatedMod);
}
```

**Benefits:**
- ✅ UI updates incrementally as each mod finishes
- ✅ User sees real-time progress in the grid
- ✅ Feels more responsive

**Drawbacks:**
- Slightly slower (updates UI N times vs 1 time)
- But better UX overall

---

### Solution 2: Parallel Downloads

**Parallelize I/O-bound operations:**

```dart
// Current (sequential)
Future<void> downloadAllMods(List<Mod> mods) async {
  for (final mod in mods) {
    await downloadAllFiles(mod);  // Wait for each
  }
}

// Proposed (parallel with concurrency limit)
Future<void> downloadAllMods(List<Mod> mods) async {
  const maxConcurrent = 3;  // Download 3 mods at a time

  // Process mods in batches of maxConcurrent
  for (int i = 0; i < mods.length; i += maxConcurrent) {
    final batch = mods.skip(i).take(maxConcurrent).toList();

    // Download all in batch concurrently
    await Future.wait(
      batch.map((mod) async {
        if (state.cancelledBulkAction) return;

        state = state.copyWith(
          currentModNumber: mods.indexOf(mod) + 1,
          statusMessage: 'Downloading ${mod.saveName} (${mods.indexOf(mod) + 1}/${mods.length})',
        );

        await ref.read(downloadProvider.notifier).downloadAllFiles(mod);
        await _refreshModInfo(mod);  // Update UI immediately after each completes
      }),
    );
  }
}
```

**Alternative: Stream-based approach**

```dart
Future<void> downloadAllMods(List<Mod> mods) async {
  final stream = Stream.fromIterable(mods);

  await for (final results in stream.asyncMap((mod) async {
    if (state.cancelledBulkAction) return null;

    state = state.copyWith(
      currentModNumber: mods.indexOf(mod) + 1,
      statusMessage: 'Downloading ${mod.saveName}',
    );

    await ref.read(downloadProvider.notifier).downloadAllFiles(mod);
    await _refreshModInfo(mod);
    return mod;
  }).buffer(3)) {  // Process 3 at a time
    // Results come in as batches complete
  }
}
```

**Benefits:**
- ✅ **3x faster** (with concurrency=3)
- ✅ Better network utilization
- ✅ UI still updates per-mod

**Drawbacks:**
- More complex code
- Need to manage concurrent state updates
- Progress bar shows concurrent operations (not strictly sequential numbers)

---

### Solution 3: Parallel Backups (Limited Value)

**Backup operations are disk I/O:**

```dart
Future<void> backupAllMods(List<Mod> mods, ...) async {
  // Could parallelize, but disk is bottleneck
  // Probably not worth the complexity

  // Sequential is fine for backups
  for (final mod in mods) {
    await createBackup(mod, folder);
    await _refreshModInfo(mod);  // Update UI after each
  }
}
```

**Analysis:**
- Backups write to same disk → sequential is actually better
- Parallel writes would cause disk thrashing
- **Keep backups sequential** ✅

---

### Solution 4: Parallel Download+Backup

**Most interesting case:**

```dart
// Current: Download all → Backup all (sequential)
for (mod in mods) {
  await download(mod);
}
for (mod in mods) {
  await backup(mod);
}

// Proposed: Pipeline pattern
Future<void> downloadAndBackupAllMods(List<Mod> mods, ...) async {
  const maxConcurrentDownloads = 3;

  final downloadQueue = Queue<Mod>.from(mods);
  final backupQueue = Queue<Mod>();

  // Download worker (runs 3 concurrently)
  Future<void> downloadWorker() async {
    while (downloadQueue.isNotEmpty) {
      final mod = downloadQueue.removeFirst();
      await downloadAllFiles(mod);
      backupQueue.add(mod);  // Add to backup queue
      await _refreshModInfo(mod);
    }
  }

  // Backup worker (runs 1 at a time, to avoid disk thrashing)
  Future<void> backupWorker() async {
    while (!downloadQueue.isEmpty || backupQueue.isNotEmpty) {
      if (backupQueue.isEmpty) {
        await Future.delayed(Duration(milliseconds: 100));
        continue;
      }

      final mod = backupQueue.removeFirst();
      await createBackup(mod, folder);
      await _refreshModInfo(mod);
    }
  }

  // Run download workers in parallel, backup worker consumes results
  await Future.wait([
    downloadWorker(),
    downloadWorker(),
    downloadWorker(),
    backupWorker(),
  ]);
}
```

**Benefits:**
- ✅ Downloads happen in parallel (3 at a time)
- ✅ Backups start as soon as first download completes
- ✅ Don't wait for all downloads before backing up
- ✅ Much faster overall

---

## Implementation Plan

### Phase 1: Immediate UI Updates (Easy Win)
1. Change `_refreshBackupInfo(List<Mod>)` to `_refreshModInfo(Mod)`
2. Call after each operation instead of batch at end
3. Update all 3 bulk operations (download, backup, download+backup)

**Impact:** Better UX, minimal code change

### Phase 2: Parallel Downloads (Big Performance Win)
1. Add `maxConcurrentDownloads` setting (default 3)
2. Implement batched `Future.wait()` in `downloadAllMods()`
3. Implement batched `Future.wait()` in `downloadAndBackupAllMods()` (download phase)

**Impact:** 2-3x faster downloads

### Phase 3: Pipeline Pattern for Download+Backup (Advanced)
1. Implement queue-based pipeline
2. Download workers (3 concurrent) → Backup worker (1 sequential)
3. Start backups as downloads complete

**Impact:** 2-4x faster overall for download+backup

---

## Code Changes Required

### Change 1: Per-Mod UI Refresh

**File:** `bulk_actions.dart`

```dart
// Remove old method
Future<void> _refreshBackupInfo(List<Mod> mods) async { ... }

// Add new method
Future<void> _refreshModInfo(Mod mod) async {
  final urls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
  final backup = ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

  // Call existing refreshModsInfo but with single mod
  await ref.read(modsProvider.notifier).refreshModsInfo([mod]);
}
```

**Update all bulk operations:**
```dart
// downloadAllMods
for (final mod in mods) {
  await downloadAllFiles(mod);
  await _refreshModInfo(mod);  // ← Add this
}
// Remove: await _refreshBackupInfo(mods);

// backupAllMods
for (final mod in mods) {
  await createBackup(mod, folder);
  await _refreshModInfo(mod);  // ← Add this
}
// Remove: await _refreshBackupInfo(mods);

// downloadAndBackupAllMods
for (final mod in mods) {
  await downloadAllFiles(mod);
  await _refreshModInfo(mod);  // ← Add this after download

  await createBackup(mod, folder);
  await _refreshModInfo(mod);  // ← Add this after backup
}
// Remove: await _refreshBackupInfo(mods);
```

---

### Change 2: Parallel Downloads

**File:** `bulk_actions.dart`

```dart
Future<void> downloadAllMods(List<Mod> mods) async {
  state = state.copyWith(
    status: BulkActionsStatusEnum.downloadAll,
    totalModNumber: mods.length,
  );

  const maxConcurrent = 3;

  for (int i = 0; i < mods.length; i += maxConcurrent) {
    if (state.cancelledBulkAction) break;

    final batch = mods.skip(i).take(maxConcurrent).toList();

    // Download batch concurrently
    await Future.wait(
      batch.map((mod) => _downloadMod(mod, mods.indexOf(mod) + 1, mods.length)),
    );
  }

  _resetState();
  ref.read(downloadProvider.notifier).resetState();
}

Future<void> _downloadMod(Mod mod, int current, int total) async {
  if (state.cancelledBulkAction) return;

  debugPrint('Downloading: ${mod.saveName}');

  state = state.copyWith(
    currentModNumber: current,
    statusMessage: 'Downloading all mods ($current/$total)',
  );

  ref.read(modsProvider.notifier).setSelectedMod(mod);
  await ref.read(downloadProvider.notifier).downloadAllFiles(mod);
  await _refreshModInfo(mod);
}
```

---

## Performance Expectations

### Before:
- **100 mods × 5 sec/mod = 500 seconds**
- UI updates only at end
- Feels unresponsive

### After Phase 1 (Per-Mod UI Updates):
- **100 mods × 5 sec/mod = 500 seconds**
- UI updates after each mod (much better UX)
- Feels responsive

### After Phase 2 (Parallel Downloads):
- **100 mods ÷ 3 concurrent × 5 sec/mod = ~170 seconds**
- **3x faster!**
- UI updates incrementally

### After Phase 3 (Pipeline):
- **Download+Backup: ~220 seconds (vs 600+ sequential)**
- **2.7x faster!**
- Backups start immediately after first download

---

## Recommendation

**Implement Phase 1 + Phase 2:**

1. ✅ **Phase 1:** Per-mod UI updates (easy, big UX win)
2. ✅ **Phase 2:** Parallel downloads (medium difficulty, huge performance win)
3. ⏸️ **Phase 3:** Pipeline pattern (complex, diminishing returns)

**Skip Phase 3 for now** - Phase 1 + 2 gives us 90% of the benefit with 50% of the complexity.

---

## Next Steps

1. Update `_refreshBackupInfo()` to `_refreshModInfo()` (single mod)
2. Add per-mod refresh calls in all bulk operations
3. Test UI updates correctly after each operation
4. Implement parallel downloads with concurrency limit
5. Test with large mod collections (50-100 mods)
6. Measure performance improvement

**Estimated effort:** 2-3 hours
**Expected speedup:** 2-3x for downloads, immediate UI feedback
