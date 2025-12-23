# TTS JSON File Structure and Metadata

## File Locations

### Default Storage Locations by Platform

**Windows:**
```
%USERPROFILE%\Documents\My Games\Tabletop Simulator\
├── Mods\                     # Workshop mods (.json files)
│   ├── Workshop\             # Steam Workshop mods
│   ├── Assetbundles\         # Asset bundle cache
│   ├── Audio\                # Audio file cache
│   ├── Images\               # Image file cache
│   ├── Models\               # 3D model file cache
│   └── PDF\                  # PDF file cache
└── Saves\                    # Saved games (.json files)
    └── SavedObjects\         # Saved objects (.json files)
```

**macOS:**
```
~/Library/Tabletop Simulator/
├── Mods/
│   ├── Workshop/
│   └── [asset folders...]
└── Saves/
    └── SavedObjects/
```

**Linux:**
```
~/.local/share/Tabletop Simulator/
├── Mods/
│   ├── Workshop/
│   └── [asset folders...]
└── Saves/
    └── SavedObjects/

# Alternative (Snap installation):
~/snap/steam/common/.local/share/Tabletop Simulator/
```

### File Naming Convention

- **Mods/Saves:** `[WorkshopID or custom name].json`
  - Example: `123456789.json` (Workshop mod)
  - Example: `MyCustomMod.json` (Custom mod)
- **Saved Objects:** Located in subdirectories within `Saves/SavedObjects/`

## JSON Structure and Metadata

### Top-Level Fields

TTS JSON files contain the following **metadata fields**:

```json
{
  "SaveName": "Cool Adventure Map",
  "Date": "12/23/2025 3:45:30 PM",
  "GameMode": "Tabletop Simulator",
  "Gravity": 0.5,
  "PlayArea": 0.5,
  "Table": "Table_RPG",
  "Sky": "Sky_Museum",
  "Note": "",
  "Rules": "",
  "LuaScript": "-- Game logic here",
  "LuaScriptState": "",
  "XmlUI": "",
  "ObjectStates": [
    // Array of game objects
  ],
  "TabStates": {},
  "VersionNumber": ""
}
```

### Key Metadata Fields

#### 1. SaveName (String)
- **What it is:** The display name of the mod/save
- **Format:** Free text string
- **Example:** `"SaveName": "Epic Dungeon Crawler"`
- **For Saved Objects:** Uses `"Nickname"` field instead of `"SaveName"`
- **Extracted by:** Regex pattern `"SaveName"\s*:\s*"([^"]*)"`

#### 2. Date (String)
- **What it is:** Timestamp when the mod was **last saved in TTS**
- **Format:** `M/d/yyyy h:mm:ss a` (12-hour) or `MM/dd/yyyy HH:mm:ss` (24-hour)
- **Examples:**
  - `"Date": "12/23/2025 3:45:30 PM"`
  - `"Date": "01/15/2025 15:30:00"`
- **Extracted by:** Regex pattern `"Date"\s*:\s*"([^"]*)"`
- **Converted to:** Unix timestamp (seconds since epoch) for storage
- **Important:** This is when the **mod file** was saved, NOT when individual assets were created

#### 3. ObjectStates (Array)
- **What it is:** Array of all game objects in the mod
- **Contains:** Object definitions with asset URLs
- **Each object has:**
  - `Name`: Object type (e.g., "Custom_Model", "Custom_Tile", "Card", "Deck")
  - `Nickname`: Display name
  - `Transform`: Position, rotation, scale
  - **Asset URLs**: References to external files (see below)

### Asset URLs in ObjectStates

**Critical Point:** The JSON does NOT store file metadata (sizes, dates, checksums) for assets. It ONLY stores URLs.

