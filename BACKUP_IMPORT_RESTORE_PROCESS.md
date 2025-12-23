# Backup Import/Restore Process - Complete Documentation

## Overview

The import process is the **reverse** of the backup process, extracting files from a `.ttsmod` ZIP archive and restoring them to the TTS Mods directories.

---

## Import Process Flow

**File:** `lib/src/state/backup/import_backup.dart`

### Step 1: User Selects Backup File

```dart
// User picks a .ttsmod file
final result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['ttsmod'],
);

final filePath = result.files.single.path;
// Example: "/path/to/backups/MyMod.ttsmod"
```

---

### Step 2: Read and Decode ZIP Archive

```dart
// Line 100-101
final bytes = await File(filePath).readAsBytes();
final archive = ZipDecoder().decodeBytes(bytes);

// archive.files contains all files in the ZIP:
// - Mods/Workshop/123456789.json
// - Mods/Workshop/123456789.png
// - Mods/Images/httpiimgurcomtHADwoQjpg.jpg
// - Mods/Images/httpiimgurcom8bVZDmujpg.jpg
// - Mods/Models/httpchrymeupmemeflag5unity3d.unity3d
// etc.
```

---

### Step 3: Extract Each File

```dart
for (final file in archive) {
  if (file.isFile) {
    // Line 114: Get the filename from inside the ZIP
    final filename = file.name;
    // Example: "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

    // Line 115-119: Determine target directory
    String targetDir = modsDir.parent.path;
    // Example: "/Users/username/Documents/My Games/Tabletop Simulator"

    if (filename.startsWith('Saves')) {
      targetDir = savesDir.parent.path;
    }

    // Line 121-122: Create output file path
    final data = file.content as List<int>;
    final outputFile = File('$targetDir/$filename');
    // Result: "/Users/.../Tabletop Simulator/Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

    // Line 150-151: Write file to disk
    await outputFile.create(recursive: true);
    await outputFile.writeAsBytes(data);
  }
}
```

**Result:** Files are extracted with their **full paths and extensions**:
- `/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg` ✓
- `/path/to/Mods/Images/httpiimgurcom8bVZDmujpg.jpg` ✓
- `/path/to/Mods/Models/httpchrymeupmemeflag5unity3d.unity3d` ✓

---

### Step 4: Track Extracted Assets

```dart
// Line 138-144: Track asset files by type
final assetType = _getAssetTypeFromPath(file.name);
// Returns: AssetTypeEnum.image, AssetTypeEnum.model, etc.

if (assetType != null) {
  // Get filename WITHOUT extension for tracking
  final assetFilename = p.basenameWithoutExtension(outputFile.path);
  // Example: "httpiimgurcomtHADwoQjpg" (no .jpg)

  extractedAssets[assetType]![assetFilename] = outputFile.path;
  // Stores: {"httpiimgurcomtHADwoQjpg": "/path/to/.../httpiimgurcomtHADwoQjpg.jpg"}
}
```

**Key Point:** Assets are tracked by their **basename WITHOUT extension**, even though the files have extensions on disk.

---

### Step 5: Register Assets in App State

```dart
// Line 161-172: Add extracted assets to app state
for (final entry in extractedAssets.entries) {
  final assetType = entry.key;  // AssetTypeEnum.image
  final assets = entry.value;    // {"httpiimgurcomtHADwoQjpg": "/full/path/..."}

  for (final asset in assets.entries) {
    ref.read(existingAssetListsProvider.notifier).addExistingAsset(
      assetType,
      asset.key,    // "httpiimgurcomtHADwoQjpg" (without extension)
      asset.value,  // "/path/to/httpiimgurcomtHADwoQjpg.jpg" (full path)
    );
  }
}

// Line 174-177: Add the mod JSON to app state
await ref.read(modsProvider.notifier).addSingleMod(
  importedJsonFilePath,
  modType,
);
```

---

## Complete Example: Single Asset Restoration

### Original Asset URL:
```
http://i.imgur.com/tHADwoQ.jpg
```

### In Backup ZIP:
```
MyMod.ttsmod (ZIP)
└── Mods/
    └── Images/
        └── httpiimgurcomtHADwoQjpg.jpg  ← Full filename WITH extension
```

### Import Process:

#### Step 3: Extract File
```dart
filename = "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
targetDir = "/Users/me/Documents/My Games/Tabletop Simulator"

outputFile = File("/Users/me/Documents/My Games/Tabletop Simulator/Mods/Images/httpiimgurcomtHADwoQjpg.jpg")

// Write file to disk
await outputFile.create(recursive: true);
await outputFile.writeAsBytes(data);
```

