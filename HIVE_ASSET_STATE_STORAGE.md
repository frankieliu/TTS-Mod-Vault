# Current Hive Asset State Storage

## Overview

Hive currently stores asset information in **three separate boxes**, using **URLs as keys** for most operations.

---

## Hive Boxes for Asset State

### Box 1: `FailedAssets` (Failed Downloads)
**Purpose:** Track assets that failed to download
**Key:** Asset URL (full URL string)
**Value:** JSON-encoded `FailedAsset` object

#### Stored Data Structure:
```json
{
  "url": "http://i.imgur.com/tHADwoQ.jpg",
  "type": "image",
  "errorType": "permanent",
  "errorMessage": "404 Not Found",
  "failedAt": 1735034600000,
  "retryCount": 2
}
```

#### Code Location:
`lib/src/state/storage/storage.dart` (lines 162-227)

```dart
// Save failed asset
await _failedAssetsBox.put(url, jsonStr);
// Key = "http://i.imgur.com/tHADwoQ.jpg"
// Value = JSON string of FailedAsset

// Get failed asset
final failedAsset = storage.getFailedAsset(url);
// Returns: FailedAsset object or null

// Get all failed assets
final allFailed = storage.getAllFailedAssets();
// Returns: Map<String, FailedAsset> (URL → FailedAsset)
```

#### Fields:
- **url:** The asset URL (also used as the key)
- **type:** Asset type enum (image, model, audio, etc.)
- **errorType:** Type of error (permanent, temporary, unknown)
- **errorMessage:** Human-readable error message
- **failedAt:** Timestamp when download failed
- **retryCount:** Number of retry attempts

---

### Box 2: `ExistingAssets` (In-Memory State)
**Purpose:** Track downloaded assets currently on disk
**Location:** NOT stored in Hive - only in memory
**Data Structure:** `ExistingAssetsListsState`

#### In-Memory State Structure:
```dart
ExistingAssetsListsState {
  assetBundles: Map<String, String>,  // filename → filepath
  audio: Map<String, String>,
  images: Map<String, String>,
  models: Map<String, String>,
  pdf: Map<String, String>,
}
```

#### Example:
```dart
{
  images: {
    "httpiimgurcomtHADwoQjpg": "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg",
    "httpiimgurcom8bVZDmujpg": "/path/to/Mods/Images/httpiimgurcom8bVZDmujpg.jpg",
  },
  models: {
    "httpchrymeupmemeflag5unity3d": "/path/to/Mods/Models/httpchrymeupmemeflag5unity3d.unity3d",
  }
}
```

#### Key Points:
- **Keys:** Filenames WITHOUT extensions (e.g., `httpiimgurcomtHADwoQjpg`)
- **Values:** Full file paths WITH extensions
- **NOT persisted** to Hive - loaded fresh each time from disk
- **Updated** when files are downloaded or imported

#### Code Location:
`lib/src/state/asset/existing_assets.dart` (lines 21-54)

```dart
// Load from disk
await loadExistingAssetsLists();
// Scans directories and builds in-memory map

// Check if file exists
final exists = doesAssetFileExist(assetFileName, type);
// assetFileName = "httpiimgurcomtHADwoQjpg" (no extension)

// Get file path
final filepath = getAssetFilePath(assetFileName, type);
// Returns: "/path/to/httpiimgurcomtHADwoQjpg.jpg"
```

---

### Box 3: `BackupFiles` (Backup Metadata)
**Purpose:** Track which files exist in each backup
**Key:** Backup filename (e.g., `"MyMod.ttsmod"`)
**Value:** JSON-encoded `BackupFileMetadata` object

#### Stored Data Structure:
```json
{
  "files": {
    "httpiimgurcomtHADwoQjpg.jpg": 12345,
    "httpiimgurcom8bVZDmujpg.jpg": 67890,
    "httpchrymeupmemeflag5unity3d.unity3d": 98765,
    "123456789.json": 1024000,
    "123456789.png": 512000
  }
}
```

#### Code Location:
`lib/src/state/storage/storage.dart` (lines 229-275)

```dart
// Save backup metadata
await storage.saveBackupFileMetadata(backupFilename, metadata);
// Key = "MyMod.ttsmod"
// Value = JSON string of BackupFileMetadata

// Get backup metadata
final metadata = storage.getBackupFileMetadata("MyMod.ttsmod");
// Returns: BackupFileMetadata object

// Get all backup metadata
final allBackups = storage.getAllBackupFileMetadata();
// Returns: Map<String, BackupFileMetadata> (backupFilename → metadata)
```

#### Key Points:
- **Keys in files map:** Filenames WITH extensions
- **Values in files map:** File sizes in bytes
- **Does NOT use URLs** - uses filenames as extracted from backup

---

