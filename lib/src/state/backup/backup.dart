import 'dart:io' show Directory, File;
import 'dart:isolate' show ReceivePort, Isolate;

import 'package:archive/archive_io.dart' show ZipFileEncoder, ZipDecoder;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basenameWithoutExtension, basename, join, normalize, relative;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show
        BackupCompleteMessage,
        BackupIsolateData,
        BackupProgressMessage,
        BackupState,
        BackupStatusEnum,
        FilepathsIsolateData;
import 'package:tts_mod_vault/src/state/backup/models/backup_file_metadata.dart';
import 'package:tts_mod_vault/src/state/backup/models/backup_file_info.dart';
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backedUpFilesProvider,
        bulkActionsProvider,
        directoriesProvider,
        existingBackupsProvider,
        settingsProvider,
        storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getBackupFilenameByMod,
        getFileNameFromURL,
        newSteamUserContentUrl,
        oldCloudUrl;

class BackupNotifier extends StateNotifier<BackupState> {
  final Ref ref;

  BackupNotifier(this.ref) : super(const BackupState());

  void resetMessage() {
    state = state.copyWith(message: "");
  }

  /// Checks if a backup should be forced based on downloaded file changes
  /// Returns true if:
  /// 1. There are downloaded files not present in the backup
  /// 2. Downloaded files have different CRC32 than backup (when both are non-zero)
  bool shouldForceBackup(Mod mod) {
    try {
      // Get backup metadata
      final forceBackupJsonFilename =
          ref.read(settingsProvider).forceBackupJsonFilename;
      final backupFileName = getBackupFilenameByMod(mod, forceBackupJsonFilename);
      final storage = ref.read(storageProvider);
      final backupMetadata = storage.getBackupFileMetadata(backupFileName);

      if (backupMetadata == null || backupMetadata.files.isEmpty) {
        debugPrint('shouldForceBackup: No backup metadata found');
        return false; // No metadata, can't determine
      }

      // Get all downloaded files metadata
      final downloadedMetadata = storage.getAllDownloadedFileInfo();

      // Get all URLs for this mod
      final assetLists = mod.assetLists;
      if (assetLists == null) {
        return false;
      }

      final allAssets = mod.getAllAssets();
      int newFilesCount = 0;
      int modifiedFilesCount = 0;

      for (final asset in allAssets) {
        if (!asset.fileExists) continue; // Skip non-downloaded files

        final filename = getFileNameFromURL(asset.url);
        final downloadInfo = downloadedMetadata[filename];
        final backupInfo = backupMetadata.files[filename];

        // Case 1: Downloaded file not in backup
        if (backupInfo == null) {
          newFilesCount++;
          debugPrint('  New file not in backup: $filename');
          continue;
        }

        // Case 2: CRC32 mismatch (when both are non-zero)
        if (downloadInfo != null &&
            downloadInfo.crc32 != 0 &&
            backupInfo.crc32 != 0 &&
            downloadInfo.crc32 != backupInfo.crc32) {
          modifiedFilesCount++;
          debugPrint(
              '  CRC32 mismatch for $filename: downloaded=${downloadInfo.crc32}, backup=${backupInfo.crc32}');
        }
      }

      final shouldForce = newFilesCount > 0 || modifiedFilesCount > 0;
      if (shouldForce) {
        debugPrint(
            'shouldForceBackup: YES - $newFilesCount new files, $modifiedFilesCount modified files');
      } else {
        debugPrint('shouldForceBackup: NO - backup is up to date');
      }

      return shouldForce;
    } catch (e) {
      debugPrint('shouldForceBackup error: $e');
      return false;
    }
  }

