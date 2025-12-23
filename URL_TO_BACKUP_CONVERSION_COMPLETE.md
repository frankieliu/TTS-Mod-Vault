# URL to Backed Up File: Complete Conversion Process

## Complete Flow: URL → Download → Backup → Metadata

### Step 1: Download Process

**File:** `lib/src/state/download/download.dart` (lines 193, 249-251)

```dart
// 1. Convert URL to filename (removes all non-alphanumeric chars)
final fileName = getFileNameFromURL(originalUrl);
// Example: "http://i.imgur.com/tHADwoQ.jpg" → "httpiimgurcomtHADwoQjpg"

// 2. Download to temp location
final tempPath = path.join(directory, '${fileName}_temp');
await dio.download(url, tempPath, ...);

// 3. Read bytes and determine proper file extension
final bytes = await tempFile.readAsBytes();
final extension = getExtensionByType(type, tempPath, bytes);
// Returns: ".jpg", ".png", ".mp3", ".obj", ".unity3d", ".PDF", etc.

// 4. Rename to final path WITH EXTENSION
final finalPath = path.join(directory, fileName + extension);
await tempFile.rename(finalPath);
// Result: "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
```

**Downloaded file on disk:**
- Filename: `httpiimgurcomtHADwoQjpg.jpg` (includes extension)
- Location: `/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg`

---

### Step 2: Backup Process

**File:** `lib/src/state/backup/backup.dart` (lines 159-188)

```dart
(List<String>, int) _getFilePathsIsolate(FilepathsIsolateData data) {
  final filePaths = <String>[];

  for (final type in AssetTypeEnum.values) {
    final directory = Directory(dirPath);
    final files = directory.listSync();

    data.mod.getAssetsByType(type).forEach((asset) {
      if (asset.filePath == null) return;

      // Get the basename WITHOUT extension from the actual downloaded file
      final newUrlBase = p.basenameWithoutExtension(asset.filePath!);
      // Example: asset.filePath = "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
      // newUrlBase = "httpiimgurcomtHADwoQjpg"

      // Handle old Steam URL format too
      final oldUrlBase = newUrlBase.replaceFirst(
        getFileNameFromURL(newSteamUserContentUrl),
        getFileNameFromURL(oldCloudUrl),
      );

      // Find the file that starts with this basename
      final match = files.firstWhereOrNull((file) {
        final base = p.basenameWithoutExtension(file.path);
        return base.startsWith(newUrlBase) || base.startsWith(oldUrlBase);
      });

      if (match != null && match.path.isNotEmpty) {
        filePaths.add(p.normalize(match.path));
        // Adds: "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
      }
    });
  }

  return (filePaths, assetFilesCount);
}
```

**Files added to backup:**
- Full file with extension: `httpiimgurcomtHADwoQjpg.jpg`
- Stored in ZIP at: `Mods/Images/httpiimgurcomtHADwoQjpg.jpg`

---

### Step 3: Backup Creation (ZIP)

**File:** `lib/src/state/backup/backup.dart` (lines 201-250)

```dart
void _backupIsolate(BackupIsolateData data) async {
  final encoder = ZipFileEncoder();
  encoder.create(data.targetBackupFilePath);

  for (int i = 0; i < data.filePaths.length; i++) {
    final filePath = data.filePaths[i];
    // Example: "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

    final file = File(filePath);

    final relativePath = p.relative(
      filePath,
      from: data.modsParentPath,
    );
    // Result: "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

    await encoder.addFile(file, relativePath);
    // Adds file to ZIP with full filename INCLUDING extension
  }

  await encoder.close();
}
```

**Inside backup.ttsmod ZIP:**
```
Mods/
├── Workshop/
│   ├── 123456789.json
│   └── 123456789.png
├── Images/
│   ├── httpiimgurcomtHADwoQjpg.jpg      ← Full filename with .jpg
│   ├── httpiimgurcom8bVZDmujpg.jpg      ← Full filename with .jpg
│   └── httpiimgurcomMINkosrjpg.jpg      ← Full filename with .jpg
├── Models/
│   └── httpchrymeupmemeflag5unity3d.unity3d  ← Full filename with .unity3d
```

---

### Step 4: Backup Metadata Extraction

**File:** `lib/src/state/backup/existing_backups.dart` (lines 322-333)

```dart
final bytes = await file.readAsBytes();
final archive = ZipDecoder().decodeBytes(bytes);

final Map<String, int> filesMap = {};
for (final zipFile in archive.files) {
  if (!zipFile.isFile) continue;

  // Get basename from the full ZIP path
  final name = path.basename(zipFile.name);
  // Example: zipFile.name = "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"
  // name = "httpiimgurcomtHADwoQjpg.jpg"

  if (name.isNotEmpty) {
    filesMap[name] = zipFile.size;
    // Stores: "httpiimgurcomtHADwoQjpg.jpg" → 12345 bytes
  }
}

metadata = BackupFileMetadata(files: filesMap);
// metadata.files = {
//   "httpiimgurcomtHADwoQjpg.jpg": 12345,
//   "httpiimgurcom8bVZDmujpg.jpg": 67890,
//   ...
// }
```

**BackupFileMetadata stored in Hive:**
```dart
{
  "files": {
    "httpiimgurcomtHADwoQjpg.jpg": 12345,
    "httpiimgurcom8bVZDmujpg.jpg": 67890,
    "httpiimgurcomMINkosrjpg.jpg": 54321,
    "httpchrymeupmemeflag5unity3d.unity3d": 98765,
    ...
  }
}
```

---

