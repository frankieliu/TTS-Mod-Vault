import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;

/// Backup behavior types for mod operations
enum BackupBehavior {
  /// Don't backup if backup exists
  skip,

  /// Always replace existing backup
  replace,

  /// Only replace if files have changed (CRC32 check)
  replaceIfNecessary,

  /// Show interactive dialogs (single-mod only)
  interactive;

  /// Convert from BulkBackupBehaviorEnum
  static BackupBehavior fromBulkEnum(BulkBackupBehaviorEnum bulkEnum) {
    switch (bulkEnum) {
      case BulkBackupBehaviorEnum.skip:
        return BackupBehavior.skip;
      case BulkBackupBehaviorEnum.replace:
        return BackupBehavior.replace;
      case BulkBackupBehaviorEnum.replaceIfOutOfDate:
        return BackupBehavior.replaceIfNecessary;
    }
  }
}

/// Configuration for backup operations
class BackupConfig {
  final BackupBehavior behavior;
  final String? targetFolder;
  final bool force;
  final bool showDialogs;

  const BackupConfig({
    required this.behavior,
    this.targetFolder,
    this.force = false,
    this.showDialogs = false,
  });

  /// Factory for single-mod interactive mode
  factory BackupConfig.interactive({bool force = false}) {
    return BackupConfig(
      behavior: force ? BackupBehavior.replace : BackupBehavior.interactive,
      showDialogs: true,
      force: force,
    );
  }

  /// Factory for bulk operations
  factory BackupConfig.bulk({
    required BulkBackupBehaviorEnum behavior,
    String? folder,
  }) {
    return BackupConfig(
      behavior: BackupBehavior.fromBulkEnum(behavior),
      targetFolder: folder,
      showDialogs: false,
    );
  }
}

/// Result of backup decision logic
class BackupDecision {
  final bool shouldBackup;
  final String? targetFolder;
  final String reason;
  final bool needsConfirmation;

  const BackupDecision({
    required this.shouldBackup,
    this.targetFolder,
    required this.reason,
    this.needsConfirmation = false,
  });

  /// Factory for skip decision
  factory BackupDecision.skip(String reason) {
    return BackupDecision(
      shouldBackup: false,
      reason: reason,
    );
  }

  /// Factory for backup decision
  factory BackupDecision.backup({
    required String folder,
    required String reason,
    bool needsConfirmation = false,
  }) {
    return BackupDecision(
      shouldBackup: true,
      targetFolder: folder,
      reason: reason,
      needsConfirmation: needsConfirmation,
    );
  }
}