  /// Update metadata from an existing backup file without creating a new backup
  /// This extracts size, CRC32, and timestamp from the ZIP metadata (fast operation)
  Future<void> updateExistingBackupMetadata(Mod mod) async {
    try {
      final forceBackupJsonFilename =
          ref.read(settingsProvider).forceBackupJsonFilename;
      final backupFileName = getBackupFilenameByMod(mod, forceBackupJsonFilename);

      // Find the backup file path
      final backupFilePath = mod.backup?.filepath;
      if (backupFilePath == null || backupFilePath.isEmpty) {
        debugPrint('No backup filepath found for ${mod.saveName}');
        return;
      }

      final backupFile = File(backupFilePath);
      if (!await backupFile.exists()) {
        debugPrint('Backup file does not exist: $backupFilePath');
        return;
      }

      final storage = ref.read(storageProvider);

      // Check if metadata already exists
      final existingMetadata = storage.getBackupFileMetadata(backupFileName);
      if (existingMetadata != null && existingMetadata.files.isNotEmpty) {
        debugPrint('Metadata already exists for $backupFileName, updating any missing fields');
      }

      debugPrint('Updating metadata from existing backup: $backupFileName');

      // Read and extract metadata from ZIP (includes CRC32 from ZIP metadata)
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final stat = await backupFile.stat();
      final backupTimestamp = stat.modified.millisecondsSinceEpoch;

      final Map<String, BackupFileInfo> filesMap = {};
      for (final zipFile in archive.files) {
        if (!zipFile.isFile) continue;

        // Use basename WITHOUT extension for consistency
        final name = p.basenameWithoutExtension(zipFile.name);
        if (name.isNotEmpty) {
          filesMap[name] = BackupFileInfo(
            size: zipFile.size,
            crc32: zipFile.crc32 ?? 0, // Extract CRC32 from ZIP metadata
            backedUpAt: backupTimestamp,
          );
        }
      }

      if (filesMap.isNotEmpty) {
        final metadata = BackupFileMetadata(files: filesMap);
        await storage.saveBackupFileMetadata(backupFileName, metadata);
        debugPrint('Updated metadata for $backupFileName with ${filesMap.length} files (including CRC32 from ZIP)');

        // Invalidate backedUpFilesProvider so it recalculates with new metadata
        ref.invalidate(backedUpFilesProvider);
        debugPrint('Invalidated backedUpFilesProvider after metadata update');
      }

      state = state.copyWith(
        message: 'Metadata updated for existing backup (including CRC32)',
      );
    } catch (e) {
      debugPrint('Error updating metadata from existing backup: $e');
      state = state.copyWith(message: 'Error updating metadata: $e');
    }
  }

  /// Populate metadata from a newly created backup WITH CRC32
  Future<void> _populateMetadataFromNewBackup(
    String backupFilePath,
    String backupFileName,
  ) async {
    try {
      final backupFile = File(backupFilePath);
      if (!await backupFile.exists()) {
        return;
      }

      debugPrint('Extracting full metadata with CRC32 from new backup: $backupFileName');

      // Read and extract metadata from ZIP with CRC32
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final stat = await backupFile.stat();
      final backupTimestamp = stat.modified.millisecondsSinceEpoch;

      final Map<String, BackupFileInfo> filesMap = {};
      for (final zipFile in archive.files) {
        if (!zipFile.isFile) continue;

        // Use basename WITHOUT extension for consistency
        final name = p.basenameWithoutExtension(zipFile.name);
        if (name.isNotEmpty) {
          filesMap[name] = BackupFileInfo(
            size: zipFile.size,
            crc32: zipFile.crc32 ?? 0, // Extract CRC32 from ZIP
            backedUpAt: backupTimestamp,
          );
        }
      }

      if (filesMap.isNotEmpty) {
        final metadata = BackupFileMetadata(files: filesMap);
        await ref.read(storageProvider).saveBackupFileMetadata(backupFileName, metadata);
        debugPrint('Saved full metadata with CRC32 for $backupFileName with ${filesMap.length} files');
      }
    } catch (e) {
      debugPrint('Error extracting metadata from new backup: $e');
      // Don't throw - this is optional metadata
    }
  }

