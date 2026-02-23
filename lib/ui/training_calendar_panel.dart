import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'paper_month_calendar.dart';
import 'paper_week_calendar.dart';
import '../constants.dart';
import '../data/user_log_service.dart';
import '../data/user_summary_service.dart';
import '../flavor_config.dart';
import '../logic/log_storage.dart';

// Kalender-Widget: liest lokale Logs und zeigt 4 Wochen pro Seite.
// Die Anzeige wird regelmaessig neu geladen, damit neue Logs sichtbar sind.
class TrainingCalendarPanel extends StatefulWidget {
  const TrainingCalendarPanel({
    super.key,
    this.thresholdMinutes = 1,
    this.idleCapSeconds = 20,
    this.refreshInterval = const Duration(seconds: 30),
    this.fallbackDatesUtc,
    this.userId,
    this.workerHost,
    this.apiPrefix,
    this.thresholdRuns = 10,
  });

  final int thresholdMinutes;
  final int idleCapSeconds;
  final Duration refreshInterval;
  final List<DateTime>? fallbackDatesUtc;
  final String? userId;
  final String? workerHost;
  final String? apiPrefix;
  final int? thresholdRuns;

  @override
  State<TrainingCalendarPanel> createState() => _TrainingCalendarPanelState();
}

class _TrainingCalendarPanelState extends State<TrainingCalendarPanel> {
  // Eine Seite zeigt 4 Wochen = 28 Tage.
  static const int _weeksPerPage = 4;
  static const int _daysPerPage = 28;
  // Grosser Startwert, damit man nach vorne und hinten scrollen kann.
  static const int _pageAnchor = 1000;

  final PageController _pageController =
      PageController(initialPage: _pageAnchor);
  // Letzter geladener Stand aus den Logs.
  TrainingCalendarData _data =
      TrainingCalendarData.empty(thresholdSeconds: 5 * 60);
  Timer? _refreshTimer;
  bool _loading = false;
  int _currentPage = _pageAnchor;
  DateTime? _selectedDayKeyUtc;

