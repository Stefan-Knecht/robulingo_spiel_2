import 'package:flutter/material.dart';

import 'paper_week_calendar.dart';

class PaperCalendarDemo extends StatefulWidget {
  const PaperCalendarDemo({super.key});

  @override
  State<PaperCalendarDemo> createState() => _PaperCalendarDemoState();
}

class _PaperCalendarDemoState extends State<PaperCalendarDemo> {
  late List<DayStatus> _days;
  late int _todayIndex;
  double _todayProgress = 0.35;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    _todayIndex = now.weekday - 1;
    _days = List.generate(7, (index) {
      return DayStatus(
        date: weekStart.add(Duration(days: index)),
        qualified: index == 1 || index == 4,
        activeSeconds: index == 1 || index == 4 ? 180 : 0,
      );
    });
  }

  void _toggleDay(int index) {
    setState(() {
      final current = _days[index];
      _days = List.of(_days);
      _days[index] = DayStatus(
        date: current.date,
        qualified: !current.qualified,
        activeSeconds: current.activeSeconds,
      );
      if (index == _todayIndex && _days[index].qualified) {
        _todayProgress = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFE9DE),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: PaperWeekCalendar(
                    days: _days,
                    todayIndex: _todayIndex,
                    todayProgress: _todayProgress,
                    animateMarks: true,
                    onTapDay: _toggleDay,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Slider(
                value: _todayProgress,
                min: 0,
                max: 1,
                activeColor: Colors.grey.shade700,
                inactiveColor: Colors.grey.shade400,
                onChanged: (value) {
                  setState(() => _todayProgress = value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
