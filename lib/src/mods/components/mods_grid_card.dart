import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart'
    show kPrimaryButton, kSecondaryButton, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        filteredModsProvider,
        modsProvider,
        selectedModProvider,
        multiSelectModsProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showModContextMenu, formatTimestamp;

class ModsGridCard extends HookConsumerWidget {
  final Mod mod;

  const ModsGridCard({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTitleOnCards = ref.watch(settingsProvider).showTitleOnCards;
    final showBackupState = ref.watch(settingsProvider).showBackupState;
    final selectedMod = ref.watch(selectedModProvider);
    final multiSelectMods = ref.watch(multiSelectModsProvider);

    final isHovered = useState(false);

    final imageExists = useMemoized(() {
      return mod.imageFilePath != null
          ? File(mod.imageFilePath!).existsSync()
          : false;
    }, [mod.imageFilePath]);

    final showAssetCount = useMemoized(() {
      return mod.existingAssetCount != null && mod.assetCount != null;
    }, [mod]);

    final isSelected = useMemoized(() {
      return selectedMod?.jsonFilePath == mod.jsonFilePath ||
          multiSelectMods.contains(mod.jsonFilePath);
    }, [selectedMod, multiSelectMods, mod]);

    final filesMessage = useMemoized(() {
      final missingCount = mod.missingAssetCount ?? 0;
      if (missingCount <= 0) return '';
      final fileLabel = missingCount == 1 ? 'file' : 'files';
      return '$missingCount missing $fileLabel';
    }, [mod.existingAssetCount]);

    final backupIconColor = useMemoized(() {
      if (mod.backup == null) {
        return null; // No backup - no icon
      }

      if (mod.backup!.totalAssetCount == null ||
          mod.existingAssetCount == null) {
        return Colors.grey; // Unknown state
      }

      // Fast comparison: backup file count vs downloaded file count
      if (mod.backup!.totalAssetCount! >= mod.existingAssetCount!) {
        return Colors.green; // Backup has all files (or more from old versions)
      } else {
        return Colors.yellow; // Backup is missing some downloaded files
      }
    }, [mod.backup, mod.existingAssetCount]);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: Listener(
        onPointerDown: (event) {
          if (ref.read(actionInProgressProvider)) {
            return;
          }

          final isCtrlPressed = event.kind == PointerDeviceKind.mouse &&
              (event.buttons == kPrimaryButton) &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed);

          final isShiftPressed = event.kind == PointerDeviceKind.mouse &&
              (event.buttons == kPrimaryButton) &&
              HardwareKeyboard.instance.isShiftPressed;

          if (event.buttons == kSecondaryButton) {
            // Right-click

            ref.read(modsProvider.notifier).setSelectedMod(mod);
            showModContextMenu(context, ref, event.position, mod);
          } else if (event.buttons == kPrimaryButton) {
            // Left-click
            if (isShiftPressed) {
              // Shift+Click: Select range from last selected to this mod
              final selectedMod = ref.read(selectedModProvider);
              final allMods = ref.read(filteredModsProvider);

              if (selectedMod != null) {
                // Find indices of the last selected mod and the clicked mod
                final lastIndex = allMods.indexWhere(
                    (m) => m.jsonFilePath == selectedMod.jsonFilePath);
                final currentIndex =
                    allMods.indexWhere((m) => m.jsonFilePath == mod.jsonFilePath);

                if (lastIndex != -1 && currentIndex != -1) {
                  // Select all mods between lastIndex and currentIndex
                  final startIndex =
                      lastIndex < currentIndex ? lastIndex : currentIndex;
                  final endIndex =
                      lastIndex < currentIndex ? currentIndex : lastIndex;

                  final rangeSelection = <String>{};
                  for (int i = startIndex; i <= endIndex; i++) {
                    rangeSelection.add(allMods[i].jsonFilePath);
                  }

                  ref.read(multiSelectModsProvider.notifier).state =
                      rangeSelection;
                }
              } else {
                // No previous selection, just select this mod
                ref.read(modsProvider.notifier).setSelectedMod(mod);
              }
            } else if (isCtrlPressed) {
              // Ctrl+Click: Toggle multi-selection
              final currentSelected = ref.read(multiSelectModsProvider);
              final newSelected = Set<String>.from(currentSelected);

              if (newSelected.contains(mod.jsonFilePath)) {
                newSelected.remove(mod.jsonFilePath);
              } else {
                newSelected.add(mod.jsonFilePath);
              }

              ref.read(multiSelectModsProvider.notifier).state = newSelected;
            } else {
              // Normal left-click: Single selection (clears multi-select)
              ref.read(multiSelectModsProvider.notifier).state = {};
              ref.read(modsProvider.notifier).setSelectedMod(mod);
            }
          }
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: Border.all(
              width: 4,
              color: isSelected
                  ? multiSelectMods.length > 1
                      ? Colors.cyan
                      : Colors.white
                  : isHovered.value
                      ? Colors.white70
                      : Colors.transparent,
            ),
          ),
          child: Stack(
            children: [
              imageExists
                  ? Image.file(
                      File(mod.imageFilePath!),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.grey[850],
                      alignment: Alignment.center,
                      child: Text(
                        '${mod.saveName}\n${mod.jsonFileName}',
                        maxLines: 5,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
              if (showTitleOnCards || mod.modType != ModTypeEnum.mod)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                        color: Colors.black.withAlpha(140),
                        width: double.infinity,
                        padding: EdgeInsets.all(4),
                        child: Text(
                          mod.modType != ModTypeEnum.save
                              ? mod.saveName
                              : '${mod.jsonFileName}\n${mod.saveName}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (showAssetCount)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            color: Colors.black.withAlpha(180),
                          ),
                          padding: EdgeInsets.all(2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              CustomTooltip(
                                waitDuration: Duration(milliseconds: 300),
                                message: filesMessage,
                                child: Text(
                                  "${mod.existingAssetCount}/${mod.assetCount}${mod.failedAssetCount != null && mod.failedAssetCount! > 0 ? ' (${mod.failedAssetCount} failed)' : ''}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: mod.failedAssetCount != null &&
                                            mod.failedAssetCount! > 0
                                        ? Colors.orange
                                        : mod.existingAssetCount == mod.assetCount
                                            ? Colors.green
                                            : Colors.white,
                                  ),
                                ),
                              ),
                              if (backupIconColor != null && showBackupState)
                                CustomTooltip(
                                  waitDuration: Duration(milliseconds: 300),
                                  message:
                                      'Update: ${formatTimestamp(mod.dateTimeStamp) ?? 'N/A'}\n'
                                      'Backup: ${formatTimestamp(mod.backup!.lastModifiedTimestamp.toString())}'
                                      '${mod.backup!.totalAssetCount == null ? '' : '\n\nBackup asset files count: ${mod.backup!.totalAssetCount}\nExisting asset files count: ${mod.existingAssetCount}'}',
                                  child: Icon(
                                    Icons.folder_zip_outlined,
                                    size: 20,
                                    color: backupIconColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
