# Mods View Component Structure

## Overview

The middle view that displays the mod/save game images in a grid or list format.

## Component Name: ModsView

**File:** `lib/src/mods/components/mods_view.dart`

## Layout in ModsPage

```
ModsPage (Row)
├── Sidebar (left edge)
├── ModsColumn (middle, flex: 2) ← THIS IS THE MIDDLE VIEW
│   ├── Header Row (top controls)
│   │   ├── ModsSelector
│   │   ├── Search
│   │   ├── BulkActionsMenu
│   │   ├── SortButton
│   │   ├── FilterButton
│   │   └── Info Icon
│   ├── ModsView (scrollable content)
│   │   ├── ModsGrid (grid view - default)
│   │   │   └── GridView.builder
│   │   │       └── ModsGridCard (individual mod cards)
│   │   └── ModsList (list view - alternative)
│   │       └── ListView.builder
│   │           └── ModsListCard (individual mod items)
│   └── BulkActionsProgressBar (bottom)
└── SelectedModView (right panel, flex: 1)
```

## Component Hierarchy

### ModsColumn
**File:** `lib/src/mods/mods_page.dart` (line 79)
- **Type:** StatelessWidget
- **Purpose:** Container for the entire middle column
- **Layout:** Column with header, scrollable content, and footer

### ModsView
**File:** `lib/src/mods/components/mods_view.dart`
- **Type:** ConsumerWidget
- **Purpose:** Switches between grid and list view based on settings
- **Data Source:** `filteredModsProvider` (filtered/sorted mods)
- **Conditional Rendering:**
  - If `useModsListView` = true → Shows **ModsList**
  - If `useModsListView` = false → Shows **ModsGrid** (default)

### ModsGrid
**File:** `lib/src/mods/components/mods_grid.dart`
- **Type:** ConsumerWidget
- **Purpose:** Displays mods in a responsive grid layout
- **Widget Type:** GridView.builder
- **Grid Configuration:**
  - Dynamic columns based on screen width
  - Formula: `constraints.maxWidth ~/ 220` (minimum 1 column)
  - Spacing: 20px horizontal and vertical
- **Children:** Multiple **ModsGridCard** widgets

### ModsGridCard
**File:** `lib/src/mods/components/mods_grid_card.dart`
- **Type:** HookConsumerWidget
- **Purpose:** Individual card showing a single mod/save with image
- **Visual Elements:**
  - **Background:** Mod image (if exists) or grey placeholder with text
  - **Border:** White (selected), Cyan (multi-selected), or transparent
  - **Title Overlay:** Bottom blur overlay with mod name (optional)
  - **Asset Count Badge:** Top-right corner showing file counts
    - Format: `downloaded/total (failed)`
    - Green = all downloaded
    - Orange = has failures
    - White = partial
  - **Backup Status Icon:** Zip icon with color coding
    - Green = backup up to date
    - Yellow = backup up to date but asset count mismatch
    - Red = backup out of date

### ModsList (Alternative View)
**File:** `lib/src/mods/components/mods_list.dart` (not read, but exists)
- Alternative to ModsGrid
- Shows mods in a vertical list instead of grid
- Contains ModsListCard components

## Interaction Behavior

### ModsGridCard Interactions
1. **Left-Click:** Select mod (shows details in right panel)
2. **Ctrl+Left-Click:** Toggle multi-selection (border turns cyan)
3. **Right-Click:** Show context menu with mod actions
4. **Hover:** White border appears (70% opacity)

### Selection States
- **Not Selected:** Transparent border
- **Hovered:** White border (70% opacity)
- **Single Selected:** White border (100% opacity)
- **Multi-Selected:** Cyan border

## Data Flow

```
modsProvider
    ↓
filteredModsProvider (filtered/sorted)
    ↓
ModsView (decides grid vs list)
    ↓
ModsGrid (creates grid layout)
    ↓
ModsGridCard (individual cards with images)
    ↓
selectedModProvider (updates when clicked)
```

## Key Features

### Visual Indicators
- **Image Display:** Shows mod thumbnail or fallback text
- **Asset Counter:** Shows downloaded vs total files
- **Backup Status:** Visual indicator of backup state
- **Selection State:** Visual feedback for selection
- **Failed Downloads:** Orange color for failed asset counts

### Responsive Design
- Grid automatically adjusts columns based on screen width
- Each card is approximately 220px wide
- Minimum 1 column on narrow screens

### Performance
- Uses `useMemoized` hooks to optimize re-renders
- Lazy loading with GridView.builder
- Only builds visible cards

## Related Files

- `lib/src/mods/mods_page.dart` - Main page layout
- `lib/src/mods/components/mods_view.dart` - View switcher
- `lib/src/mods/components/mods_grid.dart` - Grid layout
- `lib/src/mods/components/mods_grid_card.dart` - Individual cards
- `lib/src/mods/components/mods_list.dart` - List layout (alternative)
- `lib/src/state/provider.dart` - Data providers