```json
{
  "ObjectStates": [
    {
      "Name": "Custom_Model",
      "Nickname": "Dragon Miniature",
      "Transform": { /* position data */ },

      // ONLY URLs ARE STORED - NO FILE METADATA
      "MeshURL": "http://cloud-3.steamusercontent.com/ugc/123456/model.obj",
      "DiffuseURL": "http://cloud-3.steamusercontent.com/ugc/123456/texture.png",
      "ColliderURL": "http://cloud-3.steamusercontent.com/ugc/123456/collider.obj"
    },
    {
      "Name": "Custom_Tile",
      "Nickname": "Map Tile",

      // ONLY URLs - NO SIZE, DATE, OR CHECKSUM
      "FaceURL": "http://cloud-3.steamusercontent.com/ugc/987654/face.png",
      "BackURL": "http://cloud-3.steamusercontent.com/ugc/987654/back.png"
    }
  ]
}
```

## What Is NOT Stored in JSON

### ❌ Asset File Metadata

The following information is **NOT stored** in TTS JSON files:

1. **File Sizes** - Asset file sizes are not recorded
2. **File Dates** - Individual asset creation/modification dates are not recorded
3. **Checksums/Hashes** - No CRC, MD5, SHA checksums
4. **File Names** - Only URLs are stored, filenames are derived from URLs
5. **MIME Types** - File types are inferred from URL extensions
6. **Download Status** - Whether assets are cached locally
7. **File Versions** - No version tracking for assets

### Why This Matters

**Implication:** You cannot compare asset files between a mod and a backup just by reading the JSON files.

To determine if assets have changed, you must:
1. Read the URLs from JSON
2. Extract filenames from URLs
3. Check if files exist on disk or in backup
4. Compare file sizes/dates by statting actual files
5. Optionally compute checksums for content comparison

**Example:**

```json
// JSON only contains:
"MeshURL": "http://steamusercontent.com/ugc/123456/dragon.obj"

// To get file metadata, you must:
// 1. Extract filename: "dragon.obj"
// 2. Find file in cache: "Mods/Models/dragon.obj"
// 3. Stat the file:
final stat = await File('Mods/Models/dragon.obj').stat();
final size = stat.size;           // Get size from filesystem
final modified = stat.modified;   // Get date from filesystem

// The JSON itself has NO size or date information for "dragon.obj"
```

## Filesystem Metadata (Not in JSON)

### JSON File Metadata

TTS Mod Vault **does** track metadata about the JSON file itself (not the assets):

```dart
// File metadata from filesystem
final jsonFileStat = await File(jsonPath).stat();

final Mod(
  jsonFilePath: jsonPath,
  saveName: extractedSaveName,
  dateTimeStamp: extractedDateFromJSON,      // From "Date" field IN JSON
  createdAtTimestamp: jsonFileStat.changed,   // From FILE SYSTEM
  // ... other fields
);
```

**Two different timestamps:**
1. `dateTimeStamp` - From `"Date"` field **inside** JSON (when mod was saved in TTS)
2. `createdAtTimestamp` - From **file system** (when JSON file was modified on disk)

These can differ if the JSON file is copied, imported, or downloaded.

## How TTS Mod Vault Extracts Metadata

### Extraction Process

TTS Mod Vault uses **regex patterns** instead of full JSON parsing for performance:

```dart
// Extract SaveName
final saveNameRegex = RegExp(r'"SaveName"\s*:\s*"([^"]*)"');
final match = saveNameRegex.firstMatch(jsonString);
final saveName = match?.group(1);

// Extract Date
final dateRegex = RegExp(r'"Date"\s*:\s*"([^"]*)"');
final match = dateRegex.firstMatch(jsonString);
final dateValue = match?.group(1);

// Extract Asset URLs
final assetKeyRegex = RegExp(r'"MeshURL"\s*:\s*"([^"]*)"');
// ... repeat for all asset key types
```

**Why regex instead of JSON parsing?**
- Large JSON files (50+ MB for complex mods)
- Only need specific fields, not entire structure
- Streaming approach - can stop early once fields found
- Much faster for large files

### Asset URL Extraction

```dart
// All possible asset keys
final assetKeys = [
  // Asset Bundles
  'AssetbundleURL', 'AssetbundleSecondaryURL',

  // Audio
  'CurrentAudioURL', 'Item1',

  // Images
  'FaceURL', 'BackURL', 'ImageURL', 'ImageSecondaryURL',
  'DiffuseURL', 'NormalURL', 'URL', 'TableURL', 'SkyURL', 'LutURL',

  // Models
  'MeshURL', 'ColliderURL',

  // PDF
  'PDFUrl',
];

// For each key, extract URL
for (final key in assetKeys) {
  final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');
  final matches = pattern.allMatches(jsonString);

  for (final match in matches) {
    final url = match.group(1);
    // URL extracted - but NO file metadata
  }
}
```

