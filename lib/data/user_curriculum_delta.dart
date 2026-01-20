import 'package:flutter/foundation.dart';

import 'models.dart';

/// Minimaler Delta-Stand pro User: Cursor + optionale Add/Block-Listen.
class UserCurriculumDelta {
  final int? cursor; // Index des zuletzt bearbeiteten Items
  final List<String> blocked;
  final List<String> additions;
  final String? version;

  UserCurriculumDelta({
    this.cursor,
    this.blocked = const [],
    this.additions = const [],
    this.version,
  });

  factory UserCurriculumDelta.fromJson(Map<String, dynamic> json) {
    return UserCurriculumDelta(
      cursor: json['cursor'] is int ? json['cursor'] as int : (json['cursor'] as num?)?.toInt(),
      blocked: (json['blocked'] as List?)?.cast<String>() ?? const [],
      additions: (json['additions'] as List?)?.cast<String>() ?? const [],
      version: json['version'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (cursor != null) 'cursor': cursor,
        if (blocked.isNotEmpty) 'blocked': blocked,
        if (additions.isNotEmpty) 'additions': additions,
        if (version != null) 'version': version,
      };

  /// Wendet Delta auf ein Start-Curriculum an: filtert, hängt Additionen an.
  List<CurriculumEntry> applyTo(List<CurriculumEntry> base) {
    final List<CurriculumEntry> filtered =
        base.where((e) => !blocked.contains(e.uuid)).toList(growable: true);
    if (additions.isNotEmpty) {
      final startIdx = filtered.length;
      for (int i = 0; i < additions.length; i++) {
        filtered.add(CurriculumEntry(
          uuid: additions[i],
          index: 'custom_${startIdx + i}',
        ));
      }
    }
    return filtered;
  }

  /// Rotations-Offset: nächstes Item nach dem Cursor.
  int offsetForNext(List<CurriculumEntry> merged) {
    if (merged.isEmpty) return 0;
    final cursorPos = (cursor ?? -1).clamp(-1, merged.length - 1);
    final next = cursorPos + 1;
    if (next >= merged.length) return 0;
    return next;
  }

  UserCurriculumDelta withCursor(int nextCursor) {
    return UserCurriculumDelta(
      cursor: nextCursor,
      blocked: blocked,
      additions: additions,
      version: version,
    );
  }
}

/// Hilfsfunktion, um sicher eine Delta-Datei zu parsen.
UserCurriculumDelta? tryParseDelta(Map<String, dynamic>? json) {
  if (json == null) return null;
  try {
    return UserCurriculumDelta.fromJson(json);
  } catch (e) {
    debugPrint('[user-delta][parse-error] $e');
    return null;
  }
}
