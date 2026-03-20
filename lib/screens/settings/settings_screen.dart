import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pillchecker/constants/prefs_keys.dart';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _bg = Color(0xffcf5c71);
  static const Color _topBar = Color(0xFFFF6D87);
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);

  bool _loaded = false;

  bool _notifExpanded = false;
  bool _supplyExpanded = false;
  bool _feedbackExpanded = false;

  String _mode = 'standard';
  int _earlyMin = 30;
  int _lateMin = 30;

  // keep originals so we can detect changes
  String _origMode = 'standard';
  int _origEarly = 30;
  int _origLate = 30;

  String _supplyMode = 'decide';
  int _supplyLow = 10;

  String _origSupplyMode = 'decide';
  int _origSupplyLow = 10;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_changed) return true;

    final discard =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Leave without saving your changes?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave without saving'),
              ),
            ],
          ),
        ) ??
        false;

    return discard;
  }

  Future<void> _attemptClose() async {
    final ok = await _confirmDiscardIfNeeded();
    if (!ok) return;
    if (!mounted) return;
    Navigator.pop(context, false);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final mode = prefs.getString(kNotifModeKey) ?? 'standard';
    final early = prefs.getInt(kEarlyLeadMinKey) ?? 30;
    final late = prefs.getInt(kLateAfterMinKey) ?? 30;

    final supplyMode = prefs.getString(kSupplyModeKey) ?? 'decide';
    final supplyLow = (prefs.getInt(kSupplyLowThresholdKey) ?? 10).clamp(
      5,
      999,
    );

    setState(() {
      _supplyMode = supplyMode;
      _supplyLow = supplyLow;

      _origSupplyMode = supplyMode;
      _origSupplyLow = supplyLow;
    });

    setState(() {
      _mode = mode;
      _earlyMin = early;
      _lateMin = late;

      _origMode = mode;
      _origEarly = early;
      _origLate = late;

      _loaded = true;
    });
  }

  bool get _changed =>
      _mode != _origMode ||
      _earlyMin != _origEarly ||
      _lateMin != _origLate ||
      _supplyMode != _origSupplyMode ||
      _supplyLow != _origSupplyLow;

  String _hmLabel(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    if (h == 0) return '$m min';
    if (m == 0) return '$h hr';
    return '$h hr $m min';
  }

  Widget _timeBox({
    required String title,
    required String subtitle,
    required int minutes,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required bool enabled,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Value box
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _hmLabel(minutes),
                  style: const TextStyle(
                    color: Color(0xFF98404F),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // - button
              _miniBtn(icon: Icons.remove, onTap: onMinus),

              const SizedBox(width: 8),

              // + button
              _miniBtn(icon: Icons.add, onTap: onPlus),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numBox({
    required String title,
    required String subtitle,
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required bool enabled,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Value box (NO "min")
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  value.toString(),
                  style: const TextStyle(
                    color: Color(0xFF98404F),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              _miniBtn(icon: Icons.remove, onTap: onMinus),
              const SizedBox(width: 8),
              _miniBtn(icon: Icons.add, onTap: onPlus),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: const Color(0xFF98404F)),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    // saving:
    await prefs.setString(kNotifModeKey, _mode);
    await prefs.setInt(kEarlyLeadMinKey, _earlyMin);
    await prefs.setInt(kLateAfterMinKey, _lateMin);
    await prefs.setString(kSupplyModeKey, _supplyMode);
    await prefs.setInt(kSupplyLowThresholdKey, _supplyLow);

    debugPrint('SETTINGS SAVE: mode=$_mode early=$_earlyMin late=$_lateMin');
    debugPrint(
      'SETTINGS SAVE KEYS: '
      'mode=${prefs.getString(kNotifModeKey)} '
      'early=${prefs.getInt(kEarlyLeadMinKey)} '
      'late=${prefs.getInt(kLateAfterMinKey)}',
    );

    // return "true" so HomeScreen knows to resync notifications
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'standard':
        return 'Standard (Early - Main - Late)';
      case 'basic':
        return 'Basic (Main only)';
      case 'off':
        return 'Off';
      default:
        return mode;
    }
  }

  Uri get _feedbackUri => Uri.parse(
    Platform.isIOS
        ? 'https://docs.google.com/forms/d/1fInqV7iNYnWDGHIAl54mhiqIcsswi5J5-EtSU50Pd_s/edit?ts=698e0252'
        : 'https://docs.google.com/forms/d/1IwTVYPABp3hzrIP2QDfentDElskPrOh6XD5aYLpQ-cE/edit?ts=699455dd',
  );

  Future<void> _openFeedbackForm() async {
    final ok = await launchUrl(
      _feedbackUri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the feedback form.')),
      );
    }
  }

  Widget _expandSection({
    required String title,
    required bool expanded,
    required ValueChanged<bool> onChanged,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          maintainState: true,
          initiallyExpanded: expanded,
          onExpansionChanged: onChanged,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          collapsedIconColor: Colors.white70,
          iconColor: Colors.white,
          trailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            color: Colors.white,
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // we decide when popping is allowed
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _attemptClose();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: _bg,
        body: SafeArea(
          child: Stack(
            clipBehavior: Clip.none,
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
                top: Platform.isAndroid ? -6 : -1,
                left: 0,
                right: Platform.isAndroid ? 165 : 185,
                child: Opacity(
                  opacity: 0.75,
                  child: Image.asset(
                    'assets/images/pillchecker_logo.png',
                    width: 150,
                    height: 150,
                  ),
                ),
              ),

              Positioned(
                top: 15,
                left: 35,
                right: 0,
                child: Center(
                  child: SizedBox(
                    // ✅ Android gets more horizontal room so it doesn't clip/weird-render
                    width: Platform.isAndroid ? 340 : 260,
                    child: Transform.scale(
                      scale: 0.5,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'PillChecker',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 77.9,
                            fontFamily: 'Amaranth',
                            color: _card,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

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

              Positioned(
                top: 30,
                left: 4,
                child: IconButton(
                  onPressed: _attemptClose,
                  icon: const Icon(Icons.arrow_back),
                  color: const Color.fromARGB(255, 60, 59, 59),
                  iconSize: 40,
                ),
              ),

              Positioned.fill(
                top: 115,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 70, 18, 18),
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _card,
                        fontFamily: 'Amaranth',
                      ),
                    ),
                    const SizedBox(height: 18),

                    if (!_loaded)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      _expandSection(
                        title: 'Notifications',
                        expanded: _notifExpanded,
                        onChanged: (v) => setState(() => _notifExpanded = v),
                        children: [
                          const SizedBox(height: 6),

                          const Text(
                            'Reminder mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: DropdownButton<String>(
                              value: _mode,
                              underline: const SizedBox.shrink(),
                              isExpanded: true,
                              items: const ['standard', 'basic', 'off']
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(_modeLabel(m)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _mode = v);
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          Builder(
                            builder: (context) {
                              const step = 5;
                              const maxMin = 240;
                              final enabled = _mode == 'standard';

                              return Column(
                                children: [
                                  _timeBox(
                                    title: 'Early reminder',
                                    subtitle: 'How long before the dose?',
                                    minutes: _earlyMin,
                                    enabled: enabled,
                                    onMinus: () {
                                      setState(
                                        () => _earlyMin = (_earlyMin - step)
                                            .clamp(0, maxMin),
                                      );
                                    },
                                    onPlus: () {
                                      setState(
                                        () => _earlyMin = (_earlyMin + step)
                                            .clamp(0, maxMin),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _timeBox(
                                    title: 'Late reminder',
                                    subtitle: 'How long after the dose?',
                                    minutes: _lateMin,
                                    enabled: enabled,
                                    onMinus: () {
                                      setState(
                                        () => _lateMin = (_lateMin - step)
                                            .clamp(0, maxMin),
                                      );
                                    },
                                    onPlus: () {
                                      setState(
                                        () => _lateMin = (_lateMin + step)
                                            .clamp(0, maxMin),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      _expandSection(
                        title: 'Supply tracking',
                        expanded: _supplyExpanded,
                        onChanged: (v) => setState(() => _supplyExpanded = v),
                        children: [
                          const SizedBox(height: 6),

                          const Text(
                            'Mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: DropdownButton<String>(
                              value: _supplyMode,
                              underline: const SizedBox.shrink(),
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'decide',
                                  child: Text('Decide in Configure (default)'),
                                ),
                                DropdownMenuItem(
                                  value: 'on',
                                  child: Text('Always On'),
                                ),
                                DropdownMenuItem(
                                  value: 'off',
                                  child: Text('Always Off'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _supplyMode = v);
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          _numBox(
                            title: 'Low supply warning',
                            subtitle: 'When supply is at:',
                            value: _supplyLow,
                            enabled: _supplyMode != 'off',
                            onMinus: () => setState(
                              () => _supplyLow = (_supplyLow - 1).clamp(5, 999),
                            ),
                            onPlus: () => setState(
                              () => _supplyLow = (_supplyLow + 1).clamp(5, 999),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      _expandSection(
                        title: 'Issues / Feedback',
                        expanded: _feedbackExpanded,
                        onChanged: (v) => setState(() => _feedbackExpanded = v),
                        children: [
                          const SizedBox(height: 6),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _openFeedbackForm,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.open_in_new,
                                      color: Color(0xFF98404F),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Open feedback form',
                                      style: TextStyle(
                                        color: Color(0xFF98404F),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          const Text(
                            'Open this form to submit issues/feedback!',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),
                    ],
                  ],
                ),
              ),

              Positioned(
                top: 135,
                right: 3,
                child: Opacity(
                  opacity: (_loaded && _changed) ? 1.0 : 0.55,
                  child: IgnorePointer(
                    ignoring: !(_loaded && _changed),
                    child: Material(
                      color: const Color(0xFF59FF56),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _save,
                        child: const SizedBox(
                          width: 400,
                          height: 40,
                          child: Center(
                            child: Text(
                              'Save',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
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
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  static const Color _card = Color(0xFF98404F);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
