import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sync/sync_status_notifier.dart';

class SyncBadge extends ConsumerWidget {
  final VoidCallback? onTap;

  const SyncBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);

    Color badgeColor;
    String label;
    IconData icon;

    switch (syncStatus.mode) {
      case SyncConnectionMode.synced:
        badgeColor = AppColors.accentSuccess;
        label = 'Tersinkron';
        icon = Icons.check_circle_outline;
        break;
      case SyncConnectionMode.pending:
        badgeColor = AppColors.accentWarning;
        label = '${syncStatus.pendingCount} Tertunda';
        icon = Icons.cloud_upload_outlined;
        break;
      case SyncConnectionMode.syncing:
        badgeColor = AppColors.accentPrimary;
        label = 'Sinkronisasi...';
        icon = Icons.sync;
        break;
      case SyncConnectionMode.offline:
        badgeColor = AppColors.textMuted;
        label = 'Offline';
        icon = Icons.cloud_off_outlined;
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: badgeColor, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: badgeColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