## Comparing Mods vs Backups

### Challenge: No Asset Metadata in JSON

Since the JSON doesn't contain file sizes or dates for assets, comparison must be done by:

1. **Extracting URLs from both:**
   - Current mod JSON
   - Backup contents (or backup metadata)

2. **Checking file existence:**
   - Current: Check if files exist in TTS cache
   - Backup: Check if files exist in backup archive

3. **Comparing file lists:**
   - Added: URLs in current but not in backup
   - Removed: URLs in backup but not in current
   - Unchanged: URLs in both

4. **Optional: Deep comparison:**
   - Extract actual files from backup
   - Compare file sizes (from filesystem/archive metadata)
   - Compare checksums (requires reading file contents)

### Simple Comparison Strategy

**What TTS Mod Vault Can Compare:**

```dart
// 1. Mod Date (from JSON "Date" field)
if (mod.dateTimeStamp != backup.dateTimeStamp) {
  // Mod has been saved since backup
}

// 2. Asset Count
if (mod.assetCount != backup.totalAssetCount) {
  // Different number of assets
}

// 3. Asset List (from URLs)
final currentUrls = extractUrlsFromJson(mod.jsonPath);
final backupUrls = getBackupFileList(backup.filepath);

final added = currentUrls - backupUrls;
final removed = backupUrls - currentUrls;
```

**What Requires File Access:**

```dart
// File size comparison
final currentSize = File(assetPath).stat().size;
final backupSize = zipFile.size;  // From zip archive metadata

// Content comparison
final currentCrc = computeCrc32(File(assetPath));
final backupCrc = zipFile.crc32;  // From zip archive
```

## Example JSON Structure

### Minimal Mod Example

```json
{
  "SaveName": "Simple Test Mod",
  "Date": "12/23/2025 10:00:00 AM",
  "GameMode": "Tabletop Simulator",
  "ObjectStates": [
    {
      "Name": "Custom_Model",
      "GUID": "abc123",
      "Nickname": "Test Cube",
      "Transform": {
        "posX": 0,
        "posY": 1,
        "posZ": 0,
        "rotX": 0,
        "rotY": 0,
        "rotZ": 0,
        "scaleX": 1,
        "scaleY": 1,
        "scaleZ": 1
      },
      "MeshURL": "http://steamusercontent.com/ugc/123/cube.obj",
      "DiffuseURL": "http://steamusercontent.com/ugc/123/texture.png"
    }
  ]
}
```

**Metadata Available:**
- ✅ Mod name: "Simple Test Mod"
- ✅ Mod save date: "12/23/2025 10:00:00 AM"
- ✅ Asset URLs: 2 URLs found
- ❌ Asset file sizes: NOT in JSON
- ❌ Asset file dates: NOT in JSON
- ❌ Asset checksums: NOT in JSON

## Summary

### What IS in TTS JSON Files

1. **SaveName** - Mod display name
2. **Date** - When mod was last saved in TTS
3. **Asset URLs** - References to external files
4. **Object definitions** - Game object properties
5. **Game settings** - Table, sky, physics, etc.
6. **Scripts** - Lua code and UI definitions

### What is NOT in TTS JSON Files

1. ❌ Asset file sizes
2. ❌ Asset file modification dates
3. ❌ Asset file checksums/hashes
4. ❌ Asset file metadata
5. ❌ Download status
6. ❌ Cache locations
7. ❌ Version information for individual assets

### Key Insight

> **TTS JSON files are essentially "pointers" to external assets, not containers of asset metadata.**
>
> To compare mods and backups, you must:
> 1. Extract URLs from JSON (available)
> 2. Check actual files on disk or in archives (requires filesystem/archive access)
> 3. Compare file metadata from filesystem/archive, not from JSON

This is why TTS Mod Vault stores backup file metadata separately in Hive - the JSON alone doesn't provide enough information to determine what's in a backup without extracting it.
