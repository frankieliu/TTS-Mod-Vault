# Failed Download Tracking - Implementation Context

## Project Overview

TTS Mod Vault is a Flutter desktop application for managing Tabletop Simulator mod backups and assets. This document provides context for implementing failed download tracking.

---

## Current Architecture Summary

### Download System (`lib/src/state/download/download.dart`)

**Current Error Handling:**
- Line 200-214: DioException catching with special handling for Steam CDN 404 (adds trailing slash and retries once)
- Line 221-226: HTML error page detection (checks first 100 bytes for `<html>` or `<!DOCTYPE`)
- Line 243-262: Generic error handling with temp file cleanup
- Line 256: Cancellation detection separate from failures
- Errors logged via `debugPrint()` but not stored persistently

**Download Flow:**
1. Filter assets where `!fileExists` (line 66-102)
2. Double-check with `doesAssetFileExist()` (line 146-151)
3. Download in batches with concurrent downloads (configurable via settings)
4. Track successful downloads: `List<(String, String)> successfulDownloads` (line 154)
5. Update `existingAssetListsProvider` after success (line 274-281)
6. On error: delete temp file, log error, continue with next asset

**Key Methods:**
- `downloadAllFiles(Mod mod)` - Download all missing assets for a mod
- `downloadFiles({required List<String> modAssetListUrls, required AssetTypeEnum type})` - Core download logic
- `cancelAllDownloads()` - Cancel in-progress downloads
- `resolveUrlWithScheme(String url)` - Tries HTTPS then HTTP for URLs without scheme

---

### Storage System (`lib/src/state/storage/storage.dart`)

**Hive Boxes:**
```dart
Box<dynamic> _urlsBox;      // Key: jsonFileName, Value: Map<String, String> (URLs)
Box<String> _metadataBox;   // Key: modName + suffix, Value: timestamp strings
Box<String> _appDataBox;    // Key: setting name, Value: JSON strings
```

**Patterns:**
- Complex objects serialized to JSON strings before storage
- Bulk operations use `putAll()` for efficiency
- Methods follow pattern: save/get/delete/clear
- Settings use `toJson()` and `fromJson()` factory methods with safe parsing
- Example: `saveSettings()`, `getSettings()`, `deleteSettings()`

**Initialization:**
```dart
Future<void> initializeStorage() async {
  if (!_initialized) {
    _urlsBox = await Hive.openBox<dynamic>(urlsBox);
    _metadataBox = await Hive.openBox<String>(metadataBox);
    _appDataBox = await Hive.openBox<String>(appDataBox);
    _initialized = true;
  }
}
```

---

### Asset Tracking (`lib/src/state/asset/existing_assets.dart`)

**ExistingAssetsListsState:**
```dart
class ExistingAssetsListsState {
  final Map<String, String> assetBundles;  // filename -> filepath
  final Map<String, String> audio;
  final Map<String, String> images;
  final Map<String, String> models;
  final Map<String, String> pdf;
}
```

**Key Methods:**
- `loadExistingAssetsLists()` - Scans directories in parallel isolates
- `doesAssetFileExist(String assetFileName, AssetTypeEnum type)` - O(1) lookup
- `addExistingAsset(AssetTypeEnum type, String filename, String filepath)` - Updates map after download

**Process:**
1. On app startup, scan asset directories in 5 parallel isolates
2. Build `Map<String, String>` for each asset type
3. Use map for O(1) existence checks during download filtering
4. Handle legacy URL mapping (old Steam URLs to new format)

---

### Data Models

**Asset Model (`lib/src/state/asset/models/asset_model.dart`):**
```dart
class Asset {
  final String url;
  final bool fileExists;
  final String? filePath;
}
```

**Mod Model (`lib/src/state/mods/mod_model.dart`):**
```dart
class Mod {
  final ModTypeEnum modType;
  final String jsonFilePath;
  final String jsonFileName;
  final String saveName;
  final ExistingBackupStatusEnum backupStatus;
  final AssetLists? assetLists;
  final int? assetCount;
  final int? existingAssetCount;
  final int? missingAssetCount;
  // ... other fields

  Mod copyWith({...});
  List<Asset> getAllAssets();
  List<Asset> getAssetsByType(AssetTypeEnum type);
}
```

**AssetLists Model:**
```dart
class AssetLists {
  final List<Asset> assetBundles;
  final List<Asset> audio;
  final List<Asset> images;
  final List<Asset> models;
  final List<Asset> pdf;
}
```

---

### Existing Enum Patterns

**ModTypeEnum:**
```dart
enum ModTypeEnum {
  mod('mod'),
  save('save'),
  savedObject('saved object');

  final String label;
  const ModTypeEnum(this.label);
}
```

