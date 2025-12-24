import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_mod_vault/src/state/asset/models/downloaded_file_info.dart';
import 'package:tts_mod_vault/src/state/backup/models/backup_file_metadata.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class AssetMetadataDialog extends ConsumerStatefulWidget {
  const AssetMetadataDialog({super.key});

  @override
  ConsumerState<AssetMetadataDialog> createState() => _AssetMetadataDialogState();
}

class _AssetMetadataDialogState extends ConsumerState<AssetMetadataDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 1000,
        height: 700,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Asset Metadata Viewer',
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
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Downloaded Files', icon: Icon(Icons.download_done)),
                Tab(text: 'Failed Downloads', icon: Icon(Icons.error)),
                Tab(text: 'Backed Up Files', icon: Icon(Icons.backup)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _DownloadedFilesTab(),
                  _FailedDownloadsTab(),
                  _BackedUpFilesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadedFilesTab extends ConsumerWidget {
  const _DownloadedFilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageProvider);
    final downloadedFiles = storage.getAllDownloadedFileInfo();
    final entries = downloadedFiles.entries.toList()
      ..sort((a, b) => b.value.downloadedAt.compareTo(a.value.downloadedAt));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Total: ${entries.length} files',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No downloaded file metadata'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _DownloadedFileItem(
                      filename: entry.key,
                      info: entry.value,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DownloadedFileItem extends StatelessWidget {
  final String filename;
  final DownloadedFileInfo info;

  const _DownloadedFileItem({
    required this.filename,
    required this.info,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatCrc32(int crc32) {
    if (crc32 == 0) return 'Not calculated';
    return '0x${crc32.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              filename,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _InfoChip(
                  icon: Icons.folder,
                  label: 'Path',
                  value: info.filepath,
                ),
                _InfoChip(
                  icon: Icons.storage,
                  label: 'Size',
                  value: _formatBytes(info.size),
                ),
                _InfoChip(
                  icon: Icons.fingerprint,
                  label: 'CRC32',
                  value: _formatCrc32(info.crc32),
                ),
                _InfoChip(
                  icon: Icons.access_time,
                  label: 'Downloaded',
                  value: dateFormat.format(info.downloadedAtDateTime),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedDownloadsTab extends ConsumerWidget {
  const _FailedDownloadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failedAssetsState = ref.watch(failedAssetsProvider);
    final failedAssets = failedAssetsState.failedAssets.values.toList()
      ..sort((a, b) => b.failedAt.compareTo(a.failedAt));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: ${failedAssets.length} failed',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (failedAssets.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () async {
                    await ref.read(failedAssetsProvider.notifier).clearAllFailedAssets();
                  },
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear All'),
                ),
            ],
          ),
        ),
        Expanded(
          child: failedAssets.isEmpty
              ? const Center(child: Text('No failed downloads'))
              : ListView.builder(
                  itemCount: failedAssets.length,
                  itemBuilder: (context, index) {
                    final asset = failedAssets[index];
                    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              asset.url,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                _InfoChip(
                                  icon: Icons.category,
                                  label: 'Type',
                                  value: asset.type.label,
                                ),
                                _InfoChip(
                                  icon: Icons.error,
                                  label: 'Error',
                                  value: asset.errorType.label,
                                  color: asset.errorType.name == 'permanent'
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                                _InfoChip(
                                  icon: Icons.access_time,
                                  label: 'Failed',
                                  value: dateFormat.format(asset.failedAt),
                                ),
                                if (asset.retryCount > 0)
                                  _InfoChip(
                                    icon: Icons.refresh,
                                    label: 'Retries',
                                    value: '${asset.retryCount}',
                                  ),
                              ],
                            ),
                            if (asset.errorMessage.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Error: ${asset.errorMessage}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BackedUpFilesTab extends ConsumerWidget {
  const _BackedUpFilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageProvider);
    final backupMetadata = storage.getAllBackupFileMetadata();
    final entries = backupMetadata.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Count total files across all backups
    int totalFiles = 0;
    for (final entry in entries) {
      totalFiles += entry.value.files.length;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Total: ${entries.length} backups with $totalFiles files',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No backup file metadata'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _BackupMetadataItem(
                      backupName: entry.key,
                      metadata: entry.value,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BackupMetadataItem extends StatefulWidget {
  final String backupName;
  final BackupFileMetadata metadata;

  const _BackupMetadataItem({
    required this.backupName,
    required this.metadata,
  });

  @override
  State<_BackupMetadataItem> createState() => _BackupMetadataItemState();
}

class _BackupMetadataItemState extends State<_BackupMetadataItem> {
  bool _isExpanded = false;

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
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final files = widget.metadata.files.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Calculate total size
    int totalSize = 0;
    for (final file in files) {
      totalSize += file.value.size;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              widget.backupName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${files.length} files • ${_formatBytes(totalSize)}'),
            trailing: IconButton(
              icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  ...files.map((file) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.key,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              Text(
                                'Size: ${_formatBytes(file.value.size)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                'CRC32: ${_formatCrc32(file.value.crc32)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                'Backed up: ${dateFormat.format(file.value.backedUpAtDateTime)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: color ?? Colors.grey[700],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
