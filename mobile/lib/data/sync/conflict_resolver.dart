import 'dart:math';

/// Hybrid Logical Clock (HLC) format: "`<physical_ms>-<logical>-<device_id>`"
class Hlc implements Comparable<Hlc> {
  final int physicalMs;
  final int logical;
  final String deviceId;

  const Hlc({
    required this.physicalMs,
    required this.logical,
    required this.deviceId,
  });

  factory Hlc.now(String deviceId) {
    return Hlc(
      physicalMs: DateTime.now().millisecondsSinceEpoch,
      logical: 0,
      deviceId: deviceId,
    );
  }

  factory Hlc.parse(String raw) {
    final parts = raw.split('-');
    if (parts.length < 3) {
      throw FormatException('Invalid HLC format: $raw');
    }
    final physical = int.tryParse(parts[0]) ?? 0;
    final logical = int.tryParse(parts[1]) ?? 0;
    final deviceId = parts.sublist(2).join('-');
    return Hlc(
      physicalMs: physical,
      logical: logical,
      deviceId: deviceId,
    );
  }

  /// Increments local HLC given an optional remote incoming HLC.
  Hlc next({Hlc? incoming, required String localDeviceId}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final maxPhysical = max(physicalMs, max(nowMs, incoming?.physicalMs ?? 0));

    int nextLogical;
    if (maxPhysical == physicalMs && (incoming == null || maxPhysical == incoming.physicalMs)) {
      final maxLogical = max(logical, incoming?.logical ?? 0);
      nextLogical = maxLogical + 1;
    } else if (incoming != null && maxPhysical == incoming.physicalMs) {
      nextLogical = incoming.logical + 1;
    } else if (maxPhysical == physicalMs) {
      nextLogical = logical + 1;
    } else {
      nextLogical = 0;
    }

    return Hlc(
      physicalMs: maxPhysical,
      logical: nextLogical,
      deviceId: localDeviceId,
    );
  }

  @override
  int compareTo(Hlc other) {
    if (physicalMs != other.physicalMs) {
      return physicalMs.compareTo(other.physicalMs);
    }
    if (logical != other.logical) {
      return logical.compareTo(other.logical);
    }
    return deviceId.compareTo(other.deviceId);
  }

  @override
  String toString() => '$physicalMs-$logical-$deviceId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          runtimeType == other.runtimeType &&
          physicalMs == other.physicalMs &&
          logical == other.logical &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(physicalMs, logical, deviceId);
}

/// Incident representing stock that went below zero due to concurrent offline sales.
class OversoldIncident {
  final String productId;
  final String productName;
  final int currentStock;
  final int deficit; // abs(currentStock)
  final DateTime detectedAt;

  const OversoldIncident({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.deficit,
    required this.detectedAt,
  });
}

/// Resolves LWW per-field product updates using HLC.
class ProductConflictResolver {
  /// Evaluates whether incoming HLC string strictly wins over existing HLC string.
  static bool incomingWins({required String? incomingHlc, required String? currentHlc}) {
    if (incomingHlc == null || incomingHlc.isEmpty) return false;
    if (currentHlc == null || currentHlc.isEmpty) return true;

    try {
      final inH = Hlc.parse(incomingHlc);
      final curH = Hlc.parse(currentHlc);
      return inH.compareTo(curH) > 0;
    } catch (_) {
      return incomingHlc.compareTo(currentHlc) > 0;
    }
  }
}
