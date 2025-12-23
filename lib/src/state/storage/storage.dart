import 'dart:convert' show json, jsonDecode, jsonEncode;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box, Hive;
import 'package:tts_mod_vault/src/state/asset/models/failed_asset_model.dart';
import 'package:tts_mod_vault/src/state/asset/models/downloaded_file_info.dart';
import 'package:tts_mod_vault/src/state/backup/models/backup_file_metadata.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;

class Storage {
  bool _initialized = false;
  late Box<dynamic> _urlsBox;
  late Box<String> _metadataBox;
  late Box<String> _appDataBox;
  late Box<String> _failedAssetsBox;
  late Box<String> _backupFilesBox;
  late Box<String> _downloadedFilesBox;

  // Boxes
  static const String urlsBox = 'ModUrls';
  static const String metadataBox = 'ModMetadata';
  static const String appDataBox = 'AppData';
  static const String failedAssetsBox = 'FailedAssets';
  static const String backupFilesBox = 'BackupFiles';
  static const String downloadedFilesBox = 'DownloadedFiles';

  // Keys
  static const String dateTimeStampSuffix = 'DateTimeStamp';
  static const String modsDirKey = 'ModsDir';
  static const String savesDirKey = 'SavesDir';
  static const String backupsDirKey = 'BackupsDir';
  static const String settingsKey = 'TTSModVaultSettings';

  Future<void> initializeStorage() async {
    debugPrint("initializeStorage");

    if (!_initialized) {
      _urlsBox = await Hive.openBox<dynamic>(urlsBox);
      _metadataBox = await Hive.openBox<String>(metadataBox);
      _appDataBox = await Hive.openBox<String>(appDataBox);
      _failedAssetsBox = await Hive.openBox<String>(failedAssetsBox);
      _backupFilesBox = await Hive.openBox<String>(backupFilesBox);
      _downloadedFilesBox = await Hive.openBox<String>(downloadedFilesBox);

      _initialized = true;
    }
  }

  // SETTINGS
  Future<void> saveSettings(SettingsState state) async {
    final settingsJson = json.encode(state.toJson());

    await _appDataBox.put(settingsKey, settingsJson);
  }