**AssetTypeEnum:**
```dart
enum AssetTypeEnum {
  assetBundle('AssetBundles', [subtypes]),
  audio('Audio', [subtypes]),
  image('Images', [subtypes]),
  model('Models', [subtypes]),
  pdf('PDF', [subtypes]);

  final String label;
  final List<String> subtypes;
  const AssetTypeEnum(this.label, this.subtypes);
}
```

**ExistingBackupStatusEnum (similar pattern for DownloadErrorTypeEnum):**
```dart
enum ExistingBackupStatusEnum {
  upToDate('Up to date'),
  outOfDate('Out of date'),
  noBackup('No backup');

  const ExistingBackupStatusEnum(this.label);
  final String label;
}
```

---

### State Management

**Provider Pattern (Riverpod):**
```dart
final existingAssetListsProvider =
    StateNotifierProvider<ExistingAssetsNotifier, ExistingAssetsListsState>(
  (ref) => ExistingAssetsNotifier(ref),
);
```

**Notifier Pattern:**
```dart
class ExistingAssetsNotifier extends StateNotifier<ExistingAssetsListsState> {
  final Ref ref;

  ExistingAssetsNotifier(this.ref) : super(ExistingAssetsListsState.empty());

  Future<void> loadExistingAssetsLists() async {
    // Load data
    state = ExistingAssetsListsState(/* updated data */);
  }

  void addExistingAsset(AssetTypeEnum type, String filename, String filepath) {
    // Update state immutably
    final updatedMap = Map<String, String>.from(currentMap)
      ..[filename] = filepath;
    _updateStateByType(type, updatedMap);
  }
}
```

---

### Mod Loading (`lib/src/state/mods/mods.dart`)

**loadModsData() Flow:**
1. Load existing backups (line 86)
2. Load existing assets (line 95)
3. Get JSON file paths in isolates (line 107-121)
4. Get initial mods from JSON (line 134)
5. Create adaptive batches (line 137-141)
6. Distribute across isolates (line 143-197)
7. Process batches in parallel isolates (line 200-215)
8. Merge results (line 217-236)
9. Save to storage in bulk (line 238-250)
10. Update state (line 252-280)

**getCompleteMod() Method (line 662-692):**
- Retrieves backup info
- Creates AssetLists from URLs
- Checks asset existence using `existingAssetListsProvider`
- Calculates asset counts (total, existing, missing)
- Returns updated Mod with all metadata

---

### Bulk Actions (`lib/src/state/bulk_actions/bulk_actions.dart`)

**downloadAllMods() Flow:**
1. Iterate through list of mods
2. For each mod:
   - Get URLs by mod
   - Get complete mod with asset existence
   - Download all files
   - Update selected mod state
3. Reset state when done

**Key Pattern:**
```dart
for (final mod in mods) {
  if (state.cancelledBulkAction) continue;

  final modUrls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
  final completeMod = await ref.read(modsProvider.notifier).getCompleteMod(mod, modUrls);

  ref.read(modsProvider.notifier).setSelectedMod(completeMod);
  await ref.read(downloadProvider.notifier).downloadAllFiles(completeMod);
  await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);
}
```

---

### UI Components

**Component Hierarchy:**
```
ModsPage
├── Sidebar
├── MainContent
│   ├── Toolbar (ModsSelector, Search, Sort, Filter, BulkActions)
│   ├── ProgressBars (Download, Backup, BulkActions)
│   └── ContentArea
│       ├── ModsView (ModsGrid/ModsList)
│       │   └── ModCard/ModListItem (per mod)
│       └── SelectedModView
│           ├── ModInfo
│           ├── AssetLists (Images, Audio, Models, PDFs, Bundles)
│           └── ActionButtons
```

**Existing Dialog Patterns:**
- Located in `lib/src/mods/components/`
- Use ConsumerWidget or ConsumerStatefulWidget
- Access state via `ref.watch()` or `ref.read()`
- Examples: `import_json_dialog.dart`, `replace_url_dialog.dart`

---

## Error Classification Research

### HTTP Status Codes

**4xx Client Errors (Permanent):**
- 400 Bad Request
- 403 Forbidden
- 404 Not Found
- 410 Gone
- Other 4xx errors

**5xx Server Errors (Temporary):**
- 500 Internal Server Error
- 502 Bad Gateway
- 503 Service Unavailable
- 504 Gateway Timeout
- Other 5xx errors

### DioException Types

**DioExceptionType enum:**
```dart
enum DioExceptionType {
  connectionTimeout,    // Temporary
  sendTimeout,          // Temporary
  receiveTimeout,       // Temporary
  badResponse,          // Check HTTP status
  cancel,               // Don't store
  connectionError,      // Temporary
  unknown,              // Don't store
}
```

