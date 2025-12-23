# How Tabletop Simulator Mods Work

## Overview

Tabletop Simulator (TTS) mods are **JSON files** that contain object definitions and **URLs to external assets** hosted on Steam's content delivery network. TTS does NOT store the actual asset files (images, models, audio, etc.) inside the mod file - it only stores references (URLs) to them.

## Mod File Structure

### File Locations

TTS stores mods in specific locations on your computer:

**Mods:**
- Windows: `%USERPROFILE%\Documents\My Games\Tabletop Simulator\Mods`
- macOS: `~/Documents/Tabletop Simulator/Mods`
- Linux: `~/.local/share/Tabletop Simulator/Mods`

**Saves:**
- Windows: `%USERPROFILE%\Documents\My Games\Tabletop Simulator\Saves`
- macOS: `~/Documents/Tabletop Simulator/Saves`
- Linux: `~/.local/share/Tabletop Simulator/Saves`

**Saved Objects:**
- Located in subfolders within the Saves directory

### JSON File Structure

Each mod is a `.json` file containing:

1. **Metadata**: Mod name, date, version info
2. **Object Definitions**: Game objects (cards, boards, tokens, etc.)
3. **Asset URLs**: References to external files

**Example JSON snippet:**
```json
{
  "SaveName": "Cool Map Mod",
  "Date": "12/23/2025 10:30:00 AM",
  "ObjectStates": [
    {
      "Name": "Custom_Model",
      "Nickname": "Dragon Miniature",
      "MeshURL": "http://cloud-3.steamusercontent.com/ugc/123456789/model.obj",
      "DiffuseURL": "http://cloud-3.steamusercontent.com/ugc/123456789/texture.jpg",
      "ColliderURL": "http://cloud-3.steamusercontent.com/ugc/123456789/collider.obj"
    },
    {
      "Name": "Custom_Tile",
      "Nickname": "Map Tile",
      "FaceURL": "http://cloud-3.steamusercontent.com/ugc/987654321/tile.png",
      "BackURL": "http://cloud-3.steamusercontent.com/ugc/987654321/back.png"
    },
    {
      "Name": "Custom_PDF",
      "Nickname": "Rulebook",
      "PDFUrl": "http://cloud-3.steamusercontent.com/ugc/555666777/rules.pdf"
    }
  ]
}
```

## Asset Types and JSON Keys

TTS uses specific JSON keys for different types of assets. TTS Mod Vault looks for these exact keys:

### 1. Asset Bundles
**Folder:** `Mods/Assetbundles/`

**JSON Keys:**
- `AssetbundleURL` - Primary asset bundle
- `AssetbundleSecondaryURL` - Secondary asset bundle

Asset bundles are Unity's proprietary format for complex 3D objects with animations, materials, and scripts.

### 2. Audio
**Folder:** `Mods/Audio/`

**JSON Keys:**
- `CurrentAudioURL` - Audio file URL
- `Item1` - Audio item reference

Supports various audio formats (MP3, OGG, WAV).

### 3. Images
**Folder:** `Mods/Images/`

**JSON Keys:**
- `FaceURL` - Front face of cards/tiles
- `BackURL` - Back face of cards/tiles
- `ImageURL` - General image
- `ImageSecondaryURL` - Secondary image
- `DiffuseURL` - Diffuse texture map (color)
- `NormalURL` - Normal map (3D surface detail)
- `URL` - Generic URL reference
- `TableURL` - Custom table background
- `SkyURL` - Skybox texture
- `LutURL` - Color lookup table

### 4. Models
**Folder:** `Mods/Models/`

**JSON Keys:**
- `MeshURL` - 3D mesh file (.obj, .fbx)
- `ColliderURL` - Collision mesh

### 5. PDF
**Folder:** `Mods/PDF/`

**JSON Keys:**
- `PDFUrl` - PDF document URL

## Asset URL Hosting

### Steam Workshop Content Delivery Network

All TTS mod assets are hosted on Steam's content delivery network (CDN):

**Legacy URL format (deprecated):**
```
http://cloud-3.steamusercontent.com/ugc/[id]/[filename].[ext]
```

