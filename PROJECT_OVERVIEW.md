# TTS Mod Vault - Project Overview

## 1. Project Description

**TTS Mod Vault** is a cross-platform desktop application built with Flutter for managing Tabletop Simulator (TTS) mod backups, saves, and saved objects. It provides a comprehensive toolkit for downloading, backing up, organizing, and managing TTS mod assets across Windows, Linux, and macOS.

### Key Features
- Download and backup mod assets to local cache
- Support for automatic URL format migration (legacy SteamURL to new formats)
- Bulk operations (download all, backup all, download & backup all)
- Advanced filtering and sorting capabilities
- Asset management with cleanup of unused cached files
- Image viewer for downloaded mod images
- URL replacement and bulk URL updates
- Import/export .ttsmod backup files
- Workshop mod downloading by ID
- Multi-select capabilities with sidebar navigation
- Separate configuration for Mods and Saves directories

**Current Version:** 1.3.0

**Repository Status:** Active development (latest commit adds sidebar and import json dialog)

---

## 2. Technology Stack and Frameworks

### Core Framework
- **Flutter 3.29.3** - Cross-platform UI framework using Dart
- **Dart 3.5.4+**

### Key Dependencies

**State Management:**
- `hooks_riverpod: ^2.6.1` - Reactive provider-based state management
- `flutter_hooks: ^0.21.2` - React-style hooks for Flutter

**HTTP & Networking:**
- `dio: ^5.7.0` - HTTP client with cancelable requests and progress tracking
- `http: ^1.2.2` - Alternative HTTP client
- `url_launcher: ^6.3.1` - Open URLs and launch external links

**Storage & Persistence:**
- `hive_ce: ^2.11.3` - Local NoSQL database (CE = community edition)
- `hive_ce_flutter: ^2.3.1` - Flutter integration for Hive
- `hive_ce_generator: ^1.9.2` - Code generation for Hive models
- `path_provider: ^2.1.5` - Platform-specific paths

**File Operations:**
- `file_picker: ^10.1.9` - Native file picker dialogs
- `flutter_archive: ^6.0.3` - Archive handling
- `archive: ^4.0.5` - Archive creation and extraction
- `open_filex: ^4.7.0` - Open various file types

**Data Processing:**
- `image: ^4.5.4` - Image processing and manipulation
- `bson: ^5.0.7` - BSON encoding/decoding
- `fixnum: ^1.1.1` - Fixed-size numbers for BSON
- `collection: ^1.19.0` - Utility collections and extensions
- `intl: ^0.20.2` - Internationalization support
- `mime: ^2.0.0` - MIME type detection

**Desktop Integration:**
- `window_manager: ^0.5.1` - Window management for desktop
- `package_info_plus: ^9.0.0` - App version info

**Development Tools:**
- `flutter_lints: ^6.0.0` - Linting configuration
- `build_runner: ^2.5.3` - Code generation runner
- `flutter_launcher_icons: ^0.14.3` - Icon generation

---

## 3. Directory Structure and Organization

