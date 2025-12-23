import 'dart:convert' show json, jsonDecode, jsonEncode;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box, Hive;
import 'package:tts_mod_vault/src/state/asset/models/failed_asset_model.dart';
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
  late Box<String> _urlBackupStatusBox;

  // Boxes
  static const String urlsBox = 'ModUrls';
  static const String metadataBox = 'ModMetadata';
  static const String appDataBox = 'AppData';
  static const String failedAssetsBox = 'FailedAssets';
  static const String backupFilesBox = 'BackupFiles';
  static const String urlBackupStatusBox = 'UrlBackupStatus';

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
      _urlBackupStatusBox = await Hive.openBox<String>(urlBackupStatusBox);

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

  // URL BACKUP STATUS
  /// Saves the backup status for a specific URL
  ///
  /// Data format: { "backupFilename": "ModName.ttsmod", "fileSize": 12345, "backedUpAt": "2025-12-23T10:30:00Z" }
  Future<void> saveUrlBackupStatus(String url, Map<String, dynamic> status) async {
    final jsonStr = jsonEncode(status);
    await _urlBackupStatusBox.put(url, jsonStr);
  }

  /// Gets the backup status for a specific URL
  Map<String, dynamic>? getUrlBackupStatus(String url) {
    final jsonStr = _urlBackupStatusBox.get(url);
    if (jsonStr == null) return null;

    try {
      return Map<String, dynamic>.from(jsonDecode(jsonStr));
    } catch (e) {
      debugPrint('Error decoding URL backup status for $url: $e');
      return null;
    }
  }

  /// Checks if a URL is backed up
  bool isUrlBackedUp(String url) {
    return _urlBackupStatusBox.containsKey(url);
  }

  /// Deletes backup status for a specific URL
  Future<void> deleteUrlBackupStatus(String url) async {
    await _urlBackupStatusBox.delete(url);
  }

  /// Gets all URLs that are backed up
  List<String> getAllBackedUpUrls() {
    return _urlBackupStatusBox.keys.cast<String>().toList();
  }

  /// Saves backup status for multiple URLs at once (bulk operation)
  Future<void> saveUrlBackupStatusBulk(Map<String, Map<String, dynamic>> urlStatuses) async {
    final Map<String, String> encoded = {};
    for (final entry in urlStatuses.entries) {
      encoded[entry.key] = jsonEncode(entry.value);
    }
    await _urlBackupStatusBox.putAll(encoded);
  }

  /// Gets backup statuses for multiple URLs at once
  Map<String, Map<String, dynamic>> getUrlBackupStatusBulk(List<String> urls) {
    final Map<String, Map<String, dynamic>> result = {};

    for (final url in urls) {
      final jsonStr = _urlBackupStatusBox.get(url);
      if (jsonStr != null) {
        try {
          result[url] = Map<String, dynamic>.from(jsonDecode(jsonStr));
        } catch (e) {
          debugPrint('Error decoding URL backup status for $url: $e');
        }
      }
    }

    return result;
  }

  /// Clears all URL backup status data
  Future<void> clearUrlBackupStatus() async {
    await _urlBackupStatusBox.clear();
  }
}