  Map<String, String>? getSettings() {
    final jsonStr = _appDataBox.get(settingsKey);

    if (jsonStr == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(jsonStr);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> deleteSettings() async {
    await _appDataBox.delete(settingsKey);
  }

  // MODS DIR
  Future<void> saveModsDir(String value) async {
    await _appDataBox.put(modsDirKey, value);
  }

  String? getModsDir() {
    return _appDataBox.get(modsDirKey);
  }

  Future<void> deleteModsDir() async {
    await _appDataBox.delete(modsDirKey);
  }

  // SAVES DIR
  Future<void> saveSavesDir(String value) async {
    await _appDataBox.put(savesDirKey, value);
  }

  String? getSavesDir() {
    return _appDataBox.get(savesDirKey);
  }

  Future<void> deleteSavesDir() async {
    await _appDataBox.delete(savesDirKey);
  }

  // BACKUPS DIR
  Future<void> saveBackupsDir(String value) async {
    await _appDataBox.put(backupsDirKey, value);
  }

  String? getBackupsDir() {
    return _appDataBox.get(backupsDirKey);
  }

  Future<void> deleteBackupsDir() async {
    await _appDataBox.delete(backupsDirKey);
  }

  // MOD DATA
  String? getModDateTimeStamp(String modName) {
    return _metadataBox.get('$modName$dateTimeStampSuffix');
  }

  Future<void> updateModUrls(
      String jsonFileName, Map<String, String> newUrls) async {
    await _urlsBox.put(jsonFileName, newUrls);
  }

  Map<String, String>? getModUrls(String jsonFileName) {
    final urls = _urlsBox.get(jsonFileName);
    if (urls == null) return null;
    return Map<String, String>.from(urls);
  }

  /* Future<void> deleteMod(String modName) async {
    await Future.wait([
      _metadataBox.delete('$modName$dateTimeStampSuffix'),
      _urlsBox.delete(modName)
    ]);
  } */

  // Bulk operations for better performance with many mods
  Future<void> saveAllModUrlsData(
      Map<String, Map<String, String>> allModData) async {
    await _urlsBox.putAll(allModData);
  }

  Future<void> saveAllModMetadata(Map<String, String> allModMeta) async {
    await _metadataBox.putAll(allModMeta);
  }

  Map<String, Map<String, String>?> getModUrlsBulk(List<String> jsonFileNames) {
    final Map<String, Map<String, String>?> result = {};

    for (final jsonFileName in jsonFileNames) {
      final urls = _urlsBox.get(jsonFileName);
      if (urls == null) {
        result[jsonFileName] = null;
      } else {
        result[jsonFileName] = Map<String, String>.from(urls);
      }
    }

    return result;
  }

  Future<void> clearAllModData() async {
    await Hive.box<dynamic>(urlsBox).clear();
    await Hive.box<String>(metadataBox).clear();
  }

  // FAILED ASSETS
  Future<void> saveFailedAsset(String url, FailedAsset failedAsset) async {
    final jsonMap = failedAsset.toJson();
    final jsonStr = jsonEncode(jsonMap);
    await _failedAssetsBox.put(url, jsonStr);
  }

  FailedAsset? getFailedAsset(String url) {
    final jsonStr = _failedAssetsBox.get(url);
    if (jsonStr == null) return null;

    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      return FailedAsset.fromJson(decoded);
    } catch (e) {
      debugPrint('Error decoding failed asset for url $url: $e');
      return null;
    }
  }

  Future<void> deleteFailedAsset(String url) async {
    await _failedAssetsBox.delete(url);
  }

  Map<String, FailedAsset> getAllFailedAssets() {
    final Map<String, FailedAsset> result = {};

    for (final key in _failedAssetsBox.keys) {
      final jsonStr = _failedAssetsBox.get(key);
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr);
          result[key] = FailedAsset.fromJson(decoded);
        } catch (e) {
          debugPrint('Error decoding failed asset for key $key: $e');
        }
      }
    }

    return result;
  }

  Future<void> clearFailedAssets() async {
    await _failedAssetsBox.clear();
  }

  Future<void> deleteFailedAssetsByType(AssetTypeEnum type) async {
    final toDelete = <String>[];

    for (final key in _failedAssetsBox.keys) {
      final jsonStr = _failedAssetsBox.get(key);
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr);
          final failedAsset = FailedAsset.fromJson(decoded);
          if (failedAsset.type == type) {
            toDelete.add(key);
          }
        } catch (e) {
          debugPrint('Error checking failed asset type for key $key: $e');
        }
      }
    }

    await _failedAssetsBox.deleteAll(toDelete);
  }

  // BACKUP FILES
  Future<void> saveBackupFileMetadata(
      String backupFilename, BackupFileMetadata metadata) async {
    final jsonMap = metadata.toJson();
    final jsonStr = jsonEncode(jsonMap);
    await _backupFilesBox.put(backupFilename, jsonStr);
  }

  BackupFileMetadata? getBackupFileMetadata(String backupFilename) {
    final jsonStr = _backupFilesBox.get(backupFilename);
    if (jsonStr == null) return null;

    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      return BackupFileMetadata.fromJson(decoded);
    } catch (e) {
      debugPrint(
          'Error decoding backup file metadata for $backupFilename: $e');
      return null;
    }
  }

  Future<void> deleteBackupFileMetadata(String backupFilename) async {
    await _backupFilesBox.delete(backupFilename);
  }

  Map<String, BackupFileMetadata> getAllBackupFileMetadata() {
    final Map<String, BackupFileMetadata> result = {};

    for (final key in _backupFilesBox.keys) {
      final jsonStr = _backupFilesBox.get(key);
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr);
          result[key] = BackupFileMetadata.fromJson(decoded);
        } catch (e) {
          debugPrint('Error decoding backup file metadata for key $key: $e');
        }
      }
    }

    return result;
  }

  Future<void> clearBackupFileMetadata() async {
    await _backupFilesBox.clear();
  }

  // DOWNLOADED FILES METADATA
  /// Saves metadata for a downloaded file
  Future<void> saveDownloadedFileInfo(String filename, DownloadedFileInfo info) async {
    final jsonStr = jsonEncode(info.toJson());
    await _downloadedFilesBox.put(filename, jsonStr);
  }

  /// Gets metadata for a downloaded file
  DownloadedFileInfo? getDownloadedFileInfo(String filename) {
    final jsonStr = _downloadedFilesBox.get(filename);
    if (jsonStr == null) return null;

    try {
      return DownloadedFileInfo.fromJson(jsonDecode(jsonStr));
    } catch (e) {
      debugPrint('Error decoding downloaded file info for $filename: $e');
      return null;
    }
  }

  /// Gets metadata for multiple downloaded files at once
  Map<String, DownloadedFileInfo> getDownloadedFileInfoBulk(List<String> filenames) {
    final Map<String, DownloadedFileInfo> result = {};

    for (final filename in filenames) {
      final jsonStr = _downloadedFilesBox.get(filename);
      if (jsonStr != null) {
        try {
          result[filename] = DownloadedFileInfo.fromJson(jsonDecode(jsonStr));
        } catch (e) {
          debugPrint('Error decoding downloaded file info for $filename: $e');
        }
      }
    }

    return result;
  }

  /// Saves metadata for multiple downloaded files at once (bulk)
  Future<void> saveDownloadedFileInfoBulk(Map<String, DownloadedFileInfo> infos) async {
    final Map<String, String> encoded = {};
    for (final entry in infos.entries) {
      encoded[entry.key] = jsonEncode(entry.value.toJson());
    }
    await _downloadedFilesBox.putAll(encoded);
  }

  /// Deletes metadata for a downloaded file
  Future<void> deleteDownloadedFileInfo(String filename) async {
    await _downloadedFilesBox.delete(filename);
  }

  /// Gets all downloaded file metadata
  Map<String, DownloadedFileInfo> getAllDownloadedFileInfo() {
    final Map<String, DownloadedFileInfo> result = {};

    for (final key in _downloadedFilesBox.keys) {
      final jsonStr = _downloadedFilesBox.get(key);
      if (jsonStr != null) {
        try {
          result[key] = DownloadedFileInfo.fromJson(jsonDecode(jsonStr));
        } catch (e) {
          debugPrint('Error decoding downloaded file info for key $key: $e');
        }
      }
    }

    return result;
  }

  /// Clears all downloaded file metadata
  Future<void> clearDownloadedFileMetadata() async {
    await _downloadedFilesBox.clear();
  }
}
