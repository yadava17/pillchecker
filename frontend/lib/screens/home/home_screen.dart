import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:pillchecker/backend/data/offline_medication_suggestions.dart';
import 'package:pillchecker/models/pill_search_item.dart';
import 'package:pillchecker/widgets/medication_details_sheet.dart';
import 'package:pillchecker/widgets/pill_search_panel.dart';
import 'package:pillchecker/screens/directory/directory_screen.dart';
import 'package:pillchecker/widgets/dose_progress_side_bar.dart';
import 'package:pillchecker/backend/rxnorm/medication_details.dart';
import 'package:pillchecker/backend/services/adherence_service.dart';
import 'package:pillchecker/backend/services/med_service.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';
import 'package:pillchecker/backend/services/medication_prefs_mirror.dart';
import 'package:pillchecker/backend/services/prefs_migration.dart';
import 'package:pillchecker/backend/services/schedule_service.dart';
import 'package:pillchecker/backend/utils/local_date_time.dart';

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

  // -------- supply prefs keys --------
  static const _pillSupplyEnabledKey =
      'pill_supply_enabled_v1'; // JSON List<bool>
  static const _pillSupplyLeftKey = 'pill_supply_left_v1'; // JSON List<int>
  static const _pillSupplyInitKey = 'pill_supply_init_v1'; // JSON List<int>
  static const _pillSupplyLowSentKey =
      'pill_supply_low_sent_v1'; // JSON List<bool>

  static const _pillNameLockedKey = 'pill_name_locked_v1'; // JSON List<bool>

  // -------- supply in-memory state (aligned with pillNames) --------
  List<bool> pillSupplyEnabled = [];
  List<int> pillSupplyLeft = [];
  List<int> pillSupplyInitial = [];
  List<bool> pillSupplyLowSent = [];
  List<bool> pillNameLocked = []; // aligned with pillNames

  // -------- in-memory state --------
  List<String> pillNames = [];
  List<String> pillTimes = []; // legacy: first dose only
  List<List<String>> pillDoseTimes =
      []; // ["08:00","14:00"...] aligned with pillNames

  /// Parallel to [pillNames] — SQLite medication ids (staging backend).
  List<int> medicationIds = [];
  final MedService _medService = MedService();
  final ScheduleService _scheduleService = ScheduleService();
  final AdherenceService _adherenceService = AdherenceService();
  final RxNormMedicationService _rxNormService = RxNormMedicationService();

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

  bool _searchOpen = false;

  // Used to fill the config panel "info" box when a search item was picked
  String? _selectedPillInfo;

  // edit mode
  int? _editingIndex;
  bool get _isEditing => _editingIndex != null;

  final TextEditingController _nameController = TextEditingController();
  int _timesPerDay = 1;
  TimeOfDay? _singleDoseTime;
  List<TimeOfDay?> _doseTimes = [];

  // -------- supply draft (current config flow) --------
  bool _supplyTrackOn = false;
  int _supplyLeftDraft = 0; // current supply left
  int _supplyInitialDraft = 0; // original starting supply (for later)

  Timer? _labelTimer;
  Timer? _doseBoundaryTimer;
  Timer? _dayBoundaryTimer;
  Timer? _globalBoundaryTimer;

  bool _delayDailyCircleOnce = true;
  Timer? _dailyCircleDelayTimer;
  bool _dailyCircleDelayPassed = false;
  DateTime _lastSeenDay = DateTime.now(); // used to detect new-day resume

  bool _needsDailyCircleDelay = false; // only true during pillbox open sequence

  String? _labelOverride;
  bool _showPillLabel = true;

  String _supplyModeGlobal = 'decide'; // 'decide' | 'on' | 'off'
  int _supplyLowThreshold = 10;
  bool _supplyPromptedThisFlow = false;

  final FocusNode _nameFocus = FocusNode();

  late final FixedExtentScrollController _wheelController =
      FixedExtentScrollController(initialItem: 1);

  bool get _centerIsRealPill => _centerPillIndex != null;

  int _todayIndex = 3; // default Wed for safety
  bool _allowDailyFillAnim = true; // will gate the DailyCompletionCircle fill
  static const Duration _pillboxOpenAnim = Duration(milliseconds: 650);
  int? _debugDayOverride; // null = real day
  int _lastSeenDayKey = -1; // store last "day stamp"

  int _pillboxResetToken = 0;

  // Pillbox-only scale (1.0 = current size). Try 0.90 or 0.85.
  static const double _pillboxScale = 0.75;
  final pbScale = _pillboxScale;

  // what day the pillbox is CURRENTLY positioned to (for sliding)
  int _pillboxVisualDay = 3; // default Wed so your current alignment is sane

  // do we allow the pillbox to OPEN yet (we keep it closed during slide)
  bool _allowPillboxOpen = false;

  // slide timing
  Duration _pillboxSlideDur = const Duration(milliseconds: 650);
  Timer? _pillboxSlideTimer;

  bool _coldStart = true; // first time screen shows after app launch

  bool _notifRefreshBusy = false;

  bool _lockPillName = false; // true = hide/disable edit-name UI

  int _supplyBadgeCacheValue = 0; // last displayed number (prevents "0 flash")

  // ---------------- lifecycle ----------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastSeenDay = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _coldStart = false);
    });

    _lastSeenDayKey =
        DateTime.now().year * 10000 +
        DateTime.now().month * 100 +
        DateTime.now().day;
    Timer(_pillboxOpenAnim, () {
      if (!mounted) return;
      setState(() => _allowDailyFillAnim = true);
    });
    _checkMapFuture = Future.value(<String, dynamic>{});
    _loadAndMaybeAutoOpen();
    unawaited(_loadSupplyGlobalSettings());
    _coldStartOpenToday();
    _scheduleGlobalDayBoundaryRefresh();
    _scheduleGlobalBoundaryRefresh();
    _scheduleCenteredDoseBoundaryRefresh();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pillboxSlideTimer?.cancel();
    _nameFocus.dispose();

    _labelTimer?.cancel();
    _dailyCircleDelayTimer?.cancel();
    _doseBoundaryTimer?.cancel();
    _dayBoundaryTimer?.cancel();
    _globalBoundaryTimer?.cancel();

    _nameController.dispose();
    _wheelController.dispose();
    _rxNormService.dispose();

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

  Future<void> _persistSupplyLists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pillSupplyEnabledKey, jsonEncode(pillSupplyEnabled));
    await prefs.setString(_pillSupplyLeftKey, jsonEncode(pillSupplyLeft));
    await prefs.setString(_pillSupplyInitKey, jsonEncode(pillSupplyInitial));
    await prefs.setString(_pillSupplyLowSentKey, jsonEncode(pillSupplyLowSent));
  }

  Future<void> _consumeOneSupplyIfEnabled(int pillIndex) async {
    if (pillIndex < 0 || pillIndex >= pillNames.length) return;

    _alignSupplyListsToCount(pillNames.length);

    // ✅ obey global mode
    if (!_effectiveSupplyOn(pillIndex)) return;

    final oldLeft = pillSupplyLeft[pillIndex];

    // if supply was never set (0), don't spam warnings
    if (oldLeft <= 0) {
      return;
    }

    final newLeft = (oldLeft - 1).clamp(0, 1000000);
    final hitZeroNow = (oldLeft > 0 && newLeft == 0);

    // Align safety (should already be aligned, but avoid crashes)
    while (pillSupplyEnabled.length < pillNames.length)
      pillSupplyEnabled.add(false);
    while (pillSupplyLeft.length < pillNames.length) pillSupplyLeft.add(0);
    while (pillSupplyInitial.length < pillNames.length)
      pillSupplyInitial.add(0);
    while (pillSupplyLowSent.length < pillNames.length)
      pillSupplyLowSent.add(false);

    if (!pillSupplyEnabled[pillIndex]) return;

    // Update memory immediately (fast UI)
    setState(() {
      pillSupplyLeft[pillIndex] = newLeft;
    });

    // Persist in background (don’t block the check animation/UI)
    unawaited(_persistSupplyLists());

    // Low supply notification (once) when it goes under threshold
    final alreadySent = pillSupplyLowSent[pillIndex];

    // ✅ only warn when we CROSS into low territory and we had real supply
    final shouldWarnLow =
        !alreadySent && newLeft > 0 && newLeft < _supplyLowThreshold;

    if (shouldWarnLow) {
      setState(() => pillSupplyLowSent[pillIndex] = true);
      unawaited(_saveSupplyListsToPrefs());

      unawaited(
        NotificationService.scheduleLowSupplyWarning(
          pillSlot: pillIndex,
          pillName: pillNames[pillIndex],
        ),
      );
    }

    if (hitZeroNow) {
      // low warning no longer relevant
      unawaited(
        NotificationService.cancelLowSupplyWarning(pillSlot: pillIndex),
      );

      unawaited(
        NotificationService.scheduleOutOfSupplyWarning(
          pillSlot: pillIndex,
          pillName: pillNames[pillIndex],
        ),
      );
    }
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

  // Replace your existing _resyncNotifsAfterPillChange() with this:
  Future<void> _resyncNotifsAfterPillChange() async {
    unawaited(_rebuild2DayNotifWindowAndReMuteChecked(tag: 'pill-change'));
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

    _armDailyCircleDelay();
    _startNewDaySequence(today: today);
  }

  Future<void> _maybeResetForNewCycle() async {
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final cycleStart = _globalCycleStartForNow(now);
    if (cycleStart == null) return;

    final currentIso = cycleStart.toIso8601String();
    final lastIso = prefs.getString(kLastCycleStartKey);

    if (lastIso == currentIso) return; // same cycle, nothing to do

    // New cycle/day → clear check state so notifications can schedule again
    final cleared = <String, dynamic>{};
    await _saveCheckMap(cleared);
    _setCheckMapAndRebuild(cleared);
    _refreshCheckMapFuture();

    await prefs.setString(kLastCycleStartKey, currentIso);

    debugPrint('CYCLE RESET: $lastIso -> $currentIso (cleared checkMap)');
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
    final stored = _lastCheckMapCache['$pillIndex'] as String?;
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
      _lockPillName = (pillIndex < pillNameLocked.length)
          ? pillNameLocked[pillIndex]
          : false;
      _editingIndex = pillIndex;
      _infoOpen = false;
      _configOpen = true;

      _supplyPromptedThisFlow = false;
      _maybeAutoPromptSupply();

      _nameController.text = pillNames[pillIndex];
      _timesPerDay = doses.length;

      _supplyTrackOn = (pillIndex < pillSupplyEnabled.length)
          ? pillSupplyEnabled[pillIndex]
          : false;

      _supplyLeftDraft = (pillIndex < pillSupplyLeft.length)
          ? pillSupplyLeft[pillIndex]
          : 0;

      _supplyInitialDraft = (pillIndex < pillSupplyInitial.length)
          ? pillSupplyInitial[pillIndex]
          : 0;

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
    if (pillNames.isEmpty) {
      _lastCheckMapCache = {};
      return {};
    }
    if (medicationIds.length != pillNames.length) {
      await _hydrateMedicationsFromDatabase();
    }
    final map = await _deriveCheckMapFromDatabase();
    _lastCheckMapCache = map;
    return map;
  }

  Future<void> _hydrateMedicationsFromDatabase() async {
    final meds = await _medService.getAll();
    medicationIds = meds.map((m) => m.id).toList();
    pillNames = meds.map((m) => m.name).toList();
    pillTimes = [];
    pillDoseTimes = [];
    pillSupplyEnabled = [];
    pillSupplyLeft = [];
    pillSupplyInitial = [];
    pillNameLocked = [];

    for (final m in meds) {
      pillSupplyEnabled.add(m.supplyEnabled);
      pillSupplyLeft.add(m.supplyLeft);
      pillSupplyInitial.add(m.supplyInitial);
      pillNameLocked.add(m.nameLocked);

      final sch = await _scheduleService.getScheduleForMedication(m.id);
      var times = <String>['08:00'];
      if (sch != null) {
        times =
            (jsonDecode(sch['times_json']! as String) as List)
                .map((e) => e.toString())
                .toList()
              ..sort((a, b) => a.compareTo(b));
      }
      pillDoseTimes.add(times);
      pillTimes.add(times.isNotEmpty ? times.first : '08:00');
    }

    final prefs = await SharedPreferences.getInstance();
    final lowSent = _decodeBoolList(prefs.getString(_pillSupplyLowSentKey));
    pillSupplyLowSent = List.generate(
      pillNames.length,
      (i) => i < lowSent.length ? lowSent[i] : false,
    );
  }

  Future<void> _refreshAdherenceFromDb() async {
    if (medicationIds.isEmpty) return;
    await _scheduleService.ensureDoseEventsForMedications(medicationIds);
    await _adherenceService.autoMarkMissedPastPlanned();
    final map = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(map);
    if (!mounted) return;
    _setCheckMapAndRebuild(map);
  }

  Future<Map<String, dynamic>> _deriveCheckMapFromDatabase() async {
    final map = <String, dynamic>{};
    final now = DateTime.now();
    for (var i = 0; i < pillNames.length; i++) {
      if (i >= medicationIds.length) continue;
      final doses = _doseTimesForPill(i);
      if (doses.isEmpty) continue;
      final w = _computeDoseWindow(now: now, dosesSorted: doses);
      final cycleDay = DateTime(
        w.cycleStart.year,
        w.cycleStart.month,
        w.cycleStart.day,
      );
      final mid = medicationIds[i];
      final events = await _adherenceService
          .getDoseEventsForMedicationOnLocalDay(
            medicationId: mid,
            localDay: cycleDay,
          );
      var mask = 0;
      for (final e in events) {
        if (e.status == 'taken') {
          mask |= (1 << e.doseIndex);
        }
      }
      map['$i'] = _packCycleAndMask(w.cycleStart.toIso8601String(), mask);
    }
    return map;
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

  List<TimeOfDay> _doseTimesForPillFromLists(
    List<List<String>> doseTimes24h,
    int pillIndex,
  ) {
    if (pillIndex < 0 || pillIndex >= doseTimes24h.length) {
      return [const TimeOfDay(hour: 8, minute: 0)];
    }

    final list = doseTimes24h[pillIndex];
    final times = list.map(_strToTime).toList();

    times.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );
    return times;
  }

  Future<void> _muteAlreadyCheckedDosesToday({
    required Map<String, dynamic> checkMap,
    required List<String> names,
    required List<List<String>> doseTimes24h,
  }) async {
    final now = DateTime.now();

    for (int pillIndex = 0; pillIndex < names.length; pillIndex++) {
      final doses = _doseTimesForPillFromLists(doseTimes24h, pillIndex);
      if (doses.isEmpty) continue;

      // What cycle are we currently in for THIS pill?
      final w = _computeDoseWindow(now: now, dosesSorted: doses);
      final cycleIsoNow = w.cycleStart.toIso8601String();

      final stored = checkMap['$pillIndex'] as String?;
      final parsed = _readCycleAndMask(stored);

      if (parsed.cycleIso != cycleIsoNow) continue;

      final totalDoses = doses.length;
      final mask = parsed.mask;

      for (int doseIndex = 0; doseIndex < totalDoses; doseIndex++) {
        final checked = (mask & (1 << doseIndex)) != 0;
        if (!checked) continue;

        // Cancel today's early/main/late for this checked dose
        await NotificationService.muteToday(
          pillSlot: pillIndex,
          doseIndex: doseIndex,
          dosesPerDay: totalDoses,
          muteRemainingDoses: false,
        );
      }
    }
  }

  Future<void> _rebuild2DayNotifWindow({String reason = ''}) async {
    final prefs = await SharedPreferences.getInstance();

    await NotificationService.loadUserNotificationSettings();

    final names = prefs.getStringList(_pillNamesKey) ?? [];
    final doseTimes24h = _decodeListOfStringLists(
      prefs.getString(_pillDoseTimesKey),
    );

    // Align doseTimes to names (source of truth)
    while (doseTimes24h.length < names.length) doseTimes24h.add(['08:00']);
    if (doseTimes24h.length > names.length) {
      doseTimes24h.removeRange(names.length, doseTimes24h.length);
    }

    // 1) Rebuild today+tomorrow
    await NotificationService.rebuild2DayWindow(
      pillNames: names,
      doseTimes24h: doseTimes24h,
    );

    // 2) Re-apply mutes for anything already checked today
    final checkMap = await _loadCheckMap();
    await _muteAlreadyCheckedDosesToday(
      checkMap: checkMap,
      names: names,
      doseTimes24h: doseTimes24h,
    );

    await NotificationService.rescheduleInactivityWarning(
      doseTimes24h: doseTimes24h,
    );

    debugPrint('NOTIF: rebuilt 2-day window ($reason) pills=${names.length}');
  }

  String _packCycleAndMask(String cycleIso, int mask) => '$cycleIso|$mask';

  int _bitCount(int x) {
    var n = 0;
    while (x != 0) {
      x &= (x - 1);
      n++;
    }
    return n;
  }

  Future<void> _rebuild2DayNotifWindowAndReMuteChecked({
    String tag = '',
  }) async {
    if (_notifRefreshBusy) {
      debugPrint('NOTIF: skip rebuild (busy) tag=$tag');
      return;
    }
    _notifRefreshBusy = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1) Source-of-truth from prefs (NOT in-memory lists)
      final names = prefs.getStringList(_pillNamesKey) ?? <String>[];

      var doseTimes24h = _decodeListOfStringLists(
        prefs.getString(_pillDoseTimesKey),
      );

      // keep doseTimes aligned
      while (doseTimes24h.length < names.length) {
        doseTimes24h.add(<String>['08:00']);
      }
      if (doseTimes24h.length > names.length) {
        doseTimes24h.removeRange(names.length, doseTimes24h.length);
      }

      // 2) Rebuild today+tomorrow schedules
      await NotificationService.rebuild2DayWindow(
        pillNames: names,
        doseTimes24h: doseTimes24h,
      );

      await NotificationService.debugDumpPending('after_rebuild_window');

      // 3) IMPORTANT: re-mute any already-checked doses FOR TODAY
      // This prevents rebuild from "unmuting" after someone checks early.
      final map = await _loadCheckMap(); // also refreshes _lastCheckMapCache
      final now = DateTime.now();

      for (int pillIndex = 0; pillIndex < names.length; pillIndex++) {
        final rawTimes = (pillIndex < doseTimes24h.length)
            ? doseTimes24h[pillIndex]
            : <String>['08:00'];

        // Build sorted TimeOfDay list for this pill
        final dosesSorted = rawTimes.map(_strToTime).toList()
          ..sort(
            (a, b) =>
                (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
          );

        if (dosesSorted.isEmpty) continue;

        // What cycle are we in right now (based on your 2-hours-before-first-dose rule)?
        final w = _computeDoseWindow(now: now, dosesSorted: dosesSorted);
        final cycleIsoNow = w.cycleStart.toIso8601String();

        final stored = map['$pillIndex'] as String?;
        final parsed = _readCycleAndMask(stored);

        if (parsed.cycleIso != cycleIsoNow) continue;

        final mask = parsed.mask;
        for (int doseIndex = 0; doseIndex < dosesSorted.length; doseIndex++) {
          final checked = (mask & (1 << doseIndex)) != 0;
          if (!checked) continue;

          await NotificationService.muteToday(
            pillSlot: pillIndex,
            doseIndex: doseIndex,
            dosesPerDay: dosesSorted.length,
            muteRemainingDoses: false, // keep your current behavior
          );

          await NotificationService.rescheduleInactivityWarning(
            doseTimes24h: doseTimes24h,
          );
        }
      }

      debugPrint('NOTIF: rebuild2Day + re-mute complete tag=$tag');
    } catch (e, st) {
      debugPrint('NOTIF: rebuild2Day failed tag=$tag err=$e\n$st');
    } finally {
      _notifRefreshBusy = false;
    }
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

      final first = doses.first;
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

    _globalBoundaryTimer = Timer(diff, () async {
      if (!mounted) return;

      _refreshCheckMapFuture();

      await _rebuild2DayNotifWindow(reason: 'initial-load');

      if (!mounted) return;
      _scheduleGlobalBoundaryRefresh();
    });
  }

  Future<void> _scheduleGlobalDayBoundaryRefresh() async {
    _dayBoundaryTimer?.cancel();
    _dayBoundaryTimer = null;

    final now = DateTime.now();
    final cycleStart = _globalCycleStartForNow(now);
    if (cycleStart == null) return;

    final nextCycleStart = cycleStart.add(const Duration(days: 1));
    final diff = nextCycleStart.difference(now);

    if (diff.inMilliseconds <= 50) {
      if (!mounted) return;
      setState(() {
        _checkMapFuture = _loadCheckMap();
      });
      return;
    }

    _dayBoundaryTimer = Timer(diff, () async {
      if (!mounted) return;

      setState(() {
        _checkMapFuture = _loadCheckMap();
      });

      unawaited(_rebuild2DayNotifWindowAndReMuteChecked(tag: 'day-boundary'));

      if (!mounted) return;
      unawaited(_scheduleGlobalDayBoundaryRefresh());
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
    final next = w.windowEnd;

    final diff = next.difference(DateTime.now());
    if (diff.inMilliseconds <= 50) {
      if (!mounted) return;
      setState(() {});
      return;
    }

    _doseBoundaryTimer = Timer(diff, () {
      if (!mounted) return;

      _checkMapFuture = _loadCheckMap();
      setState(() {});

      _scheduleCenteredDoseBoundaryRefresh();
    });
  }

  // ---------------- selection helpers ----------------
  int? get _centerPillIndex {
    final idx = _wheelSelectedIndex - 1;
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

  double _leftFromDesignRightScaled(
    double baseW,
    double baseRight,
    Size screenSize,
    double Function(double) s,
    double designW,
    double scale,
  ) {
    final elementW = s(baseW) * scale;

    final designCenterX = designW / 2;
    final elementCenterX = designW - baseRight - (baseW / 2);
    final offsetFromCenter = elementCenterX - designCenterX;

    // ✅ scale the offset-from-center too, since the pillbox is scaled down
    return (screenSize.width / 2) +
        (s(offsetFromCenter) * scale) -
        (elementW / 2);
  }

  void _alignSupplyListsToCount(int count) {
    while (pillSupplyEnabled.length < count) pillSupplyEnabled.add(false);
    if (pillSupplyEnabled.length > count) {
      pillSupplyEnabled.removeRange(count, pillSupplyEnabled.length);
    }

    while (pillSupplyLeft.length < count) pillSupplyLeft.add(0);
    if (pillSupplyLeft.length > count) {
      pillSupplyLeft.removeRange(count, pillSupplyLeft.length);
    }

    while (pillSupplyInitial.length < count) pillSupplyInitial.add(0);
    if (pillSupplyInitial.length > count) {
      pillSupplyInitial.removeRange(count, pillSupplyInitial.length);
    }

    while (pillSupplyLowSent.length < count) pillSupplyLowSent.add(false);
    if (pillSupplyLowSent.length > count) {
      pillSupplyLowSent.removeRange(count, pillSupplyLowSent.length);
    }
  }

  void _maybeAutoPromptSupply() {
    if (_supplyModeGlobal != 'on') return;
    if (_supplyPromptedThisFlow) return;
    if (_supplyLeftDraft > 0) return;

    _supplyPromptedThisFlow = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _editSupplyDialog(setInitialToo: true);
    });
  }

  Future<void> _saveSupplyListsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pillSupplyEnabledKey, jsonEncode(pillSupplyEnabled));
    await prefs.setString(_pillSupplyLeftKey, jsonEncode(pillSupplyLeft));
    await prefs.setString(_pillSupplyInitKey, jsonEncode(pillSupplyInitial));
    await prefs.setString(_pillSupplyLowSentKey, jsonEncode(pillSupplyLowSent));
  }

  double _pillboxLeftForDay({
    required Size size,
    required double Function(double) s,
    required double designW,
    required int todayIndex,
    required double scale, // 0=Sun..6=Sat
  }) {
    final wedLeft = _leftFromDesignRightScaled(
      400,
      198,
      size,
      s,
      designW,
      scale,
    );
    const base = 92.6;
    const growth = 0.4;

    double cumulative(int day) {
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

    // scale the day-to-day shift too, since the pillbox is smaller
    return wedLeft - (s(correctedShift) * scale);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    unawaited(_refreshAdherenceFromDb());

    final now = DateTime.now();
    final dayKey = now.year * 10000 + now.month * 100 + now.day;

    if (dayKey == _lastSeenDayKey) return;
    _lastSeenDayKey = dayKey;

    _rearmDailyCircleDelay();

    final newToday = _debugDayOverride ?? (now.weekday % 7);

    _armDailyCircleDelay();
    unawaited(_rebuild2DayNotifWindowAndReMuteChecked(tag: 'resume'));
    _startNewDaySequence(today: newToday);
  }

  void _rearmDailyCircleDelay() {
    _dailyCircleDelayTimer?.cancel();
    _dailyCircleDelayTimer = null;

    _dailyCircleDelayPassed = false;
    _delayDailyCircleOnce = true;
  }

  void _armDailyCircleDelay({Duration delay = const Duration(seconds: 1)}) {
    _dailyCircleDelayTimer?.cancel();

    _needsDailyCircleDelay = true;
    _allowDailyFillAnim = false;

    _dailyCircleDelayTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _allowDailyFillAnim = true;
        _needsDailyCircleDelay = false;
      });
    });
  }

  Future<void> _loadSupplyGlobalSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final mode = prefs.getString(kSupplyModeKey) ?? 'decide';

    // User chooses the number where it should turn yellow / notify ("when supply is at:")
    // We store +1 internally because our logic uses "< threshold"
    final lowUser = (prefs.getInt(kSupplyLowThresholdKey) ?? 10).clamp(5, 999);
    final lowForLessThanLogic = lowUser + 1;

    if (!mounted) return;
    setState(() {
      _supplyModeGlobal = mode;
      _supplyLowThreshold = lowForLessThanLogic;
    });
  }

  bool _effectiveSupplyOn(int pillIndex) {
    if (_supplyModeGlobal == 'off') return false;
    if (_supplyModeGlobal == 'on') return true;
    return pillIndex < pillSupplyEnabled.length && pillSupplyEnabled[pillIndex];
  }

  Future<bool> _ensureSupplyIfRequired() async {
    final required =
        (_supplyModeGlobal == 'on') ||
        (_supplyModeGlobal == 'decide' && _supplyTrackOn);

    if (!required) return true;
    if (_supplyLeftDraft > 0) return true;

    await _editSupplyDialog(setInitialToo: true);
    return _supplyLeftDraft > 0;
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
    if (_lockPillName) return;
    setState(() => _step = _ConfigStep.name);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.requestFocus();
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

  void _cacheSupplyBadgeIfShowing() {
    final idx = _centerPillIndex;
    if (idx == null) return;

    final isOn =
        idx < pillSupplyEnabled.length && pillSupplyEnabled[idx] == true;

    if (!isOn) return;

    final v = (idx < pillSupplyLeft.length) ? pillSupplyLeft[idx] : 0;
    _supplyBadgeCacheValue = v;
  }

  // ---------------- decode helpers ----------------
  List<List<String>> _decodeListOfStringLists(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List)
        .map((e) => (e as List).map((x) => x.toString()).toList())
        .toList();
  }

  List<bool> _decodeBoolList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List).map((e) => e == true).toList();
  }

  // ---------------- load ----------------
  Future<void> _loadAndMaybeAutoOpen() async {
    final prefs = await SharedPreferences.getInstance();

    await PrefsMigration.runOnceIfNeeded(
      medService: _medService,
      scheduleService: _scheduleService,
    );

    await _hydrateMedicationsFromDatabase();

    await _scheduleService.ensureDoseEventsForMedications(medicationIds);
    await _adherenceService.autoMarkMissedPastPlanned();

    final loadedMap = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(loadedMap);

    await MedicationPrefsMirror.write(
      pillNames: pillNames,
      pillTimesFirst: pillTimes,
      pillDoseTimes: pillDoseTimes,
      pillSupplyEnabled: pillSupplyEnabled,
      pillSupplyLeft: pillSupplyLeft,
      pillSupplyInitial: pillSupplyInitial,
      pillSupplyLowSent: pillSupplyLowSent,
      pillNameLocked: pillNameLocked,
    );

    if (!mounted) return;
    setState(() {
      _checkMapCache = loadedMap;
      _checkMapFuture = Future.value(loadedMap);
    });

    unawaited(_rebuild2DayNotifWindowAndReMuteChecked(tag: 'initial-load'));

    if (pillNames.isEmpty && mounted) {
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

  void _startAddFromDirectory(PillSearchItem item) {
    _hidePillLabelNow();

    final tp = item.suggestedTimesPerDay.clamp(1, 6);

    setState(() {
      // close other overlays/panels
      _searchOpen = false;
      _infoOpen = false;

      // lock name (non-custom)
      _lockPillName = true;

      // load info + name
      _selectedPillInfo = item.info;
      _nameController.text = item.name;

      // open config panel
      _configOpen = true;
      _editingIndex = null;

      // treat like add flow so wheel locks
      _pendingSlot = true;

      // times/day + step
      _timesPerDay = tp;
      _singleDoseTime = null;

      if (tp == 1) {
        _step = _ConfigStep.config;
        _doseTimes = [];
      } else {
        _step = _ConfigStep.doses;
        _doseTimes = List<TimeOfDay?>.filled(tp, null);
      }
    });

    _centerWheelOn(_pendingWheelIndex);
  }

  Future<void> _openDirectoryScreen() async {
    // optional: don’t allow opening while config/search is open
    if (_configOpen || _infoOpen || _searchOpen) return;

    final picked = await Navigator.push<PillSearchItem>(
      context,
      MaterialPageRoute(builder: (_) => const DirectoryScreen()),
    );

    if (!mounted || picked == null) return;

    _startAddFromDirectory(picked);
  }

  void _openPillSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _hidePillLabelNow();

    setState(() {
      _searchOpen = true;

      // Make sure other panels aren't open
      _configOpen = false;
      _infoOpen = false;

      // Don't leave a pending slot from previous flows
      _pendingSlot = false;
      _editingIndex = null;
    });
  }

  void _closePillSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _searchOpen = false);
    _showPillLabelAfterSlide();
  }

  void _pickCustomFromSearch() {
    _selectedPillInfo = null;
    _lockPillName = false;
    _closePillSearch();

    // Your existing flow
    _startAddFlow(createNewSlot: true);
  }

  Future<void> _pickSearchItem(PillSearchItem item) async {
    final already = pillNames.any(
      (p) => p.trim().toLowerCase() == item.name.trim().toLowerCase(),
    );

    if (already) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Already added'),
          content: Text('"${item.name}" is already on your wheel.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return; // ✅ do not open config flow
    }

    MedicationDetails? details;
    if (item.isRxNorm) {
      details = await showModalBottomSheet<MedicationDetails?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (ctx) => MedicationDetailsSheet(
          service: _rxNormService,
          rxcui: item.rxcui!,
          fallbackName: item.name,
        ),
      );
      if (!mounted) return;
      if (details == null) return;
    }

    _applySearchSelection(item, details);
  }

  void _applySearchSelection(PillSearchItem item, MedicationDetails? details) {
    _hidePillLabelNow();

    final tp = item.suggestedTimesPerDay.clamp(1, 6);
    final resolvedName =
        (details != null && details.displayName.trim().isNotEmpty)
        ? details.displayName.trim()
        : item.name;
    final resolvedInfo = details?.userFriendlyInfoText ?? item.info;

    setState(() {
      _supplyTrackOn = false;
      _supplyLeftDraft = 0;
      _supplyInitialDraft = 0;
      _lockPillName = true;
      _searchOpen = false;

      _selectedPillInfo = resolvedInfo;
      _nameController.text = resolvedName;

      _editingIndex = null;
      _infoOpen = false;
      _configOpen = true;

      _supplyPromptedThisFlow = false;
      _maybeAutoPromptSupply();

      _timesPerDay = tp;

      _pendingSlot = true;

      _singleDoseTime = null;

      if (tp == 1) {
        _step = _ConfigStep.config;
        _doseTimes = [];
      } else {
        _step = _ConfigStep.doses;
        _doseTimes = List<TimeOfDay?>.filled(tp, null);
      }
    });

    _centerWheelOn(_pendingWheelIndex);
  }

  // ---------------- config flow ----------------
  void _startAddFlow({required bool createNewSlot}) {
    _hidePillLabelNow();
    setState(() {
      _lockPillName = false;
      _editingIndex = null; // ✅ IMPORTANT: prevent stale edit mode
      _infoOpen = false;

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
    _selectedPillInfo = null;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _supplyTrackOn = false;
      _supplyLeftDraft = 0;
      _supplyInitialDraft = 0;
      _lockPillName = false;
      _configOpen = false;
      _pendingSlot = false;
      _supplyPromptedThisFlow = false;
      _step = _ConfigStep.name;
    });
    _centerWheelOn(1);
    _showPillLabelAfterSlide();
    _maybeAutoPromptSupply();
  }

  void _setCheckMapAndRebuild(Map<String, dynamic> map) {
    _checkMapCache = map;
    _checkMapFuture = Future.value(map);
    if (mounted) setState(() {});
  }

  Future<void> _showSupplyInfoDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supply tracking'),
        content: const Text(
          'This tracks how many pills you have left for this pill.\n\n'
          'Each time you check a dose, the supply will decrease by 1.\n\n'
          'Later: you can enable refill reminders and customize it in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _editSupplyDialog({required bool setInitialToo}) async {
    final controller = TextEditingController(
      text: _supplyLeftDraft > 0 ? _supplyLeftDraft.toString() : '',
    );

    final result = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(setInitialToo ? 'Set starting supply' : 'Edit supply left'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Enter a number (ex: 60)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final v = result.clamp(0, 1000000);

    if (!mounted) return;
    setState(() {
      _supplyLeftDraft = v;
      if (setInitialToo) _supplyInitialDraft = v;
    });
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

  bool get _anyDoseTimeSet =>
      _doseTimes.isNotEmpty && _doseTimes.any((t) => t != null);

  void _handlePrimaryAction() async {
    if (_step == _ConfigStep.name) {
      if (_nameController.text.trim().isEmpty) return;
      setState(() => _step = _ConfigStep.config);
      return;
    }

    final ok = await _ensureSupplyIfRequired();
    if (!ok) return;

    if (_step == _ConfigStep.config) {
      if (_timesPerDay == 1) {
        if (_singleDoseTime == null) return;

        if (_isEditing) {
          _updatePill();
        } else {
          _savePill();
        }
      } else {
        setState(() {
          _step = _ConfigStep.doses;

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
      if (!_anyDoseTimeSet) return;

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
    if (_timesPerDay > 1 && !_anyDoseTimeSet) return;

    final List<TimeOfDay> doses = (_timesPerDay == 1)
        ? <TimeOfDay>[_singleDoseTime!]
        : _doseTimes.whereType<TimeOfDay>().toList();

    doses.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );

    final doseStrings = doses.map(_timeToStr).toList();
    final firstDose = doses.first;

    final prefs = await SharedPreferences.getInstance();

    _alignSupplyListsToCount(pillNames.length);

    final updatedNames = [...pillNames, name];
    await prefs.setStringList(_pillNamesKey, updatedNames);

    final effectiveTrack = (_supplyModeGlobal == 'on')
        ? true
        : (_supplyModeGlobal == 'off')
        ? false
        : _supplyTrackOn;

    final leftToStore = effectiveTrack ? _supplyLeftDraft : 0;
    final initToStore = effectiveTrack
        ? (_supplyInitialDraft > 0 ? _supplyInitialDraft : leftToStore)
        : 0;

    final med = await _medService.create(
      name: name,
      supplyEnabled: effectiveTrack,
      supplyLeft: leftToStore,
      supplyInitial: initToStore,
      nameLocked: _lockPillName,
      sortOrder: pillNames.length,
    );
    await _scheduleService.upsertSchedule(
      medicationId: med.id,
      times24hSorted: doseStrings,
    );
    await _scheduleService.ensureDoseEventsForMedication(med.id);

    // keep arrays aligned BEFORE modifying
    _alignSupplyListsToCount(pillNames.length);

    // append for this new pill
    pillSupplyEnabled.add(effectiveTrack);
    pillSupplyLeft.add(leftToStore);
    pillSupplyInitial.add(initToStore);
    pillSupplyLowSent.add(false);

    // align to NEW count and persist
    _alignSupplyListsToCount(updatedNames.length);
    await _saveSupplyListsToPrefs();

    final existingTimes = prefs.getStringList(_pillTimesKey) ?? [];
    final updatedTimes = [...existingTimes, _timeToStr(firstDose)];
    await prefs.setStringList(_pillTimesKey, updatedTimes);

    final existingDoseTimes = _decodeListOfStringLists(
      prefs.getString(_pillDoseTimesKey),
    );
    final updatedDoseTimes = [...existingDoseTimes, doseStrings];
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));

    final updatedSupplyEnabled = [...pillSupplyEnabled, _supplyTrackOn];
    final updatedSupplyLeft = [
      ...pillSupplyLeft,
      _supplyTrackOn ? _supplyLeftDraft : 0,
    ];
    final updatedSupplyInit = [
      ...pillSupplyInitial,
      _supplyTrackOn
          ? (_supplyInitialDraft > 0 ? _supplyInitialDraft : _supplyLeftDraft)
          : 0,
    ];
    final updatedSupplyLowSent = [...pillSupplyLowSent, false];

    await prefs.setString(
      _pillSupplyEnabledKey,
      jsonEncode(updatedSupplyEnabled),
    );
    await prefs.setString(_pillSupplyLeftKey, jsonEncode(updatedSupplyLeft));
    await prefs.setString(_pillSupplyInitKey, jsonEncode(updatedSupplyInit));
    await prefs.setString(
      _pillSupplyLowSentKey,
      jsonEncode(updatedSupplyLowSent),
    );

    final updatedNameLocked = [...pillNameLocked, _lockPillName];
    await prefs.setString(_pillNameLockedKey, jsonEncode(updatedNameLocked));

    pillSupplyEnabled.add(_supplyTrackOn);
    pillSupplyLeft.add(_supplyTrackOn ? _supplyLeftDraft : 0);
    pillSupplyInitial.add(
      _supplyTrackOn
          ? (_supplyInitialDraft > 0 ? _supplyInitialDraft : _supplyLeftDraft)
          : 0,
    );
    pillSupplyLowSent.add(false);

    // ✅ align again just in case
    _alignSupplyListsToCount(updatedNames.length);

    // ✅ persist
    await _saveSupplyListsToPrefs();

    final checkMap = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(checkMap);
    _setCheckMapAndRebuild(checkMap);
    _refreshCheckMapFuture();

    // ✅ Rebuild notif window
    await _resyncNotifsAfterPillChange();

    if (!mounted) return;
    setState(() {
      medicationIds = [...medicationIds, med.id];
      pillSupplyEnabled = [...pillSupplyEnabled];
      pillSupplyLeft = [...pillSupplyLeft];
      pillSupplyInitial = [...pillSupplyInitial];
      pillSupplyLowSent = [...pillSupplyLowSent];
      pillNameLocked = updatedNameLocked;

      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;

      _lockPillName = false;
      _pendingSlot = false;
      _configOpen = false;
      _step = _ConfigStep.name;
      _selectedPillInfo = null;
    });

    await MedicationPrefsMirror.write(
      pillNames: pillNames,
      pillTimesFirst: pillTimes,
      pillDoseTimes: pillDoseTimes,
      pillSupplyEnabled: pillSupplyEnabled,
      pillSupplyLeft: pillSupplyLeft,
      pillSupplyInitial: pillSupplyInitial,
      pillSupplyLowSent: pillSupplyLowSent,
      pillNameLocked: pillNameLocked,
    );

    _showPillLabelAfterSlide();
    _centerWheelOn(1 + (updatedNames.length - 1));
    _scheduleGlobalBoundaryRefresh();
    _scheduleGlobalDayBoundaryRefresh();
  }

  Future<void> _updatePill() async {
    final pillIndex = _editingIndex;

    // ✅ Guard against stale edit index (ex: deleted pill)
    if (pillIndex == null || pillIndex < 0 || pillIndex >= pillNames.length) {
      debugPrint(
        'UPDATE PILL aborted: editingIndex=$pillIndex pillNamesLen=${pillNames.length}',
      );
      if (mounted) {
        setState(() {
          _editingIndex = null;
          _configOpen = false;
          _step = _ConfigStep.name;
        });
      }
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_timesPerDay == 1 && _singleDoseTime == null) return;
    if (_timesPerDay > 1 && !_anyDoseTimeSet) return;

    final List<TimeOfDay> doses = (_timesPerDay == 1)
        ? <TimeOfDay>[_singleDoseTime!]
        : _doseTimes.whereType<TimeOfDay>().toList();

    doses.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );

    final doseStrings = doses.map(_timeToStr).toList();
    final firstDose = doses.first;

    final prefs = await SharedPreferences.getInstance();

    _alignSupplyListsToCount(pillNames.length);

    final effectiveTrack = (_supplyModeGlobal == 'on')
        ? true
        : (_supplyModeGlobal == 'off')
        ? false
        : _supplyTrackOn;

    pillSupplyEnabled[pillIndex] = effectiveTrack;
    pillSupplyLeft[pillIndex] = effectiveTrack ? _supplyLeftDraft : 0;

    if (effectiveTrack) {
      // keep initial unless not set yet
      if (pillSupplyInitial[pillIndex] <= 0) {
        pillSupplyInitial[pillIndex] = _supplyLeftDraft;
      }
    } else {
      pillSupplyInitial[pillIndex] = 0;
      pillSupplyLowSent[pillIndex] = false;
    }

    // If refilled back above threshold, allow low-warning again + cancel pending warnings
    if (effectiveTrack && _supplyLeftDraft >= _supplyLowThreshold) {
      pillSupplyLowSent[pillIndex] = false;
      unawaited(
        NotificationService.cancelLowSupplyWarning(pillSlot: pillIndex),
      );
    }

    // If tracking off globally or per-pill, cancel warnings too
    if (!effectiveTrack) {
      unawaited(
        NotificationService.cancelLowSupplyWarning(pillSlot: pillIndex),
      );
      unawaited(
        NotificationService.cancelOutOfSupplyWarning(pillSlot: pillIndex),
      );
    }

    // If supply is > 0, cancel any pending out-of-supply warning
    if (effectiveTrack && _supplyLeftDraft > 0) {
      unawaited(
        NotificationService.cancelOutOfSupplyWarning(pillSlot: pillIndex),
      );
    }

    await _saveSupplyListsToPrefs();

    _alignSupplyListsToCount(pillNames.length);

    final isLocked = (pillIndex < pillNameLocked.length)
        ? pillNameLocked[pillIndex]
        : false;

    final updatedNames = [...pillNames];
    if (!isLocked) {
      updatedNames[pillIndex] = name;
    } else {
      // keep original name if locked
      updatedNames[pillIndex] = pillNames[pillIndex];
    }

    final updatedTimes = [...pillTimes];
    if (pillIndex < updatedTimes.length) {
      updatedTimes[pillIndex] = _timeToStr(firstDose);
    }

    final updatedDoseTimes = [...pillDoseTimes];
    if (pillIndex < updatedDoseTimes.length) {
      updatedDoseTimes[pillIndex] = doseStrings;
    }

    await prefs.setStringList(_pillNamesKey, updatedNames);
    await prefs.setStringList(_pillTimesKey, updatedTimes);
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));

    _alignSupplyListsToCount(pillNames.length);

    // ✅ USE existing effectiveTrack (already defined above)
    pillSupplyEnabled[pillIndex] = effectiveTrack;
    pillSupplyLeft[pillIndex] = effectiveTrack ? _supplyLeftDraft : 0;

    // initial + lowSent rules
    if (effectiveTrack) {
      if (pillSupplyInitial[pillIndex] <= 0) {
        pillSupplyInitial[pillIndex] = (_supplyInitialDraft > 0)
            ? _supplyInitialDraft
            : _supplyLeftDraft;
      }

      // ✅ if user refilled above threshold, allow future warnings again
      if (_supplyLeftDraft >= _supplyLowThreshold) {
        pillSupplyLowSent[pillIndex] = false;
        unawaited(
          NotificationService.cancelLowSupplyWarning(pillSlot: pillIndex),
        );
      }

      // ✅ if supply > 0, cancel any pending "out of supply" warning
      if (_supplyLeftDraft > 0) {
        unawaited(
          NotificationService.cancelOutOfSupplyWarning(pillSlot: pillIndex),
        );
      }
    } else {
      pillSupplyInitial[pillIndex] = 0;
      pillSupplyLowSent[pillIndex] = false;

      // ✅ tracking off (either global off or decide+toggle off) => cancel any warnings
      unawaited(
        NotificationService.cancelLowSupplyWarning(pillSlot: pillIndex),
      );
      unawaited(
        NotificationService.cancelOutOfSupplyWarning(pillSlot: pillIndex),
      );
    }

    // ✅ persist ONCE (remove all updatedSupplyEnabled/Left/Init/LowSent blocks)
    await _saveSupplyListsToPrefs();

    if (pillIndex < medicationIds.length) {
      final mid = medicationIds[pillIndex];
      await _medService.update(
        id: mid,
        name: isLocked ? null : name,
        supplyEnabled: effectiveTrack,
        supplyLeft: effectiveTrack ? _supplyLeftDraft : 0,
        supplyInitial: pillSupplyInitial[pillIndex],
      );
      await _scheduleService.upsertSchedule(
        medicationId: mid,
        times24hSorted: doseStrings,
      );
      await _scheduleService.regenerateAfterScheduleChange(mid);
    }

    final checkMap = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(checkMap);
    _setCheckMapAndRebuild(checkMap);
    _refreshCheckMapFuture();

    // ✅ Rebuild notif window
    await _resyncNotifsAfterPillChange();

    if (!mounted) return;
    setState(() {
      pillSupplyEnabled = [...pillSupplyEnabled];
      pillSupplyLeft = [...pillSupplyLeft];
      pillSupplyInitial = [...pillSupplyInitial];
      pillSupplyLowSent = [...pillSupplyLowSent];
      _cacheSupplyBadgeIfShowing();

      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;

      _lockPillName = false;
      _editingIndex = null;
      _configOpen = false;
      _step = _ConfigStep.name;
    });

    await MedicationPrefsMirror.write(
      pillNames: pillNames,
      pillTimesFirst: pillTimes,
      pillDoseTimes: pillDoseTimes,
      pillSupplyEnabled: pillSupplyEnabled,
      pillSupplyLeft: pillSupplyLeft,
      pillSupplyInitial: pillSupplyInitial,
      pillSupplyLowSent: pillSupplyLowSent,
      pillNameLocked: pillNameLocked,
    );

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

    if (slot < medicationIds.length) {
      await _medService.delete(medicationIds[slot]);
    }
    final updatedMedIds = [...medicationIds]..removeAt(slot);

    // Deterministic IDs depend on pillSlot; delete shifts slots => easiest is hard clear.
    await NotificationService.cancelAll();

    // Build updated lists
    final updatedNames = [...pillNames]..removeAt(slot);

    final updatedTimes = [...pillTimes];
    if (slot < updatedTimes.length) updatedTimes.removeAt(slot);

    final updatedDoseTimes = [...pillDoseTimes];
    if (slot < updatedDoseTimes.length) updatedDoseTimes.removeAt(slot);

    // ✅ supply lists must remove the same slot too (guarded)
    _alignSupplyListsToCount(pillNames.length);

    if (slot < pillSupplyEnabled.length) pillSupplyEnabled.removeAt(slot);
    if (slot < pillSupplyLeft.length) pillSupplyLeft.removeAt(slot);
    if (slot < pillSupplyInitial.length) pillSupplyInitial.removeAt(slot);
    if (slot < pillSupplyLowSent.length) pillSupplyLowSent.removeAt(slot);

    // ✅ now align to the NEW count
    _alignSupplyListsToCount(updatedNames.length);

    // ✅ persist
    await _saveSupplyListsToPrefs();

    // Persist
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pillNamesKey, updatedNames);
    await prefs.setStringList(_pillTimesKey, updatedTimes);
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));

    // ✅ make sure supply arrays exist and match current pill count BEFORE removing
    _alignSupplyListsToCount(pillNames.length);

    // Remove the same slot as the deleted pill (guarded)
    if (slot < pillSupplyEnabled.length) pillSupplyEnabled.removeAt(slot);
    if (slot < pillSupplyLeft.length) pillSupplyLeft.removeAt(slot);
    if (slot < pillSupplyInitial.length) pillSupplyInitial.removeAt(slot);
    if (slot < pillSupplyLowSent.length) pillSupplyLowSent.removeAt(slot);

    // ✅ align to NEW count after delete
    _alignSupplyListsToCount(updatedNames.length);

    // ✅ persist the actual lists (NOT updatedSupplyEnabled vars)
    await _saveSupplyListsToPrefs();

    final updatedNameLocked = [...pillNameLocked]..removeAt(slot);
    await prefs.setString(_pillNameLockedKey, jsonEncode(updatedNameLocked));

    // Decide new centered wheel index BEFORE setState
    final newCount = updatedNames.length;
    final int newWheelIndex;
    if (newCount == 0) {
      newWheelIndex = 1;
    } else {
      final newSlot = slot.clamp(0, newCount - 1);
      newWheelIndex = newSlot + 1;
    }

    int? newEditingIndex = _editingIndex;
    if (newEditingIndex != null) {
      if (newEditingIndex == slot) {
        newEditingIndex = null; // deleted the pill being edited
      } else if (newEditingIndex > slot) {
        newEditingIndex = newEditingIndex - 1; // shift down after delete
      }
    }

    if (!mounted) return;
    setState(() {
      medicationIds = updatedMedIds;
      pillSupplyEnabled = [...pillSupplyEnabled];
      pillSupplyLeft = [...pillSupplyLeft];
      pillSupplyInitial = [...pillSupplyInitial];
      pillSupplyLowSent = [...pillSupplyLowSent];
      pillNames = updatedNames;
      pillNameLocked = updatedNameLocked;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;
      _pendingSlot = false;
      _editingIndex = newEditingIndex;
      _wheelSelectedIndex = newWheelIndex;
      _infoOpen = false; // close dashboard panel after delete
    });

    final checkMap = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(checkMap);
    _setCheckMapAndRebuild(checkMap);
    _refreshCheckMapFuture();

    await MedicationPrefsMirror.write(
      pillNames: pillNames,
      pillTimesFirst: pillTimes,
      pillDoseTimes: pillDoseTimes,
      pillSupplyEnabled: pillSupplyEnabled,
      pillSupplyLeft: pillSupplyLeft,
      pillSupplyInitial: pillSupplyInitial,
      pillSupplyLowSent: pillSupplyLowSent,
      pillNameLocked: pillNameLocked,
    );

    // Move wheel after rebuild
    _centerWheelOn(_wheelSelectedIndex);

    _scheduleGlobalDayBoundaryRefresh();
    _scheduleGlobalBoundaryRefresh();

    // Rebuild today+tomorrow notifications for the remaining pills
    await NotificationService.rebuild2DayWindow(
      pillNames: updatedNames,
      doseTimes24h: updatedDoseTimes,
    );
  }

  Future<void> _onWarningOverrideTap() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null) return;
    if (pillIndex >= medicationIds.length) return;

    final doses = _doseTimesForPill(pillIndex);
    if (doses.isEmpty) return;

    final w = _computeDoseWindow(now: DateTime.now(), dosesSorted: doses);
    final cycleDay = DateTime(
      w.cycleStart.year,
      w.cycleStart.month,
      w.cycleStart.day,
    );
    final mid = medicationIds[pillIndex];

    await _scheduleService.ensureDoseEventsForMedication(mid);
    final missed = await _adherenceService.firstMissedOnLocalDay(
      medicationId: mid,
      localDay: cycleDay,
    );

    if (missed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No missed dose to override for this pill.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Override missed dose?'),
        content: const Text(
          'Mark this missed dose as taken (overridden)? '
          'This will show in History as Taken (Overridden).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Override'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    await _adherenceService.overrideDose(missed.id);
    final map = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(map);
    _setCheckMapAndRebuild(map);
    _refreshCheckMapFuture();
  }

  // ---------------- CHECK current dose ----------------
  Future<void> _checkCenteredPill() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null) return;
    if (pillIndex >= medicationIds.length) return;

    // 1) Figure out which dose we’re checking (and the current cycle key)
    final doses = _doseTimesForPill(pillIndex);
    final w = _computeDoseWindow(now: DateTime.now(), dosesSorted: doses);

    final doseIndex = w.doseIndex;

    final cycleDay = DateTime(
      w.cycleStart.year,
      w.cycleStart.month,
      w.cycleStart.day,
    );
    final tod = doses[doseIndex];
    final plannedIso = plannedAtUtcIsoForSlot(cycleDay, tod);
    final mid = medicationIds[pillIndex];

    await _scheduleService.ensureDoseEventsForMedication(mid);
    final ev = await _adherenceService.findDoseEventForPlannedUtc(
      medicationId: mid,
      plannedAtUtcIso: plannedIso,
    );
    if (ev == null) return;
    await _adherenceService.confirmTaken(ev.id);

    final map = await _deriveCheckMapFromDatabase();
    await _saveCheckMap(map);

    // keep your existing UI/cache refresh flow
    _setCheckMapAndRebuild(map);
    _refreshCheckMapFuture();
    _checkMapFuture = _loadCheckMap();

    // NEW notif system: cancel remaining notifications for today for this pill.
    // If you want “checking dose 1 mutes dose 2+ too”, set muteRemainingDoses: true.
    await NotificationService.muteToday(
      pillSlot: pillIndex,
      doseIndex: doseIndex,
      dosesPerDay: doses.length,
      muteRemainingDoses:
          false, // change to true if you want “one check mutes rest of day”
    );

    unawaited(_consumeOneSupplyIfEnabled(pillIndex));

    // 5) Everything else unchanged
    _scheduleCenteredDoseBoundaryRefresh();

    _labelTimer?.cancel();
    setState(() => _labelOverride = 'Pill Checked!');
    _labelTimer = Timer(const Duration(seconds: 9), () {
      if (!mounted) return;
      setState(() => _labelOverride = null);
    });

    if (mounted) setState(() {});
  }

  // ---------------- config panel UI ----------------
  // (UNCHANGED below this point)
  // ------------------------------------------------------------------------
  // Everything from here down is exactly what you had (UI/layout/etc).
  // ------------------------------------------------------------------------

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
                    // ---------------- HEADER ROW ----------------
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
                              : (_lockPillName
                                    // ✅ Locked name (search-picked): NO edit button
                                    ? Text(
                                        _nameController.text.trim(),
                                        style: const TextStyle(
                                          color: white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    // ✅ Custom / normal: allow editing name
                                    : InkWell(
                                        onTap: _editNameAgain,
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
                                            ),
                                          ],
                                        ),
                                      )),
                        ),
                        IconButton(
                          onPressed: _cancelAddFlow,
                          icon: const Icon(Icons.close, color: white),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // ---------------- INFO BOX ----------------
                    Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _selectedPillInfo ?? 'Placeholder info area',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ---------------- SUPPLY TRACKING (shows on CONFIG + DOSES) ----------------
                    if (_step != _ConfigStep.name &&
                        _supplyModeGlobal != 'off') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            // ---------------- HEADER ROW ----------------
                            if (_supplyModeGlobal == 'decide') ...[
                              // ✅ Decide mode: show Track supply + switch
                              Row(
                                children: [
                                  const Text(
                                    'Track supply',
                                    style: TextStyle(
                                      color: white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: _showSupplyInfoDialog,
                                    child: const Icon(
                                      Icons.info_outline,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _supplyTrackOn,
                                    onChanged: (v) async {
                                      if (!mounted) return;

                                      if (!v) {
                                        setState(() {
                                          _supplyTrackOn = false;
                                          _supplyLeftDraft = 0;
                                          _supplyInitialDraft = 0;
                                        });
                                        return;
                                      }

                                      setState(() => _supplyTrackOn = true);
                                      await _editSupplyDialog(
                                        setInitialToo: true,
                                      );

                                      if (!mounted) return;
                                      if (_supplyLeftDraft <= 0) {
                                        setState(() => _supplyTrackOn = false);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ] else ...[
                              // ✅ Always On: NO switch row, just label
                              Row(
                                children: [
                                  const Text(
                                    'Supply',
                                    style: TextStyle(
                                      color: white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: _showSupplyInfoDialog,
                                    child: const Icon(
                                      Icons.info_outline,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'Always On',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],

                            // ---------------- SUPPLY LEFT ROW ----------------
                            if ((_supplyModeGlobal == 'on') ||
                                (_supplyModeGlobal == 'decide' &&
                                    _supplyTrackOn)) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () =>
                                    _editSupplyDialog(setInitialToo: false),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Supply left',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _supplyLeftDraft.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.edit,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ---------------- CONFIG STEP ----------------
                    if (_step == _ConfigStep.config) ...[
                      // Times per day
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

                      // Single time picker (only when 1x/day)
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

                    // ---------------- DOSES STEP ----------------
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
                                  t == null
                                      ? 'Tap to set time (leave empty to skip)'
                                      : '${_fmt(t)} • tap to change, or clear to skip',
                                  style: const TextStyle(color: cardColor),
                                ),
                                trailing: t == null
                                    ? const Icon(
                                        Icons.schedule,
                                        color: cardColor,
                                      )
                                    : IconButton(
                                        tooltip: 'Skip this dose',
                                        onPressed: () {
                                          setState(() => _doseTimes[i] = null);
                                        },
                                        icon: const Icon(
                                          Icons.cancel,
                                          color: cardColor,
                                        ),
                                      ),
                                onTap: () => _pickDoseTime(i),
                                onLongPress: () {
                                  // Long-press clears this slot so the user can skip it.
                                  setState(() => _doseTimes[i] = null);
                                },
                              ),
                            );
                          },
                        ),
                      )
                    else
                      const SizedBox(height: 12),

                    // ---------------- PRIMARY BUTTON ----------------
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
    final rawScale = (scaleW < scaleH ? scaleW : scaleH);

    // Keep iOS exactly as-is; Android gets a slightly tighter cap to prevent blow-ups
    final scale = Platform.isAndroid
        ? rawScale.clamp(0.78, 1.12)
        : rawScale.clamp(0.8, 1.3);

    double s(double v) => v * scale;
    double fs(double v) => v * scale;

    final configH = _step == _ConfigStep.doses
        ? (Platform.isAndroid ? s(620) : s(560))
        : (Platform.isAndroid ? s(520) : s(480));

    final double stripW = s(800);
    final double stripH = s(1383);

    final double wheelBoxH = s(1000);
    final double wheelBoxW = size.width;

    double cx(double w) => (size.width - w) / 2;

    final midFade = _searchOpen ? 0.0 : 1.0;
    final topShift = _searchOpen ? -s(220) : 0.0;
    final searchScrimOpacity = _searchOpen ? 1.0 : 0.0;

    final bottomSlide = (_configOpen || _infoOpen || _searchOpen)
        ? const Offset(0, 0.30)
        : Offset.zero;

    final bottomSlidDown = (_configOpen || _infoOpen || _searchOpen);
    final bottomDecorOpacity = bottomSlidDown ? 0.0 : 1.0;

    final wheelLocked = _pendingSlot;

    final centerIdx = _centerPillIndex;
    final showSupplyBadge = centerIdx != null && _effectiveSupplyOn(centerIdx);

    final supplyLeftValue =
        (centerIdx != null && centerIdx < pillSupplyLeft.length)
        ? pillSupplyLeft[centerIdx]
        : 0;

    final displaySupplyValue = showSupplyBadge
        ? supplyLeftValue
        : _supplyBadgeCacheValue;

    final supplyNumberColor = (displaySupplyValue <= 0)
        ? const Color.fromARGB(255, 255, 30, 71) // red
        : (displaySupplyValue < _supplyLowThreshold)
        ? const Color.fromARGB(255, 255, 226, 109) // yellow
        : const Color.fromARGB(245, 255, 255, 255); // your off-white

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFFF6D87),
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Stack(
          children: [
            // --- TOP BAR ---
            /* Positioned(
              right: 0,
              left: 0,
              top: s(0),
              child: Container(height: s(250), color: const Color(0xFFFF6D87)),
            ),
*/
            Positioned(
              right: 0,
              left: 0,
              top: s(238),
              bottom: s(560),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                opacity: midFade,
                child: Container(
                  height: s(5),
                  color: const Color.fromARGB(255, 158, 52, 69),
                ),
              ),
            ),

            Positioned(
              right: 0,
              left: 0,
              top: s(234),
              bottom: s(674),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                opacity: midFade,
                child: Container(
                  height: s(5),
                  color: const Color.fromARGB(123, 158, 52, 70),
                ),
              ),
            ),

            Positioned(
              right: 0,
              left: 0,
              top: s(350),
              bottom: s(555),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                opacity: midFade,
                child: Container(
                  height: s(5),
                  color: const Color.fromARGB(123, 158, 52, 70),
                ),
              ),
            ),

            // --- WEEKLY PILLBOX (Rive) ---
            AnimatedPositioned(
              duration: _pillboxSlideDur,
              curve: Curves.easeInOutCubic,
              left: _pillboxLeftForDay(
                size: size,
                s: s,
                designW: designW,
                todayIndex: _pillboxVisualDay,
                scale: pbScale, // ✅ slide uses visual day
              ),
              bottom: s(130),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                opacity: midFade,
                child: SizedBox(
                  width: s(800) * pbScale,
                  height: s(1383) * pbScale,
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
            ),

            // --- SIDE BARS ---
            Positioned(
              left: 0,
              right: 0,
              top: s(160), // main vertical placement reference
              child: FutureBuilder<Map<String, dynamic>>(
                future: _checkMapFuture,
                builder: (context, snap) {
                  final map = snap.data ?? <String, dynamic>{};

                  final idx = _centerPillIndex;
                  final hasRealPill =
                      idx != null && idx >= 0 && idx < pillNames.length;

                  final doses = hasRealPill
                      ? _doseTimesForPill(idx!)
                      : <TimeOfDay>[];

                  final showLeft = hasRealPill && doses.length > 1;

                  int totalDoses = doses.length;
                  int activeDoseIndex = 0;
                  int mask = 0;
                  int checkedCount = 0;
                  bool dayCompleteForPill = false;

                  if (showLeft) {
                    final w = _computeDoseWindow(
                      now: DateTime.now(),
                      dosesSorted: doses,
                    );

                    final cycleIso = w.cycleStart.toIso8601String();
                    final stored = map['$idx'] as String?;
                    final parsed = _readCycleAndMask(stored);

                    mask = (parsed.cycleIso == cycleIso) ? parsed.mask : 0;
                    checkedCount = _bitCount(mask).clamp(0, totalDoses);
                    dayCompleteForPill = checkedCount >= totalDoses;
                    activeDoseIndex = w.doseIndex;
                  }

                  final allDone = _areAllPillsComplete(map);

                  // Match the right bar to the same delayed completion feel as the circle
                  final doneForCircle =
                      allDone &&
                      (_allowDailyFillAnim || !_needsDailyCircleDelay);

                  // Right bar should appear immediately once all pills are complete
                  final showRight = allDone;

                  return SizedBox(
                    height: s(70),
                    child: Stack(
                      children: [
                        // LEFT BAR: multi-dose progress
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeInOutCubic,
                          left: showLeft ? s(1) : -s(220),
                          top: 0,
                          width: s(165),
                          height: s(70),
                          child: IgnorePointer(
                            child: DoseProgressSideBar(
                              totalDoses: totalDoses,
                              activeDoseIndex: activeDoseIndex,
                              checkedMask: mask,
                              height: s(70),
                            ),
                          ),
                        ),

                        // RIGHT BAR: all pills completed
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                          right: showRight ? s(2) : -s(220),
                          top: 0,
                          width: s(166.5),
                          height: s(70),
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(222, 155, 255, 168),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color.fromARGB(
                                    255,
                                    137,
                                    255,
                                    133,
                                  ),
                                  width: 5,
                                ),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: s(14)),
                              child: Center(
                                child: Text(
                                  'Checked all pills\nfor today!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Amaranth',
                                    fontSize: fs(17),
                                    color: const Color.fromARGB(
                                      255,
                                      152,
                                      64,
                                      79,
                                    ),
                                    fontWeight: FontWeight.w700,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // --- LOGO (left) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              top: s(24) + topShift,
              left: s(0),
              right: s(185),
              child: IgnorePointer(
                ignoring: _searchOpen,
                child: Opacity(
                  opacity: 0.75,
                  child: Image.asset(
                    'assets/images/pillchecker_logo.png',
                    width: s(150),
                    height: s(150),
                  ),
                ),
              ),
            ),

            // --- TITLE (center) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              top: s(40) + topShift,
              left: 35,
              right: 0,
              child: IgnorePointer(
                ignoring: _searchOpen,
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
            ),

            // --- DAILY COMPLETION CIRCLE (auto fill animation) ---
            Positioned(
              left: cx(s(60.2)),
              bottom: s(687),
              child: FutureBuilder<Map<String, dynamic>>(
                future: _checkMapFuture,
                builder: (context, snap) {
                  final map = snap.data ?? {};

                  final actualDone = _areAllPillsComplete(map);

                  // wait until pillbox open animation window is finished
                  final doneForCircle =
                      actualDone &&
                      (_allowDailyFillAnim || !_needsDailyCircleDelay);

                  // 1s delay ONLY once (re-armed on cold start + resume-after-midnight)
                  if (!doneForCircle) {
                    _dailyCircleDelayTimer?.cancel();
                    _dailyCircleDelayTimer = null;
                    _dailyCircleDelayPassed = false;
                  } else {
                    if (_delayDailyCircleOnce) {
                      _dailyCircleDelayTimer ??= Timer(
                        const Duration(milliseconds: 1300),
                        () {
                          if (!mounted) return;
                          setState(() {
                            _dailyCircleDelayPassed = true;
                            _delayDailyCircleOnce = false;
                          });
                        },
                      );
                    } else {
                      _dailyCircleDelayPassed = true;
                    }
                  }

                  final delayedDone = doneForCircle && _dailyCircleDelayPassed;

                  return DailyCompletionCircle(
                    done: delayedDone,
                    size: s(58),
                    baseColor: const Color.fromARGB(0, 231, 36, 153),
                    fillColor: const Color(0xFF59FF56),
                  );
                },
              ),
            ),

            // --- BOTTOM ZONE ---
            IgnorePointer(
              ignoring: _configOpen || _infoOpen || _searchOpen,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                offset: bottomSlide,
                child: Stack(
                  children: [
                    // --- BACK PLATE (behind everything) ---
                    Positioned(
                      left: s(100),
                      right: s(100),

                      // tweak these two to place it between pillbox and wheel
                      top: s(395),
                      bottom: s(350),

                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeInOut,
                        opacity: bottomDecorOpacity,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(s(25)),
                            ),
                          ),
                        ),
                      ),
                    ),

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

                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: s(260), // tweak if you want it higher/lower
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeInOut,
                          opacity: (showSupplyBadge && !bottomSlidDown)
                              ? 1.0
                              : 0.0,
                          child: Center(
                            child: SizedBox(
                              width: s(64),
                              height: s(64),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // ✅ tiny patch behind the icon to fill the "hole"
                                  Positioned(
                                    // tweak these 3 numbers if needed
                                    top: s(22),
                                    child: Container(
                                      width: s(25),
                                      height: s(25),
                                      decoration: BoxDecoration(
                                        color: const Color.fromARGB(
                                          255,
                                          156,
                                          68,
                                          83,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          s(4),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Icon(
                                    Icons.medication_rounded,
                                    size: s(64),
                                    color: const Color.fromARGB(
                                      255,
                                      156,
                                      68,
                                      83,
                                    ),
                                  ),

                                  Text(
                                    displaySupplyValue.toString(),
                                    style: TextStyle(
                                      fontFamily: 'Amaranth',
                                      fontSize: fs(21),
                                      color: supplyNumberColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

                          setState(() {
                            _wheelSelectedIndex = i;
                            _cacheSupplyBadgeIfShowing(); // ✅ cache value if this new pill tracks supply
                          });

                          _scheduleCenteredDoseBoundaryRefresh();
                        },
                        onAddPressed: _openPillSearch,
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
                      left: s(-75),
                      bottom: s(-100),
                      child: ClipOval(
                        child: Container(
                          width: s(200),
                          height: s(200),
                          color: const Color.fromARGB(255, 135, 255, 133),
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
                                      color: const Color.fromARGB(
                                        255,
                                        135,
                                        255,
                                        133,
                                      ),
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
                      right: s(-75),
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
                            onTap: _onWarningOverrideTap,
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
                        String displayName =
                            _labelOverride ?? _centerPillName();

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
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              left: s(-75),
              top: s(40) + topShift,
              child: IgnorePointer(
                ignoring: _searchOpen,
                child: ClipOval(
                  child: Container(
                    width: s(150),
                    height: s(85),
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),

            // --- DIRECTORY ICON (top-left) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              left: s(-10),
              top: s(45) + topShift,
              child: IgnorePointer(
                ignoring: _searchOpen || _configOpen || _infoOpen,
                child: Opacity(
                  opacity: (_configOpen || _infoOpen || _searchOpen)
                      ? 0.45
                      : 1.0,
                  child: SizedBox(
                    width: s(88),
                    height: s(70),
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(s(999)),
                          onTap: _openDirectoryScreen,
                          child: SizedBox(
                            width: s(80),
                            height: s(65),
                            child: Center(
                              child: Icon(
                                Icons.format_list_bulleted,
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

            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              right: s(-75),
              top: s(40) + topShift,
              child: IgnorePointer(
                ignoring: _searchOpen,
                child: ClipOval(
                  child: Container(
                    width: s(150),
                    height: s(85),
                    color: const Color(0xFFB4B4B4),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              right: s(-45),
              top: s(40) + topShift,
              child: IgnorePointer(
                ignoring: _searchOpen || _configOpen || _infoOpen,
                child: SizedBox(
                  width: s(150),
                  height: s(85),
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(s(999)),
                        onTap: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );

                          if (!mounted) return;

                          debugPrint(
                            'HOME: settings returned changed=$changed',
                          );

                          if (changed == true) {
                            await NotificationService.loadUserNotificationSettings();
                            await _loadSupplyGlobalSettings();
                            await _rebuild2DayNotifWindow(
                              reason: 'after-settings',
                            );
                            await NotificationService.debugDumpPending(
                              'after_settings_rebuild',
                            );
                            _scheduleGlobalBoundaryRefresh();
                            unawaited(_scheduleGlobalDayBoundaryRefresh());
                          }
                        },
                        child: SizedBox(
                          width: s(80),
                          height: s(75),
                          child: Center(
                            child: Icon(
                              Icons.settings,
                              size: s(60),
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
            ),

            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_searchOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  opacity: searchScrimOpacity,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,

                    // ✅ tap outside closes search (remove this line if you don’t want that)
                    onTap: _closePillSearch,

                    child: Container(
                      color: const Color(
                        0xFFFF6D87,
                      ), // same as Scaffold background
                    ),
                  ),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              left: s(18),
              right: s(18),
              top: _searchOpen ? s(30) : size.height + s(50),
              bottom: s(18),
              child: PillSearchPanel(
                rxNormService: _rxNormService,
                placeholderItems: kOfflineMedicationSuggestions,
                onPickCustom: _pickCustomFromSearch,
                onPickItem: _pickSearchItem,
                onClose: _closePillSearch,
                disabledNamesLower: pillNames
                    .map((e) => e.trim().toLowerCase())
                    .toSet(),
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
                    onDelete: idx == null ? null : _deleteCenteredPill,
                    rxNormService: _rxNormService,

                    // ✅ Hide supply section entirely when global mode is Always Off
                    supplyTrackingOn:
                        (_supplyModeGlobal != 'off' && idx != null)
                        ? _effectiveSupplyOn(idx)
                        : false,

                    supplyLeft: (idx != null && idx < pillSupplyLeft.length)
                        ? pillSupplyLeft[idx]
                        : 0,
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
