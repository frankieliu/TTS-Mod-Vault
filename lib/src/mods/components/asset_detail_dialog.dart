import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart';
import 'package:tts_mod_vault/src/state/asset/models/downloaded_file_info.dart';
import 'package:tts_mod_vault/src/state/asset/models/failed_asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL;

class AssetDetailDialog extends ConsumerWidget {
  final Asset asset;
  final AssetTypeEnum type;

  const AssetDetailDialog({
    super.key,
    required this.asset,
    required this.type,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatCrc32(int crc32) {
    if (crc32 == 0) return 'Not available';
    return '0x${crc32.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final storage = ref.watch(storageProvider);
    final failedAssetsState = ref.watch(failedAssetsProvider);

    final filename = getFileNameFromURL(asset.url);

    // Get downloaded file metadata
    final downloadedInfo = storage.getDownloadedFileInfo(filename);

    // Get failed asset metadata
    final failedAsset = failedAssetsState.failedAssets[asset.url];

    // Get backup metadata (from all backups)
    final allBackupMetadata = storage.getAllBackupFileMetadata();
    final backupEntries = <MapEntry<String, dynamic>>[];

    for (final backupEntry in allBackupMetadata.entries) {
      final backupName = backupEntry.key;
      final metadata = backupEntry.value;
      final fileInfo = metadata.files[filename];

      if (fileInfo != null) {
        backupEntries.add(MapEntry(backupName, fileInfo));
      }
    }

    return Dialog(
      child: Container(
        width: 700,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Asset Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic Info
                    _SectionHeader(title: 'Basic Information'),
                    _InfoRow(label: 'Filename', value: filename),
                    _InfoRow(label: 'Type', value: type.label),
                    _InfoRow(
                      label: 'URL',
                      value: asset.url,
                      copyable: true,
                    ),
                    const SizedBox(height: 16),

                    // Status
                    _SectionHeader(title: 'Status'),
                    Row(
                      children: [
                        if (asset.fileExists)
                          _StatusChip(
                            label: 'Downloaded',
                            color: Colors.green,
                            icon: Icons.check_circle,
                          ),
                        if (asset.isBackedUp)
                          _StatusChip(
                            label: 'Backed Up',
                            color: Colors.blue,
                            icon: Icons.backup,
                          ),
                        if (asset.hasFailed)
                          _StatusChip(
                            label: 'Failed',
                            color: failedAsset?.errorType.name == 'permanent'
                                ? Colors.red
                                : Colors.orange,
                            icon: Icons.error,
                          ),
                        if (!asset.fileExists && !asset.hasFailed)
                          _StatusChip(
                            label: 'Not Downloaded',
                            color: Colors.grey,
                            icon: Icons.circle_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Downloaded File Info
                    if (downloadedInfo != null) ...[
                      _SectionHeader(title: 'Downloaded File Metadata'),
                      _InfoRow(
                        label: 'File Path',
                        value: downloadedInfo.filepath,
                        copyable: true,
                      ),
                      _InfoRow(
                        label: 'Size',
                        value: _formatBytes(downloadedInfo.size),
                      ),
                      _InfoRow(
                        label: 'CRC32',
                        value: _formatCrc32(downloadedInfo.crc32),
                      ),
                      _InfoRow(
                        label: 'Downloaded At',
                        value: dateFormat.format(downloadedInfo.downloadedAtDateTime),
                      ),
                      const SizedBox(height: 16),
                    ] else if (asset.fileExists) ...[
                      _SectionHeader(title: 'Downloaded File Metadata'),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'File exists but metadata not yet populated',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Failed Download Info
                    if (failedAsset != null) ...[
                      _SectionHeader(title: 'Failed Download Metadata'),
                      _InfoRow(
                        label: 'Error Type',
                        value: failedAsset.errorType.label,
                      ),
                      _InfoRow(
                        label: 'Error Message',
                        value: failedAsset.errorMessage,
                      ),
                      _InfoRow(
                        label: 'Failed At',
                        value: dateFormat.format(failedAsset.failedAt),
                      ),
                      if (failedAsset.retryCount > 0)
                        _InfoRow(
                          label: 'Retry Count',
                          value: '${failedAsset.retryCount}',
                        ),
                      const SizedBox(height: 16),
                    ],

                    // Backup Info
                    if (backupEntries.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Backup Metadata (${backupEntries.length} backup${backupEntries.length > 1 ? 's' : ''})',
                      ),
                      ...backupEntries.map((entry) {
                        final backupName = entry.key;
                        final fileInfo = entry.value;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  backupName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _InfoRow(
                                  label: 'Size',
                                  value: _formatBytes(fileInfo.size),
                                  compact: true,
                                ),
                                _InfoRow(
                                  label: 'CRC32',
                                  value: _formatCrc32(fileInfo.crc32),
                                  compact: true,
                                ),
                                _InfoRow(
                                  label: 'Backed Up At',
                                  value: dateFormat.format(fileInfo.backedUpAtDateTime),
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ] else if (asset.isBackedUp) ...[
                      _SectionHeader(title: 'Backup Metadata'),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'File is backed up but metadata not yet loaded',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final bool compact;

  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2.0 : 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: compact ? 100 : 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: compact ? 12 : 14,
                color: Colors.grey[400],
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Chip(
        avatar: Icon(icon, color: color, size: 18),
        label: Text(label),
        backgroundColor: color.withOpacity(0.2),
        side: BorderSide(color: color),
      ),
    );
  }
}
