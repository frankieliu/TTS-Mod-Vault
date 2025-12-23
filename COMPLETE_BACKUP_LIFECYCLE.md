# Complete Backup Lifecycle: URL → Download → Backup → Restore

## Quick Reference

### Critical Facts
1. **Files on disk:** ALWAYS have extensions (`.jpg`, `.png`, `.unity3d`, etc.)
2. **Files in backup ZIP:** ALWAYS have extensions
3. **BackupFileMetadata keys:** ALWAYS have extensions
4. **App state tracking:** NEVER has extensions (uses basename without extension)
5. **URL conversion:** NEVER produces extensions

### The Matching Problem
- **URL converts to:** `httpiimgurcomtHADwoQjpg` (no extension)
- **Backup contains:** `httpiimgurcomtHADwoQjpg.jpg` (with extension)
- **Solution:** Use `startsWith()` not exact match

---

## Complete Lifecycle Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ STAGE 1: ORIGINAL URL                                       │
│ http://i.imgur.com/tHADwoQ.jpg                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 2: DOWNLOAD                                           │
│                                                             │
│ getFileNameFromURL(url)                                     │
│   → "httpiimgurcomtHADwoQjpg" (no extension)               │
│                                                             │
│ getExtensionByType() + MIME detection                       │
│   → ".jpg"                                                  │
│                                                             │
│ Final filename: "httpiimgurcomtHADwoQjpg.jpg"              │
│ Disk location: /Mods/Images/httpiimgurcomtHADwoQjpg.jpg    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 3: BACKUP CREATION                                    │
│                                                             │
│ Read file: /Mods/Images/httpiimgurcomtHADwoQjpg.jpg        │
│                                                             │
│ Get relative path: "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"│
│                                                             │
│ Add to ZIP with full path + extension                       │
│                                                             │
│ ZIP structure:                                              │
│   Mods/Images/httpiimgurcomtHADwoQjpg.jpg (WITH extension) │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 4: METADATA EXTRACTION                                │
│                                                             │
│ For each file in ZIP:                                       │
│   zipFile.name = "Mods/Images/httpiimgurcomtHADwoQjpg.jpg" │
│   basename = "httpiimgurcomtHADwoQjpg.jpg"                 │
│   size = 12345 bytes                                        │
│                                                             │
│ Store in BackupFileMetadata:                                │
│   {                                                         │
│     "httpiimgurcomtHADwoQjpg.jpg": 12345  (WITH extension) │
│   }                                                         │
│                                                             │
│ Save to Hive: BackupFiles box                               │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 5: IMPORT/RESTORE                                     │
│                                                             │
│ Read ZIP file                                               │
│                                                             │
│ For each file:                                              │
│   filename = "Mods/Images/httpiimgurcomtHADwoQjpg.jpg"     │
│   targetDir = "/path/to/Tabletop Simulator"                │
│   outputFile = targetDir + "/" + filename                   │
│   = "/path/to/Tabletop Simulator/Mods/Images/              │
│      httpiimgurcomtHADwoQjpg.jpg"                          │
│                                                             │
│ Extract: Write file to disk (WITH extension)                │
│   → /Mods/Images/httpiimgurcomtHADwoQjpg.jpg              │
│                                                             │
│ Track in app state (WITHOUT extension):                     │
│   assetFilename = basenameWithoutExtension(outputFile)      │
│   = "httpiimgurcomtHADwoQjpg"                              │
│                                                             │
│ Register:                                                   │
│   addExistingAsset(                                         │
│     AssetTypeEnum.image,                                    │
│     "httpiimgurcomtHADwoQjpg",  ← No extension             │
│     "/path/to/.../httpiimgurcomtHADwoQjpg.jpg"  ← Full path│
│   )                                                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ RESULT: File restored to original state                     │
│ /Mods/Images/httpiimgurcomtHADwoQjpg.jpg                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Format at Each Stage

