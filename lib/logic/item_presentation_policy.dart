import 'dart:collection';
import 'dart:math';

enum PresentationMode {
  comprehension,
  naming,
}

class ItemPresentationConfig {
  const ItemPresentationConfig({
    // Comprehension block
    this.comprehensionBlockSize = 10,
    this.comprehensionCoreSize = 9,
    this.comprehensionDownMaxAttempts = 15, // remove if attempts > 15
    this.distractorWindow = 10,

    // Naming qualification + blocks
    this.compWindowSize = 4,
    this.compWindowCorrectNeeded = 4, // 4/4
    this.namingBlockSize = 5,
    this.minQualifiedItemsToStart = 5, // >4
    this.namingMasteryCorrectThreshold = 1, // remove if correct > 1
    this.namingDownFromNamingMaxAttempts = 5, // remove if attempts > 5

    // Postpone/reactivate
    this.maxPostponedBlocks = 3,
  }) : assert(comprehensionBlockSize >= 2),
       assert(comprehensionCoreSize >= 1),
       assert(comprehensionCoreSize < comprehensionBlockSize);

  final int comprehensionBlockSize;
  final int comprehensionCoreSize;
  final int comprehensionDownMaxAttempts;
  final int distractorWindow;

  final int compWindowSize;
  final int compWindowCorrectNeeded;
  final int namingBlockSize;
  final int minQualifiedItemsToStart;
  final int namingMasteryCorrectThreshold;
  final int namingDownFromNamingMaxAttempts;

  final int maxPostponedBlocks;
}

class PresentationSlot {
  const PresentationSlot({
    required this.mode,
    required this.targetUuid,
  });

  final PresentationMode mode;
  final String targetUuid;
}

class PresentationAdvanceDecision {
  const PresentationAdvanceDecision({
    required this.nextSlot,
    required this.refillerQueueDirty,
  });

  final PresentationSlot nextSlot;
  final bool refillerQueueDirty;
}

class NamingAdvanceDecision {
  const NamingAdvanceDecision({
    required this.nextSlot,
    required this.refillerQueueDirty,
  });

  final PresentationSlot nextSlot;
  final bool refillerQueueDirty;
}

/// Item presentation policy:
/// - fixed repeating comprehension block of 10 (slots 1..9 curriculum, slot 10 from refiller FIFO or curriculum)
/// - distractors from previous 10 curriculum items (else next 10)
/// - up-from-comprehension: 4/4 correct comprehension qualifies for naming and removes from comprehension
/// - down-from-comprehension: remove after >15 answered comprehension attempts
/// - naming blocks of 5 (priority when available), postpone/reactivate FIFO blocks (max 3)
/// - up/down-from-naming removal returns items to refiller FIFO
class ItemPresentationPolicy {
  ItemPresentationPolicy({ItemPresentationConfig? config, Random? random})
      : config = config ?? const ItemPresentationConfig(),
        _rand = random ?? Random();

  final ItemPresentationConfig config;
  final Random _rand;

  List<String> _curriculum = const [];
  final Map<String, int> _indexByUuid = {};

  int _nextCurriculumIndex = 0;

  final List<String> _comprehensionBlock = [];
  int _comprehensionIndex = 0;

  final Queue<String> _refillerQueue = Queue<String>();
  bool _refillerDirty = false;

  // Comprehension attempt counts (answered attempts only)
  final Map<String, int> _comprehensionAttempts = {};

  // Rolling window for naming qualification
  final Map<String, List<bool>> _compLast = {};

  // Naming eligibility + pool
  final Set<String> readyToName = {};
  final List<String> _namingPool = [];
  int _poolCursor = 0;

  // Once an item is removed from naming (mastery or overuse), keep it out of naming
  // for the remainder of the session. It can still reappear via refiller/comprehension.
  final Set<String> _blockedFromNaming = {};

  // Active naming block
  List<String>? _activeNamingBlock;
  int _activeNamingIndex = 0;

  // Postponed naming blocks (FIFO)
  final Queue<List<String>> _postponedNamingBlocks = Queue<List<String>>();

  // Resume point in comprehension (block index 0..9)
  int? _resumeComprehensionIndex;

  bool _lastSlotFromRefiller = false;

