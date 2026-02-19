import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pillchecker/constants/prefs_keys.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _bg = Color(0xFFC75469);
  static const Color _topBar = Color(0xFFFF6D87);
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);

  bool _loaded = false;

  String _mode = 'standard';
  int _earlyMin = 30;
  int _lateMin = 30;

  // keep originals so we can detect changes
  String _origMode = 'standard';
  int _origEarly = 30;
  int _origLate = 30;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final mode = prefs.getString(kNotifModeKey) ?? 'standard';
    final early = prefs.getInt(kEarlyLeadMinKey) ?? 30;
    final late = prefs.getInt(kLateAfterMinKey) ?? 30;

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
      _mode != _origMode || _earlyMin != _origEarly || _lateMin != _origLate;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
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
              top: -1,
              left: 0,
              right: 185,
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
                child: Transform.scale(
                  scale: 0.5,
                  child: Text(
                    'PillChecker',
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
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.arrow_back),
                color: const Color.fromARGB(255, 60, 59, 59),
                iconSize: 40,
              ),
            ),

            Positioned.fill(
              top: 115,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      _SectionCard(
                        title: 'Notifications',
                        children: [
                          const SizedBox(height: 6),

                          // MODE
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

                          // ✅ BOX CONTROLS (no sliders)
                          // Only enabled in Standard mode (Basic ignores early/late, Off ignores everything)
                          Builder(
                            builder: (context) {
                              const step = 5; // minutes per tap
                              const maxMin = 240; // 4 hours
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

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: Opacity(
                          opacity: _changed ? 1.0 : 0.55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF59FF56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _changed ? _save : null,
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
