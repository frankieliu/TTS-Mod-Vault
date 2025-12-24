# SelectedModView Component Structure

## Overview

The list of assets on the right side of the application.

## Component Name: SelectedModView

**File:** `lib/src/mods/components/selected_mod_view.dart`

## Structure

### 1. Main Widget: SelectedModView
The entire right panel
- This is a **HookConsumerWidget** (not a dialog)
- It's a permanent panel that takes up 1/3 of the screen width (see `Expanded(flex: 1)` in mods_page.dart)

### 2. Asset List: ListView.builder
**Location:** Line 288 in selected_mod_view.dart
- This is the scrollable list that displays all assets
- Each asset is rendered as an individual item

### 3. Individual Asset: AssetsUrl
**Location:** Line 330 in selected_mod_view.dart
- This is the widget that displays each asset URL with its color indicator
- **File:** `lib/src/mods/components/assets_url.dart`

## Layout Hierarchy

```
SelectedModView (Column)
├── Header (mod name)
├── Filter buttons (All/Missing/Downloaded + Asset type chips)
├── ListView.builder
│   ├── _HeaderItem (Asset type headers: "Images", "Models", etc.)
│   └── AssetsUrl (Individual assets - the colored items you see)
└── Action Buttons / Progress bars
```

## Important Notes

- It's called a **"view"** or **"panel"** - not a dialog
- It's a fixed part of the page layout that shows the details of the selected mod
- Includes all assets with color-coded status indicators:
  - **Green** - Downloaded assets
  - **Red** - Permanently failed downloads
  - **Orange** - Retryable failed downloads
  - **White** - Not downloaded (missing)
  - **Blue border** - Backed up assets

## Related Components

### AssetsUrl Component
Shows individual asset URLs with status colors and icons.

**Behavior:**
- **Left-click:** Opens asset detail dialog with metadata
- **Right-click:** Shows context menu with actions (Open, Download, Copy, etc.)

**Status Icons:**
- ✓ Check circle (green) - Downloaded
- ⚠ Warning (orange) - Retryable failure
- ✗ Error (red) - Permanent failure
- ○ Circle outline (white) - Not downloaded