  bool get hasPostponedNamingBlocks => _postponedNamingBlocks.isNotEmpty;

  int get comprehensionIndex => _comprehensionIndex;

  List<String> get comprehensionBlockUuids =>
      List<String>.unmodifiable(_comprehensionBlock);

  void setComprehensionIndex(int idx) {
    if (_comprehensionBlock.isEmpty) return;
    _comprehensionIndex = idx.clamp(0, _comprehensionBlock.length - 1);
  }

  List<String> get refillerQueueSnapshot =>
      List<String>.unmodifiable(_refillerQueue.toList());

  bool get isNamingActive =>
      _activeNamingBlock != null && _activeNamingIndex < _activeNamingBlock!.length;

  PresentationMode get mode => isNamingActive ? PresentationMode.naming : PresentationMode.comprehension;

  bool get isCurrentSlotFromRefiller {
    if (mode != PresentationMode.comprehension) return false;
    if (!_lastSlotFromRefiller) return false;
    final lastIdx = config.comprehensionBlockSize - 1;
    if (_comprehensionBlock.length <= lastIdx) return false;
    return _comprehensionIndex == lastIdx;
  }

  PresentationSlot get currentSlot {
    if (isNamingActive) {
      return PresentationSlot(
        mode: PresentationMode.naming,
        targetUuid: _activeNamingBlock![_activeNamingIndex],
      );
    }
    if (_comprehensionBlock.isEmpty) {
      return const PresentationSlot(mode: PresentationMode.comprehension, targetUuid: '');
    }
    return PresentationSlot(
      mode: PresentationMode.comprehension,
      targetUuid: _comprehensionBlock[_comprehensionIndex],
    );
  }

  void reset() {
    _curriculum = const [];
    _indexByUuid.clear();
    _nextCurriculumIndex = 0;
    _comprehensionBlock.clear();
    _comprehensionIndex = 0;
    _refillerQueue.clear();
    _refillerDirty = false;
    _comprehensionAttempts.clear();
    _compLast.clear();
    readyToName.clear();
    _namingPool.clear();
    _poolCursor = 0;
    _blockedFromNaming.clear();
    _activeNamingBlock = null;
    _activeNamingIndex = 0;
    _postponedNamingBlocks.clear();
    _resumeComprehensionIndex = null;
    _lastSlotFromRefiller = false;
  }

  void setRefillerQueue(List<String> uuids) {
    _refillerQueue
      ..clear()
      ..addAll(uuids.where((e) => e.trim().isNotEmpty));
    _refillerDirty = true;
  }

  bool consumeRefillerDirtyFlag() {
    final v = _refillerDirty;
    _refillerDirty = false;
    return v;
  }

  void initializeComprehensionBlock({
    required List<String> curriculumUuids,
    required int startIndex,
    List<String> refillerQueue = const [],
  }) {
    reset();
    _curriculum = List<String>.from(curriculumUuids);
    _indexByUuid
      ..clear()
      ..addEntries(_curriculum.asMap().entries.map((e) => MapEntry(e.value, e.key)));

    if (refillerQueue.isNotEmpty) {
      _refillerQueue.addAll(refillerQueue);
    }

    if (_curriculum.isEmpty) return;
    final n = _curriculum.length;
    final normalizedStart = ((startIndex % n) + n) % n;

    _comprehensionBlock.clear();
    for (int i = 0; i < config.comprehensionCoreSize; i++) {
      _comprehensionBlock.add(_curriculum[(normalizedStart + i) % n]);
    }
    _nextCurriculumIndex = (normalizedStart + config.comprehensionCoreSize) % n;

    // Fill the remaining slots (including slot 10) from curriculum first, then override last slot from refiller.
    while (_comprehensionBlock.length < config.comprehensionBlockSize) {
      _comprehensionBlock.add(_takeNextCurriculum());
    }

    // Slot #10 is the last slot: prefer refiller FIFO.
    final lastIdx = config.comprehensionBlockSize - 1;
    final refill = _dequeueRefiller();
    if (refill != null) {
      _comprehensionBlock[lastIdx] = refill;
      _lastSlotFromRefiller = true;
    } else {
      _lastSlotFromRefiller = false;
    }

    _comprehensionIndex = 0;
  }