### Box 4: `UrlBackupStatus` (URL → Backup Mapping) [NEW]
**Purpose:** Map which URLs are backed up
**Key:** Asset URL (full URL string)
**Value:** JSON-encoded backup status info

#### Stored Data Structure:
```json
{
  "backupFilename": "MyMod.ttsmod",
  "fileSize": 12345,
  "backedUpAt": "2025-12-23T10:30:00Z",
  "modJsonFileName": "123456789"
}
```

#### Code Location:
`lib/src/state/storage/storage.dart` (lines 277-344)

```dart
// Save URL backup status
await storage.saveUrlBackupStatus(url, statusData);
// Key = "http://i.imgur.com/tHADwoQ.jpg"
// Value = JSON string with backup info

// Check if URL is backed up
final isBackedUp = storage.isUrlBackedUp(url);
// Returns: true/false

// Get backup info for URL
final info = storage.getUrlBackupStatus(url);
// Returns: Map<String, dynamic> or null
```

---

## How Asset State is Determined

When building assets for a mod, the system checks all three sources:

**Code:** `lib/src/state/mods/mods_isolates.dart` (lines 290-343)

```dart
for (final url in urlsByType[type]) {
  final filename = getFileNameFromURL(url);
  // Example: "http://i.imgur.com/tHADwoQ.jpg" → "httpiimgurcomtHADwoQjpg"

  // 1. Check if file exists (in-memory state)
  final filepath = assetMap[filename];  // O(1) lookup
  final fileExists = filepath != null;

  // 2. Check if download failed (Hive: FailedAssets box)
  final errorTypeString = failedAssets[url];  // O(1) lookup
  final hasFailed = errorTypeString != null;

  // 3. Check if backed up (in-memory set from BackupFiles box)
  final isBackedUp = backedUpFiles.contains(filename);  // O(1) lookup

  // Build Asset object
  return Asset(
    url: url,
    fileExists: fileExists,    // From in-memory ExistingAssets
    filePath: filepath,        // From in-memory ExistingAssets
    hasFailed: hasFailed,      // From Hive FailedAssets box
    errorType: errorType,      // From Hive FailedAssets box
    isBackedUp: isBackedUp,    // From in-memory set (derived from BackupFiles)
  );
}
```

---

## Asset State Lookup: Key Usage

### For Downloaded Assets:
```
URL → Convert to filename → Check ExistingAssets in-memory map

Example:
  URL: "http://i.imgur.com/tHADwoQ.jpg"
    ↓
  Filename: "httpiimgurcomtHADwoQjpg"
    ↓
  Check: existingAssets.images["httpiimgurcomtHADwoQjpg"]
    ↓
  Result: "/path/to/httpiimgurcomtHADwoQjpg.jpg" (exists) OR null (not exists)
```

### For Failed Assets:
```
URL → Check FailedAssets Hive box directly

Example:
  URL: "http://i.imgur.com/tHADwoQ.jpg"
    ↓
  Check: failedAssetsBox.get("http://i.imgur.com/tHADwoQ.jpg")
    ↓
  Result: FailedAsset object OR null
```

### For Backed Up Assets (Current - Incorrect):
```
URL → Convert to filename → Check backedUpFiles set

Example:
  URL: "http://i.imgur.com/tHADwoQ.jpg"
    ↓
  Filename: "httpiimgurcomtHADwoQjpg"  (no extension!)
    ↓
  Check: backedUpFiles.contains("httpiimgurcomtHADwoQjpg")
    ↓
  Problem: backedUpFiles contains "httpiimgurcomtHADwoQjpg.jpg" (with extension!)
    ↓
  Result: FALSE (doesn't match because of missing extension)
```

**THE BUG:** Line 321 uses `contains()` with exact match, but:
- `filename` = `"httpiimgurcomtHADwoQjpg"` (no extension)
- `backedUpFiles` contains `"httpiimgurcomtHADwoQjpg.jpg"` (with extension)
- Result: No match!

### For Backed Up Assets (Correct - Using UrlBackupStatus):
```
URL → Check UrlBackupStatus Hive box directly

Example:
  URL: "http://i.imgur.com/tHADwoQ.jpg"
    ↓
  Check: urlBackupStatusBox.containsKey("http://i.imgur.com/tHADwoQ.jpg")
    ↓
  Result: true/false (direct lookup, no conversion needed)
```

---

## Summary Table: Keys Used

| State | Hive Box | Key Format | Key Example | Value |
|-------|----------|------------|-------------|-------|
| **Downloaded** | None (in-memory) | Filename without extension | `httpiimgurcomtHADwoQjpg` | Full filepath |
| **Failed** | `FailedAssets` | Full URL | `http://i.imgur.com/tHADwoQ.jpg` | FailedAsset JSON |
| **Backed Up (metadata)** | `BackupFiles` | Backup filename | `MyMod.ttsmod` | Map of files in backup |
| **Backed Up (URL mapping)** | `UrlBackupStatus` | Full URL | `http://i.imgur.com/tHADwoQ.jpg` | Backup info JSON |

