# TTS Mod Vault - Architecture Documentation

## Table of Contents
1. [Architectural Overview](#architectural-overview)
2. [Layered Architecture](#layered-architecture)
3. [State Management Architecture](#state-management-architecture)
4. [Concurrency Model](#concurrency-model)
5. [Data Flow](#data-flow)
6. [Storage Architecture](#storage-architecture)
7. [Component Architecture](#component-architecture)
8. [Design Patterns](#design-patterns)
9. [Key Architectural Decisions](#key-architectural-decisions)

---

## Architectural Overview

TTS Mod Vault follows a **layered reactive architecture** with clear separation of concerns between presentation, business logic, and data persistence layers. The application uses **Hooks Riverpod** for state management and leverages Dart **isolates** for heavy computational tasks.

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                      │
│  (Flutter Widgets, Pages, Components, Hooks, Dialogs)      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                   State Management Layer                    │
│    (Riverpod Providers, Notifiers, Computed Providers)     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                   Business Logic Layer                      │
│   (Domain Models, Services, Isolate Workers, Validators)   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Data/IO Layer                            │
│  (Hive Storage, File System, HTTP Client, Archive Handler) │
└─────────────────────────────────────────────────────────────┘
```

### Core Principles

1. **Unidirectional Data Flow** - Data flows from storage → providers → UI
2. **Reactive State Management** - UI automatically updates when state changes
3. **Isolate-Based Concurrency** - Heavy operations never block the UI thread
4. **Separation of Concerns** - Clear boundaries between layers
5. **Immutable State** - State objects are immutable; updates create new instances
6. **Dependency Injection** - Providers inject dependencies where needed

---

## Layered Architecture

### 1. Presentation Layer (`lib/src/mods/`)

**Responsibility:** User interface rendering, user input handling, navigation

**Components:**
- **Pages** - Full-screen views (ModsPage, ImagesViewerPage)
- **Components** - Reusable UI widgets (ModsSelector, ModsList, Toolbar, etc.)
- **Dialogs** - Modal interactions (ImportJsonDialog, ReplaceUrlDialog, etc.)
- **Hooks** - Side effects and lifecycle management (useBackupSnackbar, useCleanupSnackbar)

**Key Characteristics:**
- Pure Flutter widgets with minimal logic
- Read state from providers via `ref.watch()`
- Trigger actions via provider methods
- No direct access to storage or file system
- Stateless where possible, using Riverpod for state

**Example File:** `lib/src/mods/mods_page.dart`

---

### 2. State Management Layer (`lib/src/state/provider.dart`)

**Responsibility:** State coordination, provider definitions, dependency management

**Provider Categories:**

#### UI State Providers (Simple)
```dart
final selectedModProvider = StateProvider<Mod?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
final multiSelectModsProvider = StateProvider<Set<String>>((ref) => {});
```

#### Domain State Providers (Notifiers)
```dart
final modsProvider = AsyncNotifierProvider<ModsStateNotifier, ModsState>(...)
final downloadProvider = NotifierProvider<DownloadNotifier, DownloadState>(...)
final backupProvider = NotifierProvider<BackupNotifier, BackupState>(...)
```

#### Computed/Derived Providers
```dart
final filteredModsProvider = Provider<List<Mod>>((ref) {
  final mods = ref.watch(modsProvider).value?.mods ?? [];
  final searchQuery = ref.watch(searchQueryProvider);
  final sortAndFilter = ref.watch(sortAndFilterProvider);
  // Apply filtering and sorting logic
  return computeFilteredMods(mods, searchQuery, sortAndFilter);
});
```

**Key Characteristics:**
- Single source of truth for each domain
- Providers can depend on other providers
- Automatic dependency tracking and invalidation
- Clear separation between mutable and immutable state

---

### 3. Business Logic Layer (`lib/src/state/*/`)

**Responsibility:** Core application logic, domain rules, data transformation

**Key Notifiers:**

#### ModsStateNotifier (`lib/src/state/mods/mods.dart`)
- Loads mod JSON files from filesystem
- Parses mod structure and extracts asset URLs
- Coordinates with asset and backup providers
- Manages URL prefix updates
- Handles mod refresh operations

**Critical Methods:**
- `loadMods()` - Main entry point for loading all mods
- `refreshAllMods()` - Reload mods and check asset existence
- `replaceUrl()` - Replace single URL in a mod
- `updateUrlPrefixesSingleFile()` - Update URL prefixes in one mod
- `updateUrlPrefixesAllFiles()` - Bulk update across all mods

#### DownloadNotifier (`lib/src/state/download/download.dart`)
- Manages HTTP downloads via Dio
- Tracks download progress per asset type
- Handles cancellation tokens
- Creates proper cache directory structure
- Retries failed downloads

**Download Flow:**
```
1. User triggers download
2. Extract asset URLs from mod
3. Filter out already-downloaded assets
4. Create Dio client with cancel token
5. Download assets in parallel (per type)
6. Save to cache with proper directory structure
7. Update progress state
8. Mark download complete
```

#### BackupNotifier (`lib/src/state/backup/backup.dart`)
- Creates .ttsmod backup archives
- Compresses mod JSON + assets into ZIP
- Tracks backup timestamps
- Compares backups to detect out-of-date status
- Supports import/restore operations

#### CleanupNotifier (`lib/src/state/cleanup/cleanup.dart`)
- Scans asset cache directories
- Identifies orphaned files (not referenced by any mod)
- Parallel processing per asset type
- Safe deletion with confirmation

---

### 4. Data/IO Layer

#### Storage Service (`lib/src/state/storage/storage.dart`)

**Hive Boxes:**
```dart
Box<String> urlsBox       // Dynamic URL cache
Box<String> metadataBox   // Mod metadata (timestamps, etc.)
Box<String> appDataBox    // App settings and preferences
```

**Key Operations:**
- `saveUrlsToStorage()` - Cache extracted URLs
- `getUrlsFromStorage()` - Retrieve cached URLs
- `saveLastModifiedDateTimeToStorage()` - Track file timestamps
- `getLastModifiedDateTimeFromStorage()` - Check if file changed

#### File System Operations
- Direct file I/O for reading JSON files
- Directory scanning for mod discovery
- Asset existence checking (file.exists())
- Backup file management

#### HTTP Client (Dio)
- Configurable timeouts and retry logic
- Progress callbacks for downloads
- Cancellation token support
- Error handling and recovery

---

## State Management Architecture

### Provider Hierarchy

```
App Root
├── storageProvider (FutureProvider)
│   └── Initializes Hive boxes
├── directoriesProvider (NotifierProvider)
│   └── Manages mod/save/backup paths
├── modsProvider (AsyncNotifierProvider)
│   ├── Depends on: directoriesProvider, storageProvider
│   └── Loads and manages all mods
├── existingAssetListsProvider (NotifierProvider)
│   └── Tracks downloaded assets
├── existingBackupsProvider (NotifierProvider)
│   └── Scans backup directory
├── sortAndFilterProvider (NotifierProvider)
│   └── Manages sort/filter state
├── filteredModsProvider (Provider)
│   ├── Depends on: modsProvider, searchQueryProvider, sortAndFilterProvider
│   └── Computes filtered/sorted mod list
├── downloadProvider (NotifierProvider)
│   └── Handles download operations
├── backupProvider (NotifierProvider)
│   └── Handles backup operations
└── settingsProvider (NotifierProvider)
    └── Persists user preferences
```

### State Update Flow

```
User Action (e.g., clicks "Download")
    ↓
Component calls provider method
    ↓
Notifier.method() updates internal state
    ↓
State object is copied with modifications (immutable)
    ↓
Riverpod notifies all listeners
    ↓
UI widgets rebuild with new state
    ↓
User sees updated UI
```

### State Models

All state is modeled as immutable classes with `copyWith()` methods:

```dart
class ModsState {
  final List<Mod> mods;
  final bool isLoading;
  final String? errorMessage;

  ModsState copyWith({
    List<Mod>? mods,
    bool? isLoading,
    String? errorMessage,
  }) => ModsState(
    mods: mods ?? this.mods,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}
```

---

## Concurrency Model

### Isolate-Based Architecture

**Problem:** Heavy operations (parsing large JSON files, scanning thousands of files) block the UI thread.

**Solution:** Execute heavy work in background isolates using `compute()` or `Isolate.run()`.

### Isolate Workers (`lib/src/state/mods/mods_isolates.dart`)

#### 1. Initial Mod Loading
```dart
Future<ProcessedBatch> processInitialModsInIsolate({
  required List<String> filePaths,
  required ModType modType,
}) async {
  return await compute(_processInitialModsWorker, {
    'filePaths': filePaths,
    'modType': modType,
  });
}
```

**Worker Tasks:**
- Read JSON file from disk
- Parse JSON to extract mod data
- Extract asset URLs using regex
- Return processed mod objects

#### 2. Asset Existence Checking
```dart
Future<List<Mod>> processMultipleBatchesInIsolate({
  required List<Mod> mods,
  required Map<AssetType, List<String>> existingAssets,
}) async {
  // Process mods in batches of 50
  // Each batch runs in separate isolate
  // Prevents memory issues with large mod collections
}
```

**Worker Tasks:**
- Check if each asset URL exists in cache
- Count existing vs. missing assets
- Update mod objects with asset existence data

#### 3. Bulk URL Updates
```dart
Future<void> updateUrlPrefixesFilesIsolate({
  required List<String> filePaths,
  required String oldPrefix,
  required String newPrefix,
}) async {
  return await Isolate.run(() async {
    // Regex-based URL replacement
    // Write updated JSON back to disk
  });
}
```

### Concurrency Patterns

**Pattern 1: Parallel Batch Processing**
```dart
// Split work into chunks
final batches = chunk(mods, batchSize: 50);

// Process batches in parallel
final results = await Future.wait(
  batches.map((batch) => processInIsolate(batch))
);
```

**Pattern 2: Cancellable Operations**
```dart
final cancelToken = CancelToken();

// Store cancel token in state
state = state.copyWith(cancelToken: cancelToken);

// Use in HTTP requests
await dio.download(url, path, cancelToken: cancelToken);

// Cancel on user request
cancelToken.cancel('User cancelled');
```

**Pattern 3: Progress Tracking**
```dart
int completed = 0;
final total = assets.length;

for (final asset in assets) {
  await downloadAsset(asset);
  completed++;

  // Update state with progress
  state = state.copyWith(
    currentProgress: completed,
    totalProgress: total,
  );
}
```

---

## Data Flow

### Complete Data Flow Example: Downloading Mod Assets

```
1. USER ACTION
   User clicks "Download" button on a mod
   ↓

2. UI COMPONENT (selected_mod_view.dart)
   IconButton(
     onPressed: () => ref.read(downloadProvider.notifier).download(mod)
   )
   ↓

3. DOWNLOAD NOTIFIER (download.dart)
   download(Mod mod) async {
     // Update state to "in progress"
     state = state.copyWith(status: DownloadStatus.inProgress);

     // Extract asset URLs
     final urls = mod.assetLists?.allUrls ?? [];

     // Filter already-downloaded
     final toDownload = urls.where((url) => !exists(url)).toList();

     // Download each asset
     for (final url in toDownload) {
       await downloadAsset(url);

       // Update progress
       state = state.copyWith(
         currentProgress: state.currentProgress + 1,
       );
     }

     // Mark complete
     state = state.copyWith(status: DownloadStatus.complete);

     // Invalidate dependent providers
     ref.invalidate(existingAssetListsProvider);
     ref.invalidate(modsProvider);
   }
   ↓

4. HTTP CLIENT (Dio)
   dio.download(url, savePath, onReceiveProgress: (received, total) {
     // Update progress callback
   })
   ↓

5. FILE SYSTEM
   Write downloaded bytes to cache directory
   ↓

6. STATE UPDATE
   Riverpod notifies listeners of state change
   ↓

7. UI RE-RENDER
   Components watching downloadProvider rebuild
   Progress bar updates
   Download button changes to "Downloaded" state
```

---

## Storage Architecture

### Hive Database Structure

```
Hive Storage
├── urls.hive (Box<String>)
│   ├── Key: "{modType}:{modPath}"
│   └── Value: JSON array of URLs as string
│
├── metadata.hive (Box<String>)
│   ├── Key: "{modType}:{modPath}:lastModified"
│   └── Value: ISO timestamp string
│
└── appData.hive (Box<String>)
    ├── Key: "settings"
    ├── Value: JSON serialized settings object
    ├── Key: "modsDirectory"
    └── Value: Directory path string
```

### Cache Strategy

**When to Cache:**
- After parsing mod JSON (cache extracted URLs)
- After file scan (cache timestamps)
- On settings change (persist preferences)

**Cache Invalidation:**
- On manual refresh
- When file timestamp changes
- On URL prefix update

**Benefits:**
- Fast subsequent loads (no JSON parsing)
- Detect file changes without re-parsing
- Persist user preferences across sessions

---

## Component Architecture

### Component Hierarchy (UI)

```
ModsPage (Full Screen)
├── Sidebar
│   └── Navigation items
├── MainContent (Column)
│   ├── Toolbar (Row)
│   │   ├── ModsSelector (Tabs)
│   │   ├── Search
│   │   ├── SortButton
│   │   ├── FilterButton
│   │   ├── BulkActionsMenu
│   │   └── SettingsButton
│   ├── ProgressBars (Stack)
│   │   ├── DownloadProgressBar
│   │   ├── BackupProgressBar
│   │   └── BulkActionsProgressBar
│   └── ContentArea (Expanded)
│       ├── ModsView (List or Grid)
│       │   └── ModCard (per mod)
│       └── SelectedModView (Detail Panel)
│           ├── ModInfo
│           ├── AssetLists (Images, Audio, etc.)
│           └── ActionButtons (Download, Backup, etc.)
```

### Component Communication

**Parent → Child:** Props (constructor parameters)
```dart
ModCard({
  required Mod mod,
  required bool isSelected,
  required VoidCallback onTap,
})
```

**Child → Parent:** Callbacks
```dart
IconButton(
  onPressed: () => onDownload(mod.id),
)
```

**Sibling → Sibling:** Shared state (providers)
```dart
// Component A sets state
ref.read(selectedModProvider.notifier).state = mod;

// Component B watches state
final selectedMod = ref.watch(selectedModProvider);
```

### Component Lifecycle Hooks

```dart
// useBackupSnackbar hook
void useBackupSnackbar() {
  final backupState = ref.watch(backupProvider);
  final messenger = ScaffoldMessenger.of(context);

  useEffect(() {
    if (backupState.status == BackupStatus.complete) {
      messenger.showSnackBar(
        SnackBar(content: Text('Backup complete!')),
      );
    }
    return null; // No cleanup needed
  }, [backupState.status]); // Re-run when status changes
}
```

---

## Design Patterns

### 1. Repository Pattern (Implicit)

While not explicitly named, the notifiers act as repositories:

```dart
class ModsStateNotifier {
  // Data access methods
  Future<List<Mod>> loadMods() { ... }
  Future<void> saveMod(Mod mod) { ... }

  // Business logic
  Future<void> refreshMod(String modId) { ... }
}
```

### 2. Command Pattern (Actions)

User actions are encapsulated as notifier methods:

```dart
// Download command
ref.read(downloadProvider.notifier).download(mod);

// Backup command
ref.read(backupProvider.notifier).backup(mod);

// Cleanup command
ref.read(cleanupProvider.notifier).scanForOrphanedFiles();
```

### 3. Observer Pattern (Riverpod)

Widgets observe state changes automatically:

```dart
// Widget rebuilds when modsProvider changes
ref.watch(modsProvider);
```

### 4. Strategy Pattern (Sorting/Filtering)

Different sorting strategies selected at runtime:

```dart
enum SortOption {
  alphabetical,
  dateCreated,
  missingAssets,
}

List<Mod> sortMods(List<Mod> mods, SortOption option) {
  switch (option) {
    case SortOption.alphabetical:
      return mods.sorted((a, b) => a.saveName.compareTo(b.saveName));
    case SortOption.dateCreated:
      return mods.sorted((a, b) => a.dateCreated.compareTo(b.dateCreated));
    case SortOption.missingAssets:
      return mods.sorted((a, b) => b.missingAssetCount.compareTo(a.missingAssetCount));
  }
}
```

### 5. Factory Pattern (Mod Creation)

Mods are created from JSON with validation:

```dart
factory Mod.fromJson(Map<String, dynamic> json, ModType modType) {
  return Mod(
    modType: modType,
    jsonFilePath: json['path'],
    saveName: json['SaveName'] ?? 'Unnamed',
    // ... validation and defaults
  );
}
```

### 6. Builder Pattern (State Updates)

State objects use `copyWith` for immutable updates:

```dart
state = state.copyWith(
  status: DownloadStatus.inProgress,
  currentProgress: 0,
  totalProgress: assets.length,
  message: 'Downloading assets...',
);
```

---

## Key Architectural Decisions

### Decision 1: Why Isolates for Heavy Work?

**Problem:** Parsing thousands of JSON files blocks UI

**Alternatives Considered:**
- Synchronous parsing (rejected: freezes UI)
- Streams with async parsing (rejected: still blocks on CPU-heavy work)
- Web workers (N/A: desktop app)

**Decision:** Use Dart isolates via `compute()` and `Isolate.run()`

**Benefits:**
- True parallelism on multi-core systems
- UI remains responsive during heavy operations
- Can process multiple mods simultaneously

**Trade-offs:**
- Isolate communication overhead (serialization)
- More complex code (isolate setup, message passing)
- Debugging across isolates is harder

---

### Decision 2: Why Riverpod over Bloc or Provider?

**Alternatives Considered:**
- **Bloc:** Verbose boilerplate, event-driven model unnecessary
- **Provider (original):** Lacks compile-time safety, deprecated
- **GetX:** Magic, implicit dependencies, hard to test

**Decision:** Hooks Riverpod

**Benefits:**
- Compile-time safety (no runtime errors from missing providers)
- Automatic dependency tracking
- Easy testing (override providers in tests)
- Combines well with Flutter Hooks
- No BuildContext needed for most operations

---

### Decision 3: Why Hive over SQLite?

**Alternatives Considered:**
- **SQLite:** Overkill for simple key-value storage, requires SQL
- **Shared Preferences:** Limited to primitive types
- **JSON files:** No indexing, slow lookups

**Decision:** Hive CE

**Benefits:**
- Fast key-value lookups (O(1))
- No SQL required
- Supports complex types via code generation
- Lazy loading (only loads needed boxes)
- Cross-platform (mobile + desktop)

**Trade-offs:**
- No relational queries
- Manual indexing if needed
- Community edition (original package abandoned)

---

### Decision 4: Immutable State Models

**Decision:** All state models are immutable with `copyWith()`

**Rationale:**
- Prevents accidental mutations
- Easier to track state changes (history/debugging)
- Safe for concurrent access
- Aligns with Riverpod best practices

**Example:**
```dart
// BAD: Mutable state
state.status = DownloadStatus.complete;

// GOOD: Immutable state
state = state.copyWith(status: DownloadStatus.complete);
```

---

### Decision 5: Separate Provider per Domain

**Decision:** Each domain (mods, downloads, backups) has its own provider

**Rationale:**
- Single Responsibility Principle
- Easier to test individual domains
- Clear boundaries between concerns
- Providers can depend on each other when needed

**Structure:**
```
lib/src/state/
├── mods/          # Mod loading and management
├── download/      # Download operations only
├── backup/        # Backup operations only
├── cleanup/       # Cleanup operations only
└── settings/      # User preferences only
```

---

## Testing Strategy (Recommended)

### Unit Tests
- Test notifier methods in isolation
- Mock dependencies (storage, file system)
- Test state transitions

### Widget Tests
- Test component rendering
- Test user interactions
- Override providers with test data

### Integration Tests
- Test full user flows (download → backup)
- Use real providers but mock I/O
- Test error handling

### Example Test
```dart
test('DownloadNotifier updates progress during download', () async {
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(mockStorage),
    ],
  );

  final notifier = container.read(downloadProvider.notifier);

  await notifier.download(testMod);

  final state = container.read(downloadProvider);
  expect(state.status, DownloadStatus.complete);
  expect(state.currentProgress, testMod.assetCount);
});
```

---

## Future Architectural Considerations

### Scalability
- If mod count grows to 10,000+, consider pagination
- Index common queries (search, filter) in Hive
- Implement virtual scrolling for large lists

### Feature Additions
- **Undo/Redo:** Consider Command pattern with history stack
- **Collaboration:** WebSocket provider for real-time sync
- **Cloud Backup:** Abstract storage layer to support cloud providers

### Performance
- Profile isolate overhead for small mod counts
- Consider lazy loading asset lists (load on demand)
- Implement image caching for gallery view

---

## Conclusion

TTS Mod Vault's architecture demonstrates best practices for Flutter desktop applications:

1. **Clear separation of concerns** through layered architecture
2. **Reactive state management** with Riverpod for maintainable UI
3. **Concurrent processing** via isolates for responsive UX
4. **Immutable state** for predictable behavior
5. **Persistent storage** for fast app startup

The architecture is designed to handle large datasets (thousands of mods) while maintaining UI responsiveness and code maintainability.
