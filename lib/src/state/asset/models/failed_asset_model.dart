import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';

class FailedAsset {
  final String url;
  final AssetTypeEnum type;
  final DownloadErrorTypeEnum errorType;
  final String errorMessage;
  final DateTime failedAt;
  final int retryCount;

  FailedAsset({
    required this.url,
    required this.type,
    required this.errorType,
    required this.errorMessage,
    required this.failedAt,
    this.retryCount = 0,
  });

  FailedAsset copyWith({
    String? url,
    AssetTypeEnum? type,
    DownloadErrorTypeEnum? errorType,
    String? errorMessage,
    DateTime? failedAt,
    int? retryCount,
  }) {
    return FailedAsset(
      url: url ?? this.url,
      type: type ?? this.type,
      errorType: errorType ?? this.errorType,
      errorMessage: errorMessage ?? this.errorMessage,
      failedAt: failedAt ?? this.failedAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'type': type.name,
      'errorType': errorType.name,
      'errorMessage': errorMessage,
      'failedAt': failedAt.millisecondsSinceEpoch,
      'retryCount': retryCount,
    };
  }

  factory FailedAsset.fromJson(Map<String, dynamic> json) {
    return FailedAsset(
      url: json['url'],
      type: AssetTypeEnum.values.firstWhere((e) => e.name == json['type']),
      errorType: DownloadErrorTypeEnum.values
          .firstWhere((e) => e.name == json['errorType']),
      errorMessage: json['errorMessage'],
      failedAt: DateTime.fromMillisecondsSinceEpoch(json['failedAt']),
      retryCount: json['retryCount'] ?? 0,
    );
  }
}
