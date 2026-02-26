import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paper_week_calendar.dart';
import '../constants.dart';
import '../data/user_log_service.dart';
import '../data/user_summary_service.dart';
import '../logic/log_storage.dart';

const Map<String, String> _runsThisDayTooltipTexts = {
  'en': 'Runs this day',
  'de': 'Trainingseinheiten an diesem Tag',
  'ar': 'عدد المحاولات في هذا اليوم',
  'fr': 'Sessions de ce jour',
  'es': 'Sesiones de este día',
  'it': 'Sessioni di questo giorno',
  'ru': 'Запуски в этот день',
  'hi': 'इस दिन के प्रयास',
  'el': 'Συνεδρίες αυτής της ημέρας',
  'zh': '当天练习次数',
  'tr': 'Bu gündeki tekrar sayısı',
  'ja': 'この日の学習回数',
};

String _runsThisDayTooltip(String languageCode) {
  final code = languageCode.trim().toLowerCase();
  return _runsThisDayTooltipTexts[code] ?? _runsThisDayTooltipTexts['en']!;
}

String _normalizedLangCode(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'[-_]'));
  return parts.isNotEmpty ? parts.first : trimmed;
}

String _tooltipLanguageCode({required String? l1, required String? l2}) {
  final l1Code = _normalizedLangCode(l1);
  if (l1Code.isNotEmpty) return l1Code;
  final l2Code = _normalizedLangCode(l2);
  if (l2Code.isNotEmpty) return l2Code;
  return 'en';
}

// Kalender-Widget: liest Logs und zeigt eine echte Monatsansicht pro Seite.
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
    this.targetLanguage,
    this.nativeLanguage,
    this.thresholdRuns = 10,
  });

  final int thresholdMinutes;
  final int idleCapSeconds;
  final Duration refreshInterval;
  final List<DateTime>? fallbackDatesUtc;
  final String? userId;
  final String? workerHost;
  final String? apiPrefix;
  final String? targetLanguage;
  final String? nativeLanguage;
  final int? thresholdRuns;

  @override
  State<TrainingCalendarPanel> createState() => _TrainingCalendarPanelState();
}

class _TrainingCalendarPanelState extends State<TrainingCalendarPanel> {
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

  DateTime _monthStartForPage({
    required int page,
    required DateTime nowUtc,
  }) {
    final currentMonthStart = DateTime.utc(nowUtc.year, nowUtc.month, 1);
    final offset = page - _pageAnchor;
    return DateTime.utc(
      currentMonthStart.year,
      currentMonthStart.month + offset,
      1,
    );
  }

  int _pageForMonthStart({
    required DateTime monthStartUtc,
    required DateTime nowUtc,
  }) {
    final currentMonthStart = DateTime.utc(nowUtc.year, nowUtc.month, 1);
    final monthDiff = (monthStartUtc.year - currentMonthStart.year) * 12 +
        (monthStartUtc.month - currentMonthStart.month);
    return _pageAnchor + monthDiff;
  }

  _CalendarMonthPage _monthPageFor({
    required int page,
    required DateTime nowUtc,
  }) {
    final monthStart = _monthStartForPage(page: page, nowUtc: nowUtc);
    final monthEnd = DateTime.utc(monthStart.year, monthStart.month + 1, 0);
    final gridStart = TrainingCalendarData.weekStartFor(monthStart);
    final coveredDays = monthEnd.difference(gridStart).inDays + 1;
    final weekCount = ((coveredDays + 6) / 7).ceil().clamp(4, 6).toInt();
    final days = _data.buildWeeks(
      gridStart,
      weekCount: weekCount,
      nowUtc: nowUtc,
    );
    return _CalendarMonthPage(
      monthStartUtc: monthStart,
      weekCount: weekCount,
      days: days,
    );
  }

  Locale _localeForTargetLanguage(String? code) {
    final norm = (code ?? '').trim().toLowerCase();
    final localeId = speechLocaleOverrides[norm] ?? norm;
    if (localeId.contains('-')) {
      final parts = localeId.split('-');
      if (parts.length >= 2) {
        return Locale(parts[0], parts[1]);
      }
    }
    if (localeId.contains('_')) {
      final parts = localeId.split('_');
      if (parts.length >= 2) {
        return Locale(parts[0], parts[1]);
      }
    }
    return Locale(norm.isEmpty ? 'en' : norm);
  }

  List<String> _weekdayLabelsMondayFirst(MaterialLocalizations localizations) {
    final labels = localizations.narrowWeekdays;
    return <String>[
      ...labels.skip(1),
      labels.first,
    ];
  }