---

## Implementation Notes

### File Paths (Base Directory)
```
/Users/frankliu/Library/CloudStorage/Box-Box/Work/TTS-Mod-Vault/
```

### Key Directories
```
lib/
├── src/
│   ├── state/
│   │   ├── enums/
│   │   ├── asset/
│   │   │   └── models/
│   │   ├── mods/
│   │   ├── download/
│   │   ├── backup/
│   │   ├── storage/
│   │   └── provider.dart
│   ├── mods/
│   │   └── components/
│   └── utils.dart
└── main.dart
```

### Import Patterns
```dart
// Enums
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

// Models
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart';

// State
import 'package:tts_mod_vault/src/state/provider.dart';

// Hooks Riverpod
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Dio
import 'package:dio/dio.dart' show DioException, DioExceptionType;

// Flutter
import 'package:flutter/material.dart';
```

---

## Existing Code Patterns to Follow

### 1. Immutable State with copyWith
```dart
state = state.copyWith(
  field1: newValue1,
  field2: newValue2,
);
```

### 2. JSON Serialization
```dart
Map<String, dynamic> toJson() {
  return {
    'field1': field1,
    'field2': field2.name,  // Use .name for enums
  };
}

factory Model.fromJson(Map<String, dynamic> json) {
  return Model(
    field1: json['field1'],
    field2: EnumType.values.firstWhere((e) => e.name == json['field2']),
  );
}
```

### 3. Safe Parsing with Defaults
```dart
static bool _parseBool(dynamic value, bool defaultValue) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return defaultValue;
}
```

### 4. Logging
```dart
debugPrint('Message: $variable');
```

### 5. Async Operations
```dart
Future<void> methodName() async {
  try {
    // Async operations
  } catch (e) {
    debugPrint('Error in methodName: $e');
  }
}
```

### 6. Provider Access
```dart
// Read (one-time access, doesn't rebuild on change)
final value = ref.read(someProvider);

// Watch (rebuilds when value changes)
final value = ref.watch(someProvider);

// Read notifier
final notifier = ref.read(someProvider.notifier);
await notifier.someMethod();
```

---

## Critical Implementation Details

### 1. URL Normalization
Assets use normalized URLs. Old Steam CDN URLs are mapped to new format:
```dart
// Old: http://cloud-3.steamusercontent.com/ugc/12345
// New: https://steamusercontent-a.akamaihd.net/ugc/12345

final normalizedUrl = url.replaceAll(oldCloudUrl, newSteamUserContentUrl);
```

### 2. Filename Extraction
```dart
final filename = getFileNameFromURL(url);  // From utils.dart
```

### 3. Temp File Pattern
Downloads use temp files that are renamed on success:
```dart
final tempPath = path.join(directory, '${fileName}_temp');
await dio.download(url, tempPath, cancelToken: cancelToken);
// ... validation ...
await File(tempPath).rename(finalPath);
```

### 4. Progress Tracking
```dart
state = state.copyWith(
  currentModNumber: mods.indexOf(mod) + 1,
  totalModNumber: mods.length,
  statusMessage: 'Processing ${mods.indexOf(mod) + 1}/${mods.length}',
);
```

### 5. Asset Type Determination
Based on file extension subtypes defined in AssetTypeEnum.

---

## Dependencies to Import

### New Utility for Error Classification
```dart
import 'package:dio/dio.dart' show DioException, DioExceptionType;
```

### For Dialog UI
```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';  // For date formatting
```

### For State Management
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
```

---

## Testing Scenarios

### Trigger Test Errors

**404 Error:**
- Use invalid URL: `https://steamusercontent-a.akamaihd.net/ugc/invalid_id`

**Timeout:**
- Modify Dio timeout settings in download.dart
- Use a slow/unresponsive URL

**Network Error:**
- Disconnect network during download

**HTML Error Page:**
- Some CDNs return HTML error pages instead of proper HTTP errors

**Cancellation:**
- Click cancel during download operation

---

## User Preferences Captured

1. **Persist in Hive** ✅
2. **Skip permanently failed URLs** ✅
3. **Show failed count in UI** ✅
4. **Classify error types (permanent vs temporary)** ✅

---

## Next Steps

Follow the implementation sequence in `FAILED_DOWNLOAD_TRACKING_PLAN.md`:
1. Phase 1: Foundation (enums, models, storage)
2. Phase 2: State Management (state, notifier, provider)
3. Phase 3: Download Logic (classifier, error capture, retry)
4. Phase 4: Integration (mod loading, asset creation, counts)
5. Phase 5: UI (dialog, badges, indicators)

Each phase builds on the previous, so implement in order.