**Result:** File written to disk:
- Path: `/Users/.../Mods/Images/httpiimgurcomtHADwoQjpg.jpg`
- Filename: `httpiimgurcomtHADwoQjpg.jpg` (WITH extension)

#### Step 4: Track Asset
```dart
assetType = _getAssetTypeFromPath("Mods/Images/httpiimgurcomtHADwoQjpg.jpg")
          = AssetTypeEnum.image

assetFilename = p.basenameWithoutExtension(
  "/Users/.../Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
)
              = "httpiimgurcomtHADwoQjpg"  // WITHOUT extension

extractedAssets[AssetTypeEnum.image]["httpiimgurcomtHADwoQjpg"]
  = "/Users/.../Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
```

#### Step 5: Register Asset
```dart
addExistingAsset(
  AssetTypeEnum.image,
  "httpiimgurcomtHADwoQjpg",  // Tracked WITHOUT extension
  "/Users/.../Mods/Images/httpiimgurcomtHADwoQjpg.jpg"  // Full path WITH extension
)
```

---

## Complete Round-Trip: Backup → Import

### Stage 1: Original Download
```
URL: http://i.imgur.com/tHADwoQ.jpg
↓
Download as: httpiimgurcomtHADwoQjpg (no extension)
Add extension: httpiimgurcomtHADwoQjpg.jpg
↓
File on disk: /path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg
```

### Stage 2: Backup
```
Read file: /path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg
↓
Get relative path: Mods/Images/httpiimgurcomtHADwoQjpg.jpg
↓
Add to ZIP: Mods/Images/httpiimgurcomtHADwoQjpg.jpg (WITH extension)
```

### Stage 3: Backup Metadata
```
Extract from ZIP: Mods/Images/httpiimgurcomtHADwoQjpg.jpg
↓
Get basename: httpiimgurcomtHADwoQjpg.jpg
↓
Store in Hive: {"httpiimgurcomtHADwoQjpg.jpg": 12345}
```

### Stage 4: Import/Restore
```
ZIP file: Mods/Images/httpiimgurcomtHADwoQjpg.jpg
↓
Extract to: /path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg (WITH extension)
↓
Track as: "httpiimgurcomtHADwoQjpg" (WITHOUT extension)
↓
Register: addExistingAsset("httpiimgurcomtHADwoQjpg", "/path/.../httpiimgurcomtHADwoQjpg.jpg")
```

---

## Key Functions in Import Process

### `_getAssetTypeFromPath()`
**Lines 198-211**

Determines asset type by looking for directory names in the path:

```dart
AssetTypeEnum? _getAssetTypeFromPath(String filePath) {
  // "Mods/Images/httpiimgurcomtHADwoQjpg.jpg" → AssetTypeEnum.image
  // "Mods/Models/dragon.obj" → AssetTypeEnum.model
  // "Mods/Audio/sound.mp3" → AssetTypeEnum.audio

  final pathParts = p.split(normalizedPath).map((part) => part.toLowerCase());

  for (final assetType in AssetTypeEnum.values) {
    if (pathParts.contains(assetType.label.toLowerCase())) {
      return assetType;
    }
  }

  return null;
}
```

**Asset type labels:**
- `AssetTypeEnum.image` → `"Images"`
- `AssetTypeEnum.model` → `"Models"`
- `AssetTypeEnum.audio` → `"Audio"`
- `AssetTypeEnum.assetBundle` → `"Assetbundles"`
- `AssetTypeEnum.pdf` → `"PDF"`

### `_isJsonFile()`
**Lines 189-196**

Identifies JSON mod files:

```dart
bool _isJsonFile(String inputPath) {
  // Must be .json file AND in Workshop directory
  final isJsonFile = p.extension(filePath).toLowerCase() == '.json';
  final containsWorkshop = p.split(filePath).contains('Workshop');

  return isJsonFile && containsWorkshop;
}
```

---

## Summary Table: Complete Flow