  /// Returns the set of UUIDs to prefetch for the current comprehension block:
  /// - block targets
  /// - each target's distractor neighborhood (prev 10 else next 10 in curriculum)
  Set<String> prefetchSetForComprehensionBlock() {
    final out = <String>{};
    if (_curriculum.isEmpty) return out;
    for (final uuid in _comprehensionBlock) {
      out.add(uuid);
      out.addAll(_distractorNeighborhood(uuid));
    }
    return out;
  }

  /// Returns the set of UUIDs to prefetch for a single target UUID:
  /// - the target
  /// - its distractor neighborhood (previous window if possible, else subsequent)
  Set<String> prefetchSetForTarget(String uuid) {
    final out = <String>{};
    if (uuid.trim().isEmpty) return out;
    out.add(uuid);
    out.addAll(_distractorNeighborhood(uuid));
    return out;
  }

  String? pickDistractorUuid(String targetUuid, {Set<String>? exclude}) {
    final ex = exclude ?? const <String>{};
    final candidates = _distractorNeighborhood(targetUuid)
        .where((u) => u != targetUuid && !ex.contains(u))
        .toList();
    if (candidates.isEmpty) return null;
    return candidates[_rand.nextInt(candidates.length)];
  }

  /// Apply a comprehension answer. Updates rolling window and attempt counts.
  /// May remove the target from comprehension (up/down-from-comprehension),
  /// may start naming (priority) if possible.
  PresentationAdvanceDecision onComprehensionAnswered({
    required String uuid,
    required bool correct,
    required bool namingDisabled,
    required bool namingInProgress,
  }) {
    bool refillerDirty = false;

    final attempts = (_comprehensionAttempts[uuid] ?? 0) + 1;
    _comprehensionAttempts[uuid] = attempts;

    final window = _compLast.putIfAbsent(uuid, () => <bool>[]);
    window.add(correct);
    if (window.length > config.compWindowSize) {
      window.removeAt(0);
    }
    final qualified = window.length == config.compWindowSize &&
        window.where((e) => e).length == config.compWindowCorrectNeeded;

    final isInBlock = _comprehensionBlock.contains(uuid);

    // Up-from-comprehension: promote to naming and remove from block.
    if (qualified) {
      if (_blockedFromNaming.contains(uuid)) {
        // Already removed from naming earlier in this session → do not re-qualify.
        // Keep spacing by returning it to refiller if it currently sits in the block.
        if (isInBlock) {
          _replaceComprehensionBlockItem(uuid, enqueueToRefiller: true);
          refillerDirty = true;
        }
        // Reset the window so we don't keep "qualifying" every time.
        _compLast.remove(uuid);
      } else {
        if (readyToName.add(uuid) && !_namingPool.contains(uuid)) {
          _namingPool.add(uuid);
        } else if (!_namingPool.contains(uuid)) {
          _namingPool.add(uuid);
        }
        if (isInBlock) {
          _replaceComprehensionBlockItem(uuid, enqueueToRefiller: false);
        }
      }
    } else if (attempts > config.comprehensionDownMaxAttempts && isInBlock) {
      // Down-from-comprehension: remove to refiller.
      _replaceComprehensionBlockItem(uuid, enqueueToRefiller: true);
      refillerDirty = true;
    }

    // Advance within 10-slot comprehension cycle if still in comprehension mode.
    if (!isNamingActive) {
      _comprehensionIndex =
          (_comprehensionIndex + 1) % max(1, _comprehensionBlock.length);
    }

    // Naming priority: start a fresh naming block if possible and not postponed.
    if (!namingDisabled &&
        !namingInProgress &&
        !isNamingActive &&
        readyToName.length >= config.minQualifiedItemsToStart &&
        _namingPool.length >= config.namingBlockSize) {
      _resumeComprehensionIndex ??= _comprehensionIndex;
      _activeNamingBlock = _buildNextNamingBlock();
      _activeNamingIndex = 0;
    }

    final slot = currentSlot;
    refillerDirty = refillerDirty || consumeRefillerDirtyFlag();
    return PresentationAdvanceDecision(nextSlot: slot, refillerQueueDirty: refillerDirty);
  }