```
TTS-Mod-Vault/
├── lib/
│   ├── main.dart                          # App entry point, window initialization
│   └── src/
│       ├── app.dart                       # Material app configuration with routing
│       ├── changelog.dart                 # Version changelog display
│       ├── utils.dart                     # Utility functions, theme, URL helpers
│       ├── localization/                  # i18n support (English)
│       ├── splash/                        # Splash/initialization screens
│       │   ├── splash_page.dart
│       │   └── components/select_directories_widget.dart
│       ├── settings/                      # User settings dialog
│       │   └── settings_dialog.dart
│       ├── mods/                          # Main UI page and components
│       │   ├── mods_page.dart             # Main page layout
│       │   ├── images_viewer_page.dart    # Image gallery view
│       │   ├── components/                # Reusable UI components
│       │   │   ├── mods_selector.dart
│       │   │   ├── mods_list.dart
│       │   │   ├── mods_grid.dart
│       │   │   ├── selected_mod_view.dart
│       │   │   ├── sidebar.dart
│       │   │   ├── toolbar.dart
│       │   │   ├── search.dart
│       │   │   ├── sort_button.dart
│       │   │   ├── filter_button.dart
│       │   │   ├── bulk_actions_menu.dart
│       │   │   ├── download_progress_bar.dart
│       │   │   ├── backup_progress_bar.dart
│       │   │   ├── bulk_actions_progress_bar.dart
│       │   │   ├── replace_url_dialog.dart
│       │   │   ├── update_urls_dialog.dart
│       │   │   ├── bulk_update_urls_dialog.dart
│       │   │   ├── import_backup_overlay.dart
│       │   │   ├── import_json_dialog.dart
│       │   │   ├── download_mod_by_id_dialog.dart
│       │   │   ├── error_message.dart
│       │   │   ├── custom_tooltip.dart
│       │   │   ├── debug_console.dart
│       │   │   ├── components.dart
│       │   │   └── [+22 more component files]
│       │   ├── enums/
│       │   │   └── context_menu_action_enum.dart
│       │   └── hooks/                     # Custom React-like hooks
│       │       ├── use_backup_snackbar.dart
│       │       └── use_cleanup_snackbar.dart
│       └── state/                         # Business logic & state management
│           ├── provider.dart              # Central provider definitions
│           ├── enums/
│           │   └── asset_type_enum.dart
│           ├── mods/                      # Mod data management
│           │   ├── mod_model.dart         # Mod data class
│           │   ├── mods.dart              # AsyncNotifier for mod loading
│           │   ├── mods_state.dart        # Mods state model
│           │   └── mods_isolates.dart     # Heavy computation in isolates
│           ├── asset/                     # Asset tracking
│           │   ├── existing_assets.dart
│           │   ├── existing_assets_state.dart
│           │   └── models/
│           │       ├── asset_model.dart
│           │       └── asset_lists_model.dart
│           ├── backup/                    # Backup functionality
│           │   ├── backup.dart
│           │   ├── backup_state.dart
│           │   ├── backup_status_enum.dart
│           │   ├── existing_backups.dart
│           │   ├── existing_backups_state.dart
│           │   ├── import_backup.dart
│           │   ├── import_backup_state.dart
│           │   └── models/existing_backup_model.dart
│           ├── download/                  # Download management
│           │   ├── download.dart
│           │   └── download_state.dart
│           ├── cleanup/                   # Unused asset cleanup
│           │   ├── cleanup.dart
│           │   └── cleanup_state.dart
│           ├── bulk_actions/              # Batch operations
│           │   ├── bulk_actions.dart
│           │   └── bulk_actions_state.dart
│           ├── storage/                   # Persistence layer
│           │   └── storage.dart
│           ├── directories/               # Path management
│           │   ├── directories.dart
│           │   └── directories_state.dart
│           ├── settings/                  # User preferences
│           │   ├── settings.dart
│           │   └── settings_state.dart
│           ├── sort_and_filter/          # List filtering/sorting
│           │   ├── sort_and_filter.dart
│           │   └── sort_and_filter_state.dart
│           └── loader/                    # Data loading utility
│               └── loader.dart
├── assets/
│   └── icon/                             # Application icons
├── linux/                                # Linux desktop platform
├── macos/                                # macOS desktop platform
├── windows/                              # Windows desktop platform
├── pubspec.yaml                          # Flutter project manifest
├── pubspec.lock                          # Locked dependency versions
├── analysis_options.yaml                 # Dart linting rules
├── l10n.yaml                             # Localization configuration
├── devtools_options.yaml                 # DevTools config
├── README.md
└── LICENSE
```

**Code Statistics:**
- 82 Dart files total
- ~12,300 lines of Dart code
- Largest files: mods.dart (866 lines), mods_isolates.dart (647 lines), utils.dart (606 lines)

---

## 4. Key Components and Their Purposes

### State Management Layer (Hooks Riverpod)

The app uses a provider-based reactive architecture with clear separation of concerns:

