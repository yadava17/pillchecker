import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pillchecker/backend/data/offline_medication_suggestions.dart';
import 'package:pillchecker/models/pill_search_item.dart';
import 'package:pillchecker/constants/prefs_keys.dart';
import 'package:pillchecker/backend/services/med_service.dart';
import 'package:pillchecker/backend/services/prefs_migration.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';
import 'package:pillchecker/backend/services/schedule_service.dart';
import 'dart:io' show Platform;

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final MedService _medService = MedService();
  final ScheduleService _scheduleService = ScheduleService();
  final RxNormMedicationService _rxNormService = RxNormMedicationService();

  static const Color _bg = Color(0xffcf5c71); // darker body like Settings
  static const Color _topBar = Color(0xFFFF6D87); // light header like Settings
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);
  static const Color _green = Color(0xFF59FF56);

  static const double _topBarH = 175; // room for title + tabs

  // supply prefs keys (must match HomeScreen)
  static const String _pillSupplyEnabledKey = 'pill_supply_enabled_v1';
  static const String _pillSupplyLeftKey = 'pill_supply_left_v1';

  String _supplyModeGlobal = 'decide'; // 'decide' | 'on' | 'off'
  int _supplyLowAtUser = 10; // the number user picked in Settings

  List<bool> _mySupplyEnabled = [];
  List<int> _mySupplyLeft = [];

  List<String> _myCustomInfo = [];
  List<bool> _myNameLocked = [];

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _searchLoading = false;
  bool _servedFromCache = false;
  bool _hadNetworkError = false;
  List<PillSearchItem> _rxItems = [];

  bool _loaded = false;

  static const String _pillCustomInfoKey = 'pill_custom_info_v1';
  static const String _pillNameLockedKey = 'pill_name_locked_v1';

  bool _effectiveSupplyOnForMyPill(int i) {
    if (_supplyModeGlobal == 'off') return false;
    if (_supplyModeGlobal == 'on') return true;
    return i < _mySupplyEnabled.length && _mySupplyEnabled[i] == true;
  }

  Color _supplyColor(int v) {
    if (v <= 0) return const Color(0xFFFF002E); // red
    if (v <= _supplyLowAtUser) return const Color(0xFFFFDF59); // yellow
    return Colors.white; // normal
  }

  // My pills from prefs
  List<String> _myNames = [];
  List<List<String>> _myDoseTimes24h = [];

  List<bool> _decodeBoolList(String? raw) {
    if (raw == null || raw.isEmpty) return <bool>[];
    final decoded = jsonDecode(raw);
    return (decoded as List).map((e) => e == true).toList();
  }

  List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.isEmpty) return <int>[];
    final decoded = jsonDecode(raw);
    return (decoded as List).map((e) => (e as num).toInt()).toList();
  }

  List<String> _readStringListPref(SharedPreferences prefs, String key) {
    final asList = prefs.getStringList(key);
    if (asList != null) {
      return List<String>.from(asList);
    }

    final asString = prefs.getString(key);
    if (asString == null || asString.isEmpty) {
      return <String>[];
    }

    final decoded = jsonDecode(asString);
    return (decoded as List).map((e) => e.toString()).toList();
  }

  final List<PillSearchItem> _catalog = kOfflineMedicationSuggestions;

  @override
  void initState() {
    super.initState();
    _loadMyPills();
    _searchCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _rxNormService.dispose();
    super.dispose();
  }

  Future<void> _loadMyPills() async {
    final prefs = await SharedPreferences.getInstance();

    await PrefsMigration.runOnceIfNeeded(
      medService: _medService,
      scheduleService: _scheduleService,
    );

    final meds = await _medService.getAll();
    final names = meds.map((m) => m.name).toList();
    final doseTimes = <List<String>>[];
    for (final m in meds) {
      final sch = await _scheduleService.getScheduleForMedication(m.id);
      var times = <String>['08:00'];
      if (sch != null) {
        times = (jsonDecode(sch['times_json']! as String) as List)
            .map((e) => e.toString())
            .toList();
      }
      doseTimes.add(times);
    }

    // ---- global supply settings ----
    final supplyMode = prefs.getString(kSupplyModeKey) ?? 'decide';
    final lowAt = (prefs.getInt(kSupplyLowThresholdKey) ?? 10).clamp(5, 999);

    // ---- per-pill supply lists ----
    final supplyEnabled = _decodeBoolList(
      prefs.getString(_pillSupplyEnabledKey),
    );
    final supplyLeft = _decodeIntList(prefs.getString(_pillSupplyLeftKey));
    final customInfo = _readStringListPref(prefs, _pillCustomInfoKey);
    final nameLocked = _decodeBoolList(prefs.getString(_pillNameLockedKey));

    // align to names
    while (supplyEnabled.length < names.length) supplyEnabled.add(false);
    while (supplyLeft.length < names.length) supplyLeft.add(0);

    if (supplyEnabled.length > names.length) {
      supplyEnabled.removeRange(names.length, supplyEnabled.length);
    }
    if (supplyLeft.length > names.length) {
      supplyLeft.removeRange(names.length, supplyLeft.length);
    }

    // align
    while (doseTimes.length < names.length) doseTimes.add(<String>['08:00']);
    if (doseTimes.length > names.length) {
      doseTimes.removeRange(names.length, doseTimes.length);
    }

    while (customInfo.length < names.length) customInfo.add('');
    while (nameLocked.length < names.length) nameLocked.add(false);

    if (customInfo.length > names.length) {
      customInfo.removeRange(names.length, customInfo.length);
    }
    if (nameLocked.length > names.length) {
      nameLocked.removeRange(names.length, nameLocked.length);
    }

    if (!mounted) return;
    setState(() {
      _myNames = names;
      _myDoseTimes24h = doseTimes;
      _loaded = true;

      _supplyModeGlobal = supplyMode;
      _supplyLowAtUser = lowAt;

      _mySupplyEnabled = supplyEnabled;
      _mySupplyLeft = supplyLeft;
      _myCustomInfo = customInfo;
      _myNameLocked = nameLocked;
    });
  }

  bool _alreadyAdded(String name) {
    final n = name.trim().toLowerCase();
    return _myNames.any((x) => x.trim().toLowerCase() == n);
  }

  String get _q => _searchCtrl.text.trim().toLowerCase();
  String get _queryRaw => _searchCtrl.text.trim();

  Future<void> _onQueryChanged() async {
    setState(() {});
    _debounce?.cancel();

    if (_queryRaw.length < 2) {
      if (mounted) {
        setState(() {
          _searchLoading = false;
          _servedFromCache = false;
          _hadNetworkError = false;
          _rxItems = [];
        });
      }
      return;
    }

    setState(() {
      _searchLoading = true;
      _rxItems = [];
    });

    _debounce = Timer(const Duration(milliseconds: 420), () async {
      final outcome = await _rxNormService.searchMedications(_queryRaw);
      if (!mounted) return;
      setState(() {
        _searchLoading = false;
        _servedFromCache = outcome.servedFromCache;
        _hadNetworkError = outcome.hadNetworkError;
        _rxItems = outcome.items
            .map(
              (m) => PillSearchItem(
                name: m.displayName,
                suggestedTimesPerDay: 2,
                info: '',
                rxcui: m.rxcui,
                searchSubtitle: m.subtitle,
                isFromCache: outcome.servedFromCache,
              ),
            )
            .toList();
      });
    });
  }

  bool _matches(String name) {
    if (_q.isEmpty) return true;
    return name.toLowerCase().contains(_q);
  }

  List<PillSearchItem> get _catalogForView {
    if (_queryRaw.length < 2) {
      return _catalog.where((p) => _matches(p.name)).toList();
    }
    final seen = <String>{};
    final merged = <PillSearchItem>[];
    for (final p in _rxItems) {
      final k = p.name.trim().toLowerCase();
      if (seen.add(k)) merged.add(p);
    }
    for (final p in _catalog.where((x) => _matches(x.name))) {
      final k = p.name.trim().toLowerCase();
      if (seen.add(k)) merged.add(p);
    }
    return merged;
  }

  Future<void> _openDetails({
    required String name,
    required bool isCatalog,
    required bool addEnabled,
    required String info,
    int? myPillIndex, // ✅ NEW: pass index when opening from "My Pills"
    PillSearchItem? addItem,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final showSupply =
            (!isCatalog) &&
            (myPillIndex != null) &&
            _effectiveSupplyOnForMyPill(myPillIndex);

        final supplyLeft =
            (myPillIndex != null && myPillIndex < _mySupplyLeft.length)
            ? _mySupplyLeft[myPillIndex]
            : 0;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(26),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // header
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
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
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // info (description only)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      info,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                  ),

                  // ✅ supply only for My Pills (and only if effectively ON)
                  if (showSupply) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.medication_rounded,
                            color: Colors.white.withOpacity(0.85),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Supply left:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            supplyLeft.toString(),
                            style: TextStyle(
                              color: _supplyColor(supplyLeft),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ✅ add button only for catalogue pills
                  if (isCatalog) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: Opacity(
                        opacity: addEnabled ? 1.0 : 0.45,
                        child: Material(
                          color: _green,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: addEnabled && addItem != null
                                ? () async {
                                    final ok =
                                        await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Add this pill?'),
                                            content: Text(
                                              'Add "$name" to your wheel?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Add'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;

                                    if (!ok) return;

                                    // close sheet then return item to HomeScreen
                                    if (!mounted) return;
                                    Navigator.pop(context); // sheet
                                    Navigator.pop(context, addItem); // screen
                                  }
                                : null,
                            child: Center(
                              child: Text(
                                addEnabled ? 'Add' : 'Already added',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 0, // ✅ Catalogue default
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Stack(
            children: [
              // ✅ top bar background (like Settings)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(height: _topBarH, color: _topBar),
              ),

              // ✅ divider line (like Settings)
              Positioned(
                left: 0,
                right: 0,
                top: _topBarH,
                child: Container(height: 5, color: _divider),
              ),

              // ✅ white oval under back button (like Settings)
              Positioned(
                left: Platform.isAndroid ? -85 : -75,
                top: 15,
                child: ClipOval(
                  child: Container(
                    width: 150,
                    height: 85,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),

              // ✅ logo
              Positioned(
                top: Platform.isAndroid ? 10 : 0,
                left: Platform.isAndroid ? 80 : 82,
                child: Opacity(
                  opacity: 0.75,
                  child: Image.asset(
                    'assets/images/pillchecker_logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // ✅ title
              Positioned(
                top: Platform.isAndroid ? 28 : 34,
                left: Platform.isAndroid ? 168 : 158,
                right: 24,
                child: Text(
                  'PillChecker',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: Platform.isAndroid ? 34 : 32,
                    fontFamily: 'Amaranth',
                    color: _card,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),

              // ✅ back button (sits on the white oval)
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

              // Tabs (Catalogue / My Pills)
              Positioned(
                left: 16,
                right: 16,
                top: _topBarH - 62,
                child: SizedBox(
                  height: 52,
                  child: TabBar(
                    dividerColor: const Color.fromARGB(120, 158, 52, 70),
                    dividerHeight: 2,
                    labelStyle: const TextStyle(
                      fontFamily: 'Amaranth',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontFamily: 'Amaranth',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    labelColor: _card,
                    unselectedLabelColor: _card.withOpacity(0.55),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(color: _card, width: 4),
                      insets: EdgeInsets.symmetric(horizontal: 10),
                    ),
                    tabs: const [
                      Tab(text: 'Catalogue'),
                      Tab(text: 'My Pills'),
                    ],
                  ),
                ),
              ),

              // content area below divider
              Positioned.fill(
                top: _topBarH - 46,
                child: Column(
                  children: [
                    const SizedBox(height: 60),

                    // search bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: _card),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Search pills…',
                                    hintStyle: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              if (_searchCtrl.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () => _searchCtrl.clear(),
                                  child: const Icon(Icons.close, color: _card),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Expanded(
                      child: !_loaded
                          ? const Center(child: CircularProgressIndicator())
                          : TabBarView(
                              children: [
                                // Catalogue tab
                                ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  children: [
                                    if (_queryRaw.length >= 2 && _searchLoading)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                    if (_queryRaw.length >= 2 &&
                                        _servedFromCache &&
                                        _rxItems.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          'Showing saved RxNorm results (offline or API unavailable).',
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    if (_queryRaw.length >= 2 &&
                                        _hadNetworkError &&
                                        _rxItems.isEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          'Offline — showing built-in medication names.',
                                          style: TextStyle(
                                            color: Colors.teal.shade900,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    for (final p in _catalogForView)
                                      _pillRow(
                                        name: p.name,
                                        subtitle: p.isRxNorm
                                            ? (p.searchSubtitle ??
                                                  (p.isFromCache
                                                      ? 'RxNorm (saved)'
                                                      : 'RxNorm'))
                                            : '${p.suggestedTimesPerDay}× per day',
                                        showAddButton: true,
                                        addEnabled: !_alreadyAdded(p.name),
                                        onAdd: !_alreadyAdded(p.name)
                                            ? () async {
                                                final ok =
                                                    await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          'Add this pill?',
                                                        ),
                                                        content: Text(
                                                          'Add "${p.name}" to your wheel?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  true,
                                                                ),
                                                            child: const Text(
                                                              'Add',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ) ??
                                                    false;

                                                if (!ok) return;
                                                if (!context.mounted) return;
                                                Navigator.pop(context, p);
                                              }
                                            : null,
                                        onTap: () {
                                          _openDetails(
                                            name: p.name,
                                            isCatalog: true,
                                            addEnabled: !_alreadyAdded(p.name),
                                            info: p.info,
                                            addItem: p,
                                          );
                                        },
                                      ),
                                  ],
                                ),

                                // My Pills tab
                                ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  children: [
                                    if (_myNames.isEmpty)
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: _card,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: const Text(
                                          'No pills added yet.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    for (int i = 0; i < _myNames.length; i++)
                                      if (_matches(_myNames[i]))
                                        _pillRow(
                                          name: _myNames[i],
                                          subtitle:
                                              '${_myDoseTimes24h[i].length}× per day',
                                          showAddButton: false,
                                          onTap: () {
                                            final isCustom =
                                                i < _myNameLocked.length &&
                                                _myNameLocked[i] == false;

                                            final savedCustomInfo =
                                                (i < _myCustomInfo.length)
                                                ? _myCustomInfo[i].trim()
                                                : '';

                                            final infoText = isCustom
                                                ? (savedCustomInfo.isNotEmpty
                                                      ? savedCustomInfo
                                                      : 'No custom pill info added yet.')
                                                : 'Medication details available in the main pill info panel.';

                                            _openDetails(
                                              name: _myNames[i],
                                              isCatalog: false,
                                              addEnabled: false,
                                              info: infoText,
                                              myPillIndex: i,
                                            );
                                          },
                                        ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillRow({
    required String name,
    required String subtitle,
    required VoidCallback onTap,
    bool showAddButton = true,
    bool addEnabled = false,
    VoidCallback? onAdd,
  }) {
    final addColor = addEnabled ? _green : Colors.white.withOpacity(0.25);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 74,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/images/pill_placeholder.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                if (showAddButton) ...[
                  IgnorePointer(
                    ignoring: !addEnabled,
                    child: Opacity(
                      opacity: addEnabled ? 1.0 : 0.55,
                      child: GestureDetector(
                        onTap: onAdd,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: addColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
