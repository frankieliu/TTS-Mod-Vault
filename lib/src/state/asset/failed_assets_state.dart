import 'package:tts_mod_vault/src/state/asset/models/failed_asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';

class FailedAssetsState {
  // Maps: url -> FailedAsset for O(1) lookups
  final Map<String, FailedAsset> failedAssets;

  FailedAssetsState({
    required this.failedAssets,
  });

  FailedAssetsState.empty() : failedAssets = {};

  FailedAssetsState copyWith({
    Map<String, FailedAsset>? failedAssets,
  }) {
    return FailedAssetsState(
      failedAssets: failedAssets ?? this.failedAssets,
    );
  }

  int get totalFailedCount => failedAssets.length;

  int getFailedCountByType(AssetTypeEnum type) {
    return failedAssets.values.where((asset) => asset.type == type).length;
  }

  int getPermanentFailedCount() {
    return failedAssets.values
        .where((asset) => asset.errorType == DownloadErrorTypeEnum.permanent)
        .length;
  }

  int getTemporaryFailedCount() {
    return failedAssets.values
        .where((asset) => asset.errorType == DownloadErrorTypeEnum.temporary)
        .length;
  }

  List<FailedAsset> getFailedAssetsByType(AssetTypeEnum type) {
    return failedAssets.values
        .where((asset) => asset.type == type)
        .toList()
      ..sort((a, b) => b.failedAt.compareTo(a.failedAt)); // Most recent first
  }

  bool hasFailedAsset(String url) {
    return failedAssets.containsKey(url);
  }
}