#### Core State Providers
- `selectedModProvider` - Currently selected mod for detail view
- `multiSelectModsProvider` - Set of selected mods for bulk operations
- `searchQueryProvider` - Current search text filter
- `selectedModTypeProvider` - Filter between mods/saves/saved objects
- `loadingMessageProvider` - Status messages during operations

#### Domain-Specific Providers
- `directoriesProvider` - Manages paths for mods, saves, backups
- `modsProvider` - Async provider for loading/processing all mods (uses isolates)
- `existingAssetListsProvider` - Tracks downloaded/cached assets
- `existingBackupsProvider` - Backup file inventory
- `downloadProvider` - Download state and progress
- `backupProvider` - Backup operation state and progress
- `importBackupProvider` - Import backup operation state
- `cleanupProvider` - Cleanup scan and deletion state
- `bulkActionsProvider` - Multi-item operation state
- `sortAndFilterProvider` - Current sort/filter settings
- `settingsProvider` - User preferences (persistent)

#### Computed Providers
- `filteredModsProvider` - Applies search, sort, and filter logic
- `actionInProgressProvider` - Boolean indicating any operation is running

### Data Models

**Mod Model** (`mod_model.dart`):
```dart
class Mod {
  modType: ModTypeEnum (mod/save/savedObject)
  jsonFilePath: String
  saveName: String
  parentFolderName: String
  backupStatus: ExistingBackupStatusEnum
  backup: ExistingBackup?
  assetLists: AssetLists?  // Images, audio, models, PDFs, bundles
  assetCount, existingAssetCount, missingAssetCount
}
```

**Asset Model** (`asset_model.dart`):
```dart
class Asset {
  url: String
  fileExists: bool
  filePath: String?
}
```

**ExistingBackup Model** (`existing_backup_model.dart`):
```dart
class ExistingBackup {
  filename, filepath, lastModifiedTimestamp, totalAssetCount
}
```

### Business Logic Layers

#### Isolate-Heavy Processing (`mods_isolates.dart`)
- `processInitialModsInIsolate()` - Loads all mod JSON files in parallel batches
- `processMultipleBatchesInIsolate()` - Processes mods in background isolates (UI non-blocking)
- `updateUrlPrefixesFilesIsolate()` - Bulk URL replacement in isolates
- `extractUrlsFromJson()` - Parse asset URLs from JSON
- Handles URL normalization (legacy steam URLs to new format)

#### Core Notifiers

**ModsStateNotifier** (866 lines) - Main mod loading orchestration
- Loads JSON files from directories
- Parses asset lists
- Caches datetime stamps and URLs
- Manages asset existence checking
- Handles bulk updates

**DownloadNotifier** (321 lines) - Download management
- Uses Dio HTTP client with cancellation support
- Tracks progress per asset type
- Manages cancel tokens for individual downloads
- Creates cache structure matching TTS's format

**BackupNotifier** - Backup creation using isolates and ZIP compression
- Creates .ttsmod archive files
- Tracks backup progress
- Shows backup state (up-to-date, out-of-date, missing)

**CleanupNotifier** (216 lines) - Unused cache file deletion
- Scans asset directories
- Identifies files not referenced by any mod
- Parallel processing per asset type

**SortAndFilterNotifier** (187 lines) - List filtering and sorting
- Sort options: alphabetical, date created, missing assets count
- Folder filtering per mod type
- Backup status filtering
- Asset completeness filtering

**Settings/Directories/Storage** - Configuration and persistence
- Hive-based local storage (3 boxes: URLs, metadata, app data)
- Settings serialization/deserialization
- Directory path management

### UI Layer (Flutter Widgets)

#### Main Pages
- `ModsPage` - Main layout with sidebar, mod list, and detail view
- `ImagesViewerPage` - Gallery view of downloaded mod images