  Future<void> createBackup(Mod mod, [String? backupDirectory]) async {
    state = state.copyWith(
      status: backupDirectory != null && backupDirectory.isNotEmpty
          ? BackupStatusEnum.backingUp
          : BackupStatusEnum.awaitingBackupFolder,
      currentCount: 0,
      totalCount: 0,
      message: "",
    );

    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backupDirPath = backupDirectory != null && backupDirectory.isNotEmpty
        ? backupDirectory
        : await FilePicker.platform.getDirectoryPath(
            lockParentWindow: true,
            initialDirectory: backupsDir.isEmpty ? null : backupsDir,
          );

    if (backupDirPath == null) {
      state = state.copyWith(status: BackupStatusEnum.idle);
      return;
    }

    // Determine backup file name and path
    final forceBackupJsonFilename =
        ref.read(settingsProvider).forceBackupJsonFilename;
    final backupFileName = getBackupFilenameByMod(mod, forceBackupJsonFilename);
    final targetBackupFilePath = p.join(backupDirPath, backupFileName);

    // Check if there's an existing backup to preserve files from
    final existingBackupPath = File(targetBackupFilePath).existsSync()
        ? targetBackupFilePath
        : null;

    state = state.copyWith(status: BackupStatusEnum.backingUp);

    // Temporary directory for extracted files from old backup
    Directory? tempDir;

    try {
      final filepathsData = FilepathsIsolateData(
        mod,
        {
          for (final type in AssetTypeEnum.values)
            type:
                ref.read(directoriesProvider.notifier).getDirectoryByType(type)
        },
      );

      final filePaths =
          await Isolate.run(() => _getFilePathsIsolate(filepathsData));
      final totalAssetCount = filePaths.$2;

      // Get list of downloaded asset filenames (without extension)
      final downloadedFilenames = <String>{};
      for (final type in AssetTypeEnum.values) {
        for (final asset in mod.getAssetsByType(type)) {
          if (asset.fileExists) {
            downloadedFilenames.add(getFileNameFromURL(asset.url));
          }
        }
      }

      // Extract files from old backup that aren't in downloaded set
      final additionalFilePaths = <String>[];
      if (existingBackupPath != null) {
        try {
          final backupMetadata = ref.read(storageProvider).getBackupFileMetadata(backupFileName);

          if (backupMetadata != null && backupMetadata.files.isNotEmpty) {
            // Find files in backup that aren't downloaded
            final filesToPreserve = <String>[];
            for (final backedUpFilename in backupMetadata.files.keys) {
              if (!downloadedFilenames.contains(backedUpFilename)) {
                filesToPreserve.add(backedUpFilename);
              }
            }

            if (filesToPreserve.isNotEmpty) {
              debugPrint('Preserving ${filesToPreserve.length} files from old backup: $filesToPreserve');

              // Create temp directory that mirrors the backup structure
              tempDir = Directory.systemTemp.createTempSync('tts_backup_preserve_');

              // Extract old backup
              final oldBackupBytes = await File(existingBackupPath).readAsBytes();
              final oldArchive = ZipDecoder().decodeBytes(oldBackupBytes);

              // Extract and save files to preserve with original directory structure
              for (final zipFile in oldArchive.files) {
                if (!zipFile.isFile) continue;

                final filenameWithoutExt = p.basenameWithoutExtension(zipFile.name);
                if (filesToPreserve.contains(filenameWithoutExt)) {
                  // Preserve the full relative path from the ZIP
                  final tempFilePath = p.join(tempDir.path, zipFile.name);
                  final file = File(tempFilePath);
                  await file.create(recursive: true);
                  await file.writeAsBytes(zipFile.content as List<int>);
                  additionalFilePaths.add(tempFilePath);
                  debugPrint('  Extracted with path: ${zipFile.name}');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error extracting old backup files: $e');
          // Continue with backup creation even if extraction fails
        }
      }

      // Combine all file paths
      final allFilePaths = [...filePaths.$1, ...additionalFilePaths];

      final receivePort = ReceivePort();

      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      final isolateData = BackupIsolateData(
        filePaths: allFilePaths,
        targetBackupFilePath: targetBackupFilePath,
        modsParentPath: modsDir.parent.path,
        savesParentPath: savesDir.parent.path,
        savesPath: savesDir.path,
        sendPort: receivePort.sendPort,
        tempDirPath: tempDir?.path, // Pass temp directory path
      );

      // Start the isolate
      await Isolate.spawn(_backupIsolate, isolateData);

      // Listen for messages from isolate
      await for (final message in receivePort) {
        if (message is BackupProgressMessage) {
          state = state.copyWith(
            currentCount: message.current,
            totalCount: message.total,
          );
        } else if (message is BackupCompleteMessage) {
          receivePort.close();

          if (message.success) {
            // Add new backup to state
            final newBackup = ExistingBackup(
              filename: backupFileName,
              filepath: targetBackupFilePath,
              lastModifiedTimestamp:
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
              totalAssetCount: totalAssetCount,
            );
            ref.read(existingBackupsProvider.notifier).addBackup(newBackup);

            // Extract full metadata with CRC32 from the newly created backup
            await _populateMetadataFromNewBackup(
              targetBackupFilePath,
              backupFileName,
            );

            // Invalidate backedUpFilesProvider so it recalculates with new metadata
            ref.invalidate(backedUpFilesProvider);
            debugPrint('Invalidated backedUpFilesProvider after backup creation');
          }

          if (ref.read(bulkActionsProvider).status ==
              BulkActionsStatusEnum.idle) {
            state = state.copyWith(message: message.message);
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('createBackup - error: ${e.toString()}');
      state = state.copyWith(message: e.toString());
    } finally {
      // Clean up temp directory
      if (tempDir != null && tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
          debugPrint('Cleaned up temp directory');
        } catch (e) {
          debugPrint('Error cleaning up temp directory: $e');
        }
      }

      state = state.copyWith(status: BackupStatusEnum.idle);
    }
  }
}

(List<String>, int) _getFilePathsIsolate(FilepathsIsolateData data) {
  final filePaths = <String>[];

  for (final type in AssetTypeEnum.values) {
    final dirPath = data.directories[type];
    if (dirPath == null) continue;

    final directory = Directory(dirPath);
    if (!directory.existsSync()) continue;

    final files = directory.listSync();
    data.mod.getAssetsByType(type).forEach((asset) {
      if (asset.filePath == null) return;

      final newUrlBase = p.basenameWithoutExtension(asset.filePath!);
      final oldUrlBase = newUrlBase.replaceFirst(
        getFileNameFromURL(newSteamUserContentUrl),
        getFileNameFromURL(oldCloudUrl),
      );

      final match = files.firstWhereOrNull((file) {
        final base = p.basenameWithoutExtension(file.path);
        return base.startsWith(newUrlBase) || base.startsWith(oldUrlBase);
      });

      if (match != null && match.path.isNotEmpty) {
        filePaths.add(p.normalize(match.path));
      }
    });
  }

  final assetFilesCount = filePaths.length;

  // Add JSON and image filepaths
  filePaths.add(data.mod.jsonFilePath);
  if (data.mod.imageFilePath != null && data.mod.imageFilePath!.isNotEmpty) {
    filePaths.add(data.mod.imageFilePath!);
  }

  return (filePaths, assetFilesCount);
}

void _backupIsolate(BackupIsolateData data) async {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(data.targetBackupFilePath);

    for (int i = 0; i < data.filePaths.length; i++) {
      final filePath = data.filePaths[i];
      final file = File(filePath);

      if (!await file.exists()) {
        continue;
      }

      try {
        // Check if file is from preserved temp directory
        final isFromTempDir = data.tempDirPath != null &&
            filePath.startsWith(p.normalize(data.tempDirPath!));

        final String relativePath;
        if (isFromTempDir) {
          // For temp files, use temp directory as base to preserve original structure
          relativePath = p.relative(filePath, from: data.tempDirPath!);
        } else {
          // For normal files, use saves or mods parent path
          final isInSavesPath = filePath.startsWith(p.normalize(data.savesPath));
          relativePath = p.relative(
            filePath,
            from: isInSavesPath ? data.savesParentPath : data.modsParentPath,
          );
        }

        await encoder.addFile(file, relativePath);

        data.sendPort.send(
          BackupProgressMessage(i + 1, data.filePaths.length),
        );
      } catch (e) {
        debugPrint('Error adding file $filePath: $e');
      }
    }

    await encoder.close();

    data.sendPort.send(BackupCompleteMessage(
      true,
      'Backup has been created at ${data.targetBackupFilePath}',
    ));
  } catch (e) {
    data.sendPort.send(BackupCompleteMessage(false, e.toString()));
  }
}
