import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_mod_vault/src/state/asset/models/failed_asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/download_error_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class FailedDownloadsDialog extends ConsumerWidget {
  const FailedDownloadsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failedAssetsState = ref.watch(failedAssetsProvider);
    final failedAssets = failedAssetsState.failedAssets.values.toList()
      ..sort((a, b) => b.failedAt.compareTo(a.failedAt));

    return Dialog(
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Failed Downloads (${failedAssets.length})',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: failedAssets.isEmpty
                          ? null
                          : () async {
                              await ref
                                  .read(downloadProvider.notifier)
                                  .retryFailedDownloads();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry All'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: failedAssets.isEmpty
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Clear All Failed Downloads'),
                                  content: const Text(
                                      'Are you sure you want to clear all failed download records?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                await ref
                                    .read(failedAssetsProvider.notifier)
                                    .clearAllFailedAssets();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              }
                            },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear All'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: failedAssets.isEmpty
                  ? const Center(
                      child: Text('No failed downloads'),
                    )
                  : ListView.builder(
                      itemCount: failedAssets.length,
                      itemBuilder: (context, index) {
                        final asset = failedAssets[index];
                        return _FailedAssetItem(asset: asset);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedAssetItem extends ConsumerWidget {
  final FailedAsset asset;

  const _FailedAssetItem({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  asset.errorType == DownloadErrorTypeEnum.permanent
                      ? Icons.error
                      : Icons.warning,
                  color: asset.errorType == DownloadErrorTypeEnum.permanent
                      ? Colors.red
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.url,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Chip(
                            label: Text(asset.type.label),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text(asset.errorType.label),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                asset.errorType == DownloadErrorTypeEnum.permanent
                                    ? Colors.red.withOpacity(0.2)
                                    : Colors.orange.withOpacity(0.2),
                          ),
                          Text(
                            'Failed: ${dateFormat.format(asset.failedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (asset.retryCount > 0)
                            Text(
                              'Retries: ${asset.retryCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        asset.errorMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await ref
                        .read(downloadProvider.notifier)
                        .retryFailedDownloads(specificUrls: [asset.url]);
                  },
                  tooltip: 'Retry this download',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    await ref
                        .read(failedAssetsProvider.notifier)
                        .removeFailedAsset(asset.url);
                  },
                  tooltip: 'Remove from failed list',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
