Future<void> loadSeedsAndInitialBatches({
  required Future<void> Function() loadSeeds,
  required int initialItemDownloadLimit,
  required int batchSize,
  required int Function() itemsLength,
  required int Function() curriculumLength,
  required int Function() nextOffset,
  required Future<void> Function(int offset, int batchLimit) loadBatch,
}) async {
  await loadSeeds();
  final total = curriculumLength();
  var offset = nextOffset();
  var attempts = 0;
  while (itemsLength() < initialItemDownloadLimit &&
      attempts < total + 1 &&
      total > 0) {
    final remaining = initialItemDownloadLimit - itemsLength();
    final batchLimit = remaining > 0
        ? (remaining < batchSize ? remaining : batchSize)
        : batchSize;
    await loadBatch(offset, batchLimit);
    attempts++;
    offset = nextOffset();
  }
}
