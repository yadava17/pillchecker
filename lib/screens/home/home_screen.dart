import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pillchecker/widgets/pill_wheel.dart';
import 'package:pillchecker/widgets/pill_check_button.dart';
import 'package:pillchecker/services/notification_service.dart';
import 'dart:convert';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _ConfigStep { name, config, doses }

class _HomeScreenState extends State<HomeScreen> {
  static const _pillNamesKey = 'pill_names';
  static const _seenPromptKey = 'seen_first_pill_prompt';
  static const _pillCheckKey = 'pill_check_state'; // json map
  static const _pillTimesKey = 'pill_times'; // "HH:MM" per pill index
  Timer? _labelTimer;
  String? _labelOverride;

  bool _showPillLabel = true; // label visible when strip is in normal position
  bool get _centerIsRealPill => _centerPillIndex != null;

  int _wheelSelectedIndex = 1;

  List<String> pillNames = [];
  List<String> pillTimes = []; // "HH:MM" per pill, same index as pillNames

  bool _pendingSlot = false;

  bool _configOpen = false;
  _ConfigStep _step = _ConfigStep.name;

  final TextEditingController _nameController = TextEditingController();
  int _timesPerDay = 1;
  TimeOfDay? _singleDoseTime;
  List<TimeOfDay?> _doseTimes = [];

  TimeOfDay _timeForPill(int pillIndex) {
    if (pillIndex < 0 || pillIndex >= pillTimes.length) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
    return _strToTime(pillTimes[pillIndex]); // uses your existing helper
  }

