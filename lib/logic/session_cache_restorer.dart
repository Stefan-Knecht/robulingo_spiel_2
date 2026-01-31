import '../data/models.dart';
import 'session_cache.dart';

class RestoredCache {
  RestoredCache({
    required this.items,
    required this.lang,
    required this.startKey,
    required this.nativeLang,
    required this.savedIndex,
    required this.savedUuid,
  });

  final List<ItemData> items;
  final String lang;
  final String startKey;
  final String? nativeLang;
  final int savedIndex;
  final String? savedUuid;
}

Future<RestoredCache?> readSessionCache(SessionCacheStore store) async {
  final cache = await store.load();
  if (cache == null) return null;
  final cachedItems = cache.items
      .map((c) => ItemData(
            uuid: c.uuid,
            index: c.index,
            position: c.position,
            text: c.text,
            nativeText: c.nativeText,
            phonetic: c.phonetic,
            hintRefsByLang: c.hintRefsByLang,
            imageBytes:
                c.imageVariants.isNotEmpty ? c.imageVariants.first : c.imageBytes,
            imageVariants:
                c.imageVariants.isEmpty ? [c.imageBytes] : c.imageVariants,
            audioUri: Uri.parse(c.audioUri),
            audioVariants: c.audioVariants.map(Uri.parse).toList(growable: false),
            imageSignature: c.imageSignature,
          ))
      .toList();
  if (cachedItems.length < 2) return null;
  final savedIndex =
      cache.lastIndex.clamp(0, cachedItems.isEmpty ? 0 : cachedItems.length - 1);
  final savedUuid = cachedItems.isNotEmpty ? cachedItems[savedIndex].uuid : null;
  return RestoredCache(
    items: cachedItems,
    lang: cache.lang,
    startKey: cache.startKey,
    nativeLang: cache.nativeLang,
    savedIndex: savedIndex,
    savedUuid: savedUuid,
  );
}