  /// Called by UI when user postpones naming. Returns the next comprehension slot.
  PresentationSlot postponeActiveNamingBlock() {
    if (!isNamingActive) return currentSlot;
    // Postpone the whole current naming block (not only the remaining items).
    // This "jumps" the entire block back into the postponed FIFO.
    final wholeBlock = _activeNamingBlock!
        .where((u) => readyToName.contains(u))
        .toList();
    if (wholeBlock.isNotEmpty) {
      _postponedNamingBlocks.addLast(wholeBlock);
      while (_postponedNamingBlocks.length > config.maxPostponedBlocks) {
        _postponedNamingBlocks.removeFirst();
      }
    }
    _activeNamingBlock = null;
    _activeNamingIndex = 0;
    final resume = _resumeComprehensionIndex;
    _resumeComprehensionIndex = null;
    if (resume != null) return _comprehensionSlotAt(resume);
    return currentSlot;
  }

  /// Reactivate postponed naming blocks FIFO. If none, stays in comprehension.
  PresentationSlot reactivatePostponedNamingBlocks({
    required bool namingDisabled,
    required bool namingInProgress,
  }) {
    if (namingDisabled || namingInProgress) return currentSlot;
    if (isNamingActive) return currentSlot;
    while (_postponedNamingBlocks.isNotEmpty) {
      final next = _postponedNamingBlocks.removeFirst()
          .where((u) => readyToName.contains(u))
          .toList();
      if (next.isEmpty) continue;
      _resumeComprehensionIndex ??= _comprehensionIndex;
      _activeNamingBlock = next;
      _activeNamingIndex = 0;
      return currentSlot;
    }
    return currentSlot;
  }

  /// Called after a naming attempt concludes (success/failure/skip) to advance.
  NamingAdvanceDecision onNamingAttemptFinished({
    required String currentUuid,
    required bool namingDisabled,
    required bool namingInProgress,
  }) {
    bool refillerDirty = false;

    if (!isNamingActive) {
      return NamingAdvanceDecision(nextSlot: currentSlot, refillerQueueDirty: false);
    }

    if (_activeNamingIndex < _activeNamingBlock!.length &&
        _activeNamingBlock![_activeNamingIndex] == currentUuid) {
      _activeNamingIndex++;
    }
    while (_activeNamingIndex < _activeNamingBlock!.length &&
        !readyToName.contains(_activeNamingBlock![_activeNamingIndex])) {
      _activeNamingIndex++;
    }

    if (_activeNamingIndex >= _activeNamingBlock!.length) {
      _activeNamingBlock = null;
      _activeNamingIndex = 0;

      // Continue draining postponed blocks FIFO automatically.
      while (_postponedNamingBlocks.isNotEmpty) {
        final next = _postponedNamingBlocks.removeFirst()
            .where((u) => readyToName.contains(u))
            .toList();
        if (next.isEmpty) continue;
        _activeNamingBlock = next;
        _activeNamingIndex = 0;
        final slot = currentSlot;
        refillerDirty = refillerDirty || consumeRefillerDirtyFlag();
        return NamingAdvanceDecision(nextSlot: slot, refillerQueueDirty: refillerDirty);
      }

      final resume = _resumeComprehensionIndex;
      _resumeComprehensionIndex = null;
      if (resume != null) {
        _comprehensionIndex = resume.clamp(0, max(0, _comprehensionBlock.length - 1));
      }

      final slot = currentSlot;
      refillerDirty = refillerDirty || consumeRefillerDirtyFlag();
      return NamingAdvanceDecision(nextSlot: slot, refillerQueueDirty: refillerDirty);
    }

    final slot = currentSlot;
    refillerDirty = refillerDirty || consumeRefillerDirtyFlag();
    return NamingAdvanceDecision(nextSlot: slot, refillerQueueDirty: refillerDirty);
  }