**Current URL format:**
```
https://steamusercontent-a.akamaihd.net/ugc/[id]/[filename].[ext]
```

**URL Structure:**
- `ugc` = User Generated Content
- `[id]` = Unique identifier for the uploaded file
- `[filename].[ext]` = Original filename and extension

### URL Migration

Steam deprecated the old `http://cloud-3.steamusercontent.com` URLs in favor of `https://steamusercontent-a.akamaihd.net`. TTS Mod Vault automatically:
1. Detects old URL format
2. Updates URLs to new format
3. Renames cached files to match new URL structure

## How TTS Loads Assets

### Loading Process

1. **Load JSON**: TTS reads the mod's JSON file
2. **Parse Objects**: Extract object definitions
3. **Extract URLs**: Find all asset URLs in the JSON
4. **Download Assets**: TTS downloads assets to local cache
5. **Load into Scene**: Assets are loaded from cache into the game

### Local Asset Cache

TTS caches downloaded assets locally to avoid re-downloading:

**Cache Location:**
- Windows: `%USERPROFILE%\Documents\My Games\Tabletop Simulator\Mods\[AssetType]\`
- macOS: `~/Documents/Tabletop Simulator/Mods/[AssetType]/`
- Linux: `~/.local/share/Tabletop Simulator/Mods/[AssetType]/`

**Cache Structure:**
```
Tabletop Simulator/
└── Mods/
    ├── Assetbundles/
    │   ├── 1234567890.unity3d
    │   └── 9876543210.unity3d
    ├── Audio/
    │   ├── sound1.mp3
    │   └── music.ogg
    ├── Images/
    │   ├── 1111111111.png
    │   ├── 2222222222.jpg
    │   └── texture.png
    ├── Models/
    │   ├── dragon.obj
    │   └── building.fbx
    └── PDF/
        └── rulebook.pdf
```

Files are named using the hash/ID from the URL or the original filename.

## How TTS Mod Vault Works

### 1. Scan for Mods

TTS Mod Vault scans the configured directories for `.json` files:

```dart
// Recursively find all JSON files
await for (final entity in directory.list(recursive: true)) {
  if (entity is File && path.extension(entity.path) == '.json') {
    // Process mod file
  }
}
```

### 2. Extract Asset URLs

For each JSON file, extract all asset URLs using regex:

```dart
// Find all asset keys in JSON
final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');

// Examples:
// "FaceURL": "http://..."
// "MeshURL": "https://..."
// "PDFUrl": "http://..."
```

**Supported asset keys:**
- AssetbundleURL, AssetbundleSecondaryURL
- CurrentAudioURL, Item1
- FaceURL, BackURL, ImageURL, ImageSecondaryURL, DiffuseURL, NormalURL, URL, TableURL, SkyURL, LutURL
- MeshURL, ColliderURL
- PDFUrl

### 3. Check Asset Existence

For each extracted URL, check if the file exists in the cache:

```dart
// Extract filename from URL
final filename = getFileNameFromURL(url);

// Check if file exists in appropriate folder
final filepath = assetMap[filename]; // O(1) lookup
final fileExists = filepath != null;
```

### 4. Download Missing Assets

When user clicks "Download":

```dart
// For each missing asset
final response = await dio.download(
  url,
  targetFilePath,
  onReceiveProgress: (received, total) {
    // Update progress
  },
);
```

Downloaded files are saved to:
```
Tabletop Simulator/Mods/[AssetType]/[filename]
```

### 5. Create Backups

When user clicks "Backup", create a `.ttsmod` file:

**Backup contents:**
- The mod's JSON file
- The mod's thumbnail image (if exists)
- All downloaded asset files

**Backup structure (ZIP format):**
```
CoolMap.ttsmod (ZIP file)
├── Mods/
│   ├── Workshop/
│   │   ├── 123456789.json
│   │   └── 123456789.png
│   ├── Assetbundles/
│   │   └── asset.unity3d
│   ├── Images/
│   │   ├── face.png
│   │   └── back.png
│   └── Models/
│       └── model.obj
```

## Common Issues and Solutions

### Issue 1: Missing Assets
**Problem:** Mod loads but some objects appear as error/question marks
**Cause:** Asset URLs are broken or files not cached
**Solution:** Use TTS Mod Vault to download missing assets

### Issue 2: Old URL Format
**Problem:** Assets fail to download (404 errors)
**Cause:** Using deprecated `http://cloud-3.steamusercontent.com` URLs
**Solution:** TTS Mod Vault automatically updates URLs to new format