| Stage | Location | Filename Format | Example |
|-------|----------|-----------------|---------|
| **1. Download** | Local disk | WITH extension | `httpiimgurcomtHADwoQjpg.jpg` |
| **2. Backup** | Inside ZIP | WITH extension | `Mods/Images/httpiimgurcomtHADwoQjpg.jpg` |
| **3. Metadata** | Hive (BackupFileMetadata) | WITH extension | `httpiimgurcomtHADwoQjpg.jpg` → 12345 bytes |
| **4. Import - Extract** | Local disk | WITH extension | `httpiimgurcomtHADwoQjpg.jpg` |
| **5. Import - Track** | App state (extractedAssets) | WITHOUT extension | `httpiimgurcomtHADwoQjpg` → path |
| **6. Import - Register** | existingAssetListsProvider | WITHOUT extension | `httpiimgurcomtHADwoQjpg` |

---

## Critical Points

1. **Files are stored in ZIP WITH extensions** (`httpiimgurcomtHADwoQjpg.jpg`)
2. **Files are extracted to disk WITH extensions** (`httpiimgurcomtHADwoQjpg.jpg`)
3. **Files are tracked in app state WITHOUT extensions** (`httpiimgurcomtHADwoQjpg`)
4. **BackupFileMetadata stores WITH extensions** (`httpiimgurcomtHADwoQjpg.jpg`)

---

## Implications for URL Matching

When checking if a URL is backed up:

```dart
// URL to check
final url = "http://i.imgur.com/tHADwoQ.jpg";

// Convert to filename (no extension)
final urlFilename = getFileNameFromURL(url);
// Result: "httpiimgurcomtHADwoQjpg"

// BackupFileMetadata has files WITH extensions
final backupFiles = backupMetadata.files.keys;
// Contains: "httpiimgurcomtHADwoQjpg.jpg", "httpiimgurcom8bVZDmujpg.jpg", etc.

// Must use startsWith() because:
// - URL converts to: "httpiimgurcomtHADwoQjpg" (no ext)
// - Backup has: "httpiimgurcomtHADwoQjpg.jpg" (with ext)

final isBackedUp = backupFiles.any((file) => file.startsWith(urlFilename));
// "httpiimgurcomtHADwoQjpg.jpg".startsWith("httpiimgurcomtHADwoQjpg") = true ✓
```

---

## File Path Examples

### Backup File Structure
```
MyMod.ttsmod (ZIP)
├── Mods/
│   ├── Workshop/
│   │   ├── 123456789.json        ← JSON mod file
│   │   └── 123456789.png         ← Workshop image
│   ├── Images/
│   │   ├── httpiimgurcomtHADwoQjpg.jpg
│   │   └── httpiimgurcom8bVZDmujpg.jpg
│   ├── Models/
│   │   └── httpchrymeupmemeflag5unity3d.unity3d
│   └── Audio/
│       └── httpsoundcloudcomaudio123mp3.mp3
```

### After Import (on disk)
```
/Users/username/Documents/My Games/Tabletop Simulator/
├── Mods/
│   ├── Workshop/
│   │   ├── 123456789.json
│   │   └── 123456789.png
│   ├── Images/
│   │   ├── httpiimgurcomtHADwoQjpg.jpg      ← Extracted WITH extension
│   │   └── httpiimgurcom8bVZDmujpg.jpg      ← Extracted WITH extension
│   ├── Models/
│   │   └── httpchrymeupmemeflag5unity3d.unity3d
│   └── Audio/
│       └── httpsoundcloudcomaudio123mp3.mp3
```

### In App State (existingAssetListsProvider)
```dart
{
  AssetTypeEnum.image: {
    "httpiimgurcomtHADwoQjpg": "/path/to/httpiimgurcomtHADwoQjpg.jpg",  // No ext in key
    "httpiimgurcom8bVZDmujpg": "/path/to/httpiimgurcom8bVZDmujpg.jpg",  // No ext in key
  },
  AssetTypeEnum.model: {
    "httpchrymeupmemeflag5unity3d": "/path/to/httpchrymeupmemeflag5unity3d.unity3d",
  },
  AssetTypeEnum.audio: {
    "httpsoundcloudcomaudio123mp3": "/path/to/httpsoundcloudcomaudio123mp3.mp3",
  }
}
```

---

## Why Extensions Matter

The system uses **two different representations**:

1. **On disk / in backup ZIP:** Files have extensions
   - Needed for OS to recognize file types
   - Needed for proper file handling

2. **In app state tracking:** Filenames without extensions
   - Matches how URLs are converted (`getFileNameFromURL()`)
   - Allows matching regardless of actual file extension
   - Example: Same URL might be `.jpg` or `.png` depending on download

This dual representation is why you must use `startsWith()` when matching URLs to backup files!
