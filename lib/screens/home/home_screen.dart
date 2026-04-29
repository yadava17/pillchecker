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
import 'package:pillchecker/screens/history/history_screen.dart';
import 'package:pillchecker/widgets/dose_progress_side_bar.dart';
import 'package:pillchecker/backend/rxnorm/medication_details.dart';
import 'package:pillchecker/backend/services/adherence_service.dart';
import 'package:pillchecker/backend/services/med_service.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';
import 'package:pillchecker/backend/services/medication_prefs_mirror.dart';
import 'package:pillchecker/backend/services/prefs_migration.dart';
import 'package:pillchecker/backend/services/schedule_service.dart';
import 'package:pillchecker/backend/utils/local_date_time.dart';
import 'package:pillchecker/screens/calendar/calendar_screen.dart';
import 'package:pillchecker/widgets/multi_dose_override_dialog.dart';
import 'package:pillchecker/backend/models/dose_event_record.dart';
import 'package:pillchecker/widgets/tutorial_spotlight_overlay.dart';
import 'package:pillchecker/constants/demo_pill_keys.dart';

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

  static const _pillMissedKey = 'pill_missed_state_v1';

  static const _pillDoseTimesKey =
      'pill_dose_times_v2'; // JSON: List<List<String>>

  static const _localStatePillSigKey = 'pill_local_state_sig_v1';
  // -------- supply prefs keys --------
  static const _pillSupplyEnabledKey =
      'pill_supply_enabled_v1'; // JSON List<bool>
  static const _pillSupplyLeftKey = 'pill_supply_left_v1'; // JSON List<int>
  static const _pillSupplyInitKey = 'pill_supply_init_v1'; // JSON List<int>
  static const _pillSupplyLowSentKey =
      'pill_supply_low_sent_v1'; // JSON List<bool>

  static const _pillNameLockedKey = 'pill_name_locked_v1'; // JSON List<bool>

  static const _doseHistoryKey = 'dose_history_v1';
  static const _streakStateKey = 'pill_streak_state_v1';

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
  int _lastDoseBarMissedMask = 0;

  Map<DateTime, List<String>> _doseHistory = {};

  List<DateTime> medicationCreatedAts = [];
  Map<String, dynamic> _lastMissedMapCache = {};

  void _refreshCheckMapFuture() {
    if (!mounted) return;

    setState(() {
      _checkMapFuture = Future.value(Map<String, dynamic>.from(_checkMapCache));
    });

    _requestStreakSyncFromLocalState();
  }

  int _wheelSelectedIndex = 1;

  bool _pendingSlot = false;

  bool _configOpen = false;
  _ConfigStep _step = _ConfigStep.name;

  bool _infoOpen = false;

  bool _searchOpen = false;

  bool _streaksOpen = false;
  bool _streaksGreenVisible = false;
  Timer? _streaksTransitionTimer;
  _StreakState _streakState = _StreakState.initial();
  Timer? _streakDotsTimer;
  Timer? _streakMarkersTimer;
  bool _streakDotsVisible = false;
  bool _streakMarkersVisible = false;
  bool _streakMessageVisible = false;
  Timer? _streakMessageTimer;
  String _streakStatusMessage = "Let's get started!";
  int _lastWeekCompleteMessageFor = 0;
  bool _streakButtonNeedsAttention = false;

  String get _currentStreakValue => _streakState.currentStreak.toString();
  String get _weeksCompletedValue => _streakState.weeksCompleted.toString();
  String get _longestStreakValue => _streakState.longestStreak.toString();
  String get _mostWeeksCompletedValue =>
      _streakState.mostWeeksCompleted.toString();
  int get _weekProgressValue => _streakState.weekProgress.clamp(0, 7).toInt();
  int? get _weekStartDayIndexValue => _streakState.weekStartDayIndex;
  int? get _nextRequiredDayIndexValue => _streakState.nextRequiredDayIndex;

  bool get _showLastCompletedWeekSnapshot {
    final progress = _streakState.weekProgress.clamp(0, 7).toInt();
    final completedKeys = _streakState.completedDayKeys.toSet().toList();

    return progress == 0 &&
        _streakState.weeksCompleted > 0 &&
        completedKeys.length >= 7;
  }

  int get _displayWeekProgressValue {
    return _showLastCompletedWeekSnapshot ? 7 : _weekProgressValue;
  }

  int? get _displayWeekStartDayIndexValue {
    // True 0/7 state: show Start on today's tab.
    if (_weekProgressValue == 0 && !_showLastCompletedWeekSnapshot) {
      return _streakDayIndexForNow();
    }

    return _streakState.weekStartDayIndex;
  }

  int? get _displayNextRequiredDayIndexValue {
    // True 0/7 state: no Next marker yet, only Start.
    if (_weekProgressValue == 0) return null;

    return _streakState.nextRequiredDayIndex;
  }

  Set<int> get _streakCompletedDayIndexes {
    final displayProgress = _displayWeekProgressValue.clamp(0, 7).toInt();
    if (displayProgress <= 0) return <int>{};

    final sortedKeys = _streakState.completedDayKeys.toSet().toList()..sort();

    if (sortedKeys.isEmpty) return <int>{};

    final recentKeys = sortedKeys.length <= displayProgress
        ? sortedKeys
        : sortedKeys.sublist(sortedKeys.length - displayProgress);

    return recentKeys.map((key) {
      final d = _dateFromKey(key);
      return _dayIndexFor(d); // 0 = Sun, 1 = Mon, ... 6 = Sat
    }).toSet();
  }

  bool get _streakAtRisk {
    return _streakState.streaksEnabled &&
        _streakState.pendingLostDayKey != null;
  }

  Timer? _streaksPillboxTimer;

  Set<int> _streakPillboxOpenDays = <int>{};
  int _streakPillboxResetToken = 0;

  // Used to fill the config panel "info" box when a search item was picked
  String? _selectedPillInfo;

  // edit mode
  int? _editingIndex;
  bool get _isEditing => _editingIndex != null;

  final TextEditingController _nameController = TextEditingController();
  int _timesPerDay = 1;
  TimeOfDay? _singleDoseTime;
  List<TimeOfDay?> _doseTimes = [];

  final ScrollController _configPanelScrollCtrl = ScrollController();
  final ScrollController _lockedInfoScrollCtrl = ScrollController();
  final ScrollController _customInfoScrollCtrl = ScrollController();

  bool _tutorialActive = false;
  int _tutorialIndex = 0;

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

  static const _pillCustomInfoKey = 'pill_custom_info_v1';

  List<String> pillCustomInfo = [];
  final TextEditingController _customInfoController = TextEditingController();

  int _lastDoseBarTotalDoses = 2;
  int _lastDoseBarActiveDoseIndex = 0;
  int _lastDoseBarCheckedMask = 0;
  bool _hasDoseBarCache = false;

  static const Color _streakBg = Color(0xFF30C05A);
  static const Color _streakBand = Color(0xFF0F7A2D);
  static const Color _streakBlue = Color(0xFF1FC7F4);
  static const Color _streakHelpBtn = Color(0xFF0C8F2E);
  static const Color _streakExitRed = Color(0xFFFF0037);
  static const Color _streakFlame = Color(0xFFFFB347);

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

  final List<Future<void>> _pendingAdherenceWrites = <Future<void>>[];

  void _trackAdherenceWrite(Future<void> future) {
    _pendingAdherenceWrites.add(future);
    future.whenComplete(() {
      _pendingAdherenceWrites.remove(future);
    });
  }

  Future<void> _flushPendingAdherenceWrites() async {
    final pending = List<Future<void>>.from(_pendingAdherenceWrites);
    if (pending.isEmpty) return;
    await Future.wait(pending);
  }

  bool _hasLocalAdherenceStateForCurrentCycle() {
    for (int pillIndex = 0; pillIndex < pillNames.length; pillIndex++) {
      final doses = _doseTimesForPill(pillIndex);
      if (doses.isEmpty) continue;

      final state = _getDisplayedDoseStateForPill(
        pillIndex: pillIndex,
        doses: doses,
        takenMap: _checkMapCache,
        missedMap: _lastMissedMapCache,
        now: DateTime.now(),
      );

      if (state.takenMask != 0 || state.missedMask != 0) {
        return true;
      }

      if (_isCurrentDoseMissed(pillIndex: pillIndex, map: _checkMapCache)) {
        return true;
      }
    }

    return false;
  }

  Future<
    List<
      ({
        int pillIndex,
        int doseIndex,
        int medicationId,
        String plannedIso,
        String cycleIso,
        String status,
      })
    >
  >
  _localDoseDbSyncJobs() async {
    final jobs =
        <
          ({
            int pillIndex,
            int doseIndex,
            int medicationId,
            String plannedIso,
            String cycleIso,
            String status,
          })
        >[];

    final seen = <String>{};

    Future<void> addJobIfDbMismatch({
      required int pillIndex,
      required int doseIndex,
      required int medicationId,
      required String plannedIso,
      required String cycleIso,
      required String status,
    }) async {
      final key = '$medicationId|$plannedIso|$status';
      if (!seen.add(key)) return;

      final ev = await _adherenceService.findDoseEventForPlannedUtc(
        medicationId: medicationId,
        plannedAtUtcIso: plannedIso,
      );

      if (ev == null || ev.status != status) {
        jobs.add((
          pillIndex: pillIndex,
          doseIndex: doseIndex,
          medicationId: medicationId,
          plannedIso: plannedIso,
          cycleIso: cycleIso,
          status: status,
        ));
      }
    }

    for (int pillIndex = 0; pillIndex < pillNames.length; pillIndex++) {
      if (pillIndex >= medicationIds.length) continue;

      final doses = _doseTimesForPill(pillIndex);
      if (doses.isEmpty) continue;

      final state = _getDisplayedDoseStateForPill(
        pillIndex: pillIndex,
        doses: doses,
        takenMap: _checkMapCache,
        missedMap: _lastMissedMapCache,
        now: DateTime.now(),
      );

      final cycleDay = DateTime(
        state.cycleStart.year,
        state.cycleStart.month,
        state.cycleStart.day,
      );

      for (int doseIndex = 0; doseIndex < doses.length; doseIndex++) {
        final bit = 1 << doseIndex;
        final plannedIso = plannedAtUtcIsoForOrderedDose(
          cycleDay,
          doses,
          doseIndex,
        );

        if ((state.takenMask & bit) != 0) {
          await addJobIfDbMismatch(
            pillIndex: pillIndex,
            doseIndex: doseIndex,
            medicationId: medicationIds[pillIndex],
            plannedIso: plannedIso,
            cycleIso: state.cycleIso,
            status: 'taken',
          );
        } else if ((state.missedMask & bit) != 0) {
          await addJobIfDbMismatch(
            pillIndex: pillIndex,
            doseIndex: doseIndex,
            medicationId: medicationIds[pillIndex],
            plannedIso: plannedIso,
            cycleIso: state.cycleIso,
            status: 'missed',
          );
        }
      }

      // Also catch the visual missed state that comes from time passing,
      // even before the missed bit has been written locally.
      if (_isCurrentDoseMissed(pillIndex: pillIndex, map: _checkMapCache)) {
        final plannedIso = plannedAtUtcIsoForOrderedDose(
          cycleDay,
          doses,
          state.doseIndex,
        );

        await addJobIfDbMismatch(
          pillIndex: pillIndex,
          doseIndex: state.doseIndex,
          medicationId: medicationIds[pillIndex],
          plannedIso: plannedIso,
          cycleIso: state.cycleIso,
          status: 'missed',
        );
      }
    }

    return jobs;
  }

  Future<bool> _shouldGateAdherenceScreen() async {
    if (_pendingAdherenceWrites.isNotEmpty) return true;
    if (!_hasLocalAdherenceStateForCurrentCycle()) return false;

    final jobs = await _localDoseDbSyncJobs();
    return jobs.isNotEmpty;
  }

  Future<void> _syncLocalAdherenceStateToDbNow() async {
    try {
      await _flushPendingAdherenceWrites().timeout(const Duration(seconds: 5));
    } catch (_) {
      // If one write is stuck, force a reconciliation pass below.
    }

    final jobs = await _localDoseDbSyncJobs();

    for (final job in jobs) {
      if (job.status == 'taken') {
        await _persistTakenToDb(
          medicationId: job.medicationId,
          plannedIso: job.plannedIso,
        );
      } else {
        _setLocalDoseStatus(
          pillIndex: job.pillIndex,
          cycleIso: job.cycleIso,
          doseIndex: job.doseIndex,
          status: 'missed',
        );

        await _persistMissedToDb(
          medicationId: job.medicationId,
          plannedIso: job.plannedIso,
        );
      }
    }

    if (jobs.isNotEmpty) {
      await _saveLocalDailyState();
      _publishLocalDailyState();
    }

    // One real DB read, not a fake delay.
    await _adherenceService.fetchHistory(limit: 1);
  }

  Future<void> _showAdherenceSyncLoading({
    required String message,
    required Future<void> Function() task,
  }) async {
    if (!mounted) {
      await task();
      return;
    }

    var dialogOpen = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFF98404F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Syncing your latest pill state...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ).then((_) => dialogOpen = false),
    );

    await Future<void>.delayed(Duration.zero);

    try {
      await task();
    } finally {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _gateAdherenceScreenIfNeeded(String message) async {
    final shouldGate = await _shouldGateAdherenceScreen();
    if (!shouldGate) return;

    await _showAdherenceSyncLoading(
      message: message,
      task: _syncLocalAdherenceStateToDbNow,
    );
  }

  // ---------------- lifecycle ----------------
  @override
  void initState() {
    super.initState();
    _customInfoController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addObserver(this);
    _lastSeenDay = DateTime.now();
    unawaited(_loadDoseHistory());

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
    _customInfoController.dispose();
    _pillboxSlideTimer?.cancel();
    _nameFocus.dispose();

    _labelTimer?.cancel();
    _dailyCircleDelayTimer?.cancel();
    _doseBoundaryTimer?.cancel();
    _dayBoundaryTimer?.cancel();
    _globalBoundaryTimer?.cancel();

    _streaksTransitionTimer?.cancel();
    _streaksPillboxTimer?.cancel();
    _streakDotsTimer?.cancel();
    _streakMarkersTimer?.cancel();
    _streakMessageTimer?.cancel();
    _nameController.dispose();
    _wheelController.dispose();
    _rxNormService.dispose();
    _configPanelScrollCtrl.dispose();
    _lockedInfoScrollCtrl.dispose();
    _customInfoScrollCtrl.dispose();

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

    // Fire only when crossing from above the user threshold into
    // the low zone (at-or-below threshold, but still above 0).
    final crossedIntoLow =
        oldLeft > _supplyLowThreshold &&
        newLeft > 0 &&
        newLeft <= _supplyLowThreshold;

    final shouldWarnLow = !alreadySent && crossedIntoLow;

    if (shouldWarnLow) {
      setState(() => pillSupplyLowSent[pillIndex] = true);
      unawaited(_saveSupplyListsToPrefs());

      debugPrint(
        'LOW SUPPLY WARNING: pill=${pillNames[pillIndex]} '
        'oldLeft=$oldLeft newLeft=$newLeft threshold=$_supplyLowThreshold',
      );

      unawaited(
        NotificationService.scheduleLowSupplyWarning(
          pillSlot: pillIndex,
          pillName: pillNames[pillIndex],
        ),
      );
      _showForegroundSupplyNotice(
        '${pillNames[pillIndex]} supply is running low. Make sure to refill!',
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
      _showForegroundSupplyNotice(
        "You're out of ${pillNames[pillIndex]} supply! Time to refill!",
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

  void _alignCustomInfoToCount(int count) {
    while (pillCustomInfo.length < count) {
      pillCustomInfo.add('');
    }
    if (pillCustomInfo.length > count) {
      pillCustomInfo.removeRange(count, pillCustomInfo.length);
    }
  }

  Future<void> _loadCustomInfoFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    pillCustomInfo = List<String>.from(
      prefs.getStringList(_pillCustomInfoKey) ?? const <String>[],
    );
    _alignCustomInfoToCount(pillNames.length);
  }

  double _infoFontSizeFor(String text, {double base = 15}) {
    final len = text.trim().length;
    if (len > 900) return 11.5;
    if (len > 700) return 12.0;
    if (len > 520) return 12.8;
    if (len > 360) return 13.5;
    if (len > 220) return 14.0;
    return base;
  }

  double _extraInfoHeightFor(String text, double Function(double) s) {
    final len = text.trim().length;
    if (len > 900) return s(170);
    if (len > 700) return s(140);
    if (len > 520) return s(110);
    if (len > 360) return s(80);
    if (len > 220) return s(50);
    return 0;
  }

  double _configPanelHeight(double Function(double) s) {
    if (_step == _ConfigStep.name) {
      return s(330);
    }

    if (_step == _ConfigStep.doses) {
      return Platform.isAndroid ? s(620) : s(560);
    }

    return Platform.isAndroid ? s(520) : s(480);
  }

  double _infoPanelHeight(double Function(double) s) {
    final idx = _centerPillIndex;
    final isCustom =
        idx != null &&
        idx < pillNameLocked.length &&
        pillNameLocked[idx] == false;

    final infoText = (isCustom && idx != null && idx < pillCustomInfo.length)
        ? pillCustomInfo[idx]
        : '';

    return s(520) + (isCustom ? _extraInfoHeightFor(infoText, s) : 0);
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

  Future<void> _syncCurrentCycleAnchorOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final cycleStart = _globalCycleStartForNow(DateTime.now());

    if (cycleStart == null) {
      await prefs.remove(kLastCycleStartKey);
      return;
    }

    await prefs.setString(kLastCycleStartKey, cycleStart.toIso8601String());
  }

  Future<void> _maybeResetForNewCycle() async {
    // ✅ Do NOT clear local masks here anymore.
    // HomeScreen already ignores stale masks when the stored cycleIso
    // does not match the currently computed cycleIso.
    await _syncCurrentCycleAnchorOnly();
  }

  void _startTutorial() {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _tutorialActive = true;
      _tutorialIndex = 0;

      _configOpen = false;
      _infoOpen = false;
      _searchOpen = false;
      _pendingSlot = false;
    });
  }

  void _closeTutorial() {
    if (!mounted) return;
    setState(() {
      _tutorialActive = false;
      _tutorialIndex = 0;
    });
  }

  void _nextTutorialStep(int totalSteps) {
    if (_tutorialIndex >= totalSteps - 1) {
      _closeTutorial();
      return;
    }

    setState(() => _tutorialIndex++);
  }

  void _prevTutorialStep() {
    if (_tutorialIndex <= 0) return;
    setState(() => _tutorialIndex--);
  }

  List<_TutorialStep> _tutorialStepsForLayout({
    required Size size,
    required double Function(double) s,
    required double designW,
    required double topShift,
  }) {
    Rect rectFromTop({
      required double left,
      required double top,
      required double width,
      required double height,
    }) {
      return Rect.fromLTWH(left, top, width, height);
    }

    Rect rectFromBottom({
      required double right,
      required double bottom,
      required double width,
      required double height,
    }) {
      return Rect.fromLTWH(
        size.width - right - width,
        size.height - bottom - height,
        width,
        height,
      );
    }

    final checkLeft = _leftFromDesignRight(135, 137, size, s, designW) - s(4);

    return [
      _TutorialStep(
        title: 'Directory',
        description:
            'Use this button to open the Directory. You can browse the catalogue, check My Pills, and add medications from there.',
        targetRect: rectFromTop(
          left: s(-10),
          top: s(45) + topShift,
          width: s(80),
          height: s(75),
        ),
      ),
      _TutorialStep(
        title: 'Settings',
        description:
            'Open Settings to change reminders, supply tracking, feedback, credits, and to run this tutorial again later.',
        targetRect: rectFromTop(
          left: s(350),
          top: s(45) + topShift,
          width: s(80),
          height: s(75),
        ),
      ),
      _TutorialStep(
        title: 'Pill Wheel',
        description:
            'The wheel is where you move between pills. The highlighted pill in the middle is the active one. The + on the wheel lets you start adding a pill.',
        targetRect: Rect.fromCenter(
          center: Offset(size.width / 2, size.height - s(235)),
          width: s(400),
          height: s(465),
        ),
      ),
      _TutorialStep(
        title: 'Check Button',
        description:
            'Hold this button to check the current dose. When a dose is missed, this button turns red and shows Missed instead.',
        targetRect: rectFromTop(
          left: checkLeft - s(12),
          top: size.height - s(100) - s(150),
          width: s(165),
          height: s(165),
        ),
      ),
      _TutorialStep(
        title: 'Info',
        description:
            'Tap this button to open the pill info panel, view details, edit a pill, or delete it.',
        targetRect: rectFromTop(
          left: s(0),
          top: size.height - s(5) - s(86),
          width: s(120),
          height: s(82),
        ),
      ),
      _TutorialStep(
        title: 'Warnings & Overrides',
        description:
            'Tap here for warning actions like override, mark missed, and open adherence history. Multiple-dose pills also get a multi-dose override option here.',
        targetRect: rectFromBottom(
          right: s(0),
          bottom: s(5),
          width: s(120),
          height: s(82),
        ),
      ),
      _TutorialStep(
        title: 'Calendar',
        description:
            'This tab opens the calendar view so you can review adherence by day.',
        targetRect: rectFromTop(
          left: s(-10),
          top: size.height - s(460) - s(58),
          width: s(72),
          height: s(58),
        ),
      ),
      _TutorialStep(
        title: 'Streaks',
        description:
            'Tap here to view your streaks. Complete all of your scheduled doses for the day to keep your streak going. If a dose is missed, this tab flashes red because your streak is at risk.',
        targetRect: rectFromBottom(
          right: s(-10),
          bottom: s(460),
          width: s(72),
          height: s(58),
        ),
      ),
    ];
  }

  // ---------------- helpers: dose lists ----------------
  List<TimeOfDay> _doseTimesForPill(int pillIndex) {
    if (pillIndex < 0 || pillIndex >= pillDoseTimes.length) {
      return [const TimeOfDay(hour: 8, minute: 0)];
    }

    final list = pillDoseTimes[pillIndex];
    if (list.isEmpty) {
      return [const TimeOfDay(hour: 8, minute: 0)];
    }

    // IMPORTANT:
    // Preserve the user's configured order.
    // Do not sort by clock time.
    return list.map(_strToTime).toList(growable: false);
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
    final doses = _doseTimesForPill(pillIndex);

    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _lastCheckMapCache,
      missedMap: _lastMissedMapCache,
    );

    final mask = state.takenMask;
    final doneCount = _bitCount(mask);
    final doseChecked = (mask & (1 << state.doseIndex)) != 0;
    final dayComplete = doneCount >= doses.length;

    return (
      doseIndex: state.doseIndex,
      totalDoses: doses.length,
      cycleIso: state.cycleIso,
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

    final doses = _doseTimesForPill(pillIndex); // configured order

    _hidePillLabelNow();
    setState(() {
      _lockPillName = (pillIndex < pillNameLocked.length)
          ? pillNameLocked[pillIndex]
          : false;
      _editingIndex = pillIndex;
      _infoOpen = false;
      _configOpen = true;

      _customInfoController.text =
          (!_lockPillName && pillIndex < pillCustomInfo.length)
          ? pillCustomInfo[pillIndex]
          : '';

      _supplyPromptedThisFlow = false;
      _maybeAutoPromptSupply();

      _nameController.text = pillNames[pillIndex];
      _timesPerDay = doses.length.clamp(1, 6);

      _supplyTrackOn = (pillIndex < pillSupplyEnabled.length)
          ? pillSupplyEnabled[pillIndex]
          : false;

      _supplyLeftDraft = (pillIndex < pillSupplyLeft.length)
          ? pillSupplyLeft[pillIndex]
          : 0;

      _supplyInitialDraft = (pillIndex < pillSupplyInitial.length)
          ? pillSupplyInitial[pillIndex]
          : 0;

      // Always start edit on config so times/day can be adjusted safely.
      _step = _ConfigStep.config;
      if (_timesPerDay == 1) {
        _singleDoseTime = doses.first;
        _doseTimes = [];
      } else {
        _singleDoseTime = null;
        _doseTimes = doses.map((t) => t as TimeOfDay?).toList();
        while (_doseTimes.length < _timesPerDay) {
          _doseTimes.add(null);
        }
      }
    });

    _centerWheelOn(pillIndex + 1);
  }

  // ---------------- helpers: check map ----------------
  Future<Map<String, dynamic>> _loadCheckMap() async {
    if (_checkMapCache.isNotEmpty || pillNames.isEmpty) {
      return Map<String, dynamic>.from(_checkMapCache);
    }

    await _loadLocalDailyState();
    return Map<String, dynamic>.from(_checkMapCache);
  }

  Future<void> _hydrateMedicationsFromDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final meds = await _medService.getAll();

    medicationIds = meds.map((m) => m.id).toList();
    medicationCreatedAts = meds.map((m) => m.createdAt).toList();

    pillNames = meds.map((m) => m.name).toList();
    pillTimes = [];
    pillDoseTimes = [];
    pillNameLocked = [];

    for (final m in meds) {
      pillNameLocked.add(m.nameLocked);

      final sch = await _scheduleService.getScheduleForMedication(m.id);
      var times = <String>['08:00'];

      if (sch != null) {
        times = (jsonDecode(sch['times_json']! as String) as List)
            .map((e) => e.toString())
            .toList();
      }

      pillDoseTimes.add(times);
      pillTimes.add(times.isNotEmpty ? times.first : '08:00');
    }

    // ✅ Local-first supply state.
    // DB can store old values, but HomeScreen display should prefer prefs.
    final hasLocalSupply =
        prefs.containsKey(_pillSupplyEnabledKey) ||
        prefs.containsKey(_pillSupplyLeftKey) ||
        prefs.containsKey(_pillSupplyInitKey);

    if (hasLocalSupply) {
      final enabled = _decodeBoolList(prefs.getString(_pillSupplyEnabledKey));
      final left = _decodeIntList(prefs.getString(_pillSupplyLeftKey));
      final initial = _decodeIntList(prefs.getString(_pillSupplyInitKey));
      final lowSent = _decodeBoolList(prefs.getString(_pillSupplyLowSentKey));

      pillSupplyEnabled = List.generate(
        pillNames.length,
        (i) => i < enabled.length ? enabled[i] : false,
      );

      pillSupplyLeft = List.generate(
        pillNames.length,
        (i) => i < left.length ? left[i] : 0,
      );

      pillSupplyInitial = List.generate(
        pillNames.length,
        (i) => i < initial.length ? initial[i] : 0,
      );

      pillSupplyLowSent = List.generate(
        pillNames.length,
        (i) => i < lowSent.length ? lowSent[i] : false,
      );
    } else {
      // Fallback only for old installs/migration cases where prefs do not exist yet.
      pillSupplyEnabled = meds.map((m) => m.supplyEnabled).toList();
      pillSupplyLeft = meds.map((m) => m.supplyLeft).toList();
      pillSupplyInitial = meds.map((m) => m.supplyInitial).toList();
      pillSupplyLowSent = List<bool>.filled(
        pillNames.length,
        false,
        growable: true,
      );
    }

    _alignMedicationCreatedAtsToCount(pillNames.length);
    _alignSupplyListsToCount(pillNames.length);
  }

  Future<void> _refreshAdherenceFromDb() async {
    if (medicationIds.isEmpty) return;

    await _scheduleService.ensureDoseEventsForMedications(medicationIds);
    await _adherenceService.autoMarkMissedPastPlanned();
  }

  Future<Map<String, dynamic>> _deriveCheckMapFromDatabase() async {
    final map = <String, dynamic>{};
    final missedMap = <String, dynamic>{};

    final now = DateTime.now();
    for (var i = 0; i < pillNames.length; i++) {
      if (i >= medicationIds.length) continue;

      final doses = _doseTimesForPill(i);
      if (doses.isEmpty) continue;

      final w = _computeDoseWindow(now: now, dosesSorted: doses, pillIndex: i);
      final cycleDay = DateTime(
        w.cycleStart.year,
        w.cycleStart.month,
        w.cycleStart.day,
      );
      final cycleIso = w.cycleStart.toIso8601String();

      final mid = medicationIds[i];
      var takenMask = 0;
      var missedMask = 0;

      for (int doseIndex = 0; doseIndex < doses.length; doseIndex++) {
        final plannedIso = plannedAtUtcIsoForOrderedDose(
          cycleDay,
          doses,
          doseIndex,
        );

        final e = await _adherenceService.findDoseEventForPlannedUtc(
          medicationId: mid,
          plannedAtUtcIso: plannedIso,
        );

        if (e == null) continue;

        if (e.status == 'taken') {
          takenMask |= (1 << doseIndex);
        } else if (e.status == 'missed') {
          missedMask |= (1 << doseIndex);
        }
      }

      map['$i'] = _packCycleAndMask(cycleIso, takenMask);
      missedMap['$i'] = _packCycleAndMask(cycleIso, missedMask);
    }

    _lastMissedMapCache = missedMap;
    return map;
  }

  Future<void> _loadDoseHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_doseHistoryKey);
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <DateTime, List<String>>{};
    for (final entry in decoded.entries) {
      final day = DateTime.parse(entry.key);
      result[DateTime(day.year, day.month, day.day)] = (entry.value as List)
          .cast<String>();
    }

    if (mounted) {
      setState(() => _doseHistory = result);
    }
  }

  Future<void> _saveDoseHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    for (final entry in _doseHistory.entries) {
      encoded[entry.key.toIso8601String()] = entry.value;
    }
    await prefs.setString(_doseHistoryKey, jsonEncode(encoded));
  }

  void _recordDoseHistory(String pillName) {
    final now = DateTime.now();
    final dayKey = DateTime(now.year, now.month, now.day);
    _doseHistory[dayKey] ??= <String>[];
    _doseHistory[dayKey]!.add(pillName);
    _saveDoseHistory();
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

  Map<String, dynamic> _decodeMaskMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _localStateSignature() {
    // medicationIds are the safest stable identity you currently have
    return medicationIds.join(',');
  }

  Future<void> _saveLocalStateSignature() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localStatePillSigKey, _localStateSignature());
  }

  void _removeSlotFromLocalDailyState(int deletedSlot) {
    Map<String, dynamic> shiftMap(Map<String, dynamic> source) {
      final out = <String, dynamic>{};

      for (final entry in source.entries) {
        final oldIndex = int.tryParse(entry.key);
        if (oldIndex == null) continue;

        // Drop the deleted pill's state.
        if (oldIndex == deletedSlot) continue;

        // Anything after the deleted pill shifts down by 1.
        final newIndex = oldIndex > deletedSlot ? oldIndex - 1 : oldIndex;
        out['$newIndex'] = entry.value;
      }

      return out;
    }

    _checkMapCache = shiftMap(_checkMapCache);
    _lastCheckMapCache = Map<String, dynamic>.from(_checkMapCache);
    _lastMissedMapCache = shiftMap(_lastMissedMapCache);

    _checkMapFuture = Future.value(Map<String, dynamic>.from(_checkMapCache));
  }

  Future<void> _clearLocalDailyState({bool publish = true}) async {
    _checkMapCache = <String, dynamic>{};
    _lastCheckMapCache = <String, dynamic>{};
    _lastMissedMapCache = <String, dynamic>{};

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pillCheckKey);
    await prefs.remove(_pillMissedKey);
    await prefs.setString(_localStatePillSigKey, _localStateSignature());

    if (publish) {
      _publishLocalDailyState();
    }
  }

  Future<void> _saveLocalDailyState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pillCheckKey, jsonEncode(_checkMapCache));
    await prefs.setString(_pillMissedKey, jsonEncode(_lastMissedMapCache));
  }

  Future<void> _loadLocalDailyState() async {
    final prefs = await SharedPreferences.getInstance();
    _checkMapCache = _decodeMaskMap(prefs.getString(_pillCheckKey));
    _lastCheckMapCache = Map<String, dynamic>.from(_checkMapCache);
    _lastMissedMapCache = _decodeMaskMap(prefs.getString(_pillMissedKey));
    _checkMapFuture = Future.value(Map<String, dynamic>.from(_checkMapCache));
  }

  void _publishLocalDailyState() {
    _lastCheckMapCache = Map<String, dynamic>.from(_checkMapCache);

    if (!mounted) {
      _requestStreakSyncFromLocalState();
      return;
    }

    setState(() {
      _checkMapFuture = Future.value(Map<String, dynamic>.from(_checkMapCache));
    });

    _requestStreakSyncFromLocalState();
  }

  void _setLocalDoseStatus({
    required int pillIndex,
    required String cycleIso,
    required int doseIndex,
    required String status, // 'taken' | 'missed'
  }) {
    final takenParsed = _readCycleAndMask(
      _checkMapCache['$pillIndex'] as String?,
    );
    final missedParsed = _readCycleAndMask(
      _lastMissedMapCache['$pillIndex'] as String?,
    );

    var takenMask = takenParsed.cycleIso == cycleIso ? takenParsed.mask : 0;
    var missedMask = missedParsed.cycleIso == cycleIso ? missedParsed.mask : 0;

    final bit = 1 << doseIndex;

    if (status == 'taken') {
      takenMask |= bit;
      missedMask &= ~bit;
    } else {
      missedMask |= bit;
      takenMask &= ~bit;
    }

    _checkMapCache['$pillIndex'] = _packCycleAndMask(cycleIso, takenMask);
    _lastMissedMapCache['$pillIndex'] = _packCycleAndMask(cycleIso, missedMask);
  }

  Future<void> _persistTakenToDb({
    required int medicationId,
    required String plannedIso,
  }) async {
    var ok = await _adherenceService.confirmTakenByPlannedUtc(
      medicationId: medicationId,
      plannedAtUtcIso: plannedIso,
    );

    if (ok) return;

    await _scheduleService.ensureDoseEventsForMedication(
      medicationId,
      daysBack: 1,
    );

    await _adherenceService.confirmTakenByPlannedUtc(
      medicationId: medicationId,
      plannedAtUtcIso: plannedIso,
    );
  }

  Future<void> _persistMissedToDb({
    required int medicationId,
    required String plannedIso,
  }) async {
    var ok = await _adherenceService.markMissedByPlannedUtc(
      medicationId: medicationId,
      plannedAtUtcIso: plannedIso,
    );

    if (ok) return;

    await _scheduleService.ensureDoseEventsForMedication(
      medicationId,
      daysBack: 1,
    );

    await _adherenceService.markMissedByPlannedUtc(
      medicationId: medicationId,
      plannedAtUtcIso: plannedIso,
    );
  }

  int _maskForCycle(Map<String, dynamic> map, int pillIndex, String cycleIso) {
    final stored = map['$pillIndex'] as String?;
    final parsed = _readCycleAndMask(stored);
    return parsed.cycleIso == cycleIso ? parsed.mask : 0;
  }

  ({
    int doseIndex,
    DateTime cycleStart,
    String cycleIso,
    int takenMask,
    int missedMask,
    int resolvedMask,
  })
  _getDisplayedDoseStateForPill({
    required int pillIndex,
    required List<TimeOfDay> doses,
    required Map<String, dynamic> takenMap,
    required Map<String, dynamic> missedMap,
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();
    final w = _computeDoseWindow(
      now: currentNow,
      dosesSorted: doses,
      pillIndex: pillIndex,
    );

    final cycleIso = w.cycleStart.toIso8601String();
    final takenMask = _maskForCycle(takenMap, pillIndex, cycleIso);
    final missedMask = _maskForCycle(missedMap, pillIndex, cycleIso);
    final resolvedMask = takenMask | missedMask;

    if (doses.isEmpty) {
      return (
        doseIndex: 0,
        cycleStart: w.cycleStart,
        cycleIso: cycleIso,
        takenMask: takenMask,
        missedMask: missedMask,
        resolvedMask: resolvedMask,
      );
    }

    final cycleDay = DateTime(
      w.cycleStart.year,
      w.cycleStart.month,
      w.cycleStart.day,
    );

    // Find the first unresolved dose in this cycle.
    int? nextUnresolvedIndex;
    for (int i = 0; i < doses.length; i++) {
      if ((resolvedMask & (1 << i)) == 0) {
        nextUnresolvedIndex = i;
        break;
      }
    }

    // If all doses already have a state, keep the last dose active until reset.
    if (nextUnresolvedIndex == null) {
      return (
        doseIndex: doses.length - 1,
        cycleStart: w.cycleStart,
        cycleIso: cycleIso,
        takenMask: takenMask,
        missedMask: missedMask,
        resolvedMask: resolvedMask,
      );
    }

    // If the very first dose is still unresolved, it should stay active.
    if (nextUnresolvedIndex == 0) {
      return (
        doseIndex: 0,
        cycleStart: w.cycleStart,
        cycleIso: cycleIso,
        takenMask: takenMask,
        missedMask: missedMask,
        resolvedMask: resolvedMask,
      );
    }

    // Otherwise, keep showing the PREVIOUS dose until 2 hours before the
    // next unresolved dose. Then switch to the next unresolved dose.
    final previousIndex = nextUnresolvedIndex - 1;

    final nextPlannedAt = plannedAtLocalForOrderedDose(
      cycleDay,
      doses,
      nextUnresolvedIndex,
    );
    final switchAt = nextPlannedAt.subtract(const Duration(hours: 2));

    final activeIndex = currentNow.isBefore(switchAt)
        ? previousIndex
        : nextUnresolvedIndex;

    return (
      doseIndex: activeIndex,
      cycleStart: w.cycleStart,
      cycleIso: cycleIso,
      takenMask: takenMask,
      missedMask: missedMask,
      resolvedMask: resolvedMask,
    );
  }

  List<TimeOfDay> _doseTimesForPillFromLists(
    List<List<String>> doseTimes24h,
    int pillIndex,
  ) {
    if (pillIndex < 0 || pillIndex >= doseTimes24h.length) {
      return [const TimeOfDay(hour: 8, minute: 0)];
    }

    final list = doseTimes24h[pillIndex];
    if (list.isEmpty) {
      return [const TimeOfDay(hour: 8, minute: 0)];
    }

    // Preserve configured dose order here too.
    return list.map(_strToTime).toList(growable: false);
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
      final w = _computeDoseWindow(
        now: now,
        dosesSorted: doses,
        pillIndex: pillIndex,
      );
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
        final dosesSorted = rawTimes.map(_strToTime).toList(growable: false);

        if (dosesSorted.isEmpty) continue;

        // What cycle are we in right now (based on your 2-hours-before-first-dose rule)?
        final w = _computeDoseWindow(
          now: now,
          dosesSorted: dosesSorted,
          pillIndex: pillIndex,
        );
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

    final w = _computeDoseWindow(
      now: DateTime.now(),
      dosesSorted: doses,
      pillIndex: pillIndex,
    );
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

  bool _isFirstDayForMedication(int pillIndex) {
    if (pillIndex < 0 || pillIndex >= medicationCreatedAts.length) return false;

    final created = medicationCreatedAts[pillIndex].toLocal();
    final now = DateTime.now();

    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }

  bool _isDoseMarkedMissedSync(int pillIndex, String cycleIso, int doseIndex) {
    final stored = _lastMissedMapCache['$pillIndex'] as String?;
    final parsed = _readCycleAndMask(stored);
    if (parsed.cycleIso != cycleIso) return false;
    return (parsed.mask & (1 << doseIndex)) != 0;
  }

  bool _isCurrentDoseMissed({
    required int pillIndex,
    required Map<String, dynamic> map,
    Duration grace = const Duration(hours: 4),
  }) {
    if (pillIndex < 0 || pillIndex >= pillNames.length) return false;

    final doses = _doseTimesForPill(pillIndex);
    if (doses.isEmpty) return false;

    final now = DateTime.now();
    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: map,
      missedMap: _lastMissedMapCache,
      now: now,
    );

    final cycleIso = state.cycleIso;

    final alreadyChecked = (state.takenMask & (1 << state.doseIndex)) != 0;
    if (alreadyChecked) return false;

    final explicitlyMissed = (state.missedMask & (1 << state.doseIndex)) != 0;
    if (explicitlyMissed) return true;

    final cycleDay = DateTime(
      state.cycleStart.year,
      state.cycleStart.month,
      state.cycleStart.day,
    );

    final plannedAt = plannedAtLocalForOrderedDose(
      cycleDay,
      doses,
      state.doseIndex,
    );

    return now.isAfter(plannedAt.add(grace));
  }

  Future<void> _materializeOverdueMissedDosesLocally({
    int? onlyPillIndex,
  }) async {
    final now = DateTime.now();
    bool changed = false;

    final indexes = onlyPillIndex == null
        ? List<int>.generate(pillNames.length, (i) => i)
        : <int>[onlyPillIndex];

    for (final pillIndex in indexes) {
      if (pillIndex < 0 || pillIndex >= pillNames.length) continue;

      final doses = _doseTimesForPill(pillIndex);
      if (doses.isEmpty) continue;

      final state = _getDisplayedDoseStateForPill(
        pillIndex: pillIndex,
        doses: doses,
        takenMap: _checkMapCache,
        missedMap: _lastMissedMapCache,
        now: now,
      );

      final cycleDay = DateTime(
        state.cycleStart.year,
        state.cycleStart.month,
        state.cycleStart.day,
      );

      var nextTakenMask = state.takenMask;
      var nextMissedMask = state.missedMask;

      for (int doseIndex = 0; doseIndex < doses.length; doseIndex++) {
        final bit = 1 << doseIndex;

        final alreadyTaken = (nextTakenMask & bit) != 0;
        final alreadyMissed = (nextMissedMask & bit) != 0;

        if (alreadyTaken || alreadyMissed) continue;

        final plannedAt = plannedAtLocalForOrderedDose(
          cycleDay,
          doses,
          doseIndex,
        );

        // Match your current missed rule.
        final missedAt = plannedAt.add(const Duration(hours: 4));

        if (now.isAfter(missedAt)) {
          nextMissedMask |= bit;
          nextTakenMask &= ~bit;
          changed = true;

          // DB catches up in the background, but UI is already correct locally.
          if (pillIndex < medicationIds.length) {
            final plannedIso = plannedAtUtcIsoForOrderedDose(
              cycleDay,
              doses,
              doseIndex,
            );

            _trackAdherenceWrite(
              _persistMissedToDb(
                medicationId: medicationIds[pillIndex],
                plannedIso: plannedIso,
              ),
            );
          }
        }
      }

      if (nextTakenMask != state.takenMask ||
          nextMissedMask != state.missedMask) {
        _checkMapCache['$pillIndex'] = _packCycleAndMask(
          state.cycleIso,
          nextTakenMask,
        );

        _lastMissedMapCache['$pillIndex'] = _packCycleAndMask(
          state.cycleIso,
          nextMissedMask,
        );
      }
    }

    if (!changed) return;

    await _saveLocalDailyState();
    await _syncCurrentCycleAnchorOnly();

    if (!mounted) return;
    _publishLocalDailyState();
    _scheduleCenteredDoseBoundaryRefresh();

    unawaited(
      _rebuild2DayNotifWindowAndReMuteChecked(
        tag: 'materialize-overdue-missed-local',
      ),
    );
  }

  Future<void> _openMultiDoseOverride() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null || pillIndex >= medicationIds.length) return;

    final doses = _doseTimesForPill(pillIndex);
    if (doses.length <= 1) return;

    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _checkMapCache,
      missedMap: _lastMissedMapCache,
      now: DateTime.now(),
    );

    final cycleDay = DateTime(
      state.cycleStart.year,
      state.cycleStart.month,
      state.cycleStart.day,
    );

    final initialTakenMask = state.takenMask;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MultiDoseOverrideDialog(
        pillName: pillNames[pillIndex],
        totalDoses: doses.length,
        initialTakenMask: initialTakenMask,
        onDone: (takenMask) async {
          final oldTakenMask = state.takenMask;
          final oldMissedMask = state.missedMask;

          for (int i = 0; i < doses.length; i++) {
            final shouldBeTaken = (takenMask & (1 << i)) != 0;
            final oldWasTaken = (oldTakenMask & (1 << i)) != 0;
            final oldWasMissed = (oldMissedMask & (1 << i)) != 0;

            _setLocalDoseStatus(
              pillIndex: pillIndex,
              cycleIso: state.cycleIso,
              doseIndex: i,
              status: shouldBeTaken ? 'taken' : 'missed',
            );

            if (!oldWasTaken && shouldBeTaken) {
              await _consumeOneSupplyIfEnabled(pillIndex);
            } else if (oldWasTaken && !shouldBeTaken) {
              await _applySupplyDeltaIfEnabled(pillIndex: pillIndex, delta: 1);
            }

            final plannedIso = plannedAtUtcIsoForOrderedDose(
              cycleDay,
              doses,
              i,
            );

            if (shouldBeTaken) {
              _trackAdherenceWrite(
                _persistTakenToDb(
                  medicationId: medicationIds[pillIndex],
                  plannedIso: plannedIso,
                ),
              );
            } else if (oldWasTaken || !oldWasMissed) {
              _trackAdherenceWrite(
                _persistMissedToDb(
                  medicationId: medicationIds[pillIndex],
                  plannedIso: plannedIso,
                ),
              );
            }
          }

          await _saveLocalDailyState();
          await _syncCurrentCycleAnchorOnly();
          _publishLocalDailyState();
          _scheduleCenteredDoseBoundaryRefresh();

          unawaited(
            _rebuild2DayNotifWindowAndReMuteChecked(tag: 'multi-dose-override'),
          );
        },
      ),
    );
  }

  // ---------------- dose window logic ----------------
  ({
    int doseIndex,
    DateTime windowStart,
    DateTime windowEnd,
    DateTime cycleStart,
  })
  _computeDoseWindowFromCycleStart({
    required DateTime now,
    required DateTime cycleStart,
    required List<TimeOfDay> dosesSorted,
  }) {
    final cycleDay = DateTime(
      cycleStart.year,
      cycleStart.month,
      cycleStart.day,
    );

    final doseInstants = List<DateTime>.generate(
      dosesSorted.length,
      (i) => plannedAtLocalForOrderedDose(cycleDay, dosesSorted, i),
      growable: false,
    );

    final windowStarts = doseInstants
        .map((d) => _minusMinutes(d, 30))
        .toList(growable: false);

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

  ({
    int doseIndex,
    DateTime windowStart,
    DateTime windowEnd,
    DateTime cycleStart,
  })
  _computeDoseWindow({
    required DateTime now,
    required List<TimeOfDay> dosesSorted,
    required int pillIndex,
  }) {
    final first = dosesSorted.first;
    final day = DateTime(now.year, now.month, now.day);

    final cycleStartToday = _atTime(
      day,
      first,
    ).subtract(const Duration(hours: 2));

    // ✅ First-day clamp:
    // if this pill was created today and we're still before today's cycle start,
    // do NOT fall back to yesterday's cycle.
    if (pillIndex != null &&
        _isFirstDayForMedication(pillIndex) &&
        now.isBefore(cycleStartToday)) {
      return _computeDoseWindowFromCycleStart(
        now: now,
        cycleStart: cycleStartToday,
        dosesSorted: dosesSorted,
      );
    }

    final cycleStart = now.isBefore(cycleStartToday)
        ? cycleStartToday.subtract(const Duration(days: 1))
        : cycleStartToday;

    return _computeDoseWindowFromCycleStart(
      now: now,
      cycleStart: cycleStart,
      dosesSorted: dosesSorted,
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

      final w = _computeDoseWindow(now: now, dosesSorted: doses, pillIndex: i);
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

      // This is the moment pending missed streaks should officially be lost
      // if they were not fixed/overridden before the new cycle.
      _requestStreakSyncFromLocalState();

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

    final now = DateTime.now();
    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _lastCheckMapCache,
      missedMap: _lastMissedMapCache,
      now: now,
    );

    final cycleDay = DateTime(
      state.cycleStart.year,
      state.cycleStart.month,
      state.cycleStart.day,
    );

    final plannedAt = plannedAtLocalForOrderedDose(
      cycleDay,
      doses,
      state.doseIndex,
    );

    final missAt = plannedAt.add(const Duration(hours: 4));

    DateTime next = state.cycleStart.add(const Duration(days: 1));
    if (missAt.isAfter(now) && missAt.isBefore(next)) {
      next = missAt;
    }

    final diff = next.difference(now);
    if (diff.inMilliseconds <= 50) {
      if (!mounted) return;
      setState(() {
        _checkMapFuture = _loadCheckMap();
      });
      _requestStreakSyncFromLocalState();
      return;
    }

    _doseBoundaryTimer = Timer(diff, () async {
      if (!mounted) return;

      await _adherenceService.autoMarkMissedPastPlanned();

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

    final rawName = pillNames[slot];
    if (isDemoPillName(rawName)) return kDemoPillName;

    return rawName;
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
    // Make every supply list growable.
    // This prevents "Cannot add to a fixed-length list" after List.filled/List.generate.
    pillSupplyEnabled = List<bool>.from(pillSupplyEnabled, growable: true);
    pillSupplyLeft = List<int>.from(pillSupplyLeft, growable: true);
    pillSupplyInitial = List<int>.from(pillSupplyInitial, growable: true);
    pillSupplyLowSent = List<bool>.from(pillSupplyLowSent, growable: true);

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

  Future<void> _applySupplyDeltaIfEnabled({
    required int pillIndex,
    required int delta,
  }) async {
    if (delta == 0) return;
    if (pillIndex < 0 || pillIndex >= pillNames.length) return;

    _alignSupplyListsToCount(pillNames.length);
    if (!_effectiveSupplyOn(pillIndex)) return;

    final oldLeft = pillSupplyLeft[pillIndex];
    final newLeft = (oldLeft + delta).clamp(0, 1000000);
    if (newLeft == oldLeft) return;

    if (!mounted) return;
    setState(() {
      pillSupplyLeft[pillIndex] = newLeft;

      if (delta > 0 && newLeft > _supplyLowThreshold) {
        pillSupplyLowSent[pillIndex] = false;
      }
    });

    if (delta > 0) {
      if (newLeft > 0) {
        unawaited(
          NotificationService.cancelOutOfSupplyWarning(pillSlot: pillIndex),
        );
      }
      if (newLeft >= _supplyLowThreshold) {
        unawaited(
          NotificationService.cancelLowSupplyWarning(pillSlot: pillIndex),
        );
      }
    }

    await _persistSupplyLists();
  }

  void _showForegroundSupplyNotice(String message) {
    if (!mounted) return;
    if (!Platform.isIOS) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _adjustSupplyForStatusTransition({
    required int pillIndex,
    required String fromStatus,
    required String toStatus,
  }) async {
    if (fromStatus == toStatus) return;

    if (toStatus == 'taken' && fromStatus != 'taken') {
      await _consumeOneSupplyIfEnabled(pillIndex);
      return;
    }

    if (fromStatus == 'taken' && toStatus != 'taken') {
      await _applySupplyDeltaIfEnabled(pillIndex: pillIndex, delta: 1);
    }
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

    // ✅ Keep the current local check/missed masks as-is.
    // The active HomeScreen logic will ignore stale cycleIso values on its own.
    _publishLocalDailyState();
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
    final lowUser = (prefs.getInt(kSupplyLowThresholdKey) ?? 10).clamp(5, 999);

    if (!mounted) return;
    setState(() {
      _supplyModeGlobal = mode;
      _supplyLowThreshold = lowUser;
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

  bool _isDemoPillIndex(int pillIndex) {
    if (pillIndex < 0 || pillIndex >= pillNames.length) return false;
    return isDemoPillName(pillNames[pillIndex]);
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

  String _truncateCenterLabel(String raw, {int maxChars = 16}) {
    final text = raw.trim();
    if (text.length <= maxChars) return text;

    // Keep total displayed length at 16 including "..."
    final keep = maxChars - 3;
    return '${text.substring(0, keep)}...';
  }

  bool _centerLabelIsTruncated(String raw, {int maxChars = 16}) {
    return raw.trim().length > maxChars;
  }

  Future<void> _showFullCenterLabelDialog(String fullText) async {
    final text = fullText.trim();
    if (text.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pill Name'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

  Widget _streaksPanel({
    required double Function(double) s,
    required double Function(double) fs,
    required VoidCallback onClose,
    required VoidCallback onShowStreaksHelp,
    required Set<int> streakPillboxOpenDays,
    required int streakPillboxResetToken,
    required String currentStreakValue,
    required String weeksCompletedValue,
    required String longestStreakValue,
    required String mostWeeksCompletedValue,
    required String streakStatusMessage,
    required int weekProgress,
    required Set<int> completedDayIndexes,
    required bool streakDotsVisible,
    required bool streakMarkersVisible,
    required bool streakMessageVisible,
    required int? weekStartDayIndex,
    required int? nextRequiredDayIndex,
  }) {
    double currentStreakFontSize(String value, double normalSize) {
      final len = value.trim().length;

      if (len <= 3) return normalSize;
      if (len == 4) return normalSize * 0.70;
      if (len == 5) return normalSize * 0.57;
      return normalSize * 0.62;
    }

    final safeWeekProgress = weekProgress.clamp(0, 7).toInt();
    final weekProgressText = '$safeWeekProgress/7';
    final weekProgressFraction = safeWeekProgress / 7.0;
    final weekProgressComplete = safeWeekProgress >= 7;
    final weekProgressFillColor = weekProgressComplete
        ? const Color(0xFF59FF56)
        : const Color.fromARGB(255, 36, 251, 255);
    final iosStreakShiftX = Platform.isIOS
        ? 5.0
        : Platform.isAndroid
        ? 15.0
        : 0.0;
    final safeCompletedDayIndexes = completedDayIndexes
        .where((day) => day >= 0 && day <= 6)
        .toSet();

    int? safeDayIndex(int? day) {
      if (day == null) return null;
      if (day < 0 || day > 6) return null;
      return day;
    }

    final safeWeekStartDay = safeDayIndex(weekStartDayIndex);
    final safeNextRequiredDay = safeDayIndex(nextRequiredDayIndex);

    final displayStartDay = safeWeekStartDay;

    final displayEndDay = safeWeekStartDay == null
        ? null
        : (safeWeekStartDay + 6) % 7;

    final hasActiveWeek = safeWeekProgress > 0 && !weekProgressComplete;

    final showStartMarker = !weekProgressComplete && displayStartDay != null;

    final showNextMarker = hasActiveWeek && safeNextRequiredDay != null;

    final showEndMarker = hasActiveWeek && displayEndDay != null;

    Widget markerForDay({
      required int day,
      required String label,
      required Color color,
    }) {
      return Positioned(
        left: s((55.5 * day) + 2.5 + (day * 1.075) + iosStreakShiftX),
        top: s(8),
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
            opacity: streakMarkersVisible ? 1.0 : 0.0,
            child: _StreakTabMarker(
              label: label,
              color: color,
              width: s(50),
              height: s(58),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(s(8), s(8), s(8), s(10)),
        child: Container(
          decoration: BoxDecoration(
            color: _streakBg,
            borderRadius: BorderRadius.circular(s(18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(height: s(12)),

              // Top row: Current Streak + flame + number overlay.
              Padding(
                padding: EdgeInsets.fromLTRB(s(17), 0, s(14), 0),
                child: SizedBox(
                  height: s(100),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: s(40)),
                              child: Text(
                                'Current Streak:',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Amaranth',
                                  fontSize: fs(35),
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(
                                      blurRadius: 2,
                                      offset: Offset(2.5, 1),
                                      color: Color.fromARGB(120, 0, 0, 0),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          SizedBox(
                            width: s(104),
                            height: s(104),
                            child: Transform.translate(
                              offset: Offset(
                                s(10), // whole flame group: left/right
                                s(-2), // whole flame group: up/down
                              ),
                              child: Transform.scale(
                                scale: 0.92, // whole flame group size
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.translate(
                                      offset: Offset(s(-15), s(0)),
                                      child: Transform.rotate(
                                        angle: -0.23,
                                        child: Icon(
                                          Icons.whatshot_rounded,
                                          size: s(105),
                                          color: const Color.fromARGB(
                                            255,
                                            255,
                                            116,
                                            66,
                                          ),
                                        ),
                                      ),
                                    ),

                                    Transform.translate(
                                      offset: Offset(s(10), s(-15)),
                                      child: Transform.scale(
                                        scaleX: -1,
                                        child: Icon(
                                          Icons.whatshot_rounded,
                                          size: s(150),
                                          color: const Color.fromARGB(
                                            255,
                                            255,
                                            116,
                                            66,
                                          ),
                                        ),
                                      ),
                                    ),

                                    Transform.translate(
                                      offset: Offset(s(-10), s(25)),
                                      child: Container(
                                        width: s(50),
                                        height: s(50),
                                        decoration: const BoxDecoration(
                                          color: _streakFlame,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),

                                    Transform.translate(
                                      offset: Offset(s(-19), s(10)),
                                      child: Icon(
                                        Icons.whatshot_rounded,
                                        size: s(109),
                                        color: _streakFlame,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Number overlay is OUTSIDE the fire Stack and OUTSIDE the Row.
                      // It has a fixed box, so 1/2/3 digit numbers don't move the flame group.
                      Positioned(
                        right: s(20),
                        top: s(45),
                        child: SizedBox(
                          width: s(76),
                          height: s(50),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Text(
                                currentStreakValue,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Amaranth',
                                  fontSize: fs(
                                    currentStreakFontSize(
                                      currentStreakValue,
                                      38,
                                    ),
                                  ),
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(
                                      blurRadius: 2,
                                      offset: Offset(2.5, 1),
                                      color: Color.fromARGB(100, 0, 0, 0),
                                    ),
                                  ],
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

              SizedBox(height: s(18)),

              AnimatedOpacity(
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeInOut,
                opacity: streakMessageVisible ? 1.0 : 0.0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    streakStatusMessage,
                    key: ValueKey(streakStatusMessage),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Amaranth',
                      fontSize: fs(20),
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          blurRadius: 2,
                          offset: Offset(2, 1),
                          color: Color.fromARGB(100, 0, 0, 0),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: s(70)),

              // Dark green pillbox band
              Container(
                width: double.infinity,
                height: s(100),
                color: _streakBand,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: OverflowBox(
                        maxWidth: s(620),
                        maxHeight: s(230),
                        child: Transform.translate(
                          offset: Offset(s(5), -s(23)),
                          child: Transform.scale(
                            scale: 1.35,
                            child: SizedBox(
                              width: s(430),
                              height: s(160),
                              child: WeeklyPillboxOrganizer(
                                key: ValueKey(
                                  'streaks_storyboard_pillbox_$streakPillboxResetToken',
                                ),
                                fit: BoxFit.contain,
                                openDays: streakPillboxOpenDays,
                                autoCloseOthers: false,
                                stateMachineName: 'PillboxSM',
                                openAnimDuration: const Duration(
                                  milliseconds: 750,
                                ),
                                openSpeedMultiplier: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Blue divider line overlays for streak pillbox sections.
                    for (final left in [
                      55.0,
                      111.5,
                      168.0,
                      224.5,
                      281.0,
                      337.0,
                    ])
                      Positioned(
                        left: s(left + iosStreakShiftX),
                        top: s(8),
                        child: IgnorePointer(
                          child: Container(
                            width: s(2),
                            height: s(60),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 108, 157, 225),
                              borderRadius: BorderRadius.circular(s(99)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: s(3),
                                  offset: Offset(0, s(1)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Pulsing Start / Next / End markers.
                    // Put these after divider lines and before mini completion circles.
                    if (showStartMarker)
                      markerForDay(
                        day: displayStartDay!,
                        label: 'Start',
                        color: const Color(0xFF59FF56),
                      ),

                    if (showNextMarker)
                      markerForDay(
                        day: safeNextRequiredDay!,
                        label: 'Next',
                        color: const Color(0xFFFFD447),
                      ),

                    if (showEndMarker)
                      markerForDay(
                        day: displayEndDay!,
                        label: 'End',
                        color: const Color(0xFFFF0037),
                      ),

                    // Mini daily completion circles over the streak pillbox.
                    // They appear only after the pillbox tabs finish opening.
                    // 0 = Sun, 1 = Mon, ... 6 = Sat.
                    if (streakDotsVisible)
                      for (int day = 0; day < 7; day++)
                        Positioned(
                          key: ValueKey('streak_mini_circle_position_$day'),
                          left: s(
                            (21.25 + (day + (day * 55.085)) - 16.0) +
                                iosStreakShiftX,
                          ),
                          top: s(-50.5),
                          child: IgnorePointer(
                            child: _StreakMiniCompletionCircle(
                              key: ValueKey('streak_mini_circle_$day'),
                              done: safeCompletedDayIndexes.contains(day),
                              size: s(47.5),
                              delay: Duration(milliseconds: day * 125),
                            ),
                          ),
                        ),
                  ],
                ),
              ),

              SizedBox(height: s(12)),

              // Week progress bar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: s(24)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Week Progress',
                          style: TextStyle(
                            fontFamily: 'Amaranth',
                            fontSize: fs(17),
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                blurRadius: 2,
                                offset: Offset(1.5, 1),
                                color: Color.fromARGB(100, 0, 0, 0),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          weekProgressText,
                          style: TextStyle(
                            fontFamily: 'Amaranth',
                            fontSize: fs(17),
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                blurRadius: 2,
                                offset: Offset(1.5, 1),
                                color: Color.fromARGB(100, 0, 0, 0),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: s(6)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(s(99)),
                      child: Container(
                        height: s(12),
                        width: double.infinity,
                        color: Colors.white.withOpacity(0.28),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: weekProgressFraction.clamp(0.0, 1.0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOut,
                            color: weekProgressFillColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: s(14)),

              // Weeks completed box
              Padding(
                padding: EdgeInsets.symmetric(horizontal: s(24)),
                child: Container(
                  height: s(54),
                  decoration: BoxDecoration(
                    color: _streakBlue,
                    borderRadius: BorderRadius.circular(s(14)),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: s(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Weeks Completed:',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Amaranth',
                            fontSize: fs(21),
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                blurRadius: 2,
                                offset: Offset(1.5, 1),
                                color: Color.fromARGB(100, 0, 0, 0),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        weeksCompletedValue,
                        style: TextStyle(
                          fontFamily: 'Amaranth',
                          fontSize: fs(36),
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: const [
                            Shadow(
                              blurRadius: 2,
                              offset: Offset(1.5, 1),
                              color: Color.fromARGB(100, 0, 0, 0),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: s(12)),

              // How streaks work button
              Material(
                color: _streakHelpBtn,
                borderRadius: BorderRadius.circular(s(16)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(s(16)),
                  onTap: onShowStreaksHelp,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: s(18),
                      vertical: s(10),
                    ),
                    child: Text(
                      'How do streaks work?',
                      style: TextStyle(
                        fontFamily: 'Amaranth',
                        fontSize: fs(17),
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Bottom stats section
              Transform.translate(
                offset: Offset(0, Platform.isIOS ? s(10) : 0),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: s(10)),
                  decoration: BoxDecoration(
                    color: _streakBand.withOpacity(0.40),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: s(24)),
                    child: SizedBox(
                      height: s(118),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: s(36),
                                  child: Center(
                                    child: Text(
                                      'Longest Streak',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Amaranth',
                                        fontSize: fs(22),
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 0.95,
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 2,
                                            offset: Offset(1.5, 1),
                                            color: Color.fromARGB(100, 0, 0, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: s(0)),
                                SizedBox(
                                  height: s(66),
                                  child: Center(
                                    child: Text(
                                      longestStreakValue,
                                      style: TextStyle(
                                        fontFamily: 'Amaranth',
                                        fontSize: fs(32),
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.0,
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 2,
                                            offset: Offset(1.5, 1),
                                            color: Color.fromARGB(100, 0, 0, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Container(
                            width: s(2),
                            height: s(118),
                            color: const Color.fromARGB(170, 0, 88, 33),
                          ),

                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: s(36),
                                  child: Center(
                                    child: Text(
                                      'Most Weeks\nCompleted',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Amaranth',
                                        fontSize: fs(18),
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 0.95,
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 2,
                                            offset: Offset(1.5, 1),
                                            color: Color.fromARGB(100, 0, 0, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: s(0)),
                                SizedBox(
                                  height: s(66),
                                  child: Center(
                                    child: Text(
                                      mostWeeksCompletedValue,
                                      style: TextStyle(
                                        fontFamily: 'Amaranth',
                                        fontSize: fs(32),
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.0,
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 2,
                                            offset: Offset(1.5, 1),
                                            color: Color.fromARGB(100, 0, 0, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: s(22)),

              // Exit button
              Transform.translate(
                offset: Offset(0, Platform.isIOS ? s(5) : 0),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(s(10), 0, s(10), s(18)),
                  child: SizedBox(
                    width: double.infinity,
                    height: s(54),
                    child: Material(
                      color: _streakExitRed,
                      borderRadius: BorderRadius.circular(s(16)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(s(16)),
                        onTap: onClose,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Exit',
                              style: TextStyle(
                                fontFamily: 'Amaranth',
                                fontSize: fs(21),
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: s(8)),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: s(24),
                              color: Colors.white,
                            ),
                          ],
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
    );
  }

  // ---------------- onboarding ----------------
  Future<void> _showWelcomeTutorialPrompt(SharedPreferences prefs) async {
    final alreadySeen = prefs.getBool(_seenPromptKey) ?? false;
    if (alreadySeen) return;

    final wantsTutorial =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Welcome to PillChecker!'),
            content: const Text('Would you like a tutorial?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start tutorial'),
              ),
            ],
          ),
        ) ??
        false;

    await prefs.setBool(_seenPromptKey, true);

    if (!mounted) return;
    if (wantsTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startTutorial();
      });
    }
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

  // ---------------- streak state ----------------
  int _dateKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  DateTime _dateFromKey(int key) {
    final year = key ~/ 10000;
    final month = (key ~/ 100) % 100;
    final day = key % 100;
    return DateTime(year, month, day);
  }

  int _daysBetweenDateKeys(int fromKey, int toKey) {
    final from = _dateFromKey(fromKey);
    final to = _dateFromKey(toKey);

    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);

    return toDay.difference(fromDay).inDays;
  }

  int? _mostRecentCompletedStreakDayKey(_StreakState state) {
    final keys = state.completedDayKeys.toSet();

    final last = state.lastCompletedDayKey;
    if (last != null) keys.add(last);

    if (keys.isEmpty) return null;

    final sorted = keys.toList()..sort();
    return sorted.last;
  }

  int _streakDayKeyForNow() {
    final now = DateTime.now();

    // Use PillChecker's cycle day, not calendar midnight.
    // This keeps streak loss aligned with the app's daily reset timing.
    final cycleStart = _globalCycleStartForNow(now);

    final d = cycleStart ?? now;
    return _dateKey(d);
  }

  /// Sun = 0, Mon = 1, ... Sat = 6
  int _dayIndexFor(DateTime d) => d.weekday % 7;

  int _streakDayIndexForNow() {
    final now = DateTime.now();

    // Match the same PillChecker cycle day used by streakDayKey.
    final cycleStart = _globalCycleStartForNow(now);
    final d = cycleStart ?? now;

    return _dayIndexFor(d);
  }

  Future<void> _loadStreakState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_streakStateKey);

    final loaded = _StreakState.fromJsonString(raw);

    if (!mounted) {
      _streakState = loaded;
      return;
    }

    setState(() {
      _streakState = loaded;
    });
  }

  Future<void> _saveStreakState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_streakStateKey, _streakState.toJsonString());
  }

  Future<void> _setStreakState(_StreakState next) async {
    final normalizedNext = next.normalized();

    final currentStreakIncreased =
        normalizedNext.currentStreak > _streakState.currentStreak;

    if (!mounted) {
      _streakState = normalizedNext;
      await _saveStreakState();
      return;
    }

    setState(() {
      _streakState = normalizedNext;

      // Bounce/highlight the streak button whenever current streak goes up by 1.
      // This clears once the user opens the streak screen.
      if (currentStreakIncreased && !_streaksOpen) {
        _streakButtonNeedsAttention = true;
      }
    });

    await _saveStreakState();
    _refreshStreakStatusMessage();
  }

  bool _hasMissedStreakRiskForToday() {
    if (pillNames.isEmpty) return false;

    final now = DateTime.now();

    for (int pillIndex = 0; pillIndex < pillNames.length; pillIndex++) {
      final doses = _doseTimesForPill(pillIndex);
      if (doses.isEmpty) continue;

      final state = _getDisplayedDoseStateForPill(
        pillIndex: pillIndex,
        doses: doses,
        takenMap: _checkMapCache,
        missedMap: _lastMissedMapCache,
        now: now,
      );

      // Explicit missed bit saved locally.
      if (state.missedMask != 0) {
        return true;
      }

      // Visual/time-based missed state, even before it gets written.
      if (_isCurrentDoseMissed(pillIndex: pillIndex, map: _checkMapCache)) {
        return true;
      }
    }

    return false;
  }

  ({
    int weekProgress,
    int weeksCompleted,
    int mostWeeksCompleted,
    int? weekStartDayIndex,
    int? nextRequiredDayIndex,
  })
  _weeklyStateAfterCompletingDay(_StreakState state, int todayDayIndex) {
    final safeProgress = state.weekProgress.clamp(0, 7).toInt();

    // If no week is active, or the last week already completed,
    // start a new rolling 7-day week from today.
    if (safeProgress == 0 ||
        safeProgress >= 7 ||
        state.weekStartDayIndex == null ||
        state.nextRequiredDayIndex == null) {
      return (
        weekProgress: 1,
        weeksCompleted: state.weeksCompleted,
        mostWeeksCompleted: state.mostWeeksCompleted,
        weekStartDayIndex: todayDayIndex,
        nextRequiredDayIndex: (todayDayIndex + 1) % 7,
      );
    }

    // If the user completed a day that is not the expected next day,
    // treat it as a fresh weekly run. This is a defensive fallback for
    // weird time travel / reset cases.
    if (state.nextRequiredDayIndex != todayDayIndex) {
      return (
        weekProgress: 1,
        weeksCompleted: state.weeksCompleted,
        mostWeeksCompleted: state.mostWeeksCompleted,
        weekStartDayIndex: todayDayIndex,
        nextRequiredDayIndex: (todayDayIndex + 1) % 7,
      );
    }

    final nextProgress = (safeProgress + 1).clamp(0, 7).toInt();

    if (nextProgress >= 7) {
      final nextWeeksCompleted = (state.weeksCompleted + 1)
          .clamp(0, 999999)
          .toInt();

      final nextMostWeeksCompleted =
          nextWeeksCompleted > state.mostWeeksCompleted
          ? nextWeeksCompleted
          : state.mostWeeksCompleted;

      return (
        weekProgress: 7,
        weeksCompleted: nextWeeksCompleted,
        mostWeeksCompleted: nextMostWeeksCompleted,
        weekStartDayIndex: state.weekStartDayIndex,
        nextRequiredDayIndex: (todayDayIndex + 1) % 7,
      );
    }

    return (
      weekProgress: nextProgress,
      weeksCompleted: state.weeksCompleted,
      mostWeeksCompleted: state.mostWeeksCompleted,
      weekStartDayIndex: state.weekStartDayIndex,
      nextRequiredDayIndex: (todayDayIndex + 1) % 7,
    );
  }

  ({
    int weekProgress,
    int weeksCompleted,
    int mostWeeksCompleted,
    int? weekStartDayIndex,
    int? nextRequiredDayIndex,
  })
  _weeklyStateAfterUndoingToday(_StreakState state, int todayDayIndex) {
    final safeProgress = state.weekProgress.clamp(0, 7).toInt();

    if (safeProgress <= 0) {
      return (
        weekProgress: 0,
        weeksCompleted: state.weeksCompleted,
        mostWeeksCompleted: state.mostWeeksCompleted,
        weekStartDayIndex: null,
        nextRequiredDayIndex: null,
      );
    }

    // If today was the 7th completed day, undo the completed week too.
    if (safeProgress >= 7) {
      final nextWeeksCompleted = (state.weeksCompleted - 1)
          .clamp(0, 999999)
          .toInt();

      // Lifetime best should never decrement automatically.
      // Only a manual Reset Streaks action should clear this later.
      final nextMostWeeksCompleted = state.mostWeeksCompleted;

      return (
        weekProgress: 6,
        weeksCompleted: nextWeeksCompleted,
        mostWeeksCompleted: nextMostWeeksCompleted,
        weekStartDayIndex: state.weekStartDayIndex,
        nextRequiredDayIndex: todayDayIndex,
      );
    }

    final nextProgress = (safeProgress - 1).clamp(0, 7).toInt();

    if (nextProgress == 0) {
      return (
        weekProgress: 0,
        weeksCompleted: state.weeksCompleted,
        mostWeeksCompleted: state.mostWeeksCompleted,
        weekStartDayIndex: null,
        nextRequiredDayIndex: null,
      );
    }

    return (
      weekProgress: nextProgress,
      weeksCompleted: state.weeksCompleted,
      mostWeeksCompleted: state.mostWeeksCompleted,
      weekStartDayIndex: state.weekStartDayIndex,
      nextRequiredDayIndex: todayDayIndex,
    );
  }

  Future<void> _syncStreakFromLocalDailyState() async {
    if (!_streakState.streaksEnabled) return;

    final todayKey = _streakDayKeyForNow();

    var state = _streakState;

    // ------------------------------------------------------------
    // 1) If yesterday/older day was pending lost and we made it to
    //    a new day, the streak is now officially lost.
    // ------------------------------------------------------------
    final pendingLostDayKey = state.pendingLostDayKey;
    final hasExpiredPendingLoss =
        pendingLostDayKey != null && pendingLostDayKey != todayKey;

    if (hasExpiredPendingLoss) {
      state = state
          .copyWith(
            currentStreak: 0,
            weeksCompleted: 0,
            weekProgress: 0,
            weekStartDayIndex: null,
            nextRequiredDayIndex: null,
            pendingLostDayKey: null,
            pendingLostStreakValue: null,
          )
          .normalized();

      await _setStreakState(state);

      // Important: stop here so this same sync pass cannot accidentally
      // re-count stale/in-between daily state right after resetting.
      return;
    }

    // ------------------------------------------------------------
    // If the user skipped one or more PillChecker days without ever
    // producing a missed state, there may be no pendingLostDayKey.
    // Example: time travel / app closed / missed state never got written.
    // If the most recent completed streak day is older than yesterday,
    // the streak is officially broken.
    // ------------------------------------------------------------
    final mostRecentCompletedDayKey = _mostRecentCompletedStreakDayKey(state);

    final skippedARequiredDay =
        state.currentStreak > 0 &&
        mostRecentCompletedDayKey != null &&
        _daysBetweenDateKeys(mostRecentCompletedDayKey, todayKey) > 1;

    final impossibleStreakState =
        state.currentStreak > 0 && mostRecentCompletedDayKey == null;

    if (skippedARequiredDay || impossibleStreakState) {
      state = state
          .copyWith(
            currentStreak: 0,
            weeksCompleted: 0,
            weekProgress: 0,
            weekStartDayIndex: null,
            nextRequiredDayIndex: null,
            pendingLostDayKey: null,
            pendingLostStreakValue: null,
          )
          .normalized();

      await _setStreakState(state);

      // Stop here. The user can earn a new streak point only after
      // completing the current day from this reset state.
      return;
    }

    final allDoneToday = _areAllPillsComplete(_checkMapCache);
    final missedRiskToday = _hasMissedStreakRiskForToday();

    final completedSet = state.completedDayKeys.toSet();
    final alreadyCountedToday =
        completedSet.contains(todayKey) ||
        state.lastCompletedDayKey == todayKey;

    // ------------------------------------------------------------
    // 2) If a dose is missed today, save the streak as pending.
    //    If today was already counted complete, undo today's +1 first.
    //    Example: user checked all pills, then marks one missed.
    // ------------------------------------------------------------
    if (missedRiskToday && !allDoneToday) {
      final alreadyPendingToday = state.pendingLostDayKey == todayKey;

      // Special case:
      // Today was already counted, but now a dose is missed.
      // Undo today's streak/week increment immediately, then put
      // the remaining streak value at risk until tomorrow.
      if (alreadyCountedToday) {
        completedSet.remove(todayKey);
        final completedDays = completedSet.toList()..sort();

        final previousCompletedDayKey = completedDays.isEmpty
            ? null
            : completedDays.last;

        final previousCurrentStreak = state.currentStreak;

        final nextCurrentStreak = (previousCurrentStreak - 1)
            .clamp(0, 999999)
            .toInt();

        // Lifetime best should never decrement automatically.
        // Only a manual Reset Streaks action should clear this later.
        final nextLongestStreak = state.longestStreak;

        final todayDayIndex = _streakDayIndexForNow();
        final weekly = _weeklyStateAfterUndoingToday(state, todayDayIndex);

        await _setStreakState(
          state
              .copyWith(
                currentStreak: nextCurrentStreak,
                longestStreak: nextLongestStreak,
                weeksCompleted: weekly.weeksCompleted,
                mostWeeksCompleted: weekly.mostWeeksCompleted,
                weekProgress: weekly.weekProgress,
                weekStartDayIndex: weekly.weekStartDayIndex,
                nextRequiredDayIndex: weekly.nextRequiredDayIndex,
                lastCompletedDayKey: previousCompletedDayKey,
                completedDayKeys: completedDays,

                // Preserve the remaining streak so an override can restore path.
                pendingLostDayKey: nextCurrentStreak > 0 ? todayKey : null,
                pendingLostStreakValue: nextCurrentStreak > 0
                    ? nextCurrentStreak
                    : null,
              )
              .normalized(),
        );

        return;
      }

      // Normal missed-risk case:
      // day was not counted yet, so keep visible streak for now
      // and mark it pending until the next PillChecker day.
      if (!alreadyPendingToday && state.currentStreak > 0) {
        await _setStreakState(
          state
              .copyWith(
                pendingLostDayKey: todayKey,
                pendingLostStreakValue: state.currentStreak,
              )
              .normalized(),
        );
      }

      return;
    }

    // ------------------------------------------------------------
    // 3) If the missed state got fixed today, clear pending loss.
    //    Example: user overrides missed dose back to taken.
    // ------------------------------------------------------------
    if (!missedRiskToday && state.pendingLostDayKey == todayKey) {
      state = state
          .copyWith(pendingLostDayKey: null, pendingLostStreakValue: null)
          .normalized();

      await _setStreakState(state);
    }

    // ------------------------------------------------------------
    // 4) Today just became complete.
    // ------------------------------------------------------------
    if (allDoneToday) {
      if (alreadyCountedToday) return;

      completedSet.add(todayKey);
      final completedDays = completedSet.toList()..sort();

      final todayDayIndex = _streakDayIndexForNow();

      final nextCurrentStreak = (state.currentStreak + 1)
          .clamp(0, 999999)
          .toInt();

      final nextLongestStreak = nextCurrentStreak > state.longestStreak
          ? nextCurrentStreak
          : state.longestStreak;

      final weekly = _weeklyStateAfterCompletingDay(state, todayDayIndex);

      await _setStreakState(
        state
            .copyWith(
              currentStreak: nextCurrentStreak,
              longestStreak: nextLongestStreak,
              weeksCompleted: weekly.weeksCompleted,
              mostWeeksCompleted: weekly.mostWeeksCompleted,
              weekProgress: weekly.weekProgress,
              weekStartDayIndex: weekly.weekStartDayIndex,
              nextRequiredDayIndex: weekly.nextRequiredDayIndex,
              lastCompletedDayKey: todayKey,
              pendingLostDayKey: null,
              pendingLostStreakValue: null,
              completedDayKeys: completedDays,
            )
            .normalized(),
      );

      return;
    }

    // ------------------------------------------------------------
    // 5) Today was counted before, but became incomplete again.
    //    Example: user added a new pill after completing the day.
    // ------------------------------------------------------------
    if (!allDoneToday && alreadyCountedToday) {
      completedSet.remove(todayKey);
      final completedDays = completedSet.toList()..sort();

      final previousCompletedDayKey = completedDays.isEmpty
          ? null
          : completedDays.last;

      final previousCurrentStreak = state.currentStreak;

      final nextCurrentStreak = (previousCurrentStreak - 1)
          .clamp(0, 999999)
          .toInt();

      // Lifetime best should never decrement automatically.
      // Only a manual Reset Streaks action should clear this later.
      final nextLongestStreak = state.longestStreak;

      final todayDayIndex = _streakDayIndexForNow();
      final weekly = _weeklyStateAfterUndoingToday(state, todayDayIndex);

      await _setStreakState(
        state
            .copyWith(
              currentStreak: nextCurrentStreak,
              longestStreak: nextLongestStreak,
              weeksCompleted: weekly.weeksCompleted,
              mostWeeksCompleted: weekly.mostWeeksCompleted,
              weekProgress: weekly.weekProgress,
              weekStartDayIndex: weekly.weekStartDayIndex,
              nextRequiredDayIndex: weekly.nextRequiredDayIndex,
              lastCompletedDayKey: previousCompletedDayKey,
              completedDayKeys: completedDays,
            )
            .normalized(),
      );
    }
  }

  Future<void> _prepareStreakScreenState() async {
    // Make sure latest saved streak state is in memory.
    await _loadStreakState();

    // Make sure any pending missed streak loss officially resets
    // before the streak screen appears.
    await _syncStreakFromLocalDailyState();
  }

  void _requestStreakSyncFromLocalState() {
    unawaited(_syncStreakFromLocalDailyState());
  }

  static const double _streakRiveOpenFrames = 35.0;
  static const double _streakRiveFps = 24.0;
  static const double _streakRiveOpenSpeed = 7.0;
  static const int _streakRiveGuardMs = 60;

  Duration _streakPillboxOpenSequenceDurationFor(int tabCount) {
    if (tabCount <= 0) return Duration.zero;

    final baseAnimMs = ((_streakRiveOpenFrames / _streakRiveFps) * 1000)
        .round();

    final boostedAnimMs = (baseAnimMs / _streakRiveOpenSpeed).round();

    final stepMs = boostedAnimMs + _streakRiveGuardMs;

    // Last tab starts at (tabCount - 1) * stepMs,
    // then needs one more step to finish.
    return Duration(milliseconds: (stepMs * tabCount) + 120);
  }

  Duration _streakDotRippleDuration() {
    // Match the mini circle settings in _streaksPanel.
    // Last circle delay: 6 * 85ms = 510ms
    // DailyCompletionCircle duration: 360ms
    // Extra buffer: 120ms
    return const Duration(milliseconds: 990);
  }

  String _pickRandomMessage(List<String> messages) {
    if (messages.isEmpty) return 'Keep Going!';

    final index = DateTime.now().microsecondsSinceEpoch.abs() % messages.length;

    return messages[index];
  }

  String _pickWeekCompleteMessage() {
    return _pickRandomMessage(const [
      'Week Complete! Good job!',
      'Week Complete! You did it!',
      'Week Complete! Great work!',
      'Week Complete! Keep it going!',
      'Week Complete! That’s a full week!',
      'Week Complete! Proud of you!',
      'Week Complete! Another one down!',
      'Week Complete! You stayed consistent!',
    ]);
  }

  String _pickStreakStatusMessage(_StreakState state) {
    final current = state.currentStreak;
    final weeks = state.weeksCompleted;
    final progress = state.weekProgress.clamp(0, 7).toInt();
    final atRisk = state.pendingLostDayKey != null;

    if (atRisk) {
      return _pickRandomMessage(const [
        "You can still save it!",
        "Don't give up yet!",
        "One override can keep it alive!",
        "Still in the fight!",
        "You’ve got time to recover!",
        "Not over yet!",
      ]);
    }

    if (progress >= 7) {
      return _pickWeekCompleteMessage();
    }

    if (current == 0 && weeks == 0 && progress == 0) {
      return _pickRandomMessage(const [
        "Let's get started!",
        "Fresh start!",
        "Start strong!",
        "One day at a time!",
        "Today is day one!",
        "Let’s build it up!",
        "Ready when you are!",
        "Small steps count!",
      ]);
    }

    if (current == 0 && (weeks > 0 || state.longestStreak > 0)) {
      return _pickRandomMessage(const [
        "An end can start new beginnings! Let's go!",
        "Fresh start. You got this!",
        "New run, same goal!",
        "Back at it!",
        "Restart strong!",
        "The comeback starts now!",
        "No worries — start again!",
        "New streak incoming!",
      ]);
    }

    if (progress >= 5 && progress < 7) {
      return _pickRandomMessage(const [
        "You're almost there! You got this!",
        "So close!",
        "Almost a full week!",
        "Finish strong!",
        "The week is nearly yours!",
        "Keep pushing!",
        "One more clean stretch!",
        "You’re right there!",
      ]);
    }

    if (weeks > 0 && progress == 0) {
      return _pickRandomMessage(const [
        "Let's tackle this next week!",
        "New week, same momentum!",
        "Run it back!",
        "Another week starts now!",
        "Keep the rhythm going!",
        "Time for the next one!",
        "Let’s stack another week!",
      ]);
    }

    if (current >= 10) {
      return _pickRandomMessage(const [
        "You're on fire!",
        "This streak is getting serious!",
        "That’s a real streak!",
        "Keep that momentum!",
        "Big streak energy!",
        "You're locked in!",
        "Don’t stop now!",
      ]);
    }

    return _pickRandomMessage(const [
      "Keep Going!",
      "Nice work!",
      "Keep it up!",
      "You're doing great!",
      "Stay consistent!",
      "One dose at a time!",
      "Momentum matters!",
      "Another day stronger!",
      "You got this!",
      "Stay on track!",
      "Good progress!",
      "Keep building!",
    ]);
  }

  void _refreshStreakStatusMessage({bool allowWeekCompleteMessage = true}) {
    _streakMessageTimer?.cancel();

    final state = _streakState;

    final shouldShowWeekComplete =
        allowWeekCompleteMessage &&
        state.weekProgress >= 7 &&
        state.weeksCompleted > _lastWeekCompleteMessageFor;

    if (shouldShowWeekComplete) {
      _lastWeekCompleteMessageFor = state.weeksCompleted;

      if (mounted) {
        setState(() {
          _streakStatusMessage = _pickWeekCompleteMessage();
        });
      } else {
        _streakStatusMessage = _pickWeekCompleteMessage();
      }

      _streakMessageTimer = Timer(const Duration(seconds: 9), () {
        if (!mounted) return;

        setState(() {
          _streakStatusMessage = _pickWeekCompleteMessage();
        });
      });

      return;
    }

    final nextMessage = _pickStreakStatusMessage(state);

    if (mounted) {
      setState(() {
        _streakStatusMessage = nextMessage;
      });
    } else {
      _streakStatusMessage = nextMessage;
    }
  }

  void _showStreaksHelpDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        const cardColor = Color(0xFF98404F);
        const green = Color(0xFF59FF56);
        const blue = Color.fromARGB(255, 36, 251, 255);
        const yellow = Color(0xFFFFD447);
        const red = Color(0xFFFF0037);

        Widget section({
          required IconData icon,
          required Color iconColor,
          required String title,
          required String body,
        }) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Amaranth',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 28,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.78,
            ),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(26),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.whatshot_rounded,
                      color: Color(0xFFFFB347),
                      size: 34,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'How do streaks work?',
                        style: TextStyle(
                          fontFamily: 'Amaranth',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Flexible(
                  child: Scrollbar(
                    thumbVisibility: true,
                    thickness: 5,
                    radius: const Radius.circular(99),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 10),
                      child: Column(
                        children: [
                          section(
                            icon: Icons.check_circle_rounded,
                            iconColor: green,
                            title: 'Daily streaks',
                            body:
                                'Complete every scheduled dose for the day to add 1 to your current streak. If you add or edit a pill and today becomes incomplete again, today’s streak point is undone until everything is checked.',
                          ),
                          section(
                            icon: Icons.calendar_month_rounded,
                            iconColor: blue,
                            title: 'Weekly progress',
                            body:
                                'Your week does not have to start on Sunday. PillChecker starts your 7-day week on the first day you complete, then counts up from 1/7 to 7/7.',
                          ),
                          section(
                            icon: Icons.flag_rounded,
                            iconColor: green,
                            title: 'Start, Next, and End',
                            body:
                                'Start marks where your current 7-day run began. Next shows the next day you need to complete. End marks the day before your starting day.',
                          ),
                          section(
                            icon: Icons.warning_rounded,
                            iconColor: yellow,
                            title: 'Missed doses',
                            body:
                                'If a dose is missed, your streak is at risk. PillChecker keeps your streak value saved for the rest of that day so an override can restore it by default.',
                          ),
                          section(
                            icon: Icons.restart_alt_rounded,
                            iconColor: red,
                            title: 'Losing a streak',
                            body:
                                'If the missed dose is not fixed before the next PillChecker day, your current streak resets to 0. Your longest streak and most weeks completed stay saved as your personal bests.',
                          ),
                          section(
                            icon: Icons.emoji_events_rounded,
                            iconColor: const Color(0xFFFFB347),
                            title: 'Week complete',
                            body:
                                'When you hit 7/7, the week counter goes up by 1. After that, a new 7-day run can begin from the next completed day.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Material(
                    color: green,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(dialogContext),
                      child: const Center(
                        child: Text(
                          'Got it',
                          style: TextStyle(
                            fontFamily: 'Amaranth',
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

  List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List).map((e) => (e as num).toInt()).toList();
  }

  // ---------------- load ----------------
  Future<void> _loadAndMaybeAutoOpen() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadStreakState();

    await PrefsMigration.runOnceIfNeeded(
      medService: _medService,
      scheduleService: _scheduleService,
    );

    await _hydrateMedicationsFromDatabase();
    await _loadCustomInfoFromPrefs();

    await _scheduleService.ensureDoseEventsForMedications(medicationIds);
    await _adherenceService.autoMarkMissedPastPlanned();

    final currentSig = _localStateSignature();
    final savedSig = prefs.getString(_localStatePillSigKey) ?? '';

    await _loadLocalDailyState();

    // If the pill list changed since the local home-state was saved,
    // wipe local HomeScreen check/missed state so a new pill does not
    // inherit stale slot-based state from an older one.
    if (savedSig != currentSig) {
      await _clearLocalDailyState(publish: false);
      await prefs.setString(_localStatePillSigKey, currentSig);
    }
    // ✅ HomeScreen stays local-first.
    // Do NOT repopulate current-cycle UI state from the DB on cold launch.
    // Calendar and History can still read the DB separately.

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

    await _saveLocalStateSignature();
    await _syncCurrentCycleAnchorOnly();

    await _materializeOverdueMissedDosesLocally();

    if (!mounted) return;
    setState(() {
      _checkMapFuture = Future.value(Map<String, dynamic>.from(_checkMapCache));
    });

    _requestStreakSyncFromLocalState();

    unawaited(_rebuild2DayNotifWindowAndReMuteChecked(tag: 'initial-load'));
    await _syncCurrentCycleAnchorOnly();

    if (pillNames.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showWelcomeTutorialPrompt(prefs);
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

  Future<void> _addDemoPillDirect() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final alreadyIndex = pillNames.indexWhere(isDemoPillName);
    if (alreadyIndex >= 0) {
      if (!mounted) return;

      setState(() {
        _searchOpen = false;
        _configOpen = false;
        _infoOpen = false;
        _pendingSlot = false;
      });

      _centerWheelOn(alreadyIndex + 1);

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Demo pill already added'),
          content: const Text('The hidden demo pill is already on your wheel.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return;
    }

    final now = DateTime.now();
    final dose1 = TimeOfDay(hour: now.hour, minute: now.minute);
    final dose2Raw = now.add(const Duration(minutes: 1));
    final dose2 = TimeOfDay(hour: dose2Raw.hour, minute: dose2Raw.minute);

    final doseStrings = <String>[_timeToStr(dose1), _timeToStr(dose2)];

    final prefs = await SharedPreferences.getInstance();

    final sortOrder = pillNames.length;

    final med = await _medService.create(
      name: kDemoPillName,
      supplyEnabled: false,
      supplyLeft: 0,
      supplyInitial: 0,
      nameLocked: true,
      sortOrder: sortOrder,
    );

    await _scheduleService.upsertSchedule(
      medicationId: med.id,
      times24hSorted: doseStrings,
    );

    await _scheduleService.ensureDoseEventsForMedication(med.id);

    final updatedNames = [...pillNames, kDemoPillName];
    final updatedTimes = [...pillTimes, doseStrings.first];
    final updatedDoseTimes = [...pillDoseTimes, doseStrings];
    final updatedNameLocked = [...pillNameLocked, true];
    final updatedCustomInfo = [...pillCustomInfo, ''];

    _alignSupplyListsToCount(pillNames.length);
    pillSupplyEnabled.add(false);
    pillSupplyLeft.add(0);
    pillSupplyInitial.add(0);
    pillSupplyLowSent.add(false);
    _alignSupplyListsToCount(updatedNames.length);

    await prefs.setStringList(_pillNamesKey, updatedNames);
    await prefs.setStringList(_pillTimesKey, updatedTimes);
    await prefs.setString(_pillDoseTimesKey, jsonEncode(updatedDoseTimes));
    await prefs.setString(_pillNameLockedKey, jsonEncode(updatedNameLocked));
    await prefs.setStringList(_pillCustomInfoKey, updatedCustomInfo);

    await _saveSupplyListsToPrefs();

    if (!mounted) return;

    setState(() {
      medicationIds = [...medicationIds, med.id];
      medicationCreatedAts = [...medicationCreatedAts, med.createdAt];

      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;
      pillNameLocked = updatedNameLocked;
      pillCustomInfo = updatedCustomInfo;

      pillSupplyEnabled = [...pillSupplyEnabled];
      pillSupplyLeft = [...pillSupplyLeft];
      pillSupplyInitial = [...pillSupplyInitial];
      pillSupplyLowSent = [...pillSupplyLowSent];

      _searchOpen = false;
      _configOpen = false;
      _infoOpen = false;
      _pendingSlot = false;
      _editingIndex = null;
      _selectedPillInfo = null;
      _lockPillName = false;
      _step = _ConfigStep.name;
      _wheelSelectedIndex = updatedNames.length;
      _showPillLabel = true;
      _labelOverride = null;
    });

    await _saveLocalDailyState();
    await _saveLocalStateSignature();
    await _syncCurrentCycleAnchorOnly();

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

    await _resyncNotifsAfterPillChange();

    await NotificationService.scheduleDemoPillDose1(
      pillSlot: updatedNames.length - 1,
      pillName: kDemoPillName,
    );

    _publishLocalDailyState();
    _centerWheelOn(updatedNames.length);

    _scheduleGlobalBoundaryRefresh();
    unawaited(_scheduleGlobalDayBoundaryRefresh());
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

      _customInfoController.text = '';

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
    if (isDemoPillName(item.name)) {
      await _addDemoPillDirect();
      return;
    }
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
      _customInfoController.text = '';

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

      _customInfoController.text = '';
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
    FocusManager.instance.primaryFocus?.unfocus();
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
            while (_doseTimes.length < _timesPerDay) {
              _doseTimes.add(null);
            }
            if (_doseTimes.length > _timesPerDay) {
              _doseTimes = _doseTimes.sublist(0, _timesPerDay);
            }
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
    FocusManager.instance.primaryFocus?.unfocus();
    _showPillLabelAfterSlide();

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_timesPerDay == 1 && _singleDoseTime == null) return;
    if (_timesPerDay > 1 && !_anyDoseTimeSet) return;

    final List<TimeOfDay> doses = (_timesPerDay == 1)
        ? <TimeOfDay>[_singleDoseTime!]
        : _doseTimes.whereType<TimeOfDay>().toList(growable: false);

    final doseStrings = doses.map(_timeToStr).toList();
    final firstDose = doses.first;

    final prefs = await SharedPreferences.getInstance();

    _alignSupplyListsToCount(pillNames.length);

    final updatedNames = [...pillNames, name];
    final updatedCustomInfo = [
      ...pillCustomInfo,
      _lockPillName ? '' : _customInfoController.text.trim(),
    ];
    await prefs.setStringList(_pillCustomInfoKey, updatedCustomInfo);
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

    final updatedNameLocked = [...pillNameLocked, _lockPillName];
    await prefs.setString(_pillNameLockedKey, jsonEncode(updatedNameLocked));

    // ✅ align again just in case
    _alignSupplyListsToCount(updatedNames.length);

    // ✅ persist
    await _saveSupplyListsToPrefs();

    // ✅ Preserve local HomeScreen adherence state when adding a new pill.
    // Adding a pill at the end should not erase today’s visual checks/missed states.
    await _saveLocalDailyState();

    _alignMedicationCreatedAtsToCount(pillNames.length);
    // ✅ Rebuild notif window
    await _resyncNotifsAfterPillChange();

    if (!mounted) return;
    setState(() {
      medicationIds = [...medicationIds, med.id];
      medicationCreatedAts = [...medicationCreatedAts, med.createdAt];
      pillSupplyEnabled = [...pillSupplyEnabled];
      pillSupplyLeft = [...pillSupplyLeft];
      pillSupplyInitial = [...pillSupplyInitial];
      pillSupplyLowSent = [...pillSupplyLowSent];
      pillNameLocked = updatedNameLocked;
      pillCustomInfo = updatedCustomInfo;

      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;

      _lockPillName = false;
      _pendingSlot = false;
      _configOpen = false;
      _step = _ConfigStep.name;
      _selectedPillInfo = null;
    });

    // Now that pillNames/pillDoseTimes include the new pill,
    // streak sync can correctly see today is incomplete again.
    await _materializeOverdueMissedDosesLocally(
      onlyPillIndex: updatedNames.length - 1,
    );
    _publishLocalDailyState();

    await _saveLocalStateSignature();
    await _syncCurrentCycleAnchorOnly();

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
    FocusManager.instance.primaryFocus?.unfocus();
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
        : _doseTimes.whereType<TimeOfDay>().toList(growable: false);

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
    if (effectiveTrack && _supplyLeftDraft > _supplyLowThreshold) {
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

    final updatedCustomInfo = [...pillCustomInfo];
    if (pillIndex < updatedCustomInfo.length) {
      updatedCustomInfo[pillIndex] = isLocked
          ? ''
          : _customInfoController.text.trim();
    }
    await prefs.setStringList(_pillCustomInfoKey, updatedCustomInfo);

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
      if (_supplyLeftDraft > _supplyLowThreshold) {
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
      pillCustomInfo = updatedCustomInfo;

      pillNames = updatedNames;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;

      _lockPillName = false;
      _editingIndex = null;
      _configOpen = false;
      _step = _ConfigStep.name;
    });

    await _clearLocalDailyState();
    await _saveLocalStateSignature();
    await _syncCurrentCycleAnchorOnly();

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

    _alignMedicationCreatedAtsToCount(pillNames.length);

    final updatedCreatedAts = [...medicationCreatedAts];
    if (slot < updatedCreatedAts.length) {
      updatedCreatedAts.removeAt(slot);
    }

    while (updatedCreatedAts.length > updatedNames.length) {
      updatedCreatedAts.removeLast();
    }
    while (updatedCreatedAts.length < updatedNames.length) {
      updatedCreatedAts.add(DateTime.fromMillisecondsSinceEpoch(0));
    }

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

    final updatedNameLocked = [...pillNameLocked]..removeAt(slot);
    final updatedCustomInfo = [...pillCustomInfo]..removeAt(slot);
    await prefs.setStringList(_pillCustomInfoKey, updatedCustomInfo);
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

    await _syncCurrentCycleAnchorOnly();

    if (!mounted) return;
    setState(() {
      medicationIds = updatedMedIds;
      medicationCreatedAts = updatedCreatedAts;
      pillSupplyEnabled = [...pillSupplyEnabled];
      pillSupplyLeft = [...pillSupplyLeft];
      pillSupplyInitial = [...pillSupplyInitial];
      pillSupplyLowSent = [...pillSupplyLowSent];
      pillCustomInfo = updatedCustomInfo;
      pillNames = updatedNames;
      pillNameLocked = updatedNameLocked;
      pillTimes = updatedTimes;
      pillDoseTimes = updatedDoseTimes;
      _pendingSlot = false;
      _editingIndex = newEditingIndex;
      _wheelSelectedIndex = newWheelIndex;
      _infoOpen = false; // close dashboard panel after delete
      _showPillLabel = updatedNames.isNotEmpty;
    });

    _removeSlotFromLocalDailyState(slot);
    await _saveLocalDailyState();
    _publishLocalDailyState();

    await _saveLocalStateSignature();

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

  Future<void> _refreshForDateJumpIfNeeded() async {
    final now = DateTime.now();
    final dayKey = now.year * 10000 + now.month * 100 + now.day;

    if (dayKey == _lastSeenDayKey) return;
    _lastSeenDayKey = dayKey;

    await _syncCurrentCycleAnchorOnly();
    await _refreshAdherenceFromDb();

    if (!mounted) return;

    _refreshCheckMapFuture();

    final newToday = _debugDayOverride ?? (now.weekday % 7);

    _rearmDailyCircleDelay();
    _armDailyCircleDelay();
    _startNewDaySequence(today: newToday);

    unawaited(_rebuild2DayNotifWindowAndReMuteChecked(tag: 'date-jump'));

    _scheduleGlobalBoundaryRefresh();
    unawaited(_scheduleGlobalDayBoundaryRefresh());

    // ✅ Do not wipe local masks on date jumps.
    _publishLocalDailyState();
  }

  void _alignMedicationCreatedAtsToCount(int count) {
    while (medicationCreatedAts.length < count) {
      // Safe fallback so old pills don't crash delete/update flows.
      medicationCreatedAts.add(DateTime.fromMillisecondsSinceEpoch(0));
    }
    if (medicationCreatedAts.length > count) {
      medicationCreatedAts.removeRange(count, medicationCreatedAts.length);
    }
  }

  Future<void> _onWarningOverrideTap() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null || pillIndex >= medicationIds.length) return;

    final doses = _doseTimesForPill(pillIndex);
    if (doses.isEmpty) return;

    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _checkMapCache,
      missedMap: _lastMissedMapCache,
      now: DateTime.now(),
    );

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark current dose taken?'),
        content: const Text(
          'This will set the current dose to taken. You can change it again later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    final cycleDay = DateTime(
      state.cycleStart.year,
      state.cycleStart.month,
      state.cycleStart.day,
    );
    final plannedIso = plannedAtUtcIsoForOrderedDose(
      cycleDay,
      doses,
      state.doseIndex,
    );

    final wasTaken = (state.takenMask & (1 << state.doseIndex)) != 0;

    _setLocalDoseStatus(
      pillIndex: pillIndex,
      cycleIso: state.cycleIso,
      doseIndex: state.doseIndex,
      status: 'taken',
    );
    await _saveLocalDailyState();
    await _syncCurrentCycleAnchorOnly();
    _publishLocalDailyState();

    if (!wasTaken) {
      unawaited(_consumeOneSupplyIfEnabled(pillIndex));
    }

    _scheduleCenteredDoseBoundaryRefresh();

    _trackAdherenceWrite(
      _persistTakenToDb(
        medicationId: medicationIds[pillIndex],
        plannedIso: plannedIso,
      ),
    );
  }

  Future<void> _markCurrentDoseMissed() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null || pillIndex >= medicationIds.length) return;

    final doses = _doseTimesForPill(pillIndex);
    if (doses.isEmpty) return;

    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _checkMapCache,
      missedMap: _lastMissedMapCache,
      now: DateTime.now(),
    );

    final cycleDay = DateTime(
      state.cycleStart.year,
      state.cycleStart.month,
      state.cycleStart.day,
    );
    final plannedIso = plannedAtUtcIsoForOrderedDose(
      cycleDay,
      doses,
      state.doseIndex,
    );

    final wasTaken = (state.takenMask & (1 << state.doseIndex)) != 0;

    _setLocalDoseStatus(
      pillIndex: pillIndex,
      cycleIso: state.cycleIso,
      doseIndex: state.doseIndex,
      status: 'missed',
    );
    await _saveLocalDailyState();
    await _syncCurrentCycleAnchorOnly();
    _publishLocalDailyState();

    if (wasTaken) {
      unawaited(_applySupplyDeltaIfEnabled(pillIndex: pillIndex, delta: 1));
    }

    _scheduleCenteredDoseBoundaryRefresh();

    _trackAdherenceWrite(
      _persistMissedToDb(
        medicationId: medicationIds[pillIndex],
        plannedIso: plannedIso,
      ),
    );
  }

  Future<void> _openHistoryScreen() async {
    await _gateAdherenceScreenIfNeeded('Preparing adherence history');

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(adherenceService: _adherenceService),
      ),
    );

    if (!mounted) return;
    unawaited(_refreshAdherenceFromDb());
    _publishLocalDailyState();
  }

  Future<void> _openWarningActions() async {
    final centered = _centerPillIndex;
    if (centered == null || centered >= medicationIds.length) {
      return;
    }

    final isMultiDose = _doseTimesForPill(centered).length > 1;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMultiDose)
              ListTile(
                leading: const Icon(Icons.pie_chart),
                title: const Text('Multiple dose override'),
                onTap: () => Navigator.pop(ctx, 'multi_override'),
              ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Override missed dose'),
              onTap: () => Navigator.pop(ctx, 'override'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Mark current dose missed'),
              onTap: () => Navigator.pop(ctx, 'miss'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Open history'),
              onTap: () => Navigator.pop(ctx, 'history'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'multi_override') {
      await _openMultiDoseOverride();
      return;
    }
    if (action == 'override') {
      await _onWarningOverrideTap();
      return;
    }
    if (action == 'miss') {
      await _markCurrentDoseMissed();
      return;
    }
    if (action == 'history') {
      await _openHistoryScreen();
    }
  }

  // ---------------- CHECK current dose ----------------
  // lib/screens/home/home_screen.dart

  Future<void> _checkCenteredPill() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null) return;
    if (pillIndex >= medicationIds.length) return;

    final doses = _doseTimesForPill(pillIndex);
    final state = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _checkMapCache,
      missedMap: _lastMissedMapCache,
      now: DateTime.now(),
    );

    final doseIndex = state.doseIndex;

    final shouldStartDemoDose2 =
        _isDemoPillIndex(pillIndex) &&
        doseIndex == 0 &&
        (state.takenMask & 1) == 0;

    final cycleDay = DateTime(
      state.cycleStart.year,
      state.cycleStart.month,
      state.cycleStart.day,
    );
    final plannedIso = plannedAtUtcIsoForOrderedDose(
      cycleDay,
      doses,
      doseIndex,
    );

    _trackAdherenceWrite(
      _persistTakenToDb(
        medicationId: medicationIds[pillIndex],
        plannedIso: plannedIso,
      ),
    );

    if (shouldStartDemoDose2) {
      unawaited(
        NotificationService.scheduleDemoPillDose2AfterCheck(
          pillSlot: pillIndex,
          pillName: pillNames[pillIndex],
        ),
      );
    }

    // LOCAL FIRST
    _setLocalDoseStatus(
      pillIndex: pillIndex,
      cycleIso: state.cycleIso,
      doseIndex: doseIndex,
      status: 'taken',
    );
    await _saveLocalDailyState();
    await _syncCurrentCycleAnchorOnly();
    _publishLocalDailyState();

    unawaited(_consumeOneSupplyIfEnabled(pillIndex));

    _scheduleCenteredDoseBoundaryRefresh();

    final visualStateAfterCheck = _getDisplayedDoseStateForPill(
      pillIndex: pillIndex,
      doses: doses,
      takenMap: _checkMapCache,
      missedMap: _lastMissedMapCache,
      now: DateTime.now(),
    );

    final movedToNextDose = visualStateAfterCheck.doseIndex != doseIndex;

    _labelTimer?.cancel();
    _labelTimer = null;

    setState(() => _labelOverride = 'Pill Checked!');

    _labelTimer = Timer(
      movedToNextDose ? const Duration(seconds: 2) : const Duration(seconds: 9),
      () {
        if (!mounted) return;
        setState(() => _labelOverride = null);
      },
    );

    _recordDoseHistory(pillNames[pillIndex]);

    // Notification cleanup can happen after UI + DB write are already moving.
    unawaited(
      NotificationService.muteToday(
        pillSlot: pillIndex,
        doseIndex: doseIndex,
        dosesPerDay: doses.length,
        muteRemainingDoses: false,
      ),
    );
  }

  Future<void> _openStreaksPanel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _hidePillLabelNow();

    await _prepareStreakScreenState();
    if (!mounted) return;

    if (!_streakState.streaksEnabled) return;

    final shouldShowRiskWarning = _streakAtRisk;

    _refreshStreakStatusMessage(allowWeekCompleteMessage: false);

    _streaksTransitionTimer?.cancel();
    _streaksPillboxTimer?.cancel();

    setState(() {
      _streaksOpen = true;
      _streaksGreenVisible = false;

      // Spawn streak pillbox closed first.
      _streakPillboxOpenDays = <int>{};
      _streakPillboxResetToken++;
      _streakDotsVisible = false;
      _streakMarkersVisible = false;
      _streakMessageVisible = false;
      _streakButtonNeedsAttention = false;

      _configOpen = false;
      _infoOpen = false;
      _searchOpen = false;
      _pendingSlot = false;
      _editingIndex = null;
    });

    if (shouldShowRiskWarning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_streaksOpen) return;
        _showStreakRiskWarningDialog();
      });
    }

    // First: home fades out to pink.
    _streaksTransitionTimer = Timer(const Duration(milliseconds: 360), () {
      if (!mounted) return;

      setState(() {
        _streaksGreenVisible = true;
      });

      // Second: wait for green streak screen/pillbox to finish fading in.
      // Then start the pillbox open sequence while it is visible.
      _streaksPillboxTimer?.cancel();
      _streaksPillboxTimer = Timer(const Duration(milliseconds: 460), () {
        if (!mounted || !_streaksOpen || !_streaksGreenVisible) return;

        final daysToOpen = <int>{0, 1, 2, 3, 4, 5, 6};

        setState(() {
          _streakPillboxOpenDays = daysToOpen;
          _streakDotsVisible = false;
        });

        _streakDotsTimer?.cancel();
        _streakDotsTimer = Timer(
          _streakPillboxOpenSequenceDurationFor(daysToOpen.length),
          () {
            if (!mounted || !_streaksOpen || !_streaksGreenVisible) return;

            setState(() {
              _streakDotsVisible = true;
              _streakMarkersVisible = false;
            });

            _streakMarkersTimer?.cancel();
            _streakMarkersTimer = Timer(_streakDotRippleDuration(), () {
              if (!mounted || !_streaksOpen || !_streaksGreenVisible) return;

              setState(() {
                _streakMarkersVisible = true;
                _streakMessageVisible = true;
              });
            });
          },
        );
      });
    });
  }

  void _closeStreaksPanel() {
    if (!mounted) return;

    _streaksTransitionTimer?.cancel();
    _streaksPillboxTimer?.cancel();
    _streakDotsTimer?.cancel();
    _streakMarkersTimer?.cancel();

    // First: fade green streak screen out.
    setState(() {
      _streaksGreenVisible = false;
      _streakDotsVisible = false;
      _streakMarkersVisible = false;
      _streakMessageVisible = false;
    });

    // After it is hidden, reset the streak pillbox back to closed
    // and fully leave streak mode.
    _streaksTransitionTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;

      setState(() {
        _streakPillboxOpenDays = <int>{};
        _streakPillboxResetToken++;

        _streaksOpen = false;
      });

      _showPillLabelAfterSlide();
    });
  }

  void _toggleStreaksPanel() {
    if (_streaksOpen) {
      _closeStreaksPanel();
    } else {
      _openStreaksPanel();
    }
  }

  void _showStreakRiskWarningDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF98404F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Streak at risk',
            style: TextStyle(
              fontFamily: 'Amaranth',
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          content: const Text(
            'You have missed doses today, so your streak is at risk. '
            'If you actually took your pill, use override to fix the missed dose before the next PillChecker day.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: Material(
                color: const Color(0xFF59FF56),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(dialogContext),
                  child: const Center(
                    child: Text(
                      'Got it',
                      style: TextStyle(
                        fontFamily: 'Amaranth',
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
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

  Future<void> _openCalendarScreen() async {
    await _gateAdherenceScreenIfNeeded('Preparing calendar');

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarScreen(adherenceService: _adherenceService),
      ),
    );

    if (!mounted) return;
    await _refreshForDateJumpIfNeeded();
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
        child: Scrollbar(
          controller: _configPanelScrollCtrl,
          thumbVisibility: true,
          thickness: 5,
          radius: const Radius.circular(99),
          child: SingleChildScrollView(
            controller: _configPanelScrollCtrl,
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                                ? Text(
                                    _nameController.text.trim(),
                                    style: const TextStyle(
                                      color: white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  )
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

                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: Container(
                    width: double.infinity,
                    height: _step == _ConfigStep.name ? 120 : 120,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: _lockPillName
                        ? Scrollbar(
                            controller: _lockedInfoScrollCtrl,
                            thumbVisibility: true,
                            thickness: 4,
                            radius: const Radius.circular(99),
                            child: SingleChildScrollView(
                              controller: _lockedInfoScrollCtrl,
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                (_selectedPillInfo != null &&
                                        _selectedPillInfo!.trim().isNotEmpty)
                                    ? _selectedPillInfo!
                                    : 'Medication info unavailable right now.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: _infoFontSizeFor(
                                    _selectedPillInfo ?? '',
                                  ),
                                  height: 1.25,
                                ),
                              ),
                            ),
                          )
                        : Scrollbar(
                            controller: _customInfoScrollCtrl,
                            thumbVisibility: true,
                            thickness: 4,
                            radius: const Radius.circular(99),
                            child: TextField(
                              controller: _customInfoController,
                              scrollController: _customInfoScrollCtrl,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: _infoFontSizeFor(
                                  _customInfoController.text,
                                  base: 15,
                                ),
                                height: 1.25,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Edit pill info here',
                                hintStyle: TextStyle(color: Colors.white70),
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

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
                        if (_supplyModeGlobal == 'decide') ...[
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
                                  await _editSupplyDialog(setInitialToo: true);

                                  if (!mounted) return;
                                  if (_supplyLeftDraft <= 0) {
                                    setState(() => _supplyTrackOn = false);
                                  }
                                },
                              ),
                            ],
                          ),
                        ] else ...[
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
                  Column(
                    children: [
                      for (int i = 0; i < _timesPerDay; i++) ...[
                        Builder(
                          builder: (context) {
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
                        if (i < _timesPerDay - 1) const SizedBox(height: 10),
                      ],
                    ],
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

    final buildDayKey =
        DateTime.now().year * 10000 +
        DateTime.now().month * 100 +
        DateTime.now().day;

    if (buildDayKey != _lastSeenDayKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshForDateJumpIfNeeded());
      });
    }

    double s(double v) => v * scale;
    double fs(double v) => v * scale;

    final configH = _configPanelHeight(s);
    final infoPanelH = _infoPanelHeight(s);

    final double stripW = s(800);
    final double stripH = s(1383);

    final double wheelBoxH = s(1000);
    final double wheelBoxW = size.width;

    double cx(double w) => (size.width - w) / 2;

    final overlayOpen = _configOpen || _infoOpen || _searchOpen;
    final streaksActive = _streaksOpen;
    final streaksScreenVisible = _streaksGreenVisible;

    final midFade = (_searchOpen || streaksActive) ? 0.0 : 1.0;

    // Only search moves the logo/title. Streaks should not move them.
    final topShift = _searchOpen ? -s(220) : 0.0;

    final searchScrimOpacity = _searchOpen ? 1.0 : 0.0;

    final bottomSlide = overlayOpen ? const Offset(0, 0.30) : Offset.zero;

    final bottomSlidDown = overlayOpen || streaksActive;

    final showPillNameBackPlate =
        pillNames.isNotEmpty && _wheelSelectedIndex != 0;

    final bottomDecorOpacity = (!bottomSlidDown && showPillNameBackPlate)
        ? 1.0
        : 0.0;

    // IMPORTANT: do NOT include streaksActive here.
    // Calendar/Streak tabs should fade out, not slide out.
    final sideZoneButtonsHidden = overlayOpen;

    final streaksPanelTop = s(140);

    // Normal HomeScreen pillbox position/size
    final normalPillboxWidth = s(800) * pbScale;
    final normalPillboxHeight = s(1383) * pbScale;

    final normalPillboxLeft = _pillboxLeftForDay(
      size: size,
      s: s,
      designW: designW,
      todayIndex: _pillboxVisualDay,
      scale: pbScale,
    );

    final normalPillboxBottom = s(130);

    final pillboxOpenDays = _allowPillboxOpen ? <int>{_todayIndex} : <int>{};

    // Streaks pillbox: separate spawned-in closed pillbox
    final streakPillboxScale = 0.48;
    final streakPillboxWidth = s(800) * streakPillboxScale;
    final streakPillboxHeight = s(1383) * streakPillboxScale;

    final streakPillboxLeft = (size.width - streakPillboxWidth) / 2;
    final streakPillboxBottom = s(112);

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

    final tutorialSteps = _tutorialStepsForLayout(
      size: size,
      s: s,
      designW: designW,
      topShift: topShift,
    );

    final supplyNumberColor = (displaySupplyValue <= 0)
        ? const Color.fromARGB(255, 255, 30, 71) // red
        : (displaySupplyValue <= _supplyLowThreshold)
        ? const Color.fromARGB(255, 255, 226, 109) // yellow
        : const Color.fromARGB(
            245,
            255,
            255,
            255,
          ); // your off-white// your off-white

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
            // Normal HomeScreen pillbox fades out during Streaks.
            AnimatedPositioned(
              duration: _pillboxSlideDur,
              curve: Curves.easeInOutCubic,
              left: normalPillboxLeft,
              bottom: normalPillboxBottom,
              child: IgnorePointer(
                ignoring: _streaksOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  opacity: _streaksOpen || _searchOpen ? 0.0 : 1.0,
                  child: SizedBox(
                    width: normalPillboxWidth,
                    height: normalPillboxHeight,
                    child: WeeklyPillboxOrganizer(
                      key: ValueKey(
                        'pillbox_normal_${_pillboxResetToken}_day_${_todayIndex}',
                      ),
                      fit: BoxFit.contain,
                      openDays: pillboxOpenDays,
                      stateMachineName: 'PillboxSM',
                    ),
                  ),
                ),
              ),
            ),

            // --- SIDE BARS ---
            Positioned(
              left: 0,
              right: 0,
              top: s(160), // main vertical placement reference
              child: IgnorePointer(
                ignoring: streaksActive,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  opacity: streaksActive ? 0.0 : 1.0,
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
                      int missedMask = 0;

                      if (showLeft) {
                        final state = _getDisplayedDoseStateForPill(
                          pillIndex: idx!,
                          doses: doses,
                          takenMap: map,
                          missedMap: _lastMissedMapCache,
                          now: DateTime.now(),
                        );

                        mask = state.takenMask;
                        missedMask = state.missedMask;
                        activeDoseIndex = state.doseIndex;

                        _lastDoseBarTotalDoses = totalDoses;
                        _lastDoseBarActiveDoseIndex = activeDoseIndex;
                        _lastDoseBarCheckedMask = mask;
                        _lastDoseBarMissedMask = missedMask;
                        _hasDoseBarCache = true;
                      }

                      final barTotalDoses = showLeft
                          ? totalDoses
                          : (_hasDoseBarCache ? _lastDoseBarTotalDoses : 2);

                      final barActiveDoseIndex = showLeft
                          ? activeDoseIndex
                          : (_hasDoseBarCache
                                ? _lastDoseBarActiveDoseIndex
                                : 0);

                      final barCheckedMask = showLeft
                          ? mask
                          : (_hasDoseBarCache ? _lastDoseBarCheckedMask : 0);

                      final barMissedMask = showLeft
                          ? missedMask
                          : (_hasDoseBarCache ? _lastDoseBarMissedMask : 0);

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
                              left: showLeft ? s(4) : -s(220),
                              top: 0,
                              width: s(165),
                              height: s(70),
                              child: IgnorePointer(
                                child: DoseProgressSideBar(
                                  totalDoses: barTotalDoses,
                                  activeDoseIndex: barActiveDoseIndex,
                                  checkedMask: barCheckedMask,
                                  missedMask: barMissedMask,
                                  height: s(70),
                                ),
                              ),
                            ),

                            // RIGHT BAR: all pills completed
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeInOutCubic,
                              right: showRight ? s(5) : -s(220),
                              top: 0,
                              width: s(166.5),
                              height: s(70),
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color.fromARGB(
                                      222,
                                      155,
                                      255,
                                      168,
                                    ),
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
                                  padding: EdgeInsets.symmetric(
                                    horizontal: s(14),
                                  ),
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
              child: IgnorePointer(
                ignoring: streaksActive,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  opacity: streaksActive ? 0.0 : 1.0,
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

                      final delayedDone =
                          doneForCircle && _dailyCircleDelayPassed;

                      return DailyCompletionCircle(
                        done: delayedDone,
                        size: s(58),
                        baseColor: const Color.fromARGB(0, 231, 36, 153),
                        fillColor: const Color(0xFF59FF56),
                      );
                    },
                  ),
                ),
              ),
            ),

            // --- BOTTOM ZONE ---
            // --- BOTTOM ZONE ---
            IgnorePointer(
              ignoring:
                  _configOpen || _infoOpen || _searchOpen || streaksActive,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                opacity: streaksActive ? 0.0 : 1.0,
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
                            if (i != _wheelSelectedIndex)
                              _clearCheckedMessage();

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
                        left: _leftFromDesignRight(
                          155,
                          127.5,
                          size,
                          s,
                          designW,
                        ),
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
                        left:
                            _leftFromDesignRight(135, 137, size, s, designW) -
                            s(1),
                        bottom: s(100),
                        child: FutureBuilder<Map<String, dynamic>>(
                          future: _checkMapFuture,
                          builder: (context, snap) {
                            final pillIndex = _centerPillIndex;
                            final map = snap.data ?? {};

                            _lastCheckMapCache = map;

                            bool checked = false;
                            bool missed = false;
                            String checkButtonKey = 'check_empty';

                            if (pillIndex != null) {
                              final doses = _doseTimesForPill(pillIndex);

                              final state = _getDisplayedDoseStateForPill(
                                pillIndex: pillIndex,
                                doses: doses,
                                takenMap: map,
                                missedMap: _lastMissedMapCache,
                                now: DateTime.now(),
                              );

                              checked =
                                  (state.takenMask & (1 << state.doseIndex)) !=
                                  0;

                              missed = _isCurrentDoseMissed(
                                pillIndex: pillIndex,
                                map: map,
                              );

                              checkButtonKey =
                                  'check_${pillIndex}_${state.cycleIso}_${state.doseIndex}_${checked ? 1 : 0}_${missed ? 1 : 0}';
                            }

                            final bool disable =
                                _configOpen ||
                                _pendingSlot ||
                                (_wheelSelectedIndex == 0) ||
                                (pillIndex == null);

                            return AbsorbPointer(
                              absorbing: disable,
                              child: PillCheckButton(
                                key: ValueKey(checkButtonKey),
                                checked: checked,
                                missed: missed,
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
                        right: s(10),
                        bottom: s(8),
                        child: IgnorePointer(
                          ignoring: _configOpen || _infoOpen,
                          child: Opacity(
                            opacity: (_configOpen || _infoOpen) ? 0.45 : 1.0,
                            child: GestureDetector(
                              onTap: _openWarningActions,
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
            ),

            // --- CENTER PILL NAME ---
            Positioned(
              left: s(0),
              right: s(0),
              bottom: s(477),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeInOut,
                opacity: _showPillLabel ? 1.0 : 0.0,
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final fullLabel = _labelOverride ?? _centerPillName();
                      final isTruncated = _centerLabelIsTruncated(fullLabel);
                      final displayLabel = _truncateCenterLabel(fullLabel);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isTruncated
                            ? () => _showFullCenterLabelDialog(fullLabel)
                            : null,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: s(12)),
                          child: Text(
                            displayLabel,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontFamily: 'Amaranth',
                              fontSize: fs(25),
                              color: const Color.fromARGB(225, 255, 255, 255),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // --- TOP OVALS ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              left: _streaksOpen ? -s(190) : s(-75),
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
              left: _streaksOpen ? -s(120) : s(-10),
              top: s(45) + topShift,
              child: IgnorePointer(
                ignoring:
                    _searchOpen || _configOpen || _infoOpen || _streaksOpen,
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
              right: _streaksOpen ? -s(190) : s(-75),
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
              right: _streaksOpen ? -s(165) : s(-45),
              top: s(40) + topShift,
              child: IgnorePointer(
                ignoring:
                    _searchOpen || _configOpen || _infoOpen || _streaksOpen,
                child: SizedBox(
                  width: s(150),
                  height: s(85),
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(s(999)),
                        onTap: () async {
                          final result = await Navigator.push<Object?>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );

                          await _loadStreakState();

                          if (!mounted) return;

                          if (result == true) {
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
                          } else if (result == 'tutorial') {
                            _startTutorial();
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
              height: infoPanelH,
              child: Builder(
                builder: (_) {
                  final idx = _centerPillIndex;
                  final name = (idx == null) ? '' : pillNames[idx];

                  final doses = (idx == null)
                      ? <TimeOfDay>[]
                      : _doseTimesForPill(idx);
                  final doseLabels = doses.map(_fmt).toList();

                  final isCustomPill =
                      idx != null &&
                      idx < pillNameLocked.length &&
                      pillNameLocked[idx] == false;

                  final customInfoText =
                      (idx != null && idx < pillCustomInfo.length)
                      ? pillCustomInfo[idx]
                      : '';

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
                    isCustomPill: isCustomPill,
                    customInfoText: customInfoText,

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

            // --- CALENDAR BUTTON (left side-zone tab) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              left: sideZoneButtonsHidden ? -s(110) : s(-10),
              bottom: s(460),
              child: IgnorePointer(
                ignoring: sideZoneButtonsHidden || streaksActive,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  opacity: (sideZoneButtonsHidden || streaksActive) ? 0.0 : 1.0,
                  child: Material(
                    color: const Color(0xFF1E3A8A),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(s(18)),
                      bottomRight: Radius.circular(s(18)),
                    ),
                    elevation: 3,
                    child: InkWell(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(s(18)),
                        bottomRight: Radius.circular(s(18)),
                      ),
                      onTap: _openCalendarScreen,
                      child: SizedBox(
                        width: s(72),
                        height: s(58),
                        child: Center(
                          child: Icon(
                            Icons.calendar_month_rounded,
                            size: s(30),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- STREAK BUTTON (right side-zone tab) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              right: (sideZoneButtonsHidden || !_streakState.streaksEnabled)
                  ? -s(110)
                  : s(-10),
              bottom: s(460),
              child: IgnorePointer(
                ignoring:
                    sideZoneButtonsHidden ||
                    streaksActive ||
                    !_streakState.streaksEnabled,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  opacity:
                      (sideZoneButtonsHidden ||
                          streaksActive ||
                          !_streakState.streaksEnabled)
                      ? 0.0
                      : 1.0,
                  child: _StreakRiskBlinkColor(
                    atRisk: _streakAtRisk,
                    normalColor: const Color.fromARGB(251, 88, 255, 85),
                    builder: (tabColor) {
                      return _StreakButtonAttentionShell(
                        needsAttention: _streakButtonNeedsAttention,
                        atRisk: _streakAtRisk,
                        child: Material(
                          color: tabColor,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(s(18)),
                            bottomLeft: Radius.circular(s(18)),
                          ),
                          elevation: 3,
                          child: InkWell(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(s(18)),
                              bottomLeft: Radius.circular(s(18)),
                            ),
                            onTap: () {
                              unawaited(_openStreaksPanel());
                            },
                            child: SizedBox(
                              width: s(72),
                              height: s(58),
                              child: Center(
                                child: Transform.translate(
                                  offset: Offset(-s(4), 0),
                                  child: SizedBox(
                                    width: s(34),
                                    height: s(34),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Positioned(
                                          top: s(14),
                                          left: s(11),
                                          child: Container(
                                            width: s(15),
                                            height: s(15),
                                            decoration: const BoxDecoration(
                                              color: Color.fromARGB(
                                                255,
                                                255,
                                                177,
                                                74,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.whatshot_rounded,
                                          size: s(34),
                                          color: const Color.fromARGB(
                                            255,
                                            255,
                                            116,
                                            66,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // --- STREAKS STORYBOARD SCREEN ---
            Positioned.fill(
              top: streaksPanelTop + (Platform.isIOS ? -s(12) : 0),
              bottom: Platform.isIOS ? s(25) : 0,
              child: IgnorePointer(
                ignoring: !streaksScreenVisible,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeInOut,
                  opacity: streaksScreenVisible ? 1.0 : 0.0,
                  child: _streaksPanel(
                    s: s,
                    fs: fs,
                    onClose: _closeStreaksPanel,
                    streakPillboxOpenDays: _streakPillboxOpenDays,
                    streakPillboxResetToken: _streakPillboxResetToken,
                    currentStreakValue: _currentStreakValue,
                    weeksCompletedValue: _weeksCompletedValue,
                    longestStreakValue: _longestStreakValue,
                    mostWeeksCompletedValue: _mostWeeksCompletedValue,
                    weekProgress: _displayWeekProgressValue,
                    completedDayIndexes: _streakCompletedDayIndexes,
                    streakDotsVisible: _streakDotsVisible,
                    streakMarkersVisible: _streakMarkersVisible,
                    weekStartDayIndex: _displayWeekStartDayIndexValue,
                    nextRequiredDayIndex: _displayNextRequiredDayIndexValue,
                    streakStatusMessage: _streakStatusMessage,
                    streakMessageVisible: _streakMessageVisible,
                    onShowStreaksHelp: _showStreaksHelpDialog,
                  ),
                ),
              ),
            ),

            // --- TUTORIAL OVERLAY (absolute topmost) ---
            if (_tutorialActive)
              Positioned.fill(
                child: TutorialSpotlightOverlay(
                  targetRect: tutorialSteps[_tutorialIndex].targetRect,
                  title: tutorialSteps[_tutorialIndex].title,
                  description: tutorialSteps[_tutorialIndex].description,
                  stepNumber: _tutorialIndex + 1,
                  totalSteps: tutorialSteps.length,
                  onBack: _tutorialIndex == 0 ? null : _prevTutorialStep,
                  onNext: () => _nextTutorialStep(tutorialSteps.length),
                  onClose: _closeTutorial,
                  isLast: _tutorialIndex == tutorialSteps.length - 1,
                  cardAtTop: _tutorialIndex >= 2 && _tutorialIndex <= 5,
                ),
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

class _TutorialStep {
  const _TutorialStep({
    required this.title,
    required this.description,
    required this.targetRect,
  });

  final String title;
  final String description;
  final Rect targetRect;
}

class _StreakState {
  const _StreakState({
    required this.streaksEnabled,
    required this.overrideRestoresStreak,
    required this.currentStreak,
    required this.longestStreak,
    required this.weeksCompleted,
    required this.mostWeeksCompleted,
    required this.weekProgress,
    required this.weekStartDayIndex,
    required this.nextRequiredDayIndex,
    required this.lastCompletedDayKey,
    required this.pendingLostDayKey,
    required this.pendingLostStreakValue,
    required this.seenHighestStreak,
    required this.completedDayKeys,
  });

  final bool streaksEnabled;

  /// Later setting:
  /// true = override restores the streak by default.
  /// false = override checks the day visually but does not restore streak.
  final bool overrideRestoresStreak;

  final int currentStreak;
  final int longestStreak;

  /// Number of completed 7-day weeks.
  final int weeksCompleted;

  /// Highest weeksCompleted value ever reached.
  final int mostWeeksCompleted;

  /// 0..7 for the current rolling week.
  final int weekProgress;

  /// 0 = Sun, 1 = Mon, ... 6 = Sat.
  /// Null until the user completes their first streak day.
  final int? weekStartDayIndex;

  /// The next day index required to continue weekly progress.
  final int? nextRequiredDayIndex;

  /// YYYYMMDD key for the last day that successfully counted.
  final int? lastCompletedDayKey;

  /// If a dose is missed, this stores the day at risk until the next reset.
  final int? pendingLostDayKey;

  /// Saves the streak value before loss so an override can restore it.
  final int? pendingLostStreakValue;

  /// Used later for the white/bouncy highlight when the user has not seen
  /// their newest highest streak yet.
  final int seenHighestStreak;

  /// Days that have been completed, stored as YYYYMMDD.
  /// Later this feeds the 7 mini completion circles.
  final List<int> completedDayKeys;

  factory _StreakState.initial() {
    return const _StreakState(
      streaksEnabled: true,
      overrideRestoresStreak: true,
      currentStreak: 0,
      longestStreak: 0,
      weeksCompleted: 0,
      mostWeeksCompleted: 0,
      weekProgress: 0,
      weekStartDayIndex: null,
      nextRequiredDayIndex: null,
      lastCompletedDayKey: null,
      pendingLostDayKey: null,
      pendingLostStreakValue: null,
      seenHighestStreak: 0,
      completedDayKeys: <int>[],
    );
  }

  static int _readInt(Map<String, dynamic> map, String key, int fallback) {
    final v = map[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  static int? _readNullableInt(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static bool _readBool(Map<String, dynamic> map, String key, bool fallback) {
    final v = map[key];
    if (v is bool) return v;
    return fallback;
  }

  static List<int> _readIntList(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is! List) return <int>[];

    return v
        .map((e) {
          if (e is int) return e;
          if (e is num) return e.toInt();
          return null;
        })
        .whereType<int>()
        .toList(growable: true);
  }

  factory _StreakState.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return _StreakState.initial();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _StreakState.initial();

      final map = Map<String, dynamic>.from(decoded);

      return _StreakState(
        streaksEnabled: _readBool(map, 'streaksEnabled', true),
        overrideRestoresStreak: _readBool(map, 'overrideRestoresStreak', true),
        currentStreak: _readInt(map, 'currentStreak', 0).clamp(0, 999999),
        longestStreak: _readInt(map, 'longestStreak', 0).clamp(0, 999999),
        weeksCompleted: _readInt(map, 'weeksCompleted', 0).clamp(0, 999999),
        mostWeeksCompleted: _readInt(
          map,
          'mostWeeksCompleted',
          0,
        ).clamp(0, 999999),
        weekProgress: _readInt(map, 'weekProgress', 0).clamp(0, 7),
        weekStartDayIndex: _readNullableInt(map, 'weekStartDayIndex'),
        nextRequiredDayIndex: _readNullableInt(map, 'nextRequiredDayIndex'),
        lastCompletedDayKey: _readNullableInt(map, 'lastCompletedDayKey'),
        pendingLostDayKey: _readNullableInt(map, 'pendingLostDayKey'),
        pendingLostStreakValue: _readNullableInt(map, 'pendingLostStreakValue'),
        seenHighestStreak: _readInt(
          map,
          'seenHighestStreak',
          0,
        ).clamp(0, 999999),
        completedDayKeys: _readIntList(map, 'completedDayKeys'),
      ).normalized();
    } catch (_) {
      return _StreakState.initial();
    }
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'streaksEnabled': streaksEnabled,
      'overrideRestoresStreak': overrideRestoresStreak,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'weeksCompleted': weeksCompleted,
      'mostWeeksCompleted': mostWeeksCompleted,
      'weekProgress': weekProgress,
      'weekStartDayIndex': weekStartDayIndex,
      'nextRequiredDayIndex': nextRequiredDayIndex,
      'lastCompletedDayKey': lastCompletedDayKey,
      'pendingLostDayKey': pendingLostDayKey,
      'pendingLostStreakValue': pendingLostStreakValue,
      'seenHighestStreak': seenHighestStreak,
      'completedDayKeys': completedDayKeys,
    };
  }

  String toJsonString() => jsonEncode(toJsonMap());

  _StreakState normalized() {
    final cleanedDays = completedDayKeys.toSet().toList()..sort();

    // Keep the list from growing forever. 60 days is plenty for UI/history
    // unless we later decide to make a full streak calendar.
    final trimmedDays = cleanedDays.length <= 60
        ? cleanedDays
        : cleanedDays.sublist(cleanedDays.length - 60);

    final safeWeekStart =
        weekStartDayIndex != null &&
            weekStartDayIndex! >= 0 &&
            weekStartDayIndex! <= 6
        ? weekStartDayIndex
        : null;

    final safeNextDay =
        nextRequiredDayIndex != null &&
            nextRequiredDayIndex! >= 0 &&
            nextRequiredDayIndex! <= 6
        ? nextRequiredDayIndex
        : null;

    return copyWith(
      currentStreak: currentStreak.clamp(0, 999999),
      longestStreak: longestStreak.clamp(0, 999999),
      weeksCompleted: weeksCompleted.clamp(0, 999999),
      mostWeeksCompleted: mostWeeksCompleted.clamp(0, 999999),
      weekProgress: weekProgress.clamp(0, 7),
      weekStartDayIndex: safeWeekStart,
      nextRequiredDayIndex: safeNextDay,
      seenHighestStreak: seenHighestStreak.clamp(0, 999999),
      completedDayKeys: trimmedDays,
    );
  }

  static const Object _unset = Object();

  _StreakState copyWith({
    bool? streaksEnabled,
    bool? overrideRestoresStreak,
    int? currentStreak,
    int? longestStreak,
    int? weeksCompleted,
    int? mostWeeksCompleted,
    int? weekProgress,
    Object? weekStartDayIndex = _unset,
    Object? nextRequiredDayIndex = _unset,
    Object? lastCompletedDayKey = _unset,
    Object? pendingLostDayKey = _unset,
    Object? pendingLostStreakValue = _unset,
    int? seenHighestStreak,
    List<int>? completedDayKeys,
  }) {
    return _StreakState(
      streaksEnabled: streaksEnabled ?? this.streaksEnabled,
      overrideRestoresStreak:
          overrideRestoresStreak ?? this.overrideRestoresStreak,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      weeksCompleted: weeksCompleted ?? this.weeksCompleted,
      mostWeeksCompleted: mostWeeksCompleted ?? this.mostWeeksCompleted,
      weekProgress: weekProgress ?? this.weekProgress,
      weekStartDayIndex: weekStartDayIndex == _unset
          ? this.weekStartDayIndex
          : weekStartDayIndex as int?,
      nextRequiredDayIndex: nextRequiredDayIndex == _unset
          ? this.nextRequiredDayIndex
          : nextRequiredDayIndex as int?,
      lastCompletedDayKey: lastCompletedDayKey == _unset
          ? this.lastCompletedDayKey
          : lastCompletedDayKey as int?,
      pendingLostDayKey: pendingLostDayKey == _unset
          ? this.pendingLostDayKey
          : pendingLostDayKey as int?,
      pendingLostStreakValue: pendingLostStreakValue == _unset
          ? this.pendingLostStreakValue
          : pendingLostStreakValue as int?,
      seenHighestStreak: seenHighestStreak ?? this.seenHighestStreak,
      completedDayKeys: completedDayKeys ?? this.completedDayKeys,
    );
  }
}

class _StreakMiniCompletionCircle extends StatefulWidget {
  const _StreakMiniCompletionCircle({
    super.key,
    required this.done,
    required this.size,
    required this.delay,
  });

  final bool done;
  final double size;
  final Duration delay;

  @override
  State<_StreakMiniCompletionCircle> createState() =>
      _StreakMiniCompletionCircleState();
}

class _StreakMiniCompletionCircleState
    extends State<_StreakMiniCompletionCircle> {
  Timer? _timer;
  bool _visualDone = false;

  @override
  void initState() {
    super.initState();
    _syncVisualState(initial: true);
  }

  @override
  void didUpdateWidget(covariant _StreakMiniCompletionCircle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.done != widget.done || oldWidget.delay != widget.delay) {
      _syncVisualState();
    }
  }

  void _syncVisualState({bool initial = false}) {
    _timer?.cancel();

    if (!widget.done) {
      _visualDone = false;
      if (mounted && !initial) {
        setState(() {});
      }
      return;
    }

    _visualDone = false;
    if (mounted && !initial) {
      setState(() {});
    }

    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() {
        _visualDone = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DailyCompletionCircle(
      done: _visualDone,
      size: widget.size,
      duration: const Duration(milliseconds: 360),
    );
  }
}

class _StreakTabMarker extends StatefulWidget {
  const _StreakTabMarker({
    required this.label,
    required this.color,
    required this.width,
    required this.height,
  });

  final String label;
  final Color color;
  final double width;
  final double height;

  @override
  State<_StreakTabMarker> createState() => _StreakTabMarkerState();
}

class _StreakTabMarkerState extends State<_StreakTabMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.78,
    end: 0.98,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  late final Animation<double> _scale = Tween<double>(
    begin: 0.985,
    end: 1.025,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Amaranth',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 2,
                      offset: Offset(1, 1),
                      color: Color.fromARGB(120, 0, 0, 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StreakButtonAttentionShell extends StatefulWidget {
  const _StreakButtonAttentionShell({
    required this.needsAttention,
    required this.atRisk,
    required this.child,
  });

  final bool needsAttention;
  final bool atRisk;
  final Widget child;

  @override
  State<_StreakButtonAttentionShell> createState() =>
      _StreakButtonAttentionShellState();
}

class _StreakButtonAttentionShellState
    extends State<_StreakButtonAttentionShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _greenPulse = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
  ]).animate(_ctrl);

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _StreakButtonAttentionShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final shouldPulseGreen = widget.needsAttention && !widget.atRisk;

    if (!shouldPulseGreen) {
      _ctrl.stop();
      _ctrl.value = 0.0;
      return;
    }

    if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldPulseGreen = widget.needsAttention && !widget.atRisk;

    if (!shouldPulseGreen) {
      return widget.child;
    }

    const updateGlowGreen = Color(0xFF8DFF7A);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final pulse = _greenPulse.value;

                return Transform.scale(
                  scale: 1.02 + (pulse * 0.105),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: updateGlowGreen.withOpacity(0.10 + pulse * 0.18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(
                            255,
                            157,
                            251,
                            140,
                          ).withOpacity(0.16 + pulse * 0.78),
                          blurRadius: 8 + (pulse * 2),
                          spreadRadius: 0.5 + (pulse * 3),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        widget.child,
      ],
    );
  }
}

class _StreakRiskBlinkColor extends StatefulWidget {
  const _StreakRiskBlinkColor({
    required this.atRisk,
    required this.normalColor,
    required this.builder,
  });

  final bool atRisk;
  final Color normalColor;
  final Widget Function(Color color) builder;

  @override
  State<_StreakRiskBlinkColor> createState() => _StreakRiskBlinkColorState();
}

class _StreakRiskBlinkColorState extends State<_StreakRiskBlinkColor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _StreakRiskBlinkColor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.atRisk) {
      if (!_ctrl.isAnimating) {
        _ctrl.repeat();
      }
    } else {
      _ctrl.stop();
      _ctrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const warningRed = Color(0xFFFF002E);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final blinkOn = widget.atRisk && _ctrl.value < 0.50;

        return widget.builder(blinkOn ? warningRed : widget.normalColor);
      },
    );
  }
}
