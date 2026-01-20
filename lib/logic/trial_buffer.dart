// ------------------------------------------------------------
// Ziel (Laien): Geladene Items halten und daraus 2AFC-Trials bauen (Ziel vs. Ablenker).
// Verbindung: Bekommt Items aus ApiClient/robulingo_app.dart, liefert Trials an Session-UI.
// Tücken: Vermeidet Duplikate per imageSignature/uuid; Distractor-Auswahl nimmt erst Nachbarschaft (nächste 5, dann letzte 5), dann erweitert schrittweise.
// ------------------------------------------------------------
import 'dart:math';
import 'dart:typed_data';

import '../constants.dart';
import '../data/models.dart';

/// Maintains the in-memory item/trial lists and encapsulates how new trials
/// are built (distractor choice, image variants, target side).
class TrialBuffer {
  TrialBuffer({Random? random}) : _rand = random ?? Random();

  static const int _vicinityWindow = 5;
  final Random _rand;
  final List<ItemData> items = [];
  final List<Trial> trials = [];
  final Set<String> loadedUuids = {};
  final List<ItemData> _presentedTargets = [];

  void reset() {
    items.clear();
    trials.clear();
    loadedUuids.clear();
    _presentedTargets.clear();
  }

  /// Replaces the full item list (e.g. when restoring a cache) and rebuilds
  /// all trials from scratch.
  void replaceAll(List<ItemData> newItems) {
    final Set<String> seen = {};
    final List<ItemData> unique = [];
    for (final item in newItems) {
      if (seen.add(item.uuid)) {
        unique.add(item);
      }
    }
    items
      ..clear()
      ..addAll(unique);
    loadedUuids
      ..clear()
      ..addAll(unique.map((e) => e.uuid));
    rebuildTrials();
  }

  /// Adds fresh items and appends trials for them (without touching existing
  /// trials). Duplicates are ignored defensively.
  void addNewItems(List<ItemData> newItems) {
    if (newItems.isEmpty) return;
    final List<ItemData> uniques = [];
    for (final item in newItems) {
      if (loadedUuids.contains(item.uuid)) continue;
      loadedUuids.add(item.uuid);
      uniques.add(item);
    }
    if (uniques.isEmpty) return;
    items.addAll(uniques);
    _appendTrials(uniques);
  }

  /// Rebuilds the entire trial list based on the current items.
  void rebuildTrials() {
    trials.clear();
    _presentedTargets.clear();
    _appendTrials(items);
  }

  void _appendTrials(List<ItemData> newItems) {
    if (newItems.isEmpty || items.length < 2) return;
    for (final target in newItems) {
      final distractor = _pickDistractor(target);
      if (distractor == null) continue;
      _maybeAppendReviewTrial();
      final targetImg = _pickVariantBytes(target);
      final distractorImg = _pickVariantBytes(distractor);
      trials.add(Trial(
        target: target,
        distractor: distractor,
        targetOnLeft: _rand.nextBool(),
        targetImageBytes: targetImg,
        distractorImageBytes: distractorImg,
      ));
      _presentedTargets.add(target);
    }
  }

  void _maybeAppendReviewTrial() {
    if (reviewInterval <= 0) return;
    if ((trials.length + 1) % reviewInterval != 0) return;
    final review = _buildReviewTrial();
    if (review != null) {
      trials.add(review);
    }
  }

  Trial? _buildReviewTrial() {
    if (_presentedTargets.length < 2) return null;
    final target = _pickReviewTarget();
    if (target == null) return null;
    final distractor = _pickReviewDistractor(target);
    if (distractor == null) return null;
    return Trial(
      target: target,
      distractor: distractor,
      targetOnLeft: _rand.nextBool(),
      targetImageBytes: _pickVariantBytes(target),
      distractorImageBytes: _pickVariantBytes(distractor),
      isReview: true,
    );
  }

  ItemData? _pickReviewTarget() {
    if (_presentedTargets.length < 2) return null;
    final maxIndexExclusive = _presentedTargets.length - 1;
    if (maxIndexExclusive <= 0) return null;
    return _presentedTargets[_rand.nextInt(maxIndexExclusive)];
  }

  ItemData? _pickReviewDistractor(ItemData target) {
    final candidates = _presentedTargets
        .where((item) =>
            item.uuid != target.uuid &&
            item.imageSignature != target.imageSignature)
        .toList();
    if (candidates.isEmpty) return null;
    return candidates[_rand.nextInt(candidates.length)];
  }

  ItemData? _pickDistractor(ItemData target) {
    if (items.length < 2) return null;
    final idx = items.indexWhere((e) => e.uuid == target.uuid);
    if (idx == -1) return null;

    // Prefer items in the forward vicinity (next 5), then backward (last 5).
    final candidates = <ItemData>[];
    void addIfValid(int pos) {
      if (pos < 0 || pos >= items.length) return;
      final cand = items[pos];
      if (cand.uuid == target.uuid) return;
      if (cand.imageSignature == target.imageSignature) return;
      candidates.add(cand);
    }

    for (int offset = 1; offset <= _vicinityWindow; offset++) {
      addIfValid(idx + offset); // next items
    }
    for (int offset = 1; offset <= _vicinityWindow; offset++) {
      addIfValid(idx - offset); // last items
    }

    // If nothing suitable in the immediate window, expand outward by distance.
    for (int offset = _vicinityWindow + 1;
        candidates.isEmpty && offset < items.length;
        offset++) {
      addIfValid(idx + offset);
      addIfValid(idx - offset);
    }

    if (candidates.isEmpty) return null;
    return candidates[_rand.nextInt(candidates.length)];
  }

  Uint8List _pickVariantBytes(ItemData item) {
    if (item.imageVariants.isEmpty) return item.imageBytes;
    return item.imageVariants[_rand.nextInt(item.imageVariants.length)];
  }
}