  bool _sameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  Future<void> _handleDayTap(
    DayStatus day,
    DateTime visibleMonthStartUtc,
    DateTime nowUtc,
  ) async {
    final dayKey = TrainingCalendarData.dayKey(day.date.toUtc());
    setState(() {
      _selectedDayKeyUtc = dayKey;
    });
    if (_sameMonth(day.date, visibleMonthStartUtc)) return;
    final targetMonthStart = DateTime.utc(day.date.year, day.date.month, 1);
    final targetPage = _pageForMonthStart(
      monthStartUtc: targetMonthStart,
      nowUtc: nowUtc,
    );
    if (targetPage == _currentPage) return;
    await _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final locale = _localeForTargetLanguage(widget.targetLanguage);
    final runsThisDayTooltip = _runsThisDayTooltip(
      _tooltipLanguageCode(
        l1: widget.nativeLanguage,
        l2: widget.targetLanguage,
      ),
    );
    final todayKey = TrainingCalendarData.dayKey(now);
    final selectedDayKey = _selectedDayKeyUtc ?? todayKey;
    final currentMonthPage = _monthPageFor(page: _currentPage, nowUtc: now);

    return Localizations.override(
      context: context,
      locale: locale,
      child: Builder(
        builder: (localizedContext) {
          final localizations = MaterialLocalizations.of(localizedContext);
          final monthLabel = localizations.formatMonthYear(
            currentMonthPage.monthStartUtc.toLocal(),
          );
          final weekdayLabels = _weekdayLabelsMondayFirst(localizations);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(localizedContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E2936),
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: List.generate(7, (index) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          weekdayLabels[index],
                          style: Theme.of(localizedContext)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF66707A),
                              ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    if (!mounted) return;
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final page = _monthPageFor(page: index, nowUtc: now);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: _CalendarMonthView(
                        page: page,
                        selectedDayKeyUtc: selectedDayKey,
                        todayDayKeyUtc: todayKey,
                        runsByDay: _data.runsByDay,
                        runsThisDayTooltip: runsThisDayTooltip,
                        onTapDay: (day) {
                          _handleDayTap(day, page.monthStartUtc, now);
                        },
                        dayLabelBuilder: (date) {
                          return localizations.formatDecimal(date.day);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CalendarMonthPage {
  const _CalendarMonthPage({
    required this.monthStartUtc,
    required this.weekCount,
    required this.days,
  });

  final DateTime monthStartUtc;
  final int weekCount;
  final List<DayStatus> days;
}

class _CalendarMonthView extends StatelessWidget {
  const _CalendarMonthView({
    required this.page,
    required this.selectedDayKeyUtc,
    required this.todayDayKeyUtc,
    required this.runsByDay,
    required this.runsThisDayTooltip,
    required this.onTapDay,
    required this.dayLabelBuilder,
  });

  final _CalendarMonthPage page;
  final DateTime selectedDayKeyUtc;
  final DateTime todayDayKeyUtc;
  final Map<DateTime, int> runsByDay;
  final String runsThisDayTooltip;
  final ValueChanged<DayStatus> onTapDay;
  final String Function(DateTime date) dayLabelBuilder;

  bool _sameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(page.weekCount, (week) {
        return Expanded(
          child: Row(
            children: List.generate(7, (weekday) {
              final index = week * 7 + weekday;
              if (index < 0 || index >= page.days.length) {
                return const Expanded(child: SizedBox.shrink());
              }
              final day = page.days[index];
              final key = TrainingCalendarData.dayKey(day.date.toUtc());
              final inMonth = _sameMonth(day.date, page.monthStartUtc);
              final runs = runsByDay[key] ?? 0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: _MonthDayCell(
                    dayLabel: dayLabelBuilder(day.date.toLocal()),
                    inMonth: inMonth,
                    isToday: key == todayDayKeyUtc,
                    isSelected: key == selectedDayKeyUtc,
                    completed: day.qualified,
                    runCount: runs,
                    runsThisDayTooltip: runsThisDayTooltip,
                    onTap: () => onTapDay(day),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.dayLabel,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.completed,
    required this.runCount,
    required this.runsThisDayTooltip,
    required this.onTap,
  });

  final String dayLabel;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool completed;
  final int runCount;
  final String runsThisDayTooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isToday ? const Color(0xFF2E7D32) : const Color(0xFFD7DCE2);
    final baseBgColor = inMonth ? Colors.white : const Color(0xFFF7F8FA);
    final bool used = runCount > 0;
    final usedBgColor =
        (used && inMonth) ? const Color(0x0F4B7BEC) : baseBgColor;
    final completedBgColor =
        (completed && inMonth) ? const Color(0x144B7BEC) : usedBgColor;
    final bgColor = isSelected ? const Color(0xFFEAF2FF) : completedBgColor;
    final textColor =
        inMonth ? const Color(0xFF1E2936) : const Color(0xFF9AA3AC);
    final tallyColor =
        completed ? const Color(0xFF2F63C8) : const Color(0xFF7F8C98);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: isToday ? 1.6 : 1.0,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  dayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                ),
              ),
              if (runCount > 0)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Tooltip(
                    message: runsThisDayTooltip,
                    child: SizedBox(
                      height: 16,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _TallyMarksPainter(
                          runCount: runCount,
                          color: tallyColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TallyMarksPainter extends CustomPainter {
  _TallyMarksPainter({
    required this.runCount,
    required this.color,
  });

  final int runCount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (runCount <= 0 || size.width <= 2 || size.height <= 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;
    const yTop = 1.0;
    final yBottom = size.height - 1.0;
    final groupCount = runCount ~/ 5;
    final units = runCount + groupCount * 0.9;
    final step = (size.width - 2.0) / max(1.0, units);
    final lineStep = step.clamp(0.2, 1.8).toDouble();
    final groupGap = lineStep * 0.9;
    double x = 1.0;

    for (int i = 0; i < runCount; i++) {
      canvas.drawLine(Offset(x, yTop), Offset(x, yBottom), paint);
      final isFifth = ((i + 1) % 5) == 0;
      if (isFifth) {
        final startX = x - 4 * lineStep;
        canvas.drawLine(
          Offset(startX - lineStep * 0.15, yBottom - 0.6),
          Offset(x + lineStep * 0.15, yTop + 0.6),
          paint,
        );
        x += groupGap;
      } else {
        x += lineStep;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TallyMarksPainter oldDelegate) {
    return oldDelegate.runCount != runCount || oldDelegate.color != color;
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