  @override
  void initState() {
    super.initState();
    _data = TrainingCalendarData.empty(
      thresholdSeconds: widget.thresholdMinutes * 60,
    );
    _loadData();
    if (widget.refreshInterval > Duration.zero) {
      _refreshTimer =
          Timer.periodic(widget.refreshInterval, (_) => _loadData());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrainingCalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameFallbackDates(
            oldWidget.fallbackDatesUtc, widget.fallbackDatesUtc) ||
        oldWidget.userId != widget.userId ||
        oldWidget.workerHost != widget.workerHost ||
        oldWidget.apiPrefix != widget.apiPrefix ||
        oldWidget.thresholdMinutes != widget.thresholdMinutes ||
        oldWidget.thresholdRuns != widget.thresholdRuns) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (_loading) return;
    _loading = true;
    // Best-effort: Log-Fehler sollen die UI nicht blockieren.
    try {
      final data = await TrainingCalendarLoader.load(
        thresholdMinutes: widget.thresholdMinutes,
        idleCapSeconds: widget.idleCapSeconds,
        fallbackDatesUtc: widget.fallbackDatesUtc,
        userId: widget.userId,
        workerHost: widget.workerHost,
        apiPrefix: widget.apiPrefix,
        thresholdRuns: widget.thresholdRuns,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
      });
    } finally {
      _loading = false;
    }
  }

  bool _sameFallbackDates(List<DateTime>? a, List<DateTime>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    final aKeys = a.map(TrainingCalendarData.dayKey).toSet();
    final bKeys = b.map(TrainingCalendarData.dayKey).toSet();
    return setEquals(aKeys, bKeys);
  }

  int _todayIndexFromDays(DateTime today, List<DayStatus> days) {
    final dayKey = TrainingCalendarData.dayKey(today.toUtc());
    for (int i = 0; i < days.length; i++) {
      if (TrainingCalendarData.dayKey(days[i].date) == dayKey) return i;
    }
    return -1;
  }

  List<DayStatus> _daysForPage({
    required int page,
    required DateTime nowUtc,
  }) {
    final currentWeek = TrainingCalendarData.weekStartFor(nowUtc);
    final baseWeek = currentWeek.subtract(const Duration(days: 7 * 2));
    final offset = page - _pageAnchor;
    final weekStart = baseWeek.add(Duration(days: offset * _daysPerPage));
    return _data.buildWeeks(
      weekStart,
      weekCount: _weeksPerPage,
      nowUtc: nowUtc,
    );
  }

  DayStatus? _resolveSelectedDay(List<DayStatus> visibleDays, DateTime nowUtc) {
    final key = _selectedDayKeyUtc;
    if (key != null) {
      for (final day in visibleDays) {
        if (TrainingCalendarData.dayKey(day.date.toUtc()) == key) {
          return day;
        }
      }
    }
    final todayIndex = _todayIndexFromDays(nowUtc, visibleDays);
    if (todayIndex >= 0 && todayIndex < visibleDays.length) {
      return visibleDays[todayIndex];
    }
    return visibleDays.isNotEmpty ? visibleDays.last : null;
  }

  String _rangeLabel(BuildContext context, List<DayStatus> days) {
    if (days.isEmpty) return '';
    final localizations = MaterialLocalizations.of(context);
    final start = localizations.formatShortDate(days.first.date.toLocal());
    final end = localizations.formatShortDate(days.last.date.toLocal());
    return '$start - $end';
  }

  String _selectedDayLabel(BuildContext context, DayStatus day) {
    final localizations = MaterialLocalizations.of(context);
    final dayKey = TrainingCalendarData.dayKey(day.date.toUtc());
    final runs = _data.runsByDay[dayKey] ?? 0;
    final minutes = (day.activeSeconds / 60).floor();
    final dateText = localizations.formatMediumDate(day.date.toLocal());
    final minText = localizations.formatDecimal(minutes);
    final runText = localizations.formatDecimal(runs);
    return '$dateText • $minText min • $runText runs';
  }

  Future<void> _openDailyWordsProject() async {
    final uri = Uri.parse(activeFlavor.dashboardLandingUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  PaperStyle _styleForDate(DateTime date) {
    const tints = [
      Color(0xFFF4EFE6),
      Color(0xFFF3E9DA),
      Color(0xFFF1EDD4),
      Color(0xFFECF2E0),
      Color(0xFFE9F1E6),
      Color(0xFFE6F1EC),
      Color(0xFFE7F0F3),
      Color(0xFFEAEAF4),
      Color(0xFFF0E6F2),
      Color(0xFFF3E5E7),
      Color(0xFFF3E8DA),
      Color(0xFFF1EEE3),
    ];
    final monthIndex = (date.month - 1).clamp(0, 11).toInt();
    final tint = tints[monthIndex];
    final glow = Color.lerp(tint, Colors.white, 0.4) ?? tint;
    return PaperStyle(
      paperColor: Colors.transparent,
      gridLineColor: Colors.black,
      glowColor: glow,
      playerMarkColor: const Color(0xFF2E6BCB),
      rivalMarkColor: const Color(0xFFE27A2A),
      textureEnabled: false,
      showBinding: false,
      bindingHeight: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final visibleDays = _daysForPage(page: _currentPage, nowUtc: now);
    final selectedDay = _resolveSelectedDay(visibleDays, now);
    final rangeLabel = _rangeLabel(context, visibleDays);
    final selectedLabel =
        selectedDay == null ? '' : _selectedDayLabel(context, selectedDay);
    final headlineLabel = selectedLabel.isNotEmpty ? selectedLabel : rangeLabel;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headlineLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                child: Text(
                  headlineLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2F4B56),
                      ),
                ),
              ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      if (!mounted) return;
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final days = _daysForPage(page: index, nowUtc: now);
                      final todayIndex = _todayIndexFromDays(now, days);
                      final style = _styleForDate(
                        days[14].date,
                      );
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 6.0),
                          child: PaperMonthCalendar(
                            days: days,
                            todayIndex: todayIndex,
                            animateMarks: true,
                            onTapDay: (dayIndex) {
                              if (dayIndex < 0 || dayIndex >= days.length) {
                                return;
                              }
                              setState(() {
                                _selectedDayKeyUtc =
                                    TrainingCalendarData.dayKey(
                                  days[dayIndex].date.toUtc(),
                                );
                              });
                            },
                            paperStyle: style,
                            thresholdSeconds: _data.thresholdSeconds,
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: IgnorePointer(
                      child: Image.asset(
                        'assets/icons/writing_hand.png',
                        width: max(110.0, constraints.maxWidth * 0.3),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _openDailyWordsProject,
                  child: Text(
                    'DailyWord-project.org',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Liest logs/events.ndjson und berechnet aktive Sekunden pro Tag.
class TrainingCalendarLoader {
  // Kleiner Bonus, damit eine echte Aktivitaet ohne lange Dauer sichtbar ist.
  static const int _startBonusSeconds = 5;

  static Future<TrainingCalendarData> load({
    int thresholdMinutes = 5,
    int idleCapSeconds = 20,
    int? maxEventsPerSession,
    List<DateTime>? fallbackDatesUtc,
    String? userId,
    String? workerHost,
    String? apiPrefix,
    int? thresholdRuns = 10,
    int rangeDays = 60,
  }) async {
    final Map<String, _SessionData> sessions = {};
    final thresholdSeconds = thresholdMinutes * 60;
    if (userId != null && userId.isNotEmpty) {
      final now = DateTime.now().toUtc();
      final from = now.subtract(Duration(days: max(1, rangeDays) - 1));
      final summaryService = UserSummaryService(
        workerHost: (workerHost ?? defaultWorkerHost),
        apiPrefix: (apiPrefix ?? defaultApiPrefix),
      );
      final summary = await summaryService.fetchSummary(
        userId: userId,
        from: from,
        to: now,
      );
      if (summary.isNotEmpty) {
        final activeByDay = <DateTime, int>{};
        final runsByDay = <DateTime, int>{};
        for (final entry in summary.entries) {
          final key = TrainingCalendarData.dayKey(entry.key);
          activeByDay[key] = entry.value.seconds;
          if (entry.value.runs > 0) {
            runsByDay[key] = entry.value.runs;
          }
        }
        return TrainingCalendarData(
          activeSecondsByDay: activeByDay,
          runsByDay: runsByDay,
          thresholdSeconds: thresholdSeconds,
          thresholdRuns: thresholdRuns,
        );
      }

      try {
        final remoteLines = await _fetchRemoteLogLines(
          userId: userId,
          workerHost: workerHost ?? defaultWorkerHost,
          apiPrefix: apiPrefix ?? defaultApiPrefix,
        );
        if (remoteLines.isNotEmpty) {
          _accumulateSessionLines(sessions, remoteLines, maxEventsPerSession);
        }
      } catch (_) {
        // ignore remote log errors
      }
    }

    if (sessions.isEmpty) {
      try {
        final storage = LogStorage();
        final lines = await storage.readLines();
        _accumulateSessionLines(sessions, lines, maxEventsPerSession);
      } catch (_) {
        // ignore log errors
      }
    }

    final aggregates =
        _computeDailyAggregates(sessions, idleCapSeconds, _startBonusSeconds);
    if (aggregates.activeByDay.isEmpty &&
        fallbackDatesUtc != null &&
        fallbackDatesUtc.isNotEmpty) {
      final fallback = <DateTime, int>{};
      for (final date in fallbackDatesUtc) {
        final dayKey = TrainingCalendarData.dayKey(date);
        fallback[dayKey] = thresholdSeconds;
      }
      return TrainingCalendarData(
        activeSecondsByDay: fallback,
        runsByDay: const {},
        thresholdSeconds: thresholdSeconds,
        thresholdRuns: thresholdRuns,
      );
    }
    return TrainingCalendarData(
      activeSecondsByDay: aggregates.activeByDay,
      runsByDay: aggregates.runsByDay,
      thresholdSeconds: thresholdSeconds,
      thresholdRuns: thresholdRuns,
    );
  }

  static Future<List<String>> _fetchRemoteLogLines({
    required String userId,
    required String workerHost,
    required String apiPrefix,
  }) async {
    final service =
        UserLogService(workerHost: workerHost, apiPrefix: apiPrefix);
    return await service.fetchLines(userId: userId);
  }

  static void _accumulateSessionLines(
    Map<String, _SessionData> sessions,
    Iterable<String> lines,
    int? maxEventsPerSession,
  ) {
    for (final line in lines) {
      final raw = line.trim();
      if (raw.isEmpty) continue;
      Map<String, dynamic> data;
      try {
        data = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final tsStr = data['ts'] as String?;
      final session = data['session'] as String?;
      if (tsStr == null ||
          tsStr.isEmpty ||
          session == null ||
          session.isEmpty) {
        continue;
      }
      final ts = _parseTs(tsStr);
      if (ts == null) continue;

      final sessionData = sessions.putIfAbsent(session, _SessionData.new);
      sessionData.eventCount += 1;
      if (maxEventsPerSession != null &&
          sessionData.eventCount > maxEventsPerSession) {
        sessionData.exceededMax = true;
      }
      sessionData.timestampsMs.add(ts.millisecondsSinceEpoch);
      final type = data['type'] as String?;
      if (type == 'session_start') {
        final tsMs = ts.millisecondsSinceEpoch;
        sessionData.sessionStartMs = sessionData.sessionStartMs == null
            ? tsMs
            : min(sessionData.sessionStartMs!, tsMs);
      } else if (type == 'trial_result' || type == 'naming_result') {
        sessionData.runCount += 1;
      } else {
        // Nur "echte" Events zaehlen als Aktivitaet.
        sessionData.hasNonStart = true;
      }
    }
  }

  static DateTime? _parseTs(String tsStr) {
    if (tsStr.isEmpty) return null;
    try {
      return DateTime.parse(tsStr).toUtc();
    } catch (_) {
      return null;
    }
  }

  static int _computeActiveSeconds(
    List<int> timestampsMs,
    int idleCapSeconds,
    bool hasNonStart,
    int startBonusSeconds,
  ) {
    if (timestampsMs.isEmpty) return 0;
    timestampsMs.sort();
    double active = 0;
    for (int i = 0; i < timestampsMs.length - 1; i++) {
      final gapSeconds = (timestampsMs[i + 1] - timestampsMs[i]) / 1000.0;
      // Lange Pausen werden gedeckelt, damit Idle-Zeit nicht zaehlt.
      active += min(max(gapSeconds, 0.0), idleCapSeconds.toDouble());
    }
    // Kleiner Bonus, wenn die Session echte Aktivitaet hatte.
    if (hasNonStart) {
      active += startBonusSeconds;
    }
    return active.toInt();
  }

  static _DailyAggregates _computeDailyAggregates(
    Map<String, _SessionData> sessions,
    int idleCapSeconds,
    int startBonusSeconds,
  ) {
    final Map<DateTime, int> activeByDay = {};
    final Map<DateTime, int> runsByDay = {};
    for (final session in sessions.values) {
      if (session.timestampsMs.isEmpty) continue;
      final activeSeconds = _computeActiveSeconds(
        session.timestampsMs,
        idleCapSeconds,
        session.hasNonStart,
        startBonusSeconds,
      );
      final startMs = session.sessionStartMs ?? session.timestampsMs.first;
      final startDate = DateTime.fromMillisecondsSinceEpoch(
        startMs,
        isUtc: true,
      );
      // Wir ordnen die gesamte Session dem Tag des Session-Starts zu.
      final dayKey = TrainingCalendarData.dayKey(startDate);
      activeByDay[dayKey] = (activeByDay[dayKey] ?? 0) + activeSeconds;
      if (session.runCount > 0) {
        runsByDay[dayKey] = (runsByDay[dayKey] ?? 0) + session.runCount;
      }
    }
    return _DailyAggregates(activeByDay: activeByDay, runsByDay: runsByDay);
  }
}

// Wandelt aktive Sekunden pro Tag in Kalenderdaten um.
// Enthalten ist auch eine "Rival"-Logik fuer die Anzeige.
class TrainingCalendarData {
  final Map<DateTime, int> activeSecondsByDay;
  final Map<DateTime, int> runsByDay;
  final int thresholdSeconds;
  final int? thresholdRuns;
  // Rival soll in einem 14-Tage-Fenster 9 Tage erreichen.
  static const int rollingWindowDays = 14;
  static const int rollingQualifiedTarget = 9;

  TrainingCalendarData({
    required this.activeSecondsByDay,
    required this.runsByDay,
    required this.thresholdSeconds,
    required this.thresholdRuns,
  });

  static TrainingCalendarData empty({required int thresholdSeconds}) {
    return TrainingCalendarData(
      activeSecondsByDay: const {},
      runsByDay: const {},
      thresholdSeconds: thresholdSeconds,
      thresholdRuns: null,
    );
  }

  static DateTime dayKey(DateTime dateUtc) {
    final utc = dateUtc.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static DateTime weekStartFor(DateTime dateUtc) {
    final day = dayKey(dateUtc);
    final delta = day.weekday - DateTime.monday;
    return day.subtract(Duration(days: delta));
  }

  int idleDaysSince(DateTime nowUtc) {
    final todayKey = dayKey(nowUtc);
    DateTime? lastQualified;
    for (final entry in activeSecondsByDay.entries) {
      if (!_isQualified(entry.key)) continue;
      if (lastQualified == null) {
        lastQualified = entry.key;
      } else if (entry.key.isAfter(lastQualified)) {
        lastQualified = entry.key;
      }
    }
    final last = lastQualified;
    if (last == null) return 0;
    final diff = todayKey.difference(last).inDays;
    return diff < 0 ? 0 : diff;
  }

  List<DayStatus> buildWeeks(
    DateTime startWeek, {
    int weekCount = 4,
    DateTime? nowUtc,
  }) {
    final todayKey = dayKey((nowUtc ?? DateTime.now().toUtc()).toUtc());
    final totalDays = weekCount * 7;
    final base = weekStartFor(startWeek);
    final dateKeys = <DateTime>[];
    final activeSecondsList = <int>[];
    final playerQualified = <bool>[];

    for (int i = 0; i < totalDays; i++) {
      final date = base.add(Duration(days: i));
      final dateKey = dayKey(date);
      final activeSeconds = activeSecondsByDay[dateKey] ?? 0;
      final qualified = _isQualified(dateKey);
      dateKeys.add(dateKey);
      activeSecondsList.add(activeSeconds);
      playerQualified.add(qualified);
    }

    // Rival-Kreis immer auf Trainingstagen; Rival-only erst nach dem ersten Nutzer-Tag.
    final firstPlayerIndex = playerQualified.indexWhere((q) => q);
    final rivalDays = <DateTime>{};
    final weeksWithRival = <DateTime>{};
    final List<DayStatus> days = [];

    for (int i = 0; i < totalDays; i++) {
      final dateKey = dateKeys[i];
      final qualified = playerQualified[i];
      bool rivalQualified = qualified; // shared training day
      if (!qualified &&
          firstPlayerIndex != -1 &&
          i > firstPlayerIndex &&
          !dateKey.isAfter(todayKey)) {
        final weekStart = weekStartFor(dateKey);
        if (!weeksWithRival.contains(weekStart)) {
          // Rival-only wird pro Woche nur einmal gesetzt.
          // Pro Woche maximal eine Rival-Markierung setzen.
          final qualifiedCount = _qualifiedCountInWindow(
            dateKey,
            rollingWindowDays,
            rivalDays,
          );
          if (qualifiedCount < rollingQualifiedTarget) {
            rivalQualified = true;
            rivalDays.add(dateKey);
            weeksWithRival.add(weekStart);
          }
        }
      }
      days.add(
        DayStatus(
          date: dateKey,
          qualified: qualified,
          rivalQualified: rivalQualified,
          activeSeconds: activeSecondsList[i],
        ),
      );
    }
    return days;
  }

  int _qualifiedCountInWindow(
    DateTime endDateKey,
    int windowDays,
    Set<DateTime> rivalDays,
  ) {
    // Zaehlt qualifizierte Nutzer- und Rival-Tage im Rueckblick.
    int qualifiedCount = 0;
    for (int i = 0; i < windowDays; i++) {
      final date = endDateKey.subtract(Duration(days: i));
      final key = dayKey(date);
      if (rivalDays.contains(key)) {
        qualifiedCount += 1;
        continue;
      }
      if (_isQualified(key)) {
        qualifiedCount += 1;
      }
    }
    return qualifiedCount;
  }

  bool _isQualified(DateTime dateKey) {
    final activeSeconds = activeSecondsByDay[dateKey] ?? 0;
    if (activeSeconds >= thresholdSeconds) return true;
    final runTarget = thresholdRuns;
    if (runTarget == null || runTarget <= 0) return false;
    final runs = runsByDay[dateKey] ?? 0;
    return runs >= runTarget;
  }
}

class _SessionData {
  final List<int> timestampsMs = [];
  int? sessionStartMs;
  bool hasNonStart = false;
  int eventCount = 0;
  bool exceededMax = false;
  int runCount = 0;
}

class _DailyAggregates {
  const _DailyAggregates({
    required this.activeByDay,
    required this.runsByDay,
  });

  final Map<DateTime, int> activeByDay;
  final Map<DateTime, int> runsByDay;
}
