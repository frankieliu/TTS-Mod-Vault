import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/asset_detail_dialog.dart'
    show AssetDetailDialog;
import 'package:tts_mod_vault/src/mods/components/replace_url_dialog.dart'
    show showReplaceUrlDialog;
import 'package:tts_mod_vault/src/mods/enums/context_menu_action_enum.dart'
    show ContextMenuActionEnum;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        downloadProvider,
        failedAssetsProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        copyToClipboard,
        getFileNameFromPath,
        getFileNameFromURL,
        openFile,
        openInFileExplorer,
        openUrl,
        showSnackBar;

class AssetsUrl extends ConsumerWidget {
  final Asset asset;
  final AssetTypeEnum type;

  const AssetsUrl({
    super.key,
    required this.asset,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    void showURLContextMenu(BuildContext context, Offset position) {
      showMenu(
        context: context,
        color: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white, width: 2),
        ),
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: [
          if (asset.fileExists &&
              [AssetTypeEnum.audio, AssetTypeEnum.image, AssetTypeEnum.pdf]
                  .contains(type))
            PopupMenuItem(
              value: ContextMenuActionEnum.openFile,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.file_open),
                  Text('Open File'),
                ],
              ),
            ),
          if (asset.fileExists)
            PopupMenuItem(
              value: ContextMenuActionEnum.openInExplorer,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.folder_open),
                  Text('Open in File Explorer'),
                ],
              ),
            ),
          PopupMenuItem(
            value: ContextMenuActionEnum.openInBrowser,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.open_in_browser),
                Text('Open URL in Browser'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.copyUrl,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.link),
                Text('Copy URL'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.copyFilename,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.file_copy),
                Text('Copy Filename'),
              ],
            ),
          ),
          if (!asset.fileExists)
            PopupMenuItem(
              value: ContextMenuActionEnum.download,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.download),
                  Text(asset.hasFailed ? 'Retry Download' : 'Download'),
                ],
              ),
            ),
          if (ref.read(settingsProvider).enableTtsModdersFeatures)
            PopupMenuItem(
              value: ContextMenuActionEnum.replaceUrl,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.find_replace),
                  Text('Replace URL'),
                ],
              ),
            ),
        ],
      ).then((value) async {
        if (value != null) {
          switch (value) {
            case ContextMenuActionEnum.openFile:
              if (asset.filePath != null && asset.filePath!.isNotEmpty) {
                openFile(asset.filePath!);
              }
              break;

            case ContextMenuActionEnum.openInExplorer:
              if (asset.filePath != null && asset.filePath!.isNotEmpty) {
                openInFileExplorer(asset.filePath!);
              }
              break;

            case ContextMenuActionEnum.openInBrowser:
              final result = await openUrl(asset.url);
              if (!result && context.mounted) {
                showSnackBar(context, "Failed to open: ${asset.url}");
              }
              break;

            case ContextMenuActionEnum.copyUrl:
              if (context.mounted) {
                copyToClipboard(context, asset.url);
              }
              break;

            case ContextMenuActionEnum.copyFilename:
              if (context.mounted) {
                copyToClipboard(
                  context,
                  asset.filePath != null && asset.filePath!.isNotEmpty
                      ? getFileNameFromPath(asset.filePath ?? '')
                      : getFileNameFromURL(asset.url),
                );
              }
              break;

            case ContextMenuActionEnum.replaceUrl:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null || !context.mounted) break;

              showReplaceUrlDialog(context, ref, asset, type, selectedMod);
              break;

            case ContextMenuActionEnum.download:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null) break;

              // If asset has failed before, remove from failed list before retrying
              if (asset.hasFailed) {
                await ref
                    .read(failedAssetsProvider.notifier)
                    .removeFailedAsset(asset.url);
              }

              await ref.read(downloadProvider.notifier).downloadFiles(
                modAssetListUrls: [asset.url],
                type: type,
                downloadingAllFiles: false,
              );
              await ref
                  .read(modsProvider.notifier)
                  .updateSelectedMod(selectedMod);
              break;

            default:
              break;
          }
        }
      });
    }

    void onTapDown(TapDownDetails details) {
      if (ref.read(actionInProgressProvider)) return;

      // Show asset detail dialog on left-click
      showDialog(
        context: context,
        builder: (context) => AssetDetailDialog(asset: asset, type: type),
      );
    }

    void onSecondaryTapDown(TapDownDetails details) {
      if (ref.read(actionInProgressProvider)) return;

      // Show context menu on right-click (unchanged)
      showURLContextMenu(context, details.globalPosition);
    }

    return Container(
      decoration: asset.isBackedUp
          ? BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      padding: asset.isBackedUp ? const EdgeInsets.all(2) : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (details) => onTapDown(details),
          onSecondaryTapDown: (details) => onSecondaryTapDown(details),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status icon
              Icon(
                asset.fileExists
                    ? Icons.check_circle
                    : asset.hasFailed
                        ? (asset.errorType == DownloadErrorTypeEnum.permanent
                            ? Icons.error
                            : Icons.warning)
                        : Icons.circle_outlined,
                size: 14,
                color: asset.fileExists
                    ? Colors.green
                    : asset.hasFailed
                        ? (asset.errorType == DownloadErrorTypeEnum.permanent
                            ? Colors.red
                            : Colors.orange)
                        : Colors.white,
              ),
              const SizedBox(width: 4),
              // URL text
              Flexible(
                child: Text(
                  asset.url,
                  style: TextStyle(
                    fontSize: 12,
                    color: asset.fileExists
                        ? Colors.green
                        : asset.hasFailed
                            ? (asset.errorType == DownloadErrorTypeEnum.permanent
                                ? Colors.red
                                : Colors.orange)
                            : Colors.white,
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
