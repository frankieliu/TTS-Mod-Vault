import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';

class Asset {
  final String url;
  final bool fileExists;
  final String? filePath;
  final bool hasFailed;
  final DownloadErrorTypeEnum? errorType;

  Asset({
    required this.url,
    required this.fileExists,
    this.filePath,
    this.hasFailed = false,
    this.errorType,
  });
}
