import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncConnectionMode {
  synced,   // Online, 0 pending
  pending,  // Online, > 0 pending
  syncing,  // Currently in flight
  offline,  // Offline / unreachable
}

class SyncStatusState {
  final SyncConnectionMode mode;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final bool simulateOffline; // Debug toggle for showcase

  const SyncStatusState({
    this.mode = SyncConnectionMode.synced,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastError,
    this.simulateOffline = false,
  });

  SyncStatusState copyWith({
    SyncConnectionMode? mode,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? lastError,
    bool? simulateOffline,
  }) {
    return SyncStatusState(
      mode: mode ?? this.mode,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError ?? this.lastError,
      simulateOffline: simulateOffline ?? this.simulateOffline,
    );
  }
}

class SyncStatusNotifier extends Notifier<SyncStatusState> {
  @override
  SyncStatusState build() {
    return const SyncStatusState();
  }

  void updatePendingCount(int count) {
    if (state.simulateOffline) {
      state = state.copyWith(
        mode: SyncConnectionMode.offline,
        pendingCount: count,
      );
      return;
    }

    final mode = count == 0 ? SyncConnectionMode.synced : SyncConnectionMode.pending;
    state = state.copyWith(mode: mode, pendingCount: count);
  }

  void setSyncing() {
    state = state.copyWith(mode: SyncConnectionMode.syncing);
  }

  void setSynced({required DateTime at, required int remainingPending}) {
    state = state.copyWith(
      mode: remainingPending == 0 ? SyncConnectionMode.synced : SyncConnectionMode.pending,
      pendingCount: remainingPending,
      lastSyncedAt: at,
      lastError: null,
    );
  }

  void setOffline({required String reason}) {
    state = state.copyWith(
      mode: SyncConnectionMode.offline,
      lastError: reason,
    );
  }

  void toggleSimulateOffline() {
    final next = !state.simulateOffline;
    state = state.copyWith(
      simulateOffline: next,
      mode: next ? SyncConnectionMode.offline : (state.pendingCount == 0 ? SyncConnectionMode.synced : SyncConnectionMode.pending),
    );
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatusState>(
  SyncStatusNotifier.new,
);
