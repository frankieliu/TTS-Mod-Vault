/// Information about a downloaded asset file
class DownloadedFileInfo {
  final String filepath;
  final int size;
  final int crc32;
  final int downloadedAt; // Timestamp in milliseconds since epoch

  DownloadedFileInfo({
    required this.filepath,
    required this.size,
    required this.crc32,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'filepath': filepath,
      'size': size,
      'crc32': crc32,
      'downloadedAt': downloadedAt,
    };
  }

  factory DownloadedFileInfo.fromJson(Map<String, dynamic> json) {
    return DownloadedFileInfo(
      filepath: json['filepath'] as String,
      size: json['size'] as int,
      crc32: json['crc32'] as int? ?? 0,
      downloadedAt: json['downloadedAt'] as int? ?? 0,
    );
  }

  DateTime get downloadedAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(downloadedAt);
}
