import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pillchecker/widgets/pill_check_button.dart';
import 'package:pillchecker/widgets/pill_wheel.dart';
import 'package:pillchecker/services/notification_service.dart';
import 'package:pillchecker/widgets/daily_completion_circle.dart';
import 'package:pillchecker/screens/settings/settings_screen.dart';
import 'package:pillchecker/widgets/pill_info_panel.dart';
import 'package:pillchecker/widgets/weekly_pillbox_organizer.dart';
import 'package:pillchecker/constants/prefs_keys.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _ConfigStep { name, config, doses }

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // -------- prefs keys --------
  static const _pillNamesKey = 'pill_names';
  static const _pillTimesKey =
      'pill_times'; // legacy: first dose "HH:mm" per pill
  static const _pillCheckKey =
      'pill_check_state'; // json map: pillIndex -> "cycleIso|mask"
  static const _seenPromptKey = 'seen_first_pill_prompt';

  static const _pillDoseTimesKey =
      'pill_dose_times_v2'; // JSON: List<List<String>>
  static const _pillDoseNotifIdsKey =
      'pill_dose_notif_ids_v2'; // JSON: List<List<int>>

  // -------- in-memory state --------
  List<String> pillNames = [];
  List<String> pillTimes = []; // legacy: first dose only
  List<List<String>> pillDoseTimes =
      []; // ["08:00","14:00"...] aligned with pillNames
  List<List<int>> pillDoseNotifIds = []; // aligned with pillNames
  Map<String, dynamic> _checkMapCache = {};
  Future<Map<String, dynamic>> _checkMapFuture = Future.value(
    <String, dynamic>{},
  );

  Map<String, dynamic> _lastCheckMapCache = {};

  void _refreshCheckMapFuture() {
    if (!mounted) return;
    setState(() {
      _checkMapFuture = _loadCheckMap();
    });
  }

  int _wheelSelectedIndex = 1;

  bool _pendingSlot = false;

  bool _configOpen = false;
  _ConfigStep _step = _ConfigStep.name;

  bool _infoOpen = false;

  // edit mode
  int? _editingIndex;
  bool get _isEditing => _editingIndex != null;

  final TextEditingController _nameController = TextEditingController();
  int _timesPerDay = 1;
  TimeOfDay? _singleDoseTime;
  List<TimeOfDay?> _doseTimes = [];

  Timer? _labelTimer;
  Timer? _doseBoundaryTimer;
  Timer? _dayBoundaryTimer;
  Timer? _globalBoundaryTimer;

  String? _labelOverride;
  bool _showPillLabel = true;

  final FocusNode _nameFocus = FocusNode();

  late final FixedExtentScrollController _wheelController =
      FixedExtentScrollController(initialItem: 1);

  bool get _centerIsRealPill => _centerPillIndex != null;

  int _todayIndex = 3; // default Wed for safety
  bool _allowDailyFillAnim = true; // will gate the DailyCompletionCircle fill
  static const Duration _pillboxOpenAnim = Duration(milliseconds: 650);
  int? _debugDayOverride; // null = real day
  int _lastSeenDayKey = -1; // store last "day stamp"

  int get _realTodayIndex => _debugDayOverride ?? (DateTime.now().weekday % 7);

  final _pillboxKey = GlobalKey<WeeklyPillboxOrganizerState>();
  int _pillboxResetToken = 0;

  // what day the pillbox is CURRENTLY positioned to (for sliding)
  int _pillboxVisualDay = 3; // default Wed so your current alignment is sane

  // do we allow the pillbox to OPEN yet (we keep it closed during slide)
  bool _allowPillboxOpen = false;

  // slide timing
  Duration _pillboxSlideDur = const Duration(milliseconds: 650);
  Timer? _pillboxSlideTimer;

  // stable-ish notification id generator
  int _newNotifId() =>
      DateTime.now().microsecondsSinceEpoch.remainder(2000000000);

  // ---------------- lifecycle ----------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _lastSeenDayKey =
        DateTime.now().year * 10000 +
        DateTime.now().month * 100 +
        DateTime.now().day;
    Timer(_pillboxOpenAnim, () {
      if (!mounted) return;
      setState(() => _allowDailyFillAnim = true);
    });
    _loadAndMaybeAutoOpen();
    _coldStartOpenToday();
    _scheduleGlobalDayBoundaryRefresh();
    _scheduleGlobalBoundaryRefresh();
    _checkMapFuture = _loadCheckMap();
    _scheduleCenteredDoseBoundaryRefresh();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pillboxSlideTimer?.cancel();
    _nameFocus.dispose();

    _labelTimer?.cancel();
    _doseBoundaryTimer?.cancel();
    _dayBoundaryTimer?.cancel();
    _globalBoundaryTimer?.cancel();

    _nameController.dispose();
    _wheelController.dispose();

    super.dispose();
  }

  int _yesterdayOf(int day) => (day + 6) % 7; // 0..6

  int _slideDistanceSteps(int from, int to) {
    // Your special rule:
    // Sunday should start on Saturday and slide "all the way back"
    // (big distance). Since from=yesterday, only Sunday needs special.
    if (from == 6 && to == 0) return 6;

    // normal days: just 1 step
    return (to - from).abs();
  }

  Duration _durationForSlideSteps(int steps) {
    // Tune these if you want:
    const minMs = 520;
    const perStepMs = 180;
    const maxMs = 1250;

    final ms = (minMs + steps * perStepMs).clamp(minMs, maxMs);
    return Duration(milliseconds: ms);
  }

  void _startNewDaySequence({required int today}) {
    final from = _yesterdayOf(today);

    // Reset Rive back to idle/closed (since no CLOSE triggers)
    // so yesterday's flap doesn't remain open.
    setState(() {
      _todayIndex = today;

      _pillboxResetToken++;
      _allowPillboxOpen = false;

      // start visually on yesterday
      _pillboxVisualDay = from;

      // gate daily fill too
      _allowDailyFillAnim = false;

      // compute slide duration
      final steps = _slideDistanceSteps(from, today);
      _pillboxSlideDur = _durationForSlideSteps(steps);
    });

    // 1 frame later: animate to today
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _pillboxVisualDay = today; // triggers AnimatedPositioned slide
      });

      // after slide completes: allow OPEN trigger + start daily fill gate
      _pillboxSlideTimer?.cancel();
      _pillboxSlideTimer = Timer(_pillboxSlideDur, () {
        if (!mounted) return;

        setState(() {
          _allowPillboxOpen = true;
        });

        // now start your open-animation wait for the daily circle
        Timer(_pillboxOpenAnim, () {
          if (!mounted) return;
          setState(() => _allowDailyFillAnim = true);
        });
      });
    });
  }

  Future<void> _resyncNotifsAfterPillChange() async {
    // Pull latest mode/early/late into NotificationService (optional but good)
    await NotificationService.loadUserNotificationSettings();

    // Rebuild schedules using the current prefs + current early/late values
    await _syncDoseNotifications(forceReschedule: true);
  }

  // ---------------- helpers: time ----------------
  String _timeToStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _strToTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _fmt(TimeOfDay t) {
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$mm $suffix';
  }

  DateTime _atTime(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  DateTime _minusMinutes(DateTime dt, int m) =>
      dt.subtract(Duration(minutes: m));

  void _coldStartOpenToday() {
    // DEBUG: set to 0..6 (Sun..Sat). Set to null to use real day.
    // _debugDayOverride = 5; // example: Friday

    // DateTime.weekday: Mon=1..Sun=7
    final wd = DateTime.now().weekday;

    // Convert to Sun=0..Sat=6, but allow override for testing
    final today = _debugDayOverride ?? (wd % 7);

    // first open of the day sequence:
    // - reset pillbox to idle (closed)
    // - start centered on yesterday
    // - slide to today
    // - THEN allow today's flap to open
    // - THEN allow daily completion fill animation
    _startNewDaySequence(today: today);
  }

  // ---------------- helpers: dose lists ----------------
  List<TimeOfDay> _doseTimesForPill(int pillIndex) {
    if (pillIndex < 0 || pillIndex >= pillDoseTimes.length) {
      return [const TimeOfDay(hour: 8, minute: 0)];
    }
    final list = pillDoseTimes[pillIndex];
    final times = list.map(_strToTime).toList();

    times.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );
    return times;
  }

  ({
    int doseIndex,
    int totalDoses,
    String cycleIso,
    int mask,
    int doneCount,
    bool doseChecked,
    bool dayComplete,
  })
  _getActiveDoseStateForPill(int pillIndex) {
    final now = DateTime.now();

    final doses = _doseTimesForPill(pillIndex); // sorted TimeOfDay list
    final w = _computeDoseWindow(now: now, dosesSorted: doses);

    final cycleIso = w.cycleStart.toIso8601String();

    // read stored mask for this pill
    final stored = _lastCheckMapCache?['$pillIndex'] as String?;
    final parsed = _readCycleAndMask(stored);

    final mask = (parsed.cycleIso == cycleIso) ? parsed.mask : 0;

    final doseChecked = (mask & (1 << w.doseIndex)) != 0;
    final doneCount = _bitCount(mask);
    final dayComplete = doneCount >= doses.length;

    return (
      doseIndex: w.doseIndex,
      totalDoses: doses.length,
      cycleIso: cycleIso,
      mask: mask,
      doneCount: doneCount,
      doseChecked: doseChecked,
      dayComplete: dayComplete,
    );
  }

  void _openInfoPanel() {
    if (!_centerIsRealPill) return;

    _hidePillLabelNow();
    setState(() {
      _infoOpen = true;
      _configOpen = false; // don’t allow both open at once
    });
  }

  void _closeInfoPanel() {
    setState(() => _infoOpen = false);
    _showPillLabelAfterSlide();
  }

  void _startEditFlow(int pillIndex) {
    if (pillIndex < 0 || pillIndex >= pillNames.length) return;

    final doses = _doseTimesForPill(pillIndex); // sorted list

    _hidePillLabelNow();
    setState(() {
      _editingIndex = pillIndex;
      _infoOpen = false;
      _configOpen = true;

      _nameController.text = pillNames[pillIndex];
      _timesPerDay = doses.length;

      if (doses.length == 1) {
        _step = _ConfigStep.config;
        _singleDoseTime = doses.first;
        _doseTimes = [];
      } else {
        _step = _ConfigStep.doses;
        _singleDoseTime = null;
        _doseTimes = doses.map((t) => t as TimeOfDay?).toList();
      }
    });

    _centerWheelOn(pillIndex + 1);
  }

  // ---------------- helpers: check map ----------------
  Future<Map<String, dynamic>> _loadCheckMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pillCheckKey);
    if (raw == null || raw.isEmpty) {
      _lastCheckMapCache = {};
      return {};
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _lastCheckMapCache = decoded;
    return decoded;
  }

  Future<void> _saveCheckMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pillCheckKey, jsonEncode(map));
  }

  ({String cycleIso, int mask}) _readCycleAndMask(String? stored) {
    if (stored == null || stored.isEmpty) return (cycleIso: '', mask: 0);
    final parts = stored.split('|');
    if (parts.length != 2) return (cycleIso: '', mask: 0);
    return (cycleIso: parts[0], mask: int.tryParse(parts[1]) ?? 0);
  }

  Future<void> _syncDoseNotifications({bool forceReschedule = false}) async {
    final prefs = await SharedPreferences.getInstance();

    //  ALWAYS pull latest notif settings into prefs->service memory
    await NotificationService.loadUserNotificationSettings();

    // Load latest from prefs (source of truth)
    final names = prefs.getStringList(_pillNamesKey) ?? [];
    final doseTimes = _decodeListOfStringLists(
      prefs.getString(_pillDoseTimesKey),
    );
    final notifIds = _decodeListOfIntLists(
      prefs.getString(_pillDoseNotifIdsKey),
    );

    // ---- Notification settings (read directly from prefs) ----
    //  ONLY the v1 keys (remove old redundant keys)
    final mode = prefs.getString(kNotifModeKey) ?? 'standard';
    final earlyMin = prefs.getInt(kEarlyLeadMinKey) ?? 30;
    final lateMin = prefs.getInt(kLateAfterMinKey) ?? 30;

    debugPrint(
      'SYNC NOTIFS: force=$forceReschedule mode=$mode earlyMin=$earlyMin lateMin=$lateMin names=${names.length}',
    );

    //  If forcing, do a clean wipe so edits ALWAYS apply (fixes your “edit pill after settings” bug)
    if (forceReschedule) {
      await NotificationService.cancelAll();
      debugPrint('SYNC NOTIFS: cancelAll() done');
    }

    // Make lists align in length
    while (doseTimes.length < names.length) doseTimes.add(['08:00']);
    if (doseTimes.length > names.length) {
      doseTimes.removeRange(names.length, doseTimes.length);
    }

    while (notifIds.length < names.length) notifIds.add(<int>[]);
    if (notifIds.length > names.length) {
      notifIds.removeRange(names.length, notifIds.length);
    }

    bool changed = false;

    for (int pillIndex = 0; pillIndex < names.length; pillIndex++) {
      final pillName = names[pillIndex];
      final timesForPill = doseTimes[pillIndex];
      final idsForPill = notifIds[pillIndex];

      final doseCount = timesForPill.length;
      final wantLen = doseCount * 3; // ✅ 3 notifications per dose

      // MIGRATION: old format had 1 id per dose. Convert to 3 ids per dose.
      // Old ID becomes MAIN, and we generate EARLY + LATE.
      if (doseCount > 0 && idsForPill.length == doseCount) {
        final expanded = <int>[];
        for (int d = 0; d < doseCount; d++) {
          final main = idsForPill[d];
          expanded.add(_newNotifId()); // early
          expanded.add(main); // main (keep old)
          expanded.add(_newNotifId()); // late
        }
        notifIds[pillIndex] = expanded;
        changed = true;
      }

      // Refresh local reference (might have been migrated)
      final fixedIds = notifIds[pillIndex];

      // If notifIds list is longer than needed, trim
      if (fixedIds.length > wantLen) {
        notifIds[pillIndex] = fixedIds.take(wantLen).toList();
        changed = true;
      }

      // If notifIds list is shorter than needed, generate missing IDs
      while (notifIds[pillIndex].length < wantLen) {
        notifIds[pillIndex].add(_newNotifId());
        changed = true;
      }

      // Now schedule each dose using the stored IDs so it never duplicates
      for (int doseIndex = 0; doseIndex < doseCount; doseIndex++) {
        final base = doseIndex * 3;
        final earlyId = notifIds[pillIndex][base + 0];
        final mainId = notifIds[pillIndex][base + 1];
        final lateId = notifIds[pillIndex][base + 2];

        final t = _strToTime(timesForPill[doseIndex]);

        debugPrint(
          'SYNC NOTIFS: pill="$pillName" dose=${doseIndex + 1}/$doseCount '
          'time=${timesForPill[doseIndex]} ids=(E:$earlyId M:$mainId L:$lateId)',
        );

        if (mode == 'off') {
          // make sure nothing lingers
          await NotificationService.cancel(earlyId);
          await NotificationService.cancel(mainId);
          await NotificationService.cancel(lateId);
          continue;
        }

        // MAIN always in basic + standard
        await NotificationService.scheduleDailyDoseReminder(
          id: mainId,
          pillName: pillName,
          doseNumber1Based: doseIndex + 1,
          time: t,
          totalDoses: doseCount,
        );

        if (mode == 'standard') {
          // DAILY repeating early/late
          await NotificationService.scheduleDailyDoseEarlyReminder(
            id: earlyId,
            pillName: pillName,
            doseNumber1Based: doseIndex + 1,
            time: t,
            totalDoses: doseCount,
          );

          await NotificationService.scheduleDailyDoseLateReminder(
            id: lateId,
            pillName: pillName,
            doseNumber1Based: doseIndex + 1,
            time: t,
            totalDoses: doseCount,
          );
        } else {
          // basic mode => ensure early/late are not lingering
          await NotificationService.cancel(earlyId);
          await NotificationService.cancel(lateId);
        }
      }
    }

    // Persist any fixes to the ID structure
    if (changed) {
      await prefs.setString(_pillDoseNotifIdsKey, jsonEncode(notifIds));
    }

    //  Always update local state (even if no ID migration happened)
    if (mounted) {
      setState(() {
        pillDoseNotifIds = notifIds;
        pillDoseTimes = doseTimes;
        pillNames = names;
      });
    }

    // Optional: dump pending after scheduling (remove later)
    await NotificationService.debugDumpPending('after_sync');
  }

  String _packCycleAndMask(String cycleIso, int mask) => '$cycleIso|$mask';

  // Counts set bits (you already had this earlier; if missing, add it)
  int _bitCount(int x) {
    var n = 0;
    while (x != 0) {
      x &= (x - 1);
      n++;
    }
    return n;
  }

  // Earliest "first dose" time across ALL pills (minutes since midnight)
  int? _earliestFirstDoseMinutes() {
    if (pillDoseTimes.isEmpty) return null;

    int? best;
    for (final doseList in pillDoseTimes) {
      if (doseList.isEmpty) continue;

      // doseList is ["HH:mm", ...] (not guaranteed sorted)
      final times = doseList.map(_strToTime).toList();
      times.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );
      final first = times.first;
      final m = first.hour * 60 + first.minute;

      if (best == null || m < best) best = m;
    }
    return best;
  }

  // Global "day cycle" iso key: 2 hours before earliest first dose
  String _globalCycleIso(DateTime now) {
    final earliestMins = _earliestFirstDoseMinutes();
    if (earliestMins == null) return '';

    final earliest = TimeOfDay(
      hour: earliestMins ~/ 60,
      minute: earliestMins % 60,
    );

    final resetToday = DateTime(
      now.year,
      now.month,
      now.day,
      earliest.hour,
      earliest.minute,
    ).subtract(const Duration(hours: 2));

    final cycleStart = now.isBefore(resetToday)
        ? resetToday.subtract(const Duration(days: 1))
        : resetToday;

    return cycleStart.toIso8601String();
  }

  // True if every pill is fully completed for this global cycle
  bool _allPillsCompletedForCycle(Map<String, dynamic> checkMap, DateTime now) {
    if (pillNames.isEmpty) return false;

    final cycleIso = _globalCycleIso(now);
    if (cycleIso.isEmpty) return false;

    for (int i = 0; i < pillNames.length; i++) {
      final totalDoses =
          (i < pillDoseTimes.length && pillDoseTimes[i].isNotEmpty)
          ? pillDoseTimes[i].length
          : 1;

      final stored = checkMap['$i'] as String?;
      final parsed = _readCycleAndMask(stored);

      // Must match this global cycle
      if (parsed.cycleIso != cycleIso) return false;

      // Must have all dose bits set
      if (_bitCount(parsed.mask) < totalDoses) return false;
    }

    return true;
  }

  int _doneDoseCountForPill(Map<String, dynamic> map, int pillIndex) {
    final doses = _doseTimesForPill(pillIndex);
    final total = doses.length;

    if (total == 0) return 0;

    final w = _computeDoseWindow(now: DateTime.now(), dosesSorted: doses);
    final cycleIso = w.cycleStart.toIso8601String();

    final stored = map['$pillIndex'] as String?;
    final parsed = _readCycleAndMask(stored);

    if (parsed.cycleIso != cycleIso) return 0;

    final done = _bitCount(parsed.mask);
    return done.clamp(0, total);
  }

  bool _isPillComplete(Map<String, dynamic> map, int pillIndex) {
    final doses = _doseTimesForPill(pillIndex);
    if (doses.isEmpty) return false;
    return _doneDoseCountForPill(map, pillIndex) >= doses.length;
  }

  bool _areAllPillsComplete(Map<String, dynamic> map) {
    if (pillNames.isEmpty) return false;
    for (int i = 0; i < pillNames.length; i++) {
      if (!_isPillComplete(map, i)) return false;
    }
    return true;
  }

  bool _isDoseCheckedSync(
    Map<String, dynamic> map,
    int pillIndex,
    String cycleIso,
    int doseIndex,
  ) {
    final stored = map['$pillIndex'] as String?;
    final parsed = _readCycleAndMask(stored);
    if (parsed.cycleIso != cycleIso) return false;
    return (parsed.mask & (1 << doseIndex)) != 0;
  }

  // ---------------- dose window logic ----------------
  ({
    int doseIndex,
    DateTime windowStart,
    DateTime windowEnd,
    DateTime cycleStart,
  })
  _computeDoseWindow({
    required DateTime now,
    required List<TimeOfDay> dosesSorted,
  }) {
    final first = dosesSorted.first;
    final day = DateTime(now.year, now.month, now.day);

    // cycleStart = firstDose - 2 hours
    final cycleStartToday = _atTime(
      day,
      first,
    ).subtract(const Duration(hours: 2));

    final cycleStart = now.isBefore(cycleStartToday)
        ? cycleStartToday.subtract(const Duration(days: 1))
        : cycleStartToday;

    final cycleDay = DateTime(
      cycleStart.year,
      cycleStart.month,
      cycleStart.day,
    );

    final doseInstants = dosesSorted
        .map((t) => _atTime(cycleDay, t))
        .toList(growable: false);

    // Each window begins 30m before its dose time
    final windowStarts = doseInstants.map((d) => _minusMinutes(d, 30)).toList();

    final nextCycleStart = cycleStart.add(const Duration(days: 1));
    final windowEnds = <DateTime>[
      for (int i = 0; i < windowStarts.length - 1; i++) windowStarts[i + 1],
      nextCycleStart,
    ];

    for (int i = 0; i < windowStarts.length; i++) {
      if (!now.isBefore(windowStarts[i]) && now.isBefore(windowEnds[i])) {
        return (
          doseIndex: i,
          windowStart: windowStarts[i],
          windowEnd: windowEnds[i],
          cycleStart: cycleStart,
        );
      }
    }

    return (
      doseIndex: 0,
      windowStart: windowStarts[0],
      windowEnd: windowEnds[0],
      cycleStart: cycleStart,
    );
  }

  DateTime? _globalCycleStartForNow(DateTime now) {
    if (pillNames.isEmpty) return null;

    DateTime? earliest;
    for (int i = 0; i < pillNames.length; i++) {
      final doses = _doseTimesForPill(i);
      if (doses.isEmpty) continue;

      final first = doses.first; // doses are sorted in _doseTimesForPill
      final day = DateTime(now.year, now.month, now.day);
      final cycleStartToday = DateTime(
        day.year,
        day.month,
        day.day,
        first.hour,
        first.minute,
      ).subtract(const Duration(hours: 2));

      final cycleStart = now.isBefore(cycleStartToday)
          ? cycleStartToday.subtract(const Duration(days: 1))
          : cycleStartToday;

      if (earliest == null || cycleStart.isBefore(earliest)) {
        earliest = cycleStart;
      }
    }

    return earliest;
  }

  void _scheduleGlobalBoundaryRefresh() {
    _globalBoundaryTimer?.cancel();
    _globalBoundaryTimer = null;

    if (pillNames.isEmpty) return;

    final now = DateTime.now();
    DateTime? soonest;

    for (int i = 0; i < pillNames.length; i++) {
      final doses = _doseTimesForPill(i);
      if (doses.isEmpty) continue;

      final w = _computeDoseWindow(now: now, dosesSorted: doses);
      final candidate = w.windowEnd;

      // windowEnd can be "now-ish" if we're right on the boundary
      if (candidate.isAfter(now)) {
        if (soonest == null || candidate.isBefore(soonest)) soonest = candidate;
      }
    }

    if (soonest == null) return;

    final diff = soonest.difference(now);
    if (diff.inMilliseconds <= 50) {
      if (!mounted) return;
      _refreshCheckMapFuture();
      _scheduleGlobalBoundaryRefresh();
      return;
    }

    _globalBoundaryTimer = Timer(diff, () {
      if (!mounted) return;

      // Reload map so ANY pill that reset/changed window shows correct state
      _refreshCheckMapFuture();

      // Reschedule for the next soonest boundary
      _scheduleGlobalBoundaryRefresh();
    });
  }

  void _scheduleGlobalDayBoundaryRefresh() {
    _dayBoundaryTimer?.cancel();
    _dayBoundaryTimer = null;

    final now = DateTime.now();
    final cycleStart = _globalCycleStartForNow(now);
    if (cycleStart == null) return;

    final nextCycleStart = cycleStart.add(const Duration(days: 1));
    final diff = nextCycleStart.difference(now);

    if (diff.inMilliseconds <= 50) {
      if (!mounted) return;
      _checkMapFuture = _loadCheckMap();
      setState(() {});
      return;
    }

    _dayBoundaryTimer = Timer(diff, () {
      if (!mounted) return;

      // Day reset moment hit (2h before earliest first dose)
      _checkMapFuture = _loadCheckMap();
      setState(() {});

      // reschedule for the next day
      _scheduleGlobalDayBoundaryRefresh();
    });
  }

  void _scheduleCenteredDoseBoundaryRefresh() {
    _doseBoundaryTimer?.cancel();
    _doseBoundaryTimer = null;

    final pillIndex = _centerPillIndex;
    if (pillIndex == null) return;

    final doses = _doseTimesForPill(pillIndex);
    if (doses.isEmpty) return;

    final w = _computeDoseWindow(now: DateTime.now(), dosesSorted: doses);

    // Next time the UI should change for this centered pill:
    // (this is the "reset" moment: 30 min before next dose, or cycle reset after final)
    final next = w.windowEnd;

    // If it's already passed or basically now, rebuild immediately
    final diff = next.difference(DateTime.now());
    if (diff.inMilliseconds <= 50) {
      if (!mounted) return;
      setState(() {});
      return;
    }

    _doseBoundaryTimer = Timer(diff, () {
      if (!mounted) return;

      // Refresh check state + label "(dose X)" immediately at the boundary
      _checkMapFuture = _loadCheckMap();
      setState(() {});

      // Schedule the NEXT boundary too (because now we're in the next window)
      _scheduleCenteredDoseBoundaryRefresh();
    });
  }

  // ---------------- selection helpers ----------------
  int? get _centerPillIndex {
    final idx = _wheelSelectedIndex - 1; // wheel->pill
    if (_wheelSelectedIndex <= 0) return null;
    if (idx < 0 || idx >= pillNames.length) return null;
    return idx;
  }

  String _centerPillName() {
    if (_wheelSelectedIndex <= 0) return '';
    final slot = _wheelSelectedIndex - 1;
    if (slot < 0) return '';
    if (slot >= pillNames.length) return '';
    return pillNames[slot];
  }

  double _leftFromDesignRight(
    double baseW,
    double baseRight,
    Size screenSize,
    double Function(double) s,
    double designW,
  ) {
    final elementW = s(baseW);
    final designCenterX = designW / 2;
    final elementCenterX = designW - baseRight - (baseW / 2);
    final offsetFromCenter = elementCenterX - designCenterX;
    return (screenSize.width / 2) + s(offsetFromCenter) - (elementW / 2);
  }

  double _pillboxLeftForDay({
    required Size size,
    required double Function(double) s,
    required double designW,
    required int todayIndex, // 0=Sun..6=Sat
  }) {
    final wedLeft = _leftFromDesignRight(400, 198, size, s, designW);

    const base = 92.6;
    const growth = 0.4;

    double cumulative(int day) {
      // sum_{k=0}^{day-1} (base + growth*k)
      // = base*day + growth*(day-1)*day/2
      return (base * day) + (growth * (day - 1) * day / 2.0);
    }

    const anchor = 3; // Wednesday
    final shiftFromWed = cumulative(todayIndex) - cumulative(anchor);

    const tweak = <double>[
      -0.2, // Sun
      -0.4, // Mon
      0.0, // Tue
      0.0, // Wed (anchor)
      -0.4, // Thu
      -1.1, // Fri
      -2.3, // Sat
    ];

    final correctedShift = shiftFromWed + tweak[todayIndex];

    return wedLeft - s(correctedShift);

    // If it moves the wrong way, flip the sign:
    // return wedLeft + s(shiftFromWed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final now = DateTime.now();
    final dayKey = now.year * 10000 + now.month * 100 + now.day;

    if (dayKey == _lastSeenDayKey) return; // same day, nothing to do
    _lastSeenDayKey = dayKey;

    // new day → recompute day index (Sun=0..Sat=6, allow override)
    final newToday = _debugDayOverride ?? (now.weekday % 7);

    //run the full "yesterday -> slide -> open today" sequence
    _startNewDaySequence(today: newToday);
  }

  // ---------------- UI label helpers ----------------
  void _hidePillLabelNow() {
    if (_showPillLabel) setState(() => _showPillLabel = false);
  }

  void _showPillLabelAfterSlide() {
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      if (!_configOpen) setState(() => _showPillLabel = true);
    });
  }

  void _clearCheckedMessage() {
    if (_labelOverride == null) return;
    _labelTimer?.cancel();
    _labelTimer = null;
    if (!mounted) return;
    setState(() => _labelOverride = null);
  }

  void _editNameAgain() {
    setState(() => _step = _ConfigStep.name);

    // focus AFTER rebuild so the TextField exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.requestFocus();

      // optional: put cursor at end
      _nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _nameController.text.length),
      );
    });
  }

  // ---------------- onboarding ----------------
  Future<void> _showWelcomeThenOpenConfig(SharedPreferences prefs) async {
    final alreadySeen = prefs.getBool(_seenPromptKey) ?? false;
    if (alreadySeen) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Welcome!'),
        content: const Text('Configure your first pill.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    await prefs.setBool(_seenPromptKey, true);

    if (!mounted) return;
    _startAddFlow(createNewSlot: true);
  }

  // ---------------- decode helpers ----------------
  List<List<String>> _decodeListOfStringLists(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List)
        .map((e) => (e as List).map((x) => x.toString()).toList())
        .toList();
  }

  List<List<int>> _decodeListOfIntLists(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List)
        .map((e) => (e as List).map((x) => (x as num).toInt()).toList())
        .toList();
  }

  // ---------------- load ----------------
  Future<void> _loadAndMaybeAutoOpen() async {
    final prefs = await SharedPreferences.getInstance();

    final savedNames = prefs.getStringList(_pillNamesKey) ?? [];
    final savedTimes = prefs.getStringList(_pillTimesKey) ?? [];

    final early = prefs.getInt(kEarlyLeadMinKey) ?? 30;
    final late = prefs.getInt(kLateAfterMinKey) ?? 30;

    // align legacy times to names
    final alignedTimes = List<String>.from(savedTimes);
    while (alignedTimes.length < savedNames.length) {
      alignedTimes.add('08:00');
    }
    if (alignedTimes.length > savedNames.length) {
      alignedTimes.removeRange(savedNames.length, alignedTimes.length);
    }
    await prefs.setStringList(_pillTimesKey, alignedTimes);

    // load v2
    final rawDoseTimes = prefs.getString(_pillDoseTimesKey);
    final rawDoseNotifIds = prefs.getString(_pillDoseNotifIdsKey);

    var loadedDoseTimes = _decodeListOfStringLists(rawDoseTimes);
    var loadedDoseNotifIds = _decodeListOfIntLists(rawDoseNotifIds);

    // seed doseTimes from legacy if upgrading
    if (loadedDoseTimes.isEmpty && savedNames.isNotEmpty) {
      loadedDoseTimes = [
        for (int i = 0; i < savedNames.length; i++) [alignedTimes[i]],
      ];
    }

    while (loadedDoseTimes.length < savedNames.length) {
      loadedDoseTimes.add(['08:00']);
    }
    if (loadedDoseTimes.length > savedNames.length) {
      loadedDoseTimes.removeRange(savedNames.length, loadedDoseTimes.length);
    }

    while (loadedDoseNotifIds.length < savedNames.length) {
      loadedDoseNotifIds.add(<int>[]);
    }
    if (loadedDoseNotifIds.length > savedNames.length) {
      loadedDoseNotifIds.removeRange(
        savedNames.length,
        loadedDoseNotifIds.length,
      );
    }

    await prefs.setString(_pillDoseTimesKey, jsonEncode(loadedDoseTimes));
    await prefs.setString(_pillDoseNotifIdsKey, jsonEncode(loadedDoseNotifIds));
    final loadedMap = await _loadCheckMap();

    setState(() {
      pillNames = savedNames;
      pillTimes = alignedTimes;
      _checkMapCache = loadedMap;
      _checkMapFuture = Future.value(loadedMap);
      pillDoseTimes = loadedDoseTimes;
      pillDoseNotifIds = loadedDoseNotifIds;
    });

    // After loading pills, sync notifications to prevent old schedules / duplicates
    await _syncDoseNotifications(forceReschedule: true);

    if (savedNames.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showWelcomeThenOpenConfig(prefs);
      });
    }
  }

  // ---------------- wheel counts ----------------
  int get _displayPillCount {
    final real = pillNames.length;
    final baselineEmpty = (real == 0 && !_pendingSlot) ? 1 : 0;
    final pendingExtra = _pendingSlot ? 1 : 0;
    return real + baselineEmpty + pendingExtra;
  }

  int get _realPillCount => pillNames.length;
  int get _pendingWheelIndex => 1 + pillNames.length;

  void _centerWheelOn(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_wheelController.hasClients) return;
      _wheelController.jumpToItem(index);
    });
  }

  // ---------------- config flow ----------------
  void _startAddFlow({required bool createNewSlot}) {
    _hidePillLabelNow();
    setState(() {
      _configOpen = true;
      _step = _ConfigStep.name;

      _nameController.text = '';
      _timesPerDay = 1;
      _singleDoseTime = null;
      _doseTimes = [];

      if (createNewSlot) _pendingSlot = true;
    });

    if (_pendingSlot) _centerWheelOn(_pendingWheelIndex);
  }

  void _cancelAddFlow() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _configOpen = false;
      _pendingSlot = false;
      _step = _ConfigStep.name;
    });
    _centerWheelOn(1);
    _showPillLabelAfterSlide();
  }

  void _setCheckMapAndRebuild(Map<String, dynamic> map) {
    _checkMapCache = map;
    _checkMapFuture = Future.value(map);
    if (mounted) setState(() {});
  }

  Future<void> _pickTimeSingle() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _singleDoseTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _singleDoseTime = picked);
  }

  Future<void> _pickDoseTime(int i) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _doseTimes[i] ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _doseTimes[i] = picked);
  }

  bool get _allDoseTimesSet =>
      _doseTimes.isNotEmpty && _doseTimes.every((t) => t != null);

  void _handlePrimaryAction() {
    if (_step == _ConfigStep.name) {
      if (_nameController.text.trim().isEmpty) return;
      setState(() => _step = _ConfigStep.config);
      return;
    }

    if (_step == _ConfigStep.config) {
      if (_timesPerDay == 1) {
        if (_singleDoseTime == null) return;

        //  if editing, update; otherwise save new
        if (_isEditing) {
          _updatePill();
        } else {
          _savePill();
        }
      } else {
        setState(() {
          _step = _ConfigStep.doses;

          //  if editing, prefill the existing times (so they can tweak them)
          // otherwise create empty slots
          if (_isEditing) {
            final idx = _editingIndex;
            final existing = (idx == null)
                ? <TimeOfDay>[]
                : _doseTimesForPill(idx);
            _doseTimes = List<TimeOfDay?>.from(existing);
          } else {
            _doseTimes = List<TimeOfDay?>.filled(_timesPerDay, null);
          }
        });

        _scheduleGlobalDayBoundaryRefresh();
      }
      return;
    }

    if (_step == _ConfigStep.doses) {
      if (!_allDoseTimesSet) return;

      // ✅ if editing, update; otherwise save new
      if (_isEditing) {
        _updatePill();
      } else {
        _savePill();
      }
    }
  }

  // ---------------- SAVE pill ----------------
  Future<void> _savePill() async {
    _showPillLabelAfterSlide();

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_timesPerDay == 1 && _singleDoseTime == null) return;
    if (_timesPerDay > 1 && !_allDoseTimesSet) return;

    // build sorted doses
    final List<TimeOfDay> doses = (_timesPerDay == 1)
        ? <TimeOfDay>[_singleDoseTime!]
        : _doseTimes.map((t) => t!).toList();

    doses.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );

    final doseStrings = doses.map(_timeToStr).toList();
    final firstDose = doses.first;

    final prefs = await SharedPreferences.getInstance();

    // persist names
    final updatedNames = [...pillNames, name];
    await prefs.setStringList(_pillNamesKey, updatedNames);

    // persist legacy first-dose times (for now)
    final existingTimes = prefs.getStringList(_pillTimesKey) ?? [];
    final updatedTimes = [...existingTimes, _timeToStr(firstDose)];
    await prefs.setStringList(_pillTimesKey, updatedTimes);

    // persist dose times list-of-lists
    final existingDoseTimes = _decodeListOfStringLists(
      prefs.getString(_pillDoseTimesKey),
    );
    final updatedDoseTimes = [...existingDoseTimes, doseStrings];
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));

    // schedule + persist notif ids per dose
    final existingDoseNotifIds = _decodeListOfIntLists(
      prefs.getString(_pillDoseNotifIdsKey),
    );

    final List<int> notifIdsForThisPill = <int>[];
    for (int i = 0; i < doses.length; i++) {
      final id = _newNotifId();
      notifIdsForThisPill.add(id);

      await NotificationService.scheduleDailyDoseReminder(
        id: id,
        pillName: name,
        doseNumber1Based: i + 1,
        time: doses[i],
        totalDoses: doses.length,
      );
    }

    final updatedDoseNotifIds = [...existingDoseNotifIds, notifIdsForThisPill];
    await prefs.setString(
      _pillDoseNotifIdsKey,
      jsonEncode(updatedDoseNotifIds),
    );

    // clear stale check state for new pill index
    final checkMap = await _loadCheckMap();
    final newIndex = updatedNames.length - 1;
    checkMap.remove('$newIndex');
    await _saveCheckMap(checkMap);
    _setCheckMapAndRebuild(checkMap);
    _refreshCheckMapFuture();

    await _resyncNotifsAfterPillChange();


    setState(() {
      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;
      pillDoseNotifIds = updatedDoseNotifIds;

      _pendingSlot = false;
      _configOpen = false;
      _step = _ConfigStep.name;
    });
    await _syncDoseNotifications(forceReschedule: true);
    _showPillLabelAfterSlide();
    _centerWheelOn(1 + (updatedNames.length - 1));
    _scheduleGlobalBoundaryRefresh();
  }

  Future<void> _updatePill() async {
    final pillIndex = _editingIndex;
    if (pillIndex == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_timesPerDay == 1 && _singleDoseTime == null) return;
    if (_timesPerDay > 1 && !_allDoseTimesSet) return;

    // build sorted doses
    final List<TimeOfDay> doses = (_timesPerDay == 1)
        ? <TimeOfDay>[_singleDoseTime!]
        : _doseTimes.map((t) => t!).toList();

    doses.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );
    final doseStrings = doses.map(_timeToStr).toList();
    final firstDose = doses.first;

    final prefs = await SharedPreferences.getInstance();

    // Cancel existing notifications for this pill
    if (pillIndex < pillDoseNotifIds.length) {
      for (final id in pillDoseNotifIds[pillIndex]) {
        await NotificationService.cancel(id);
      }
    }

    // Schedule new notifications
    final List<int> notifIdsForThisPill = <int>[];
    for (int i = 0; i < doses.length; i++) {
      final id = _newNotifId();
      notifIdsForThisPill.add(id);

      await NotificationService.scheduleDailyDoseReminder(
        id: id,
        pillName: name,
        doseNumber1Based: i + 1,
        time: doses[i],
        totalDoses: doses.length,
      );
    }

    // Update in-memory lists
    final updatedNames = [...pillNames];
    updatedNames[pillIndex] = name;

    final updatedTimes = [...pillTimes];
    if (pillIndex < updatedTimes.length) {
      updatedTimes[pillIndex] = _timeToStr(firstDose);
    }

    final updatedDoseTimes = [...pillDoseTimes];
    if (pillIndex < updatedDoseTimes.length) {
      updatedDoseTimes[pillIndex] = doseStrings;
    }

    final updatedDoseNotifIds = [...pillDoseNotifIds];
    if (pillIndex < updatedDoseNotifIds.length) {
      updatedDoseNotifIds[pillIndex] = notifIdsForThisPill;
    }

    // Persist prefs
    await prefs.setStringList(_pillNamesKey, updatedNames);
    await prefs.setStringList(_pillTimesKey, updatedTimes);
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));
    await prefs.setString(
      _pillDoseNotifIdsKey,
      jsonEncode(updatedDoseNotifIds),
    );

    // Clear THIS pill’s check state (safe, avoids weird mismatches after edits)
    final checkMap = await _loadCheckMap();
    checkMap.remove('$pillIndex');
    await _saveCheckMap(checkMap);
    _setCheckMapAndRebuild(checkMap);
    _refreshCheckMapFuture();

    await _resyncNotifsAfterPillChange();


    setState(() {
      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;
      pillDoseNotifIds = updatedDoseNotifIds;

      _editingIndex = null;
      _configOpen = false;
      _step = _ConfigStep.name;
    });

    _scheduleGlobalDayBoundaryRefresh();
    _scheduleGlobalBoundaryRefresh();
    _showPillLabelAfterSlide();
  }

  // ---------------- DELETE pill (cancel all doses) ----------------
  Future<void> _deleteCenteredPill() async {
    if (_wheelSelectedIndex <= 0) return;

    final slot = _wheelSelectedIndex - 1;
    if (slot < 0 || slot >= pillNames.length) return;

    final pillName = pillNames[slot];

    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete pill?'),
            content: Text('Delete "$pillName"? This can’t be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    // cancel ALL notifications for this pill (all doses)
    if (slot < pillDoseNotifIds.length) {
      for (final id in pillDoseNotifIds[slot]) {
        await NotificationService.cancel(id);
      }
    }

    final updatedNames = [...pillNames]..removeAt(slot);

    final updatedTimes = [...pillTimes];
    if (slot < updatedTimes.length) updatedTimes.removeAt(slot);

    final updatedDoseTimes = [...pillDoseTimes];
    if (slot < updatedDoseTimes.length) updatedDoseTimes.removeAt(slot);

    final updatedDoseNotifIds = [...pillDoseNotifIds];
    if (slot < updatedDoseNotifIds.length) updatedDoseNotifIds.removeAt(slot);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pillNamesKey, updatedNames);
    await prefs.setStringList(_pillTimesKey, updatedTimes);
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));
    await prefs.setString(
      _pillDoseNotifIdsKey,
      jsonEncode(updatedDoseNotifIds),
    );

    await _syncDoseNotifications(forceReschedule: true);

    // shift check map indices down
    final checkMap = await _loadCheckMap();
    final Map<String, dynamic> shifted = {};
    checkMap.forEach((k, v) {
      final idx = int.tryParse(k);
      if (idx == null) return;
      if (idx < slot) {
        shifted['$idx'] = v;
      } else if (idx > slot) {
        shifted['${idx - 1}'] = v;
      }
    });
    await _saveCheckMap(shifted);
    _setCheckMapAndRebuild(shifted);
    _refreshCheckMapFuture();

    setState(() {
      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;
      pillDoseNotifIds = updatedDoseNotifIds;
      _pendingSlot = false;
    });

    _scheduleGlobalDayBoundaryRefresh();
    _scheduleGlobalBoundaryRefresh();

    final newCount = updatedNames.length;
    if (newCount == 0) {
      _wheelSelectedIndex = 1;
      _centerWheelOn(1);
    } else {
      final newSlot = slot.clamp(0, newCount - 1);
      final newWheelIndex = newSlot + 1;
      _wheelSelectedIndex = newWheelIndex;
      _centerWheelOn(newWheelIndex);
    }
  }

  // ---------------- CHECK current dose ----------------
  Future<void> _checkCenteredPill() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null) return;

    // Ensure cache is fresh
    final map = await _loadCheckMap();

    final doses = _doseTimesForPill(pillIndex);
    final w = _computeDoseWindow(now: DateTime.now(), dosesSorted: doses);

    final cycleIso = w.cycleStart.toIso8601String();
    final doseIndex = w.doseIndex;

    final stored = map['$pillIndex'] as String?;
    final parsed = _readCycleAndMask(stored);

    final baseMask = (parsed.cycleIso == cycleIso) ? parsed.mask : 0;
    final newMask = baseMask | (1 << doseIndex);

    map['$pillIndex'] = _packCycleAndMask(cycleIso, newMask);
    await _saveCheckMap(map);
    _setCheckMapAndRebuild(map);
    _refreshCheckMapFuture(); // ✅ forces daily circle + button builders to see new map
    _checkMapFuture = _loadCheckMap();
    _scheduleCenteredDoseBoundaryRefresh();

    // show "Pill Checked!" for ~9 seconds
    _labelTimer?.cancel();
    setState(() => _labelOverride = 'Pill Checked!');
    _labelTimer = Timer(const Duration(seconds: 9), () {
      if (!mounted) return;
      setState(() => _labelOverride = null);
    });

    if (mounted) setState(() {});
  }

  // ---------------- config panel UI ----------------
  Widget _configPanel() {
    const cardColor = Color(0xFF98404F);
    const white = Color(0xFFFFFFFF);
    const green = Color(0xFF59FF56);

    final titleText = _isEditing
        ? 'Save'
        : (_step == _ConfigStep.name)
        ? 'Continue'
        : (_timesPerDay > 1 && _step == _ConfigStep.config)
        ? 'Next'
        : (_step == _ConfigStep.doses ? 'Save' : 'Add');

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(26),
        ),
        padding: const EdgeInsets.all(16),

        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/images/pill_placeholder.png',
                              width: 36,
                              height: 36,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),
                        Expanded(
                          child: (_step == _ConfigStep.name)
                              ? TextField(
                                  focusNode: _nameFocus,
                                  controller: _nameController,
                                  style: const TextStyle(
                                    color: white,
                                    fontSize: 18,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Pill name...',
                                    hintStyle: TextStyle(color: Colors.white70),
                                    border: InputBorder.none,
                                  ),
                                )
                              : InkWell(
                                  onTap: _editNameAgain, // tap name to edit
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _nameController.text.trim(),
                                          style: const TextStyle(
                                            color: white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.edit,
                                        color: Colors.white70,
                                        size: 20,
                                      ), // ✅ cue
                                    ],
                                  ),
                                ),
                        ),

                        IconButton(
                          onPressed: _cancelAddFlow,
                          icon: const Icon(Icons.close, color: white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Placeholder info area',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_step == _ConfigStep.config) ...[
                      Row(
                        children: [
                          const Icon(Icons.schedule, color: white),
                          const SizedBox(width: 10),
                          const Text(
                            'Times per day',
                            style: TextStyle(color: white),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButton<int>(
                              value: _timesPerDay,
                              underline: const SizedBox.shrink(),
                              items: List.generate(6, (i) => i + 1)
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text('$n'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _timesPerDay = v;
                                  _singleDoseTime = null;
                                  _doseTimes = [];
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_timesPerDay == 1)
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _pickTimeSingle,
                            child: Center(
                              child: Text(
                                _singleDoseTime == null
                                    ? 'Pick time'
                                    : _fmt(_singleDoseTime!),
                                style: const TextStyle(
                                  color: cardColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],

                    if (_step == _ConfigStep.doses)
                      SizedBox(
                        height: 220,
                        child: ListView.separated(
                          itemCount: _timesPerDay,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final t = _doseTimes[i];
                            return Container(
                              decoration: BoxDecoration(
                                color: white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                title: Text(
                                  'Dose ${i + 1}',
                                  style: const TextStyle(
                                    color: cardColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  t == null ? 'Tap to set time' : _fmt(t),
                                  style: const TextStyle(color: cardColor),
                                ),
                                trailing: const Icon(
                                  Icons.schedule,
                                  color: cardColor,
                                ),
                                onTap: () => _pickDoseTime(i),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: Material(
                        color: green,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _handlePrimaryAction,
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    titleText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                width: 56,
                                height: 56,
                                child: Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    const designW = 411.0;
    const designH = 914.0;

    final scaleW = size.width / designW;
    final scaleH = size.height / designH;
    final scale = (scaleW < scaleH ? scaleW : scaleH).clamp(0.8, 1.3);

    double s(double v) => v * scale;
    double fs(double v) => v * scale;

    final configH = _step == _ConfigStep.doses ? s(560) : s(480);

    final double stripW = s(800);
    final double stripH = s(1383);

    final double wheelBoxH = s(1000);
    final double wheelBoxW = size.width;

    double cx(double w) => (size.width - w) / 2;

    final bottomSlide = (_configOpen || _infoOpen)
        ? const Offset(0, 0.30)
        : Offset.zero;

    final wheelLocked = _pendingSlot;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFC75469),
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Stack(
          children: [
            // --- TOP BAR ---
            Positioned(
              right: 0,
              left: 0,
              top: s(0),
              child: Container(height: s(140), color: const Color(0xFFFF6D87)),
            ),

            // --- WEEKLY PILLBOX (Rive) ---
            AnimatedPositioned(
              duration: _pillboxSlideDur,
              curve: Curves.easeInOutCubic,
              left: _pillboxLeftForDay(
                size: size,
                s: s,
                designW: designW,
                todayIndex: _pillboxVisualDay, // ✅ slide uses visual day
              ),
              bottom: s(-70),
              child: SizedBox(
                width: s(800),
                height: s(1383),
                child: WeeklyPillboxOrganizer(
                  key: ValueKey(
                    'pillbox_${_pillboxResetToken}_day_${_todayIndex}',
                  ),

                  fit: BoxFit.contain,

                  // keep closed during slide, only open AFTER slide finishes
                  openDays: _allowPillboxOpen ? <int>{_todayIndex} : <int>{},

                  stateMachineName: 'PillboxSM',
                ),
              ),
            ),

            Positioned(
              right: 0,
              left: 0,
              top: s(140),
              child: Container(
                height: s(5),
                color: const Color.fromARGB(255, 158, 52, 69),
              ),
            ),

            // --- LOGO (left) ---
            Positioned(
              top: s(24),
              left: s(0),
              right: s(185),
              child: Opacity(
                opacity: 0.75,
                child: Image.asset(
                  'assets/images/pillchecker_logo.png',
                  width: s(150),
                  height: s(150),
                ),
              ),
            ),

            // --- TITLE (center) ---
            Positioned(
              top: s(40),
              left: 35,
              right: 0,
              child: Center(
                child: Transform.scale(
                  scale: 0.5,
                  child: Text(
                    'PillChecker',
                    style: TextStyle(
                      fontSize: fs(77.9),
                      fontFamily: 'Amaranth',
                      color: const Color(0xFF98404F),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),

            // --- DAILY COMPLETION CIRCLE (auto fill animation) ---
            Positioned(
              left: cx(s(80.1)),
              bottom: s(674),
              child: FutureBuilder<Map<String, dynamic>>(
                future: _checkMapFuture,
                builder: (context, snap) {
                  final map = snap.data ?? {};

                  final actualDone = _areAllPillsComplete(map);

                  // wait until pillbox open animation window is finished
                  final doneForCircle = actualDone && _allowDailyFillAnim;

                  return DailyCompletionCircle(
                    done: doneForCircle,
                    size: s(77.1),
                    baseColor: const Color.fromARGB(0, 231, 36, 153),
                    fillColor: const Color(0xFF59FF56),
                  );
                },
              ),
            ),

            // --- BOTTOM ZONE ---
            IgnorePointer(
              ignoring: _configOpen || _infoOpen,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                offset: bottomSlide,
                child: Stack(
                  children: [
                    // --- RED STRIP (background) ---
                    Positioned(
                      left: cx(stripW),
                      bottom: s(-910),
                      child: ClipOval(
                        child: Container(
                          width: stripW,
                          height: stripH,
                          color: const Color(0xFFE72447),
                        ),
                      ),
                    ),

                    Positioned(
                      left: _leftFromDesignRight(400, 5, size, s, designW),
                      bottom: s(-1055),
                      child: ClipOval(
                        child: Container(
                          width: s(400),
                          height: s(1383),
                          color: const Color(0xFFFF6D87),
                        ),
                      ),
                    ),

                    // --- WHEEL (below button/rings so it doesn't steal touches) ---
                    Positioned(
                      left: cx(wheelBoxW),
                      width: wheelBoxW,
                      bottom: s(-95),
                      height: wheelBoxH,
                      child: PillWheel(
                        onDeleteCentered: _deleteCenteredPill,
                        controller: _wheelController,
                        displayPillCount: _displayPillCount,
                        realPillCount: _realPillCount,
                        scrollEnabled: !wheelLocked,
                        addEnabled: !wheelLocked,
                        onSelectedChanged: (i) {
                          if (i != _wheelSelectedIndex) _clearCheckedMessage();
                          setState(() => _wheelSelectedIndex = i);
                          _scheduleCenteredDoseBoundaryRefresh();
                        },
                        onAddPressed: () => _startAddFlow(createNewSlot: true),
                      ),
                    ),

                    // --- GREEN OUTER RING ---
                    Positioned(
                      left: _leftFromDesignRight(175, 118, size, s, designW),
                      bottom: s(80),
                      child: ClipOval(
                        child: Container(
                          width: s(175),
                          height: s(175),
                          color: const Color(0xFF0CF000),
                        ),
                      ),
                    ),

                    // --- DARK RED RING ---
                    Positioned(
                      left: _leftFromDesignRight(155, 127.5, size, s, designW),
                      bottom: s(90),
                      child: ClipOval(
                        child: Container(
                          width: s(155),
                          height: s(155),
                          color: const Color(0xFF8C1C2F),
                        ),
                      ),
                    ),

                    // --- CHECK BUTTON (last so it gets touches) ---
                    Positioned(
                      left: _leftFromDesignRight(135, 137, size, s, designW),
                      bottom: s(100),
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: _checkMapFuture,
                        builder: (context, snap) {
                          final pillIndex = _centerPillIndex;
                          final map = snap.data ?? {};

                          // only keep this line if you actually declared _lastCheckMapCache
                          _lastCheckMapCache = map;

                          bool checked = false;
                          if (pillIndex != null) {
                            final doses = _doseTimesForPill(pillIndex);
                            final w = _computeDoseWindow(
                              now: DateTime.now(),
                              dosesSorted: doses,
                            );
                            final cycleIso = w.cycleStart.toIso8601String();

                            checked = _isDoseCheckedSync(
                              map,
                              pillIndex,
                              cycleIso,
                              w.doseIndex,
                            );
                          }

                          final bool disable =
                              _configOpen ||
                              _pendingSlot ||
                              (_wheelSelectedIndex == 0) ||
                              (pillIndex == null);

                          return AbsorbPointer(
                            absorbing: disable,
                            child: PillCheckButton(
                              checked: checked,
                              onChecked: _checkCenteredPill,
                              size: s(135),
                              baseColor: const Color(0xFFFF002E),
                              fillColor: const Color(0xFF59FF56),
                            ),
                          );
                        },
                      ),
                    ),

                    // --- Bottom-left oval ---
                    Positioned(
                      left: s(-85),
                      bottom: s(-100),
                      child: ClipOval(
                        child: Container(
                          width: s(200),
                          height: s(200),
                          color: const Color(0xFF59FF56),
                        ),
                      ),
                    ),

                    // --- INFO BUTTON (bottom-left green i) ---
                    Positioned(
                      left: s(5),
                      bottom: s(5),
                      child: IgnorePointer(
                        ignoring:
                            _configOpen || _pendingSlot || !_centerIsRealPill,
                        child: Opacity(
                          opacity:
                              (_configOpen ||
                                  _pendingSlot ||
                                  !_centerIsRealPill)
                              ? 0.45
                              : 1.0,
                          child: GestureDetector(
                            onTap: _openInfoPanel,
                            child: SizedBox(
                              width: s(82),
                              height: s(82),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // green base
                                  Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF59FF56),
                                    ),
                                  ),

                                  // dark ring
                                  Container(
                                    width: s(74),
                                    height: s(74),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        width: s(5),
                                        color: const Color.fromARGB(
                                          255,
                                          255,
                                          255,
                                          255,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // "i" (dot + stem) built from shapes
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: s(10),
                                        height: s(10),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color.fromARGB(
                                            255,
                                            255,
                                            255,
                                            255,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: s(6)),
                                      Container(
                                        width: s(10),
                                        height: s(30),
                                        decoration: BoxDecoration(
                                          color: const Color.fromARGB(
                                            255,
                                            255,
                                            255,
                                            255,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            s(8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- Bottom-right oval ---
                    Positioned(
                      right: s(-85),
                      bottom: s(-100),
                      child: ClipOval(
                        child: Container(
                          width: s(200),
                          height: s(200),
                          color: const Color(0xFFFFDF59),
                        ),
                      ),
                    ),
                    // --- WARNING ICON (bottom-right) ---
                    Positioned(
                      right: s(5),
                      bottom: s(5),
                      child: IgnorePointer(
                        ignoring: _configOpen || _infoOpen,
                        child: Opacity(
                          opacity: (_configOpen || _infoOpen) ? 0.45 : 1.0,
                          child: GestureDetector(
                            onTap: () {
                              // TODO: override button functionality later
                            },
                            child: ClipOval(
                              child: Container(
                                width: s(82),
                                height: s(82),
                                color: const Color(0xFFFFDF59),
                                child: Center(
                                  child: Icon(
                                    Icons.warning_rounded,
                                    size: s(75),
                                    color: const Color(0xFFE72447),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- CENTER PILL NAME ---
            Positioned(
              left: s(0),
              right: s(0),
              bottom: s(477),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeInOut,
                  opacity: _showPillLabel ? 1.0 : 0.0,
                  child: Center(
                    child: Builder(
                      builder: (context) {
                        final pillIndex = _centerPillIndex;

                        String displayName =
                            _labelOverride ?? _centerPillName();

                        if (_labelOverride == null && pillIndex != null) {
                          final doses = _doseTimesForPill(pillIndex);
                          if (doses.length > 1) {
                            final w = _computeDoseWindow(
                              now: DateTime.now(),
                              dosesSorted: doses,
                            );
                            displayName =
                                '${_centerPillName()} (Dose ${w.doseIndex + 1})';
                          }
                        }

                        return Text(
                          displayName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Amaranth',
                            fontSize: fs(25),
                            color: const Color.fromARGB(225, 255, 255, 255),
                            fontWeight: FontWeight.w400,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // --- TOP OVALS ---
            Positioned(
              left: s(-75),
              top: s(40),
              child: ClipOval(
                child: Container(
                  width: s(150),
                  height: s(85),
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),

            // --- DIRECTORY ICON (top-left) ---
            Positioned(
              left: s(-10),
              top: s(45),
              child: IgnorePointer(
                ignoring: _configOpen || _infoOpen,
                child: Opacity(
                  opacity: (_configOpen || _infoOpen) ? 0.45 : 1.0,
                  child: SizedBox(
                    width: s(88),
                    height: s(70),
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(s(999)),
                          onTap: () {
                            // TODO: directory button functionality later
                          },
                          child: SizedBox(
                            width: s(80),
                            height: s(65),
                            child: Center(
                              child: Icon(
                                Icons
                                    .format_list_bulleted, // ✅ closest to "dots + lines"
                                size: s(56),
                                color: const Color.fromARGB(
                                  255,
                                  60,
                                  59,
                                  59,
                                ).withOpacity(0.70),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              right: s(-75),
              top: s(40),
              child: ClipOval(
                child: Container(
                  width: s(150),
                  height: s(85),
                  color: const Color(0xFFB4B4B4),
                ),
              ),
            ),
            Positioned(
              right: s(-45),
              top: s(40),
              child: SizedBox(
                width: s(150),
                height: s(85),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        s(999),
                      ), // big soft circle
                      onTap: () async {
                        final changed = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );

                        if (!mounted) return;

                        debugPrint('HOME: settings returned changed=$changed');

                        if (changed == true) {
                          // reload NotificationService settings + re-sync schedules
                          await NotificationService.loadUserNotificationSettings();
                          await _syncDoseNotifications(forceReschedule: true);

                          // dump pending scheduled notifications so we can verify they're actually scheduled
                          await NotificationService.debugDumpPending(
                            'after_settings_resync',
                          );
                        }
                      },
                      child: SizedBox(
                        width: s(80), // ✅ use the whole oval area
                        height: s(75),
                        child: Center(
                          child: Icon(
                            Icons.settings,
                            size: s(60), // ✅ this will actually look big now
                            color: const Color.fromARGB(
                              255,
                              60,
                              59,
                              59,
                            ).withOpacity(0.65),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- INFO PANEL (topmost-ish) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              left: s(18),
              right: s(18),
              top: _infoOpen
                  ? s(165)
                  : MediaQuery.of(context).size.height + s(50),
              height: s(520),
              child: Builder(
                builder: (_) {
                  final idx = _centerPillIndex;
                  final name = (idx == null) ? '' : pillNames[idx];

                  final doses = (idx == null)
                      ? <TimeOfDay>[]
                      : _doseTimesForPill(idx);
                  final doseLabels = doses.map(_fmt).toList();

                  return PillInfoPanel(
                    pillName: name,
                    doseTimesLabel: doseLabels,
                    onClose: _closeInfoPanel,
                    onEdit: () {
                      final pillIndex = _centerPillIndex;
                      if (pillIndex == null) return;
                      _startEditFlow(pillIndex);
                    },
                  );
                },
              ),
            ),

            // --- CONFIG PANEL (topmost) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              left: s(18),
              right: s(18),
              top: _configOpen
                  ? s(160)
                  : MediaQuery.of(context).size.height + s(50),
              height: configH,
              child: _configPanel(),
            ),
          ],
        ),
      ),
    );
  }
}

class DayCompleteCircle extends StatelessWidget {
  const DayCompleteCircle({super.key, required this.complete, this.size = 120});

  final bool complete;
  final double size;

  @override
  Widget build(BuildContext context) {
    final baseRed = const Color(0xFFFF002E);
    final green = const Color(0xFF59FF56);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: Container(
              width: size,
              height: size,
              color: complete ? green : baseRed,
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: complete ? 1.0 : 0.0,
            child: Icon(Icons.check, color: Colors.white, size: size * 0.55),
          ),
        ],
      ),
    );
  }
}