### Issue 3: Ephemeral URLs
**Problem:** URLs that worked before now return 404
**Cause:** Steam removed or relocated the content
**Solution:**
- If you have a backup: restore from backup
- If no backup: asset is permanently lost unless re-uploaded

### Issue 4: Large Mods
**Problem:** Slow loading or timeouts
**Cause:** Many high-resolution assets
**Solution:** Download assets in advance using TTS Mod Vault

## Why TTS Mod Vault Exists

### The Problem

1. **URLs Go Stale**: Steam Workshop content can be removed or URLs can break
2. **Slow Downloads**: Large mods take time to download in TTS
3. **No Version Control**: Hard to track changes between mod versions
4. **Lost Content**: If URLs break, content is permanently lost
5. **No Bulk Operations**: TTS doesn't support downloading all assets at once

### The Solution

TTS Mod Vault provides:
1. **Pre-download Assets**: Download all assets before playing
2. **Create Backups**: Save complete mods with all assets
3. **URL Migration**: Automatically update deprecated URLs
4. **Asset Tracking**: Know which assets are downloaded/missing/backed up
5. **Bulk Operations**: Download/backup multiple mods at once
6. **Content Preservation**: Keep copies even if Steam removes content

## Technical Implementation Details

### Regex-Based Extraction

TTS Mod Vault uses regex instead of full JSON parsing for performance:

**Why?**
- JSON parsing requires loading entire file into memory
- Regex can stream through the file
- Only need to find specific keys, not parse entire structure
- Much faster for large JSON files (some mods are 50+ MB)

**Pattern:**
```dart
final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');
```

Matches:
```json
"FaceURL": "http://example.com/image.png"
"MeshURL":"https://example.com/model.obj"
"PDFUrl"  :  "http://example.com/doc.pdf"
```

### URL Processing

URLs in TTS JSON can have special formats:

**Localized URLs:**
```json
"FaceURL": "{en}http://example.com/en.png{fr}http://example.com/fr.png"
```

**Processing:**
1. Extract all URLs using regex
2. Split on `{language_code}` markers
3. Filter out `file:/` local paths
4. Update old URL format to new
5. Create separate entries for each language variant

### Isolate-Based Processing

Asset processing runs in Dart isolates (background threads):

**Benefits:**
- UI remains responsive during processing
- Can process multiple mods in parallel
- Utilize multi-core CPUs
- 10,000+ mods can be processed in seconds

**Process:**
```dart
// Main thread
final futures = batches.map((batch) =>
  Isolate.run(() => processBatch(batch))
).toList();

final results = await Future.wait(futures);
```

### O(1) Asset Lookups

Asset existence is checked using hash maps:

```dart
// Pre-build map of all cached files
final Map<String, String> existingAssets = {
  'filename.png': '/path/to/file.png',
  'model.obj': '/path/to/model.obj',
};

// O(1) lookup when checking each asset
final filepath = existingAssets[filename];
final exists = filepath != null;
```

This allows checking 10,000+ assets in milliseconds instead of doing file system checks for each one.

## Summary

**TTS mods are JSON files containing:**
- Object definitions
- References (URLs) to external assets
- Metadata (name, date, etc.)

**Assets are:**
- Hosted on Steam's CDN
- Downloaded to local cache by TTS
- Referenced by URL in the JSON
- Can be: images, 3D models, audio, PDFs, asset bundles

**TTS Mod Vault helps by:**
- Pre-downloading all assets
- Creating complete backups
- Tracking asset states (downloaded/missing/backed up/failed)
- Migrating deprecated URLs
- Providing bulk operations
- Preserving content even if URLs break

**Key Insight:**
> TTS mods are NOT self-contained. They rely on external URLs that can break. This is why backing up and tracking assets is critical for long-term mod preservation.