---

## The Problem with Current Backup Check

### Current Code (Line 321):
```dart
final isBackedUp = backedUpFiles.contains(filename);
```

### What's Wrong:
1. `filename` = `"httpiimgurcomtHADwoQjpg"` (from `getFileNameFromURL()`, no extension)
2. `backedUpFiles` = Set of filenames from backup WITH extensions
   - Contains: `{"httpiimgurcomtHADwoQjpg.jpg", "httpiimgurcom8bVZDmujpg.jpg", ...}`
3. `contains()` does exact match
4. `"httpiimgurcomtHADwoQjpg"` ≠ `"httpiimgurcomtHADwoQjpg.jpg"`
5. Result: Always `false` even if file is backed up!

### Solution 1: Use `startsWith()` instead of `contains()`
```dart
final isBackedUp = backedUpFiles.any((file) => file.startsWith(filename));
```

### Solution 2: Use UrlBackupStatus box (recommended)
```dart
final isBackedUp = storage.isUrlBackedUp(url);
// Direct URL lookup, no conversion needed
```

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────┐
│ USER ACTION: Download Asset                              │
└──────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌─────────────────┐         ┌─────────────────────┐
│ SUCCESS         │         │ FAILURE             │
└─────────────────┘         └─────────────────────┘
        │                               │
        ▼                               ▼
┌─────────────────────────────┐   ┌───────────────────────────┐
│ Update ExistingAssets       │   │ Save to FailedAssets box  │
│ (in-memory)                 │   │ Key: URL                   │
│                             │   │ Value: FailedAsset JSON    │
│ Key: filename (no ext)      │   └───────────────────────────┘
│ Value: full filepath        │
└─────────────────────────────┘


┌──────────────────────────────────────────────────────────┐
│ USER ACTION: Create Backup                               │
└──────────────────────────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │ Extract backup metadata       │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │ Save to BackupFiles box       │
        │ Key: backup filename          │
        │ Value: BackupFileMetadata     │
        │   files: {                    │
        │     "filename.jpg": size,     │
        │     ...                       │
        │   }                           │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │ (Optional) Scan for URLs      │
        │ and save to UrlBackupStatus   │
        │ Key: URL                      │
        │ Value: Backup info JSON       │
        └───────────────────────────────┘


┌──────────────────────────────────────────────────────────┐
│ QUERY: Is asset downloaded/failed/backed up?             │
└──────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Downloaded?  │ │ Failed?      │ │ Backed up?   │
│              │ │              │ │              │
│ URL → filename│ │ URL → Hive   │ │ URL → Hive   │
│ Check        │ │ FailedAssets │ │ UrlBackupStatus│
│ ExistingAssets│ │              │ │ OR           │
│ (in-memory)  │ │              │ │ URL → filename│
│              │ │              │ │ Check        │
│              │ │              │ │ BackupFiles  │
│              │ │              │ │ (needs       │
│              │ │              │ │ startsWith!) │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## Recommendations

### Current System:
- ✅ **Downloaded assets:** Works correctly (in-memory, filename keys)
- ✅ **Failed assets:** Works correctly (Hive box, URL keys)
- ❌ **Backed up assets:** BROKEN (using `contains()` with wrong format)

### Fix Options:

#### Option 1: Quick Fix (Change line 321)
```dart
// OLD (WRONG)
final isBackedUp = backedUpFiles.contains(filename);

// NEW (CORRECT)
final isBackedUp = backedUpFiles.any((file) => file.startsWith(filename));
```

**Pros:** One-line fix
**Cons:** Still O(n) lookup, no persistence

#### Option 2: Use UrlBackupStatus box (Recommended)
```dart
// Populate UrlBackupStatus when loading backups
await service.scanBackupForMod(mod, backupFilename, backupMetadata);

// Then check using direct URL lookup
final isBackedUp = storage.isUrlBackedUp(url);  // O(1) lookup
```

**Pros:**
- O(1) lookup performance
- Persisted across app restarts
- Direct URL mapping (no conversion needed)
- Can store additional metadata (which backup, file size, etc.)

**Cons:**
- Requires initial population
- More complex setup

---

## Code Location Reference

- **Storage class:** `lib/src/state/storage/storage.dart`
- **FailedAssets:** Lines 162-227
- **BackupFiles:** Lines 229-275
- **UrlBackupStatus:** Lines 277-344
- **ExistingAssets:** `lib/src/state/asset/existing_assets.dart`
- **Asset building:** `lib/src/state/mods/mods_isolates.dart` (lines 290-343)
- **The bug:** Line 321 in `mods_isolates.dart`
