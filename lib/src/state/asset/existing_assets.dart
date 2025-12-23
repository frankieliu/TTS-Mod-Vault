import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/asset/existing_assets_state.dart'
    show ExistingAssetsListsState;
import 'package:tts_mod_vault/src/state/asset/models/downloaded_file_info.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newSteamUserContentUrl, oldCloudUrl;

class ExistingAssetsNotifier extends StateNotifier<ExistingAssetsListsState> {
  final Ref ref;

  ExistingAssetsNotifier(this.ref) : super(ExistingAssetsListsState.empty());

  Future<void> loadExistingAssetsLists() async {
    debugPrint('loadExistingAssetsLists - started at ${DateTime.now()}');

    final directoryPaths = {
      for (final type in AssetTypeEnum.values)
        type: ref.read(directoriesProvider.notifier).getDirectoryByType(type)
    };

    final futures = AssetTypeEnum.values.map((type) async {
      final directoryPath = directoryPaths[type] ?? '';

      final assetMap = await Isolate.run(
        () => _getDirectoryFileNamesAndPaths(directoryPath),
      );

      return (type, assetMap);
    });

    final results = await Future.wait(futures);

    final Map<AssetTypeEnum, Map<String, String>> resultMap = {
      for (final (type, assetMap) in results) type: assetMap
    };

    state = ExistingAssetsListsState(
      assetBundles: resultMap[AssetTypeEnum.assetBundle] ?? {},
      audio: resultMap[AssetTypeEnum.audio] ?? {},
      images: resultMap[AssetTypeEnum.image] ?? {},
      models: resultMap[AssetTypeEnum.model] ?? {},
      pdf: resultMap[AssetTypeEnum.pdf] ?? {},
    );

    debugPrint('loadExistingAssetsLists - finished at ${DateTime.now()}');

    // Populate metadata for existing files
    await _populateExistingFileMetadata();
  }

  Future<void> _populateExistingFileMetadata() async {
    debugPrint('_populateExistingFileMetadata - started');

    final storage = ref.read(storageProvider);
    final downloadInfoMap = <String, DownloadedFileInfo>{};

    // Get all files from state
    final allFiles = <String, String>{
      ...state.assetBundles,
      ...state.audio,
      ...state.images,
      ...state.models,
      ...state.pdf,
    };

    debugPrint('  Checking ${allFiles.length} existing files');

    int processedCount = 0;
    int errorCount = 0;

    for (final entry in allFiles.entries) {
      final filename = entry.key;
      final filepath = entry.value;

      try {
        final file = File(filepath);
        if (await file.exists()) {
          final stat = await file.stat();

          downloadInfoMap[filename] = DownloadedFileInfo(
            filepath: filepath,
            size: stat.size,
            crc32: 0, // Default to 0, only calculate for new downloads
            downloadedAt: stat.modified.millisecondsSinceEpoch,
          );
          processedCount++;
        }
      } catch (e) {
        errorCount++;
        debugPrint('  Error reading file $filepath: $e');
      }
    }

    // Bulk save metadata
    if (downloadInfoMap.isNotEmpty) {
      await storage.saveDownloadedFileInfoBulk(downloadInfoMap);
      debugPrint(
          '_populateExistingFileMetadata - finished: $processedCount files processed, $errorCount errors');
    }
  }

  Future<void> setExistingAssetsListByType(AssetTypeEnum type) async {
    final directoryPath =
        ref.read(directoriesProvider.notifier).getDirectoryByType(type);

    final assetMap = await Isolate.run(
      () => _getDirectoryFileNamesAndPaths(directoryPath),
    );

    _updateStateByType(type, assetMap);
  }

  void addExistingAsset(AssetTypeEnum type, String filename, String filepath) {
    final currentMap = _getAssetMapByType(type);
    final updatedMap = Map<String, String>.from(currentMap)..[filename] = filepath;
    _updateStateByType(type, updatedMap);
  }

  Map<String, String> _getAssetMapByType(AssetTypeEnum type) {
    return switch (type) {
      AssetTypeEnum.assetBundle => state.assetBundles,
      AssetTypeEnum.audio => state.audio,
      AssetTypeEnum.image => state.images,
      AssetTypeEnum.model => state.models,
      AssetTypeEnum.pdf => state.pdf,
    };
  }

  void _updateStateByType(AssetTypeEnum type, Map<String, String> assetMap) {
    state = switch (type) {
      AssetTypeEnum.assetBundle => state.copyWith(assetBundles: assetMap),
      AssetTypeEnum.audio => state.copyWith(audio: assetMap),
      AssetTypeEnum.image => state.copyWith(images: assetMap),
      AssetTypeEnum.model => state.copyWith(models: assetMap),
      AssetTypeEnum.pdf => state.copyWith(pdf: assetMap),
    };
  }

  bool doesAssetFileExist(String assetFileName, AssetTypeEnum type) {
    return _getAssetMapByType(type).containsKey(assetFileName);
  }

  String? getAssetFilePath(String assetFilename, AssetTypeEnum type) {
    final filepath = _getAssetMapByType(type)[assetFilename];
    return filepath != null ? path.normalize(filepath) : null;
  }
}

///
/// Top-level function required by Isolate.run
/// Returns a map of filename -> filepath for O(1) lookups
///
Future<Map<String, String>> _getDirectoryFileNamesAndPaths(
    String dirPath) async {
  final directory = Directory(dirPath);

  if (!directory.existsSync()) {
    return <String, String>{};
  }

  final files = await directory
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList();

  final assetMap = <String, String>{};

  for (final file in files) {
    final filename = p.basenameWithoutExtension(file.path);
    final mappedFilename = filename.startsWith(getFileNameFromURL(oldCloudUrl))
        ? filename.replaceFirst(getFileNameFromURL(oldCloudUrl),
            getFileNameFromURL(newSteamUserContentUrl))
        : filename;

    assetMap[mappedFilename] = file.path;
  }

  return assetMap;
}
