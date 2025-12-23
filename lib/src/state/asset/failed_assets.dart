import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/asset/failed_assets_state.dart';
import 'package:tts_mod_vault/src/state/asset/models/failed_asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart' show storageProvider;

class FailedAssetsNotifier extends StateNotifier<FailedAssetsState> {
  final Ref ref;

  FailedAssetsNotifier(this.ref) : super(FailedAssetsState.empty());

  Future<void> loadFailedAssets() async {
    debugPrint('loadFailedAssets - started at ${DateTime.now()}');

    final storage = ref.read(storageProvider);
    final failedAssets = storage.getAllFailedAssets();

    state = FailedAssetsState(failedAssets: failedAssets);

    debugPrint('loadFailedAssets - loaded ${failedAssets.length} failed assets');
  }

  Future<void> addFailedAsset({
    required String url,
    required AssetTypeEnum type,
    required DownloadErrorTypeEnum errorType,
    required String errorMessage,
  }) async {
    final failedAsset = FailedAsset(
      url: url,
      type: type,
      errorType: errorType,
      errorMessage: errorMessage,
      failedAt: DateTime.now(),
      retryCount: state.failedAssets[url]?.retryCount ?? 0,
    );

    final storage = ref.read(storageProvider);
    await storage.saveFailedAsset(url, failedAsset);

    final updatedMap = Map<String, FailedAsset>.from(state.failedAssets)
      ..[url] = failedAsset;

    state = state.copyWith(failedAssets: updatedMap);

    debugPrint('Added failed asset: $url (${errorType.label})');
  }

  Future<void> removeFailedAsset(String url) async {
    final storage = ref.read(storageProvider);
    await storage.deleteFailedAsset(url);

    final updatedMap = Map<String, FailedAsset>.from(state.failedAssets)
      ..remove(url);

    state = state.copyWith(failedAssets: updatedMap);

    debugPrint('Removed failed asset: $url');
  }

  Future<void> clearAllFailedAssets() async {
    final storage = ref.read(storageProvider);
    await storage.clearFailedAssets();

    state = FailedAssetsState.empty();

    debugPrint('Cleared all failed assets');
  }

  Future<void> clearFailedAssetsByType(AssetTypeEnum type) async {
    final storage = ref.read(storageProvider);
    await storage.deleteFailedAssetsByType(type);

    final updatedMap = Map<String, FailedAsset>.from(state.failedAssets)
      ..removeWhere((key, asset) => asset.type == type);

    state = state.copyWith(failedAssets: updatedMap);

    debugPrint('Cleared failed assets for type: ${type.label}');
  }

  bool isAssetFailed(String url) {
    return state.hasFailedAsset(url);
  }

  Future<void> incrementRetryCount(String url) async {
    final failedAsset = state.failedAssets[url];
    if (failedAsset == null) return;

    final updated = failedAsset.copyWith(
      retryCount: failedAsset.retryCount + 1,
      failedAt: DateTime.now(),
    );

    final storage = ref.read(storageProvider);
    await storage.saveFailedAsset(url, updated);

    final updatedMap = Map<String, FailedAsset>.from(state.failedAssets)
      ..[url] = updated;

    state = state.copyWith(failedAssets: updatedMap);
  }
}
