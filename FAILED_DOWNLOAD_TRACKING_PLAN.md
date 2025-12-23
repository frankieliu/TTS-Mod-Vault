# Failed Download Tracking - Implementation Plan

## User Requirements

1. **Persistence:** ✅ Persist in Hive - Store in database, remember across restarts
2. **Retry Behavior:** ✅ Skip permanently - Don't retry failed URLs automatically, allow manual retry
3. **UI Feedback:** ✅ Show failed count - Display in UI with ability to view/retry
4. **Error Classification:** ✅ Classify errors - Distinguish permanent (404, 403) from temporary (timeout, network)

---

## Implementation Approach

Full-featured solution with persistent storage, error classification, UI feedback, and retry functionality.

---

## Key Components

### 1. New Data Models
- **DownloadErrorTypeEnum** - Classify errors (permanent, temporary, unknown)
- **FailedAsset** - Model with url, type, errorType, errorMessage, timestamp, retryCount
- **Asset** (extended) - Add `hasFailed` and `errorType` fields
- **Mod** (extended) - Add `failedAssetCount` field

### 2. Storage Layer
- New Hive box: `failedAssetsBox` (Box<String>)
- Methods: saveFailedAsset(), getFailedAsset(), getAllFailedAssets(), clearFailedAssets()
- JSON serialization for FailedAsset objects

### 3. State Management
- **FailedAssetsState** - Map<String, FailedAsset> for O(1) lookups
- **FailedAssetsNotifier** - Manages failed asset state and persistence
- Helper methods: getFailedCountByType(), getPermanentFailedCount(), etc.

### 4. Download Logic
- **DownloadErrorClassifier** - Classify errors based on HTTP status and DioException type
  - Permanent: 404, 403, 410, 4xx errors
  - Temporary: 5xx errors, timeouts, connection errors
- Filter permanently failed assets before download
- Capture and store failures with classification
- Retry functionality: retryFailedDownloads()

### 5. UI Components
- **FailedDownloadsDialog** - Full-screen dialog showing all failures
  - List view with error details, timestamps, retry counts
  - Actions: Retry All, Clear All, individual retry/delete
  - Visual indicators (red for permanent, orange for temporary)
- **Failed count badge** - On selected mod view
- **Asset count display** - Show failed count in grid/list cards
- **Visual indicators** - Icons on failed assets in asset lists

---

## Implementation Sequence

### Phase 1: Foundation (Data & Storage)
1. Create `lib/src/state/enums/download_error_type_enum.dart`
2. Create `lib/src/state/asset/models/failed_asset_model.dart`
3. Modify `lib/src/state/asset/models/asset_model.dart` (add hasFailed, errorType)
4. Modify `lib/src/state/mods/mod_model.dart` (add failedAssetCount)
5. Modify `lib/src/state/storage/storage.dart` (add failedAssetsBox and methods)

### Phase 2: State Management
6. Create `lib/src/state/asset/failed_assets_state.dart`
7. Create `lib/src/state/asset/failed_assets.dart`
8. Modify `lib/src/state/provider.dart` (add failedAssetsProvider)

### Phase 3: Download Logic
9. Create `lib/src/utils/download_error_classifier.dart`
10. Modify `lib/src/state/download/download.dart`:
    - Filter failed assets in downloadFiles()
    - Capture and store errors
    - Add retryFailedDownloads() method

### Phase 4: Integration
11. Modify `lib/src/state/mods/mods.dart`:
    - Load failed assets on startup
    - Update asset creation to include failure status
    - Calculate failedAssetCount

### Phase 5: UI
12. Create `lib/src/mods/components/failed_downloads_dialog.dart`
13. Modify `lib/src/mods/components/selected_mod_view.dart` (add badge)
14. Modify `lib/src/mods/components/mods_grid_card.dart` (show failed count)
15. Modify `lib/src/mods/components/mods_list_item.dart` (show failed count)

---

## Critical Files

### New Files (6)
- `lib/src/state/enums/download_error_type_enum.dart`
- `lib/src/state/asset/models/failed_asset_model.dart`
- `lib/src/state/asset/failed_assets_state.dart`
- `lib/src/state/asset/failed_assets.dart`
- `lib/src/utils/download_error_classifier.dart`
- `lib/src/mods/components/failed_downloads_dialog.dart`

### Modified Files (8)
- `lib/src/state/asset/models/asset_model.dart`
- `lib/src/state/mods/mod_model.dart`
- `lib/src/state/storage/storage.dart`
- `lib/src/state/provider.dart`
- `lib/src/state/download/download.dart`
- `lib/src/state/mods/mods.dart`
- `lib/src/mods/components/selected_mod_view.dart`
- `lib/src/mods/components/mods_grid_card.dart` (or mods_list_item.dart)

---

## Error Classification Logic

### Permanent Errors (Skip on future downloads)
- HTTP 403 (Forbidden)
- HTTP 404 (Not Found)
- HTTP 410 (Gone)
- HTTP 4xx (Other client errors)

### Temporary Errors (Can be retried)
- HTTP 5xx (Server errors)
- Connection timeout
- Send/receive timeout
- Connection errors

### Not Stored
- Cancellations (user-initiated)
- Unknown errors (unclassified)