## Complete Example: Single Asset

### Asset URL:
```
http://i.imgur.com/tHADwoQ.jpg
```

### Download (Step 1):
```dart
fileName = getFileNameFromURL("http://i.imgur.com/tHADwoQ.jpg")
        = "httpiimgurcomtHADwoQjpg"

extension = getExtensionByType(AssetTypeEnum.image, ...)
          = ".jpg"

finalPath = "httpiimgurcomtHADwoQjpg" + ".jpg"
          = "httpiimgurcomtHADwoQjpg.jpg"
```

**Downloaded file:** `/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg`

### Backup (Step 2):
```dart
asset.filePath = "/path/to/Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

newUrlBase = p.basenameWithoutExtension(asset.filePath)
           = "httpiimgurcomtHADwoQjpg"

// Find file that starts with "httpiimgurcomtHADwoQjpg"
files.firstWhereOrNull((file) {
  final base = p.basenameWithoutExtension(file.path);
  // base = "httpiimgurcomtHADwoQjpg"
  return base.startsWith("httpiimgurcomtHADwoQjpg");
  // "httpiimgurcomtHADwoQjpg".startsWith("httpiimgurcomtHADwoQjpg") = TRUE
})

// Matches! Add to backup
```

**Added to backup ZIP:** `Mods/Images/httpiimgurcomtHADwoQjpg.jpg`

### Metadata Extraction (Step 4):
```dart
zipFile.name = "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"

name = path.basename(zipFile.name)
     = "httpiimgurcomtHADwoQjpg.jpg"

filesMap["httpiimgurcomtHADwoQjpg.jpg"] = zipFile.size
```

**BackupFileMetadata:**
```json
{
  "files": {
    "httpiimgurcomtHADwoQjpg.jpg": 12345
  }
}
```

---

## Checking if URL is Backed Up

### Given:
- **URL:** `http://i.imgur.com/tHADwoQ.jpg`
- **BackupFileMetadata.files:** `{"httpiimgurcomtHADwoQjpg.jpg": 12345, ...}`

### Process:

```dart
// Step 1: Convert URL to filename (NO extension)
final urlFilename = getFileNameFromURL(url);
// urlFilename = "httpiimgurcomtHADwoQjpg"

// Step 2: Check if ANY file in backup starts with this filename
for (final backupFile in backupMetadata.files.keys) {
  // backupFile = "httpiimgurcomtHADwoQjpg.jpg"

  if (backupFile.startsWith(urlFilename)) {
    // "httpiimgurcomtHADwoQjpg.jpg".startsWith("httpiimgurcomtHADwoQjpg")
    // = TRUE ✓
    return true;
  }
}
```

### Why `startsWith()` is Required:

❌ **This won't work (exact match):**
```dart
final urlFilename = "httpiimgurcomtHADwoQjpg";  // NO extension
final backupFile = "httpiimgurcomtHADwoQjpg.jpg";  // WITH extension

backupFile == urlFilename  // FALSE
```

✓ **This works (prefix match):**
```dart
backupFile.startsWith(urlFilename)  // TRUE
```

---

## Summary Table

| Stage | Format | Example |
|-------|--------|---------|
| Original URL | Full URL | `http://i.imgur.com/tHADwoQ.jpg` |
| Download: fileName | Alphanumeric only, no extension | `httpiimgurcomtHADwoQjpg` |
| Download: finalPath | fileName + extension | `httpiimgurcomtHADwoQjpg.jpg` |
| On Disk | Full filename with extension | `httpiimgurcomtHADwoQjpg.jpg` |
| In Backup ZIP | Full path with extension | `Mods/Images/httpiimgurcomtHADwoQjpg.jpg` |
| BackupFileMetadata | Basename with extension | `httpiimgurcomtHADwoQjpg.jpg` |
| Check URL | Convert to alphanumeric (no ext) | `httpiimgurcomtHADwoQjpg` |
| Match Logic | Use `startsWith()` | `"httpiimgurcomtHADwoQjpg.jpg".startsWith("httpiimgurcomtHADwoQjpg")` |

---

## Critical Points

1. **Downloaded files ALWAYS have extensions** (`.jpg`, `.png`, `.obj`, etc.)
2. **Backup metadata stores filenames WITH extensions**
3. **URL conversion produces filename WITHOUT extension**
4. **Must use `startsWith()` not exact match** when checking if URL is backed up

---

## Code Pattern

### ✓ Correct:
```dart
final urlFilename = getFileNameFromURL(url);  // No extension
final backedUpFiles = backupMetadata.files.keys;  // With extensions

final isBackedUp = backedUpFiles.any((file) => file.startsWith(urlFilename));
```

### ✗ Incorrect:
```dart
final urlFilename = getFileNameFromURL(url);
final backedUpFiles = backupMetadata.files.keys;

final isBackedUp = backedUpFiles.contains(urlFilename);  // Won't match!
```

---

## Real Example from Your Log

```
Asset #2: filename="httpiimgurcomtHADwoQjpg", isBackedUp=false
Sample from backedUpFiles: httpiimgurcomjQeVtWEjpg.jpg, httpiimgurcomMINkosrjpg.jpg
```

The file `httpiimgurcomtHADwoQjpg.jpg` should exist in your `backedUpFiles` if it was backed up. If it's showing `isBackedUp=false`, then either:

1. The file `httpiimgurcomtHADwoQjpg.jpg` (or anything starting with `httpiimgurcomtHADwoQjpg`) is NOT in the backup
2. Your matching logic is using exact match instead of `startsWith()`
3. The file was downloaded but never backed up
