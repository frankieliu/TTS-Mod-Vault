import 'dart:io' show Directory, File, Process;
import 'dart:isolate' show Isolate;
import 'dart:math' show max, min;
import 'dart:io' show Platform;

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart'
    show ExistingBackupsState;
import 'package:tts_mod_vault/src/state/backup/models/backup_file_metadata.dart';
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, loadingMessageProvider, settingsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart' show getBackupFilenameByMod;

class ExistingBackupsStateNotifier extends StateNotifier<ExistingBackupsState> {
  final Ref ref;

  ExistingBackupsStateNotifier(this.ref) : super(ExistingBackupsState.empty());

  Future<void> loadExistingBackups() async {
    debugPrint('loadExistingBackups - started at ${DateTime.now()}');

    final backupsDir = ref.read(directoriesProvider).backupsDir;
    final directory = Directory(backupsDir);

    if (backupsDir.isEmpty || !directory.existsSync()) {
      debugPrint(
          'loadExistingBackups - finished at ${DateTime.now()} - backups dir is not set or directory does not exist');
      state = ExistingBackupsState(backups: []);
      return;
    }

    final files = await directory
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => path.extension(file.path).toLowerCase() == '.ttsmod')
        .toList();

    if (files.isEmpty) {
      debugPrint(
          'loadExistingBackups - finished at ${DateTime.now()} - files are empty');
      state = ExistingBackupsState(backups: []);
      return;
    }

    // TODO: Remove this limit after testing - currently limiting to first 10 backups
    final limitedFiles = files.take(10).toList();
    debugPrint(
        'loadExistingBackups - TESTING MODE: Processing ${limitedFiles.length} of ${files.length} total backups');

    ref.read(loadingMessageProvider.notifier).state = 'Loading backup files';

    // Get existing metadata from storage
    final storage = ref.read(storageProvider);
    final existingMetadata = storage.getAllBackupFileMetadata();

    // Split files into those with cached metadata and those needing extraction
    final filesNeedingExtraction = <File>[];
    final backupsFromCache = <ExistingBackup>[];

    for (final file in limitedFiles) {
      final filename = path.basename(file.path);
      final cachedMetadata = existingMetadata[filename];

      if (cachedMetadata != null) {
        // Use cached metadata - no need to extract ZIP
        final stat = await file.stat();
        backupsFromCache.add(ExistingBackup(
          filename: filename,
          filepath: path.normalize(file.path),
          lastModifiedTimestamp: stat.modified.millisecondsSinceEpoch ~/ 1000,
          totalAssetCount: null,
        ));
      } else {
        // Need to extract metadata from ZIP
        filesNeedingExtraction.add(file);
      }
    }

    debugPrint(
        'loadExistingBackups - ${backupsFromCache.length} backups loaded from cache, ${filesNeedingExtraction.length} need extraction');

    // Process files that need extraction
    final List<ExistingBackup> extractedBackups = [];
    if (filesNeedingExtraction.isNotEmpty) {
      // Split files into ASCII and Unicode groups
      final asciiFiles = <File>[];
      final unicodeFiles = <File>[];

      for (final file in filesNeedingExtraction) {
        if (_containsUnicode(file.path)) {
          unicodeFiles.add(file);
        } else {
          asciiFiles.add(file);
        }
      }

      debugPrint(
          'loadExistingBackups - Processing ${asciiFiles.length} ASCII files in isolates, ${unicodeFiles.length} Unicode files in main thread');

      final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
      final chunkedAsciiFiles = _chunkList(asciiFiles, numberOfIsolates);

      // Process each isolate and save metadata incrementally
      for (final chunk in chunkedAsciiFiles) {
        final result = await Isolate.run(() => _processBackupFiles(chunk));

        // Save metadata immediately after each batch completes
        for (final (backup, metadata) in result) {
          extractedBackups.add(backup);
          if (metadata != null) {
            await storage.saveBackupFileMetadata(backup.filename, metadata);
            debugPrint('Saved metadata for ${backup.filename}');
          }
        }
      }

      // Process unicode files in main thread
      if (unicodeFiles.isNotEmpty) {
        final result = await _processBackupFiles(unicodeFiles);

        // Save metadata immediately
        for (final (backup, metadata) in result) {
          extractedBackups.add(backup);
          if (metadata != null) {
            await storage.saveBackupFileMetadata(backup.filename, metadata);
            debugPrint('Saved metadata for ${backup.filename}');
          }
        }
      }
    }

