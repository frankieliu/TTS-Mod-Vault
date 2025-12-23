import 'package:tts_mod_vault/src/state/backup/models/backup_file_info.dart';

/// Stores metadata about files contained in a backup
/// Maps asset filename -> file info (size, crc32)
class BackupFileMetadata {
  // Map of filename (basename without extension) -> file info
  final Map<String, BackupFileInfo> files;

  BackupFileMetadata({
    required this.files,
  });

  BackupFileMetadata.empty() : files = {};

  Map<String, dynamic> toJson() {
    return {
      'files': files.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory BackupFileMetadata.fromJson(Map<String, dynamic> json) {
    final filesMap = (json['files'] as Map<dynamic, dynamic>).map(
      (key, value) => MapEntry(
        key.toString(),
        BackupFileInfo.fromJson(value as Map<String, dynamic>),
      ),
    );

    return BackupFileMetadata(
      files: filesMap,
    );
  }

  bool containsFile(String filename) {
    return files.containsKey(filename);
  }

  int? getFileSize(String filename) {
    return files[filename]?.size;
  }

  int? getFileCrc32(String filename) {
    return files[filename]?.crc32;
  }

  int? getFileBackedUpAt(String filename) {
    return files[filename]?.backedUpAt;
  }

  DateTime? getFileBackedUpAtDateTime(String filename) {
    final timestamp = files[filename]?.backedUpAt;
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  BackupFileInfo? getFileInfo(String filename) {
    return files[filename];
  }

  int get totalFiles => files.length;
}