  /// If naming stats cross thresholds, remove item from naming and enqueue it to refiller FIFO.
  bool onNamingStatsUpdated({
    required String uuid,
    required int namingAttempts,
    required int namingCorrect,
  }) {
    final shouldRemove = namingCorrect > config.namingMasteryCorrectThreshold ||
        namingAttempts > config.namingDownFromNamingMaxAttempts;
    if (!shouldRemove) return false;
    _blockedFromNaming.add(uuid);
    readyToName.remove(uuid);
    _namingPool.remove(uuid);
    // Important: reset the comprehension qualification window. Otherwise, once the item
    // reappears via refiller/comprehension, it can immediately re-qualify for naming
    // based on stale 4/4 history, causing "more than 3 correct namings" within a session.
    _compLast.remove(uuid);
    if (isNamingActive && _activeNamingBlock != null) {
      _activeNamingBlock = _activeNamingBlock!.where((u) => u != uuid).toList();
      if (_activeNamingIndex > _activeNamingBlock!.length) {
        _activeNamingIndex = _activeNamingBlock!.length;
      }
    }
    if (_postponedNamingBlocks.isNotEmpty) {
      final updated = Queue<List<String>>();
      for (final block in _postponedNamingBlocks) {
        final filtered = block.where((u) => u != uuid).toList();
        if (filtered.isNotEmpty) updated.add(filtered);
      }
      _postponedNamingBlocks
        ..clear()
        ..addAll(updated);
    }
    _enqueueRefiller(uuid);
    return true;
  }

  PresentationSlot _comprehensionSlotAt(int idx) {
    if (_comprehensionBlock.isEmpty) {
      return const PresentationSlot(mode: PresentationMode.comprehension, targetUuid: '');
    }
    final i = idx.clamp(0, _comprehensionBlock.length - 1);
    return PresentationSlot(
      mode: PresentationMode.comprehension,
      targetUuid: _comprehensionBlock[i],
    );
  }

  void _replaceComprehensionBlockItem(String uuid, {required bool enqueueToRefiller}) {
    if (_comprehensionBlock.isEmpty) return;
    final idx = _comprehensionBlock.indexOf(uuid);
    if (idx < 0) return;
    if (enqueueToRefiller) {
      _enqueueRefiller(uuid);
    }
    final int lastIdx = config.comprehensionBlockSize - 1;
    String replacement;
    if (idx == lastIdx) {
      final refill = _dequeueRefiller();
      if (refill != null) {
        replacement = refill;
        _lastSlotFromRefiller = true;
      } else {
        replacement = _takeNextCurriculum();
        _lastSlotFromRefiller = false;
      }
    } else {
      replacement = _takeNextCurriculum();
    }
    _comprehensionBlock[idx] = replacement;
  }

  void _enqueueRefiller(String uuid) {
    _refillerQueue.addLast(uuid);
    _refillerDirty = true;
  }

  String? _dequeueRefiller() {
    while (_refillerQueue.isNotEmpty) {
      final u = _refillerQueue.removeFirst();
      if (u.trim().isNotEmpty) {
        _refillerDirty = true;
        return u;
      }
    }
    return null;
  }

  String _takeNextCurriculum() {
    if (_curriculum.isEmpty) return '';
    final uuid = _curriculum[_nextCurriculumIndex % _curriculum.length];
    _nextCurriculumIndex = (_nextCurriculumIndex + 1) % _curriculum.length;
    return uuid;
  }

  List<String> _buildNextNamingBlock() {
    if (_namingPool.length < config.namingBlockSize) return const [];
    final block = <String>[];
    int guard = 0;
    while (block.length < config.namingBlockSize && guard < _namingPool.length * 3) {
      final idx = _poolCursor % _namingPool.length;
      _poolCursor++;
      final uuid = _namingPool[idx];
      if (!block.contains(uuid)) {
        block.add(uuid);
      }
      guard++;
    }
    return block;
  }

  List<String> _distractorNeighborhood(String uuid) {
    if (_curriculum.isEmpty) return const [];
    final idx = _indexByUuid[uuid];
    if (idx == null) return const [];
    final n = _curriculum.length;
    if (n < 2) return const [];
    final window = min(config.distractorWindow, n - 1);

    // Spec: use a random one of the previous N curriculum items as distractor;
    // if there are fewer than N previous items, use the subsequent N items.
    if (idx >= window) {
      return _curriculum.sublist(idx - window, idx);
    }

    final nextStart = idx + 1;
    final nextEnd = min(n, nextStart + window);
    final next = _curriculum.sublist(nextStart, nextEnd);
    if (next.isNotEmpty) return next;

    final prevStart = max(0, idx - window);
    return _curriculum.sublist(prevStart, idx);
  }
}