| Stage | Key/Identifier | Value/Path | Has Extension? |
|-------|---------------|------------|----------------|
| URL | `http://i.imgur.com/tHADwoQ.jpg` | - | Yes (in URL) |
| URL → Filename | `httpiimgurcomtHADwoQjpg` | - | **NO** |
| Download | `httpiimgurcomtHADwoQjpg.jpg` | `/Mods/Images/httpiimgurcomtHADwoQjpg.jpg` | **YES** |
| Backup ZIP | `Mods/Images/httpiimgurcomtHADwoQjpg.jpg` | (binary data) | **YES** |
| BackupFileMetadata | `httpiimgurcomtHADwoQjpg.jpg` | `12345` (size) | **YES** |
| Import - Disk | `httpiimgurcomtHADwoQjpg.jpg` | `/Mods/Images/httpiimgurcomtHADwoQjpg.jpg` | **YES** |
| Import - Tracking | `httpiimgurcomtHADwoQjpg` | `/Mods/Images/httpiimgurcomtHADwoQjpg.jpg` | **NO** |

---

## Matching URLs to Backup Files

### The Challenge

You have:
- **Asset URL:** `http://i.imgur.com/tHADwoQ.jpg`
- **BackupFileMetadata:** `{"httpiimgurcomtHADwoQjpg.jpg": 12345, ...}`

You need to determine: **Is this URL backed up?**

### The Solution

```dart
// Step 1: Convert URL to filename (no extension)
final urlFilename = getFileNameFromURL(url);
// Result: "httpiimgurcomtHADwoQjpg"

// Step 2: Check if ANY backup file STARTS WITH this filename
final backupFiles = backupMetadata.files.keys;
// backupFiles = ["httpiimgurcomtHADwoQjpg.jpg", "httpiimgurcom8bVZDmujpg.jpg", ...]

final isBackedUp = backupFiles.any((file) => file.startsWith(urlFilename));
// Check: "httpiimgurcomtHADwoQjpg.jpg".startsWith("httpiimgurcomtHADwoQjpg")
// Result: true ✓
```

### Why `startsWith()` is Required

```dart
// ❌ WRONG: Exact match
final urlFilename = "httpiimgurcomtHADwoQjpg";  // No extension
final backupFile = "httpiimgurcomtHADwoQjpg.jpg";  // With extension

backupFile == urlFilename  // false (won't match!)

// ✓ CORRECT: Prefix match
backupFile.startsWith(urlFilename)  // true (matches!)
```

---

## Code Examples

### Example 1: Check if URL is backed up

```dart
import 'package:tts_mod_vault/src/state/backup/url_backup_checker.dart';
import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL;

// Given
final url = "http://i.imgur.com/tHADwoQ.jpg";
final backupMetadata = storage.getBackupFileMetadata("MyMod.ttsmod");

// Method 1: Using UrlBackupChecker utility
final backedUpFiles = backupMetadata.files.keys.toSet();
final isBackedUp = UrlBackupChecker.isUrlBackedUp(url, backedUpFiles);

// Method 2: Manual check
final urlFilename = getFileNameFromURL(url);  // "httpiimgurcomtHADwoQjpg"
final isBackedUp2 = backupMetadata.files.keys.any(
  (file) => file.startsWith(urlFilename)
);

print('Is URL backed up? $isBackedUp');
```

### Example 2: Debug why URL isn't matching

```dart
final url = "http://i.imgur.com/tHADwoQ.jpg";
final backedUpFiles = backupMetadata.files.keys.toSet();

// Use debug helper to see what's happening
UrlBackupChecker.debugUrlMatching(url, backedUpFiles);

// This will print:
// - Original URL
// - Converted filename
// - Whether any backup files match
// - Sample backup files
// - Partial matches (if any)
```

### Example 3: Batch check multiple URLs

