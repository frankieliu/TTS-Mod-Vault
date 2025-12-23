/// Information about a file in a backup
class BackupFileInfo {
  final int size;
  final int crc32;
  final int backedUpAt; // Timestamp in milliseconds since epoch

  BackupFileInfo({
    required this.size,
    required this.crc32,
    required this.backedUpAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'size': size,
      'crc32': crc32,
      'backedUpAt': backedUpAt,
    };
  }

  factory BackupFileInfo.fromJson(Map<String, dynamic> json) {
    return BackupFileInfo(
      size: json['size'] as int,
      crc32: json['crc32'] as int,
      backedUpAt: json['backedUpAt'] as int? ?? 0, // Default to 0 for old data
    );
  }

  DateTime get backedUpAtDateTime => DateTime.fromMillisecondsSinceEpoch(backedUpAt);
}