  Future<Map<String, dynamic>> _loadCheckMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pillCheckKey);
    if (raw == null || raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _showWelcomeThenOpenConfig(SharedPreferences prefs) async {
    // Don’t show twice
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

    // Mark seen AFTER they actually saw it
    await prefs.setBool(_seenPromptKey, true);

    if (!mounted) return;
    _startAddFlow(createNewSlot: true);
  }

  Future<void> _saveCheckMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pillCheckKey, jsonEncode(map));
  }

  bool _isPillCheckedNowSync(Map<String, dynamic> map, int pillIndex) {
    final pillTime = _timeForPill(pillIndex);
    final cycleKey = _cycleKeyForNow(pillTime, DateTime.now());
    final stored = map['$pillIndex'] as String?;
    return stored == cycleKey;
  }

  Future<void> _checkCenteredPill() async {
    final pillIndex = _centerPillIndex;
    if (pillIndex == null) return;

    final map = await _loadCheckMap();
    final pillTime = _timeForPill(pillIndex);
    final cycleKey = _cycleKeyForNow(pillTime, DateTime.now());

    map['$pillIndex'] = cycleKey;
    await _saveCheckMap(map);

    // show "Pill Checked!" for ~10 seconds
    _labelTimer?.cancel();
    setState(() => _labelOverride = 'Pill Checked!');
    _labelTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _labelOverride = null);
    });

    // refresh UI (so the check button flips to checked)
    if (mounted) setState(() {});
  }

  // returns the "cycle key" that defines whether it's considered checked
  String _cycleKeyForNow(TimeOfDay pillTime, DateTime now) {
    final resetToday = DateTime(
      now.year,
      now.month,
      now.day,
      pillTime.hour,
      pillTime.minute,
    ).subtract(const Duration(hours: 2));

    // if we haven't reached today's reset boundary yet, we are still in yesterday's cycle
    final cycleStart = now.isBefore(resetToday)
        ? resetToday.subtract(const Duration(days: 1))
        : resetToday;
    return cycleStart.toIso8601String();
  }

  late final FixedExtentScrollController _wheelController =
      FixedExtentScrollController(initialItem: 1);

  void _clearCheckedMessage() {
    if (_labelOverride == null) return;

    _labelTimer?.cancel();
    _labelTimer = null;

    if (!mounted) return;
    setState(() => _labelOverride = null);
  }

  @override
  void initState() {
    super.initState();
    _loadAndMaybeAutoOpen();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wheelController.dispose();
    super.dispose();
  }

  int? get _centerPillIndex {
    final idx = _wheelSelectedIndex - 1; // wheel->pill
    if (_wheelSelectedIndex <= 0) return null;
    if (idx < 0 || idx >= pillNames.length) return null;
    return idx;
  }

  // ONLY show a pill name when a real pill is centered.
  String _centerPillName() {
    // wheel index 0 is "+"
    if (_wheelSelectedIndex <= 0) return '';
    final slot = _wheelSelectedIndex - 1; // 0-based pill slot
    if (slot < 0) return '';
    if (slot >= pillNames.length) return ''; // pending/empty slot
    return pillNames[slot];
  }

  void _hidePillLabelNow() {
    if (_showPillLabel) setState(() => _showPillLabel = false);
  }

  void _showPillLabelAfterSlide() {
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      // Only show if we truly returned to normal (config closed)
      if (!_configOpen) setState(() => _showPillLabel = true);
    });
  }

  Future<void> _showWelcomeDialog() async {
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
  }

  Future<void> _loadAndMaybeAutoOpen() async {
    final prefs = await SharedPreferences.getInstance();

    final savedNames = prefs.getStringList(_pillNamesKey) ?? [];
    final savedTimes = prefs.getStringList(_pillTimesKey) ?? [];
    final seen = prefs.getBool(_seenPromptKey) ?? false;

    // Keep times aligned with names (so indexes always match)
    final alignedTimes = List<String>.from(savedTimes);
    while (alignedTimes.length < savedNames.length) {
      alignedTimes.add('08:00'); // default placeholder time
    }
    if (alignedTimes.length > savedNames.length) {
      alignedTimes.removeRange(savedNames.length, alignedTimes.length);
    }

    // Persist alignment so it stays clean
    await prefs.setStringList(_pillTimesKey, alignedTimes);

    setState(() {
      pillNames = savedNames;
      pillTimes = alignedTimes;
    });

    if (savedNames.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showWelcomeThenOpenConfig(prefs);
      });
    }
  }

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
    setState(() {
      _configOpen = false;
      _pendingSlot = false;
      _step = _ConfigStep.name;
    });
    _centerWheelOn(1);
    _showPillLabelAfterSlide(); // <-- add
  }

  String _fmt(TimeOfDay t) {
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$mm $suffix';
  }

  String _timeToStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _strToTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
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

  Future<void> _savePill() async {
    _showPillLabelAfterSlide();

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_timesPerDay == 1 && _singleDoseTime == null) return;
    if (_timesPerDay > 1 && !_allDoseTimesSet) return;

    final prefs = await SharedPreferences.getInstance();
    final updated = [...pillNames, name];
    await prefs.setStringList(_pillNamesKey, updated);

    // ---- Save pill time (single time for now) ----
    final t = _singleDoseTime!; // safe because we checked above
    final existingTimes = prefs.getStringList(_pillTimesKey) ?? [];
    final updatedTimes = [...existingTimes, _timeToStr(t)];
    await prefs.setStringList(_pillTimesKey, updatedTimes);
    // --------------------------------------------

    // ---- IMPORTANT: new pill should NEVER inherit old check state ----
    final checkMap = await _loadCheckMap();
    final newIndex = updated.length - 1;

    checkMap.remove('$newIndex'); // clears any old state at this index
    await _saveCheckMap(checkMap);
    // ---------------------------------------------------------------

    // ---- Notifications (TEST) ----
    debugPrint(
      'SAVE -> scheduling id=${1000 + newIndex} '
      'name="$name" time=${_timeToStr(t)}',
    );

    await NotificationService.scheduleDailyPillReminder(
      id: 1000 + newIndex,
      pillName: name,
      time: t,
    );
    // -----------------------------

    setState(() {
      pillNames = updated;
      _pendingSlot = false;
      _configOpen = false;
      _step = _ConfigStep.name;
    });

    _showPillLabelAfterSlide();
    _centerWheelOn(1 + (updated.length - 1));
  }

  Future<void> _deleteCenteredPill() async {
    // wheel index 0 is "+"
    if (_wheelSelectedIndex <= 0) return;

    final slot = _wheelSelectedIndex - 1; // 0-based pill index
    if (slot < 0 || slot >= pillNames.length) return; // empty/pending

    final pillName = pillNames[slot];

    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
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
            );
          },
        ) ??
        false;

    if (!shouldDelete) return;
    // later: cancel notification for this pill (safe no-op right now)
    await NotificationService.cancel(1000 + slot);

    // Remove from list + persist
    // Remove from lists + persist (KEEP INDICES ALIGNED)
    final updatedNames = [...pillNames]..removeAt(slot);

    // times list should remove at the same index if it exists
    final updatedTimes = [...pillTimes];
    if (slot < updatedTimes.length) {
      updatedTimes.removeAt(slot);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pillNamesKey, updatedNames);
    await prefs.setStringList(_pillTimesKey, updatedTimes);

    // --- FIX: also update the check-map so deleted index doesn't "stick" ---
    final checkMap = await _loadCheckMap(); // Map<String, dynamic>

    final Map<String, dynamic> shifted = {};
    checkMap.forEach((k, v) {
      final idx = int.tryParse(k);
      if (idx == null) return;

      if (idx < slot) {
        shifted['$idx'] = v; // unchanged
      } else if (idx > slot) {
        shifted['${idx - 1}'] = v; // shift down
      }
      // if idx == slot -> dropped (deleted pill)
    });

    await _saveCheckMap(shifted);
    // --- end FIX ---

    setState(() {
      pillNames = updatedNames;
      pillTimes = updatedTimes;
      _pendingSlot = false;
    });

    // Recenter on a safe item:
    // wheel index 0 is "+", so pills start at 1.
    final newPillCount = updatedNames.length;
    if (newPillCount == 0) {
      _wheelSelectedIndex = 1;
      _centerWheelOn(1);
    } else {
      // Keep it near the same position
      final newSlot = slot.clamp(0, newPillCount - 1);
      final newWheelIndex = newSlot + 1;
      _wheelSelectedIndex = newWheelIndex;
      _centerWheelOn(newWheelIndex);
    }
  }

  void _handlePrimaryAction() {
    if (_step == _ConfigStep.name) {
      if (_nameController.text.trim().isEmpty) return;
      setState(() => _step = _ConfigStep.config);
      return;
    }

    if (_step == _ConfigStep.config) {
      if (_timesPerDay == 1) {
        if (_singleDoseTime == null) return;
        _savePill();
      } else {
        setState(() {
          _step = _ConfigStep.doses;
          _doseTimes = List<TimeOfDay?>.filled(_timesPerDay, null);
        });
      }
      return;
    }

    if (_step == _ConfigStep.doses) {
      if (!_allDoseTimesSet) return;
      _savePill();
    }
  }

  Widget _configPanel() {
    const cardColor = Color(0xFF98404F);
    const white = Color(0xFFFFFFFF);
    const green = Color(0xFF59FF56);

    final titleText = (_step == _ConfigStep.name)
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
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: white,
                  ),
                  child: const Center(
                    child: Icon(Icons.medication, color: cardColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: (_step == _ConfigStep.name)
                      ? TextField(
                          controller: _nameController,
                          style: const TextStyle(color: white, fontSize: 18),
                          decoration: const InputDecoration(
                            hintText: 'Pill name...',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                        )
                      : Text(
                          _nameController.text.trim(),
                          style: const TextStyle(
                            color: white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
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
                  const Text('Times per day', style: TextStyle(color: white)),
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
                            (n) =>
                                DropdownMenuItem(value: n, child: Text('$n')),
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
              Expanded(
                child: ListView.separated(
                  itemCount: _timesPerDay,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                        trailing: const Icon(Icons.schedule, color: cardColor),
                        onTap: () => _pickDoseTime(i),
                      ),
                    );
                  },
                ),
              )
            else
              const Spacer(),

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
                        child: Icon(Icons.add, color: Colors.white, size: 34),
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
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Your design reference (phone you built on)
    const designW = 411.0;
    const designH = 914.0;

    final scaleW = size.width / designW;
    final scaleH = size.height / designH;

    // Use the smaller one so it fits both directions
    final scale = (scaleW < scaleH ? scaleW : scaleH).clamp(0.8, 1.3);

    double s(double v) => v * scale;
    double fs(double v) => v * scale; // font size scale

    // ---- CENTERING HELPERS (keeps sizes, fixes offset on tablets) ----
    // use your existing sizes, just center them in X
    final double stripW = s(800);
    final double stripH = s(1383);

    // keep the wheel size you already had; just center it
    final double wheelBoxH = s(1000);
    final double wheelBoxW = size.width; // since you were using left+right=0

    double cx(double w) => (size.width - w) / 2;

    final bottomSlide = _configOpen ? const Offset(0, 0.30) : Offset.zero;
    final wheelLocked = _pendingSlot;
    final plusIsCentered = _wheelSelectedIndex == 0;
    final checkDisabled = plusIsCentered || _configOpen || _pendingSlot;

    final labelText = _labelOverride ?? _centerPillName();

    double leftFromDesignRight(double baseW, double baseRight) {
      // baseW/baseRight are the ORIGINAL numbers you used on the phone design (411 wide)
      final elementW = s(baseW);

      // where the element's center was on the 411-wide design:
      final designCenterX = designW / 2;
      final elementCenterX = designW - baseRight - (baseW / 2);
      final offsetFromCenter = elementCenterX - designCenterX;

      // keep that same offset-from-center on any screen
      return (size.width / 2) + s(offsetFromCenter) - (elementW / 2);
    }

    final logoSize = s(
      150,
    ).clamp(80.0, 150.0); // min on small screens, max like your phone

    return Scaffold(
      backgroundColor: const Color(0xFFC75469),
      body: Stack(
        children: [
          // ---- TOP / STATIC UI ----
          Positioned(
            right: 0,
            left: 0,
            top: s(0),
            child: Container(
              height: s(140), // important: use height here, not SizedBox.square
              color: const Color(0xFFFF6D87),
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

          // Logo (left)
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

          // Title (centered)
          Positioned(
            top: s(40),
            left: 35,
            right: 0,
            child: Center(
              child: Transform.scale(
                scale: 0.5, // back to original
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

          // ---- BOTTOM SECTION (centered wheel + centered strip) ----
          IgnorePointer(
            ignoring: _configOpen,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              offset: bottomSlide,
              child: Stack(
                children: [
                  // pill strip (WAS right: -195) -> now truly centered
                  Positioned(
                    left: cx(stripW),
                    bottom: s(-900),
                    child: ClipOval(
                      child: Container(
                        width: stripW,
                        height: stripH,
                        color: const Color(0xFFE72447),
                      ),
                    ),
                  ),

                  // wheel (keep your sizing, just explicitly centered)
                  Positioned(
                    left: cx(wheelBoxW),
                    width: wheelBoxW,
                    bottom: s(-85),
                    height: wheelBoxH,
                    child: PillWheel(
                      onDeleteCentered: _deleteCenteredPill,
                      controller: _wheelController,
                      displayPillCount: _displayPillCount,
                      realPillCount: _realPillCount,
                      scrollEnabled: !wheelLocked,
                      addEnabled: !wheelLocked,
                      onSelectedChanged: (i) {
                        // If selection changed, kill the "Pill Checked!" message immediately
                        if (i != _wheelSelectedIndex) {
                          _clearCheckedMessage();
                        }

                        setState(() => _wheelSelectedIndex = i);
                      },

                      onAddPressed: () {
                        _startAddFlow(createNewSlot: true);
                      },
                    ),
                  ),

                  Positioned(
                    left: leftFromDesignRight(400, 5),
                    bottom: s(-1045),
                    child: ClipOval(
                      child: Container(
                        width: s(400),
                        height: s(1383),
                        color: const Color(0xFFFF6D87),
                      ),
                    ),
                  ),

                  Positioned(
                    left: leftFromDesignRight(175, 118),
                    bottom: s(90),
                    child: ClipOval(
                      child: Container(
                        width: s(175),
                        height: s(175),
                        color: const Color(0xFF0CF000),
                      ),
                    ),
                  ),

                  Positioned(
                    left: leftFromDesignRight(155, 127.5),
                    bottom: s(100),
                    child: ClipOval(
                      child: Container(
                        width: s(155),
                        height: s(155),
                        color: const Color(0xFF8C1C2F),
                      ),
                    ),
                  ),

                  Positioned(
                    left: leftFromDesignRight(135, 137),
                    bottom: s(110),
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: _loadCheckMap(),
                      builder: (context, snap) {
                        final pillIndex = _centerPillIndex;
                        final map = snap.data ?? {};
                        final checked = (pillIndex != null)
                            ? _isPillCheckedNowSync(map, pillIndex)
                            : false;

                        final checkDisabled =
                            !_centerIsRealPill || _configOpen || _pendingSlot;

                        return AbsorbPointer(
                          absorbing: checkDisabled,
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

                  // Bottom-left oval
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

                  // Bottom-right oval
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
                ],
              ),
            ),
          ),

          // ---- CENTER PILL NAME (ON TOP OF STRIP) ----
          Positioned(
            left: s(0),
            right: s(0),
            bottom: s(490),
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeInOut,
                opacity: _showPillLabel ? 1.0 : 0.0,
                child: Center(
                  child: Text(
                    _labelOverride ?? _centerPillName(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Amaranth',
                      fontSize: fs(25),
                      color: const Color.fromARGB(255, 237, 179, 189),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ---- TOP OVALS ----
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

          // ---- CONFIG PANEL LAST (ON TOP) ----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            left: s(18),
            right: s(18),
            top: _configOpen
                ? s(160)
                : MediaQuery.of(context).size.height + s(50),
            height: s(420),
            child: _configPanel(),
          ),
        ],
      ),
    );
  }
}