    // Combine cached and extracted backups
    final allBackups = [...backupsFromCache, ...extractedBackups];
    state = ExistingBackupsState(backups: allBackups);
    debugPrint('loadExistingBackups - finished at ${DateTime.now()}');
  }

  bool _containsUnicode(String filePath) {
    final fileName = path.basename(filePath);

    // Check if any character in the filename is outside ASCII range (0-127)
    for (int i = 0; i < fileName.length; i++) {
      if (fileName.codeUnitAt(i) > 127) {
        return true;
      }
    }
    return false;
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    final itemsPerChunk = (list.length / chunkSize).ceil();

    for (int i = 0; i < list.length; i += itemsPerChunk) {
      final end = min(i + itemsPerChunk, list.length);
      chunks.add(list.sublist(i, end));
    }

    return chunks;
  }

  void addBackup(ExistingBackup newBackup) {
    final existingIndex = state.backups
        .indexWhere((backup) => backup.filename == newBackup.filename);

    if (existingIndex >= 0) {
      // Replace existing backup
      final updatedBackups = [...state.backups];
      updatedBackups[existingIndex] = newBackup;
      state = ExistingBackupsState(backups: updatedBackups);
    } else {
      // Add new backup
      state = ExistingBackupsState(backups: [...state.backups, newBackup]);
    }
  }

  ExistingBackup? _getMostRecentBackupByFilename(String filename) {
    final matchingBackups =
        state.backups.where((backup) => backup.filename == filename).toList();

    if (matchingBackups.isEmpty) {
      return null;
    }

    // Sort by lastModifiedTimestamp in descending order and take the first (most recent)
    matchingBackups.sort(
        (a, b) => b.lastModifiedTimestamp.compareTo(a.lastModifiedTimestamp));

    return matchingBackups.first;
  }

  ExistingBackup? getBackupByMod(Mod mod) {
    try {
      final forceBackupJsonFilename =
          ref.read(settingsProvider).forceBackupJsonFilename;

      if (forceBackupJsonFilename && mod.modType == ModTypeEnum.mod) {
        // Try to find backup name which includes JSON filename
        final backupFileNameWithJson = getBackupFilenameByMod(mod, true);
        final backupFileWithJson =
            _getMostRecentBackupByFilename(backupFileNameWithJson);

        if (backupFileWithJson != null) {
          return backupFileWithJson;
        }

        // Try to find backup name which doesn't force inclusion of JSON filename
        final standardBackupFileName = getBackupFilenameByMod(mod, false);
        final standardBackup =
            _getMostRecentBackupByFilename(standardBackupFileName);

        return standardBackup;
      }

      final backupFileName = getBackupFilenameByMod(mod, false);
      return _getMostRecentBackupByFilename(backupFileName);
    } catch (e) {
      return null;
    }
  }

  Future<int> listZipContents(String zipPath) async {
    List<String> filePaths;
    if (Platform.isWindows) {
      filePaths = await _listWithTar(zipPath);
    } else {
      filePaths = await _listWithUnzip(zipPath);
    }

    final folderCounts = <String, int>{};
    for (final path in filePaths) {
      if (path.endsWith('/')) continue; // Skip folders
      final folder = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/'))
          : 'root';
      folderCounts.update(folder, (count) => count + 1, ifAbsent: () => 1);
    }

    // Calculate total for asset folders
    const assetFolders = ['Assetbundles', 'Audio', 'Images', 'PDF', 'Models'];
    final assetTotal = assetFolders
        .map((folder) => folderCounts['Mods/$folder'] ?? 0)
        .fold(0, (a, b) => a + b);

    return assetTotal;
  }

  Future<List<String>> _listWithUnzip(String zipPath) async {
    try {
      final result = await Process.run('unzip', ['-Z1', zipPath]);

      if (result.exitCode != 0) {
        debugPrint('_listWithUnzip result error: ${result.stderr}');
        return _fallbackToDartZip(zipPath);
      }

      final lines = (result.stdout as String).split('\n');
      return lines.where((line) => line.trim().isNotEmpty).toList();
    } catch (e) {
      debugPrint('_listWithUnzip error: $e');
      return _fallbackToDartZip(zipPath);
    }
  }

  Future<List<String>> _listWithTar(String zipPath) async {
    try {
      final result = await Process.run('tar', ['-tf', zipPath]);

      if (result.exitCode != 0) {
        debugPrint('_listWithTar result error: ${result.stderr}');
        return _fallbackToDartZip(zipPath);
      }

      final lines = (result.stdout as String).split('\n');
      return lines.where((line) => line.trim().isNotEmpty).toList();
    } catch (e) {
      debugPrint('_listWithTar error: $e');
      return _fallbackToDartZip(zipPath);
    }
  }

  Future<List<String>> _fallbackToDartZip(String zipPath) async {
    debugPrint('Falling back to Dart archive package for: $zipPath');

    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      return archive.files
          // Normalize to forward slashes to align with Tar and Unzip methods
          .map((file) => file.name.trim().replaceAll('\\', '/'))
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('_fallbackToDartZip error: $e');
      return [];
    }
  }
}

// Top-level function required by Isolate.run
// Returns list of (ExistingBackup, BackupFileMetadata?)
Future<List<(ExistingBackup, BackupFileMetadata?)>> _processBackupFiles(
    List<File> files) async {
  final results = <(ExistingBackup, BackupFileMetadata?)>[];

  for (final file in files) {
    try {
      final stat = await file.stat();
      final filename = path.basename(file.path);

      // Extract file metadata from zip
      BackupFileMetadata? metadata;
      try {
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        final Map<String, int> filesMap = {};
        for (final zipFile in archive.files) {
          if (!zipFile.isFile) continue;
          final name = path.basename(zipFile.name);
          if (name.isNotEmpty) {
            filesMap[name] = zipFile.size;
          }
        }

        if (filesMap.isNotEmpty) {
          metadata = BackupFileMetadata(files: filesMap);
        }
      } catch (e) {
        debugPrint("Error extracting metadata from $filename: $e");
      }

      final backup = ExistingBackup(
        filename: filename,
        filepath: path.normalize(file.path),
        lastModifiedTimestamp: stat.modified.millisecondsSinceEpoch ~/ 1000,
        totalAssetCount: null,
      );

      results.add((backup, metadata));
    } catch (e) {
      debugPrint("_processBackupFiles error $e");
    }
  }

  return results;
}
