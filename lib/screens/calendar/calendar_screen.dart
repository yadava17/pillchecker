import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:io' show Platform;

import 'package:pillchecker/backend/models/history_entry.dart';
import 'package:pillchecker/backend/services/adherence_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.adherenceService});

  final AdherenceService adherenceService;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Color _bg = Color(0xffcf5c71);
  static const Color _topBar = Color(0xFFFF6D87);
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);
  static const Color _green = Color(0xFF59FF56);
  static const Color _red = Color(0xFFFF002E);
  static const Color _yellow = Color(0xFFFFDF59);

  late DateTime _focusedDay;
  late DateTime _selectedDay;

  bool _loaded = false;
  List<HistoryEntry> _allEntries = [];

  final Map<DateTime, List<HistoryEntry>> _entriesByDay = {};
  final Map<DateTime, List<String>> _markersByDay = {};

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = _key(DateTime.now());
    _load();
  }

  Future<void> _load() async {
    final items = await widget.adherenceService.fetchHistory(limit: 5000);

    final byDay = <DateTime, List<HistoryEntry>>{};
    final markers = <DateTime, List<String>>{};

    for (final e in items) {
      final day = _key(e.plannedAtLocal);

      byDay.putIfAbsent(day, () => <HistoryEntry>[]).add(e);

      final list = markers.putIfAbsent(day, () => <String>[]);
      final status = e.displayStatus;

      final isTaken = status == 'Taken' || status == 'Taken (Overridden)';
      final isMissed = status == 'Missed';

      if (isTaken && !list.contains('taken')) {
        list.add('taken');
      }
      if (isMissed && !list.contains('missed')) {
        list.add('missed');
      }
    }

    if (!mounted) return;
    setState(() {
      _allEntries = items;
      _entriesByDay
        ..clear()
        ..addAll(byDay);
      _markersByDay
        ..clear()
        ..addAll(markers);
      _loaded = true;
    });
  }

  List<String> _eventsFor(DateTime day) => _markersByDay[_key(day)] ?? [];

  List<HistoryEntry> _entriesFor(DateTime day) =>
      _entriesByDay[_key(day)] ?? [];

  String _formatDate(DateTime d) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${months[d.month]} ${d.day}';
  }

  String _statusLabel(HistoryEntry e) {
    return e.displayStatus;
  }

  Color _statusColor(HistoryEntry e) {
    final s = e.displayStatus;
    if (s == 'Taken (Overridden)') return _yellow;
    if (s == 'Missed') return _red;
    return _green;
  }

  String _timeLabel(DateTime dt) {
    final hh = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entriesFor(_selectedDay);
    final today = _key(DateTime.now());

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(height: 115, color: _topBar),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 115,
              child: Container(height: 5, color: _divider),
            ),
            Positioned(
              left: -75,
              top: 15,
              child: ClipOval(
                child: Container(
                  width: 150,
                  height: 85,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
            Positioned(
              top: 30,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                color: const Color.fromARGB(255, 60, 59, 59),
                iconSize: 40,
              ),
            ),
            Positioned(
              top: 32,
              left: Platform.isIOS ? 0 : 0,
              right: Platform.isIOS ? 7 : 0,
              child: const Center(
                child: Text(
                  'Calendar',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: _card,
                    fontFamily: 'Amaranth',
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: 125,
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: TableCalendar<String>(
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2100, 12, 31),
                            focusedDay: _focusedDay,
                            selectedDayPredicate: (d) =>
                                isSameDay(d, _selectedDay),
                            eventLoader: _eventsFor,
                            calendarFormat: CalendarFormat.month,
                            availableCalendarFormats: const {
                              CalendarFormat.month: 'Month',
                            },
                            startingDayOfWeek: StartingDayOfWeek.sunday,
                            headerStyle: const HeaderStyle(
                              formatButtonVisible: false,
                              titleCentered: true,
                              leftChevronIcon: Icon(
                                Icons.chevron_left,
                                color: Colors.white,
                                size: 28,
                              ),
                              rightChevronIcon: Icon(
                                Icons.chevron_right,
                                color: Colors.white,
                                size: 28,
                              ),
                              titleTextStyle: TextStyle(
                                fontFamily: 'Amaranth',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              headerPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            daysOfWeekStyle: const DaysOfWeekStyle(
                              weekdayStyle: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              weekendStyle: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            calendarStyle: CalendarStyle(
                              outsideDaysVisible: false,
                              defaultTextStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              weekendTextStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              todayTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              selectedTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              todayDecoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.75),
                                  width: 1.5,
                                ),
                              ),
                              selectedDecoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              markerSize: 0,
                              markersMaxCount: 0,
                              cellMargin: const EdgeInsets.all(4),
                            ),
                            calendarBuilders: CalendarBuilders(
                              markerBuilder: (context, day, events) {
                                if (events.isEmpty) return null;

                                final hasTaken = events.contains('taken');
                                final hasMissed = events.contains('missed');

                                return Positioned(
                                  bottom: 9,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasTaken)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: _green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      if (hasTaken && hasMissed)
                                        const SizedBox(width: 4),
                                      if (hasMissed)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: _red,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            onDaySelected: (selected, focused) {
                              setState(() {
                                _selectedDay = _key(selected);
                                _focusedDay = focused;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isSameDay(_selectedDay, today)
                              ? 'Today'
                              : _formatDate(_selectedDay),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: _card,
                            fontFamily: 'Amaranth',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (entries.isEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              isSameDay(_selectedDay, today)
                                  ? 'No adherence history today.'
                                  : 'No adherence history on ${_formatDate(_selectedDay)}.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              children: [
                                for (int i = 0; i < entries.length; i++) ...[
                                  _HistoryRow(
                                    pillName: entries[i].medicationName,
                                    timeLabel: _timeLabel(
                                      entries[i].plannedAtLocal,
                                    ),
                                    statusLabel: _statusLabel(entries[i]),
                                    statusColor: _statusColor(entries[i]),
                                  ),
                                  if (i < entries.length - 1)
                                    Divider(
                                      height: 1,
                                      indent: 16,
                                      endIndent: 14,
                                      color: Colors.white.withOpacity(0.18),
                                    ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.pillName,
    required this.timeLabel,
    required this.statusLabel,
    required this.statusColor,
  });

  final String pillName;
  final String timeLabel;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pillName,
                  style: const TextStyle(
                    fontFamily: 'Amaranth',
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 14,
              color: statusColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