```dart
final mod = modsProvider.getMod(modId);
final urls = mod.getAllAssets().map((a) => a.url).toList();

// Get backup metadata
final backupMetadata = storage.getBackupFileMetadata("MyMod.ttsmod");
final backedUpFiles = backupMetadata.files.keys.toSet();

// Check all URLs at once
final statusMap = UrlBackupChecker.checkUrlsBatch(urls, backedUpFiles);

// Results
for (final entry in statusMap.entries) {
  final url = entry.key;
  final isBackedUp = entry.value;

  print('${url}: ${isBackedUp ? "✓ Backed up" : "✗ Not backed up"}');
}
```

---

## Common Issues and Solutions

### Issue 1: "All URLs showing as not backed up"

**Possible causes:**
1. Using exact match instead of `startsWith()`
2. Comparing wrong data (comparing with extensions on both sides)
3. Files were downloaded but never backed up

**Solution:**
```dart
// ✓ Correct
final isBackedUp = backupFiles.any((file) => file.startsWith(urlFilename));

// ❌ Wrong
final isBackedUp = backupFiles.contains(urlFilename);
```

### Issue 2: "Backup metadata is empty"

**Possible causes:**
1. Backup hasn't been scanned yet
2. Backup file is corrupted
3. Backup is an old format without metadata

**Solution:**
```dart
// Check if metadata exists
final metadata = storage.getBackupFileMetadata("MyMod.ttsmod");
if (metadata == null) {
  print('No metadata found - need to scan backup');
  // Trigger metadata extraction
  await existingBackupsProvider.notifier.loadExistingBackups();
}
```

### Issue 3: "URL filename doesn't match backup filename"

**Possible causes:**
1. File was downloaded with different URL
2. URL changed between download and backup
3. Old vs new Steam CDN URL format

**Example:**
```
Old URL: http://cloud-3.steamusercontent.com/ugc/123/image.jpg
New URL: https://steamusercontent-a.akamaihd.net/ugc/123/image.jpg

Old filename: httpcloud3steamusercontentcomugc123imagejpg
New filename: httpssteamusercontentaakamaihd789imagejpg
```

**Solution:** The backup code handles this with URL mapping:
```dart
final newUrlBase = p.basenameWithoutExtension(asset.filePath);
final oldUrlBase = newUrlBase.replaceFirst(
  getFileNameFromURL(newSteamUserContentUrl),
  getFileNameFromURL(oldCloudUrl),
);

// Check both formats
final match = files.firstWhereOrNull((file) {
  final base = p.basenameWithoutExtension(file.path);
  return base.startsWith(newUrlBase) || base.startsWith(oldUrlBase);
});
```

---

## Key Takeaways

1. **Extensions are ONLY removed for tracking**, not for storage
2. **Files always have extensions on disk and in backups**
3. **BackupFileMetadata stores filenames WITH extensions**
4. **URL conversion produces filenames WITHOUT extensions**
5. **Must use `startsWith()` to match URL to backup file**
6. **Import process extracts WITH extensions, tracks WITHOUT**

---

## References

- **Download Process:** `lib/src/state/download/download.dart`
- **Backup Process:** `lib/src/state/backup/backup.dart`
- **Metadata Extraction:** `lib/src/state/backup/existing_backups.dart`
- **Import Process:** `lib/src/state/backup/import_backup.dart`
- **URL Conversion:** `lib/src/utils.dart` (getFileNameFromURL)
- **Matching Utility:** `lib/src/state/backup/url_backup_checker.dart`

---

## Next Steps

To implement URL backup status checking in your app:

1. **Load backup metadata** when app starts
2. **For each mod**, query which URLs are backed up
3. **Update Asset models** with `isBackedUp` flag
4. **Display indicators** in UI showing backup status
5. **Update on backup** creation/deletion

See `URL_BACKUP_MATCHING.md` and `URL_BACKUP_CHECKER_USAGE.md` for implementation details.