---

## Behavior Summary

### 1. On Download Failure
- Classify error type using HTTP status codes and exception types
- Store in Hive (if not unknown/cancelled)
- Update in-memory state
- Continue with next asset

### 2. Before Download
- Check if file exists (skip)
- Check if permanently failed (skip)
- Proceed with download

### 3. On App Restart
- Load failed assets from Hive
- Mark assets as failed in UI
- Automatically skip on download attempts

### 4. Manual Retry
- Remove from failed list
- Attempt download again
- If fails, re-add with incremented retry count

### 5. UI Display
- Show failed count on mods (e.g., "5 downloaded, 2 failed, 3 missing")
- Badge with failed count on selected mod view
- Full dialog with retry/clear options
- Visual indicators (red for permanent, orange for temporary)

---

## Data Model Details

### DownloadErrorTypeEnum
```dart
enum DownloadErrorTypeEnum {
  permanent('Permanent Error'),
  temporary('Temporary Error'),
  unknown('Unknown Error');

  final String label;
  const DownloadErrorTypeEnum(this.label);
}
```

### FailedAsset
```dart
class FailedAsset {
  final String url;
  final AssetTypeEnum type;
  final DownloadErrorTypeEnum errorType;
  final String errorMessage;
  final DateTime failedAt;
  final int retryCount;

  // toJson() / fromJson() for Hive serialization
}
```

### Asset (Extended)
```dart
class Asset {
  final String url;
  final bool fileExists;
  final String? filePath;
  final bool hasFailed;  // NEW
  final DownloadErrorTypeEnum? errorType;  // NEW
}
```

### Mod (Extended)
```dart
class Mod {
  // ... existing fields
  final int? failedAssetCount;  // NEW
}
```

---

## Storage Structure

### Hive Box: failedAssetsBox
- **Key:** URL (String)
- **Value:** JSON-serialized FailedAsset object (String)

**Example:**
```dart
{
  "https://example.com/asset.jpg": {
    "url": "https://example.com/asset.jpg",
    "type": "image",
    "errorType": "permanent",
    "errorMessage": "HTTP 404: Not Found",
    "failedAt": 1703345678000,
    "retryCount": 0
  }
}
```

---

## UI Components

### Failed Downloads Dialog
**Features:**
- List view with all failed downloads sorted by most recent
- Shows: URL, asset type, error type, error message, timestamp, retry count
- Visual indicators: Red icon for permanent, orange for temporary
- Actions:
  - "Retry All" button - Attempts all failed downloads
  - "Clear All" button - Removes all failure records (with confirmation)
  - Individual retry button per asset
  - Individual delete button per asset

### Failed Count Badge
**Location:** Selected mod view header

**Display:**
- Red badge with count of failed assets
- Only shown if failedAssetCount > 0
- Opens Failed Downloads Dialog on click

### Asset Count Display
**Location:** Mod grid cards and list items

**Format:**
```
"5/10 (2 failed)"
```

**Color Coding:**
- Orange: Has failed downloads
- Green: All downloaded
- Red: Has missing downloads

### Asset List Visual Indicators
**Location:** Individual asset items in selected mod view

**Display:**
- Red error icon: Permanently failed
- Orange warning icon: Temporarily failed
- Shows error type on hover

---

## Testing Scenarios

### Manual Testing Checklist
1. ✓ Trigger 404 error - verify stored as permanent
2. ✓ Trigger timeout - verify stored as temporary
3. ✓ Restart app - verify failures persist
4. ✓ Retry permanent failure - verify it attempts download
5. ✓ Retry temporary failure - verify it attempts download
6. ✓ Successful retry - verify removed from failed list
7. ✓ Failed retry - verify count increments
8. ✓ Clear all failed - verify UI updates and storage cleared
9. ✓ Download new assets - verify skips permanent failures
10. ✓ Failed asset count - verify matches UI display
11. ✓ HTML error page - verify not stored as failure
12. ✓ Cancellation - verify not stored as failure

### Edge Cases
- Hive box fails to open - graceful degradation
- JSON deserialization fails - skip invalid entries
- URL removed from mod JSON but still in failed list - orphaned entries handled
- Same URL fails with different error types on retry - latest error type wins

---

## Performance Considerations

### Memory Usage
- Failed assets stored as Map<String, FailedAsset> for O(1) lookups
- Typical usage: ~100-1000 failed assets = ~50-500 KB memory
- Acceptable overhead for improved UX

### Disk I/O
- Hive writes are asynchronous
- Batch operations use putAll() for efficiency
- Minimal impact on download performance

### UI Performance
- Failed assets loaded once on startup
- O(1) lookup for existence checks
- Dialog lazy-loads (only created when opened)

---

## Future Enhancements (Out of Scope)

- Automatic retry with exponential backoff for temporary errors
- Maximum retry limit configuration (e.g., stop after 3 attempts)
- Export failed downloads as CSV/JSON report
- Bulk URL replacement for migrated content
- Analytics dashboard on most common failure reasons
- Push notifications for new failures
- Filter/sort failed downloads by date, type, error type
- Scheduled retry (e.g., retry temporary failures daily)
- Integration with mod author notifications