#### Component Structure
- **ModsSelector** - Tab/button group for mod/save/saved object type
- **ModsView** - Central list/grid display with selection
- **SelectedModView** - Detail panel showing selected mod assets
- **Sidebar** - Navigation sidebar with collapsible width
- **Toolbar** - Action buttons (download, backup, settings)
- **Search** - Text input with live filtering
- **SortButton/FilterButton** - Dropdown menus for sorting and filtering
- **BulkActionsMenu** - Multi-select operations
- **ProgressBars** - Download, backup, and bulk action progress
- **Dialogs** - Replace URL, update URLs, import backup, download by ID

#### Custom Hooks
- `useCleanupSnackbar()` - Listens to cleanup state and shows notifications
- `useBackupSnackbar()` - Listens to backup state and shows notifications

---

## 5. Architecture Patterns and Decisions

### Key Architectural Decisions

#### 1. Isolate-Based Heavy Lifting
- All heavy computation (JSON parsing, URL extraction, file scanning) runs in background isolates
- Prevents UI blocking during long operations
- `compute()` and explicit `Isolate.run()` used throughout
- Batch processing for mod loading in separate isolates

#### 2. Provider-Based Reactive Architecture
- Single source of truth per domain (mod data, downloads, backups, etc.)
- Computed providers for derived state (filtered mods)
- Async providers for async operations with proper loading/error states
- State notifiers for mutable state with clear update patterns

#### 3. Hive-Based Persistence
- Three separate boxes: URLs (dynamic), metadata (strings), app data (strings)
- Simple key-value storage for settings, paths, and mod metadata
- Efficient lookups during asset checking

#### 4. Multi-Type Support with Enums
- ModTypeEnum: mod, save, savedObject
- AssetTypeEnum: assetBundle, audio, image, model, pdf
- BackupStatusEnum: idle, upToDate, outOfDate, missing
- SortOptionEnum: alphabetical, dateCreated, missingAssets
- FilterAssetCountEnum: complete, missing

#### 5. URL Normalization
- Handles legacy Steam URLs (http://cloud-3.steamusercontent.com/)
- Maps to modern format (https://steamusercontent-a.akamaihd.net/)
- Supports custom URL replacement and bulk prefix updates

#### 6. Progress Tracking with State Machines
- Status enums track operation phases (idle, in-progress, complete)
- Progress counters (current/total) for multi-item operations
- Message field for user feedback

#### 7. Component Composition
- Reusable components for common patterns
- Hooks for side effects (snackbar notifications)
- Context menus for mod-level actions
- Overlay system for import operations

### Recent Development Additions

From git history (latest commits):
- Added sidebar with dynamic width management
- Import JSON dialog for direct JSON import
- Multi-select implementation for bulk operations
- Filter by asset completeness (missing/complete)
- Sort by missing asset count
- Asset preload optimizations
- URL regex handling improvements

---

## 6. Technical Highlights

### Performance Optimizations
- Isolate-based processing prevents UI freezing
- Batch processing of mods to manage memory
- Asset existence maps (O(1) lookups) instead of linear searches
- Regex-based URL extraction from JSON
- Parallel asset type processing during cleanup

### Cross-Platform Support
- Flutter provides iOS/Android/web readiness (though app focuses on desktop)
- Platform-specific platform channels for window management
- Window manager integration for desktop window sizing and positioning

### Data Flow
```
JSON Files on Disk
  ↓
[Isolates] Parse JSON → Extract URLs → Check Asset Existence
  ↓
Mod Models with Asset Lists
  ↓
Storage (Hive) caches URLs and metadata
  ↓
Providers manage reactive state
  ↓
UI Widgets display filtered/sorted data
  ↓
User Actions trigger notifiers → Update state → Re-render UI
```

---

## Summary

TTS Mod Vault is a well-architected Flutter application demonstrating:
- Modern state management with Hooks Riverpod
- Efficient multi-threaded computation using Dart isolates
- Responsive UI through reactive programming
- Persistent local storage with Hive
- Clean separation between UI, business logic, and data layers
- Cross-platform desktop development best practices

The codebase is actively maintained with recent additions focusing on UI improvements (sidebar, multi-select) and asset management features (import dialogs, completeness filtering).
