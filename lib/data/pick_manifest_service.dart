// lib/data/pick_manifest_service.dart
import 'dart:convert';

import '../constants.dart';
import 'api_client.dart';
import 'models.dart';

class PickManifestRowTexts {
  final String l1;
  final String l2;
  final String? l2Phonetic;

  const PickManifestRowTexts({
    required this.l1,
    required this.l2,
    this.l2Phonetic,
  });
}

class PickManifestService {
  PickManifestService({required this.api});

  final ApiClient api;

  static const List<String> _fallbackKeys = [
    'pick_01_hoeflich.json',
  ];

  Future<List<String>> fetchManifestKeys() async {
    String? rawIndex;
    try {
      rawIndex = await api.loadTextFile(pickManifestIndexKey);
    } catch (_) {
      return List<String>.from(_fallbackKeys);
    }

    if (rawIndex != null) {
      try {
        final data = jsonDecode(rawIndex);
        if (data is Map<String, dynamic>) {
          final rawItems = data['manifests'];
          if (rawItems is List) {
            final keys = rawItems
                .map((entry) {
                  if (entry is String) return entry;
                  if (entry is Map && entry['key'] is String) {
                    return entry['key'] as String;
                  }
                  return null;
                })
                .whereType<String>()
                .toList();
            if (keys.isNotEmpty) return keys;
          }
        }
      } catch (_) {
        final extracted = _extractManifestNames(rawIndex);
        if (extracted.isNotEmpty) return extracted;
      }
    }
    return List<String>.from(_fallbackKeys);
  }

  Future<List<CurriculumEntry>> loadManifestEntries(String fileName) {
    return api.loadStartCurriculum(fileName, allowDefaultFallback: false);
  }

  Future<List<CurriculumEntry>> loadFullManifestEntries(String fileName) async {
    final data = await api.loadJsonFile(fileName);
    if (data is! Map<String, dynamic>) return const [];
    final items =
        (data['item_order'] as List?) ?? (data['items'] as List?) ?? [];
    return _entriesFromList(items);
  }

  Future<String> previewLabel(String fileName,
      {required String l1Lang, String? l2Lang}) async {
    final entries = await loadManifestEntries(fileName);
    if (entries.isEmpty) return fileName;
    final entry = entries.first;
    final textPair = await api.loadItemTexts(
      entry.uuid,
      l1Lang,
      nativeLang: l2Lang ?? l1Lang,
    );
    if (textPair.text.isNotEmpty) return textPair.text;
    return fileName;
  }

  Future<PickManifestRowTexts> fetchRowTexts(
    CurriculumEntry entry, {
    required String lang,
    String? nativeLang,
  }) async {
    final textPair = await api.loadItemTexts(
      entry.uuid,
      lang,
      nativeLang: nativeLang,
    );
    final l1 = textPair.nativeText?.isNotEmpty == true
        ? textPair.nativeText!
        : textPair.text;
    final l2 = textPair.text.isNotEmpty ? textPair.text : (textPair.nativeText ?? '');
    final l2Phonetic = textPair.phonetic?.trim().isNotEmpty == true
        ? textPair.phonetic
        : null;
    return PickManifestRowTexts(
      l1: l1,
      l2: l2,
      l2Phonetic: l2Phonetic,
    );
  }

  List<String> _extractManifestNames(String raw) {
    final seen = <String>{};
    final order = <String>[];
    final regex = RegExp(r'pick_[\w_]+\.json', caseSensitive: false);
    for (final match in regex.allMatches(raw)) {
      final name = match.group(0);
      if (name == null) continue;
      if (name.toLowerCase() == pickManifestIndexKey.toLowerCase()) continue;
      if (seen.add(name)) {
        order.add(name);
      }
    }
    return order;
  }

  List<CurriculumEntry> _entriesFromList(List items) {
    final entries = <CurriculumEntry>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final uuid = (map['uuid'] ?? map['id'])?.toString();
      if (uuid == null || uuid.isEmpty) continue;
      entries.add(CurriculumEntry.fromJson(map, fallbackIndex: i));
    }
    return entries;
  }
}
