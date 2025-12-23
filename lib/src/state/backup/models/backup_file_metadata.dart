/// Stores metadata about files contained in a backup
/// Maps asset filename -> file size for quick comparison
class BackupFileMetadata {
  // Map of filename (basename) -> size in bytes
  final Map<String, int> files;

  BackupFileMetadata({
    required this.files,
  });

  BackupFileMetadata.empty() : files = {};

  Map<String, dynamic> toJson() {
    return {
      'files': files,
    };
  }

  factory BackupFileMetadata.fromJson(Map<String, dynamic> json) {
    final filesMap = (json['files'] as Map<dynamic, dynamic>).map(
      (key, value) => MapEntry(key.toString(), value as int),
    );

    return BackupFileMetadata(
      files: filesMap,
    );
  }

  bool containsFile(String filename) {
    return files.containsKey(filename);
  }

  int? getFileSize(String filename) {
    return files[filename];
  }

  int get totalFiles => files.length;
}
