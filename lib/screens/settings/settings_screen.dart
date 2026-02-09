import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const Color _bg = Color(0xFFC75469);
  static const Color _topBar = Color(0xFFFF6D87);
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _bg,
      body: SafeArea(
        // ✅ makes sure nothing gets hidden by the notch + keeps content below header
        child: Stack(
          children: [
            // ---- TOP BAR (match home vibe) ----
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

            // ---- LOGO (left) ----
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

            // ---- TITLE (center) ----
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

            // ---- BACK BUTTON (top-left, on top of header) ----
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

            // ---- SCROLLABLE CONTENT (✅ prevents overlap on small/tall phones) ----
            Positioned.fill(
              top: 115, // ✅ push content below the header area
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Optional "Settings" label under the header
                    const Text(
                      'Settings (NOT FUNCTIONAL)',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _card,
                        fontFamily: 'Amaranth',
                      ),
                    ),
                    const SizedBox(height: 18),

                    _SectionCard(
                      title: 'Notifications',
                      children: const [
                        _RowItem(label: 'Daily reminders', trailing: 'On'),
                        _RowItem(label: 'Exact alarms', trailing: 'Required'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _SectionCard(
                      title: 'App',
                      children: const [
                        _RowItem(label: 'Theme', trailing: 'Default'),
                        _RowItem(label: 'About', trailing: ''),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Bottom action placeholder
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(
                          child: Text(
                            'More coming soon',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // extra space so it never feels cramped at the bottom
                    const SizedBox(height: 12),
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

class _RowItem extends StatelessWidget {
  const _RowItem({required this.label, required this.trailing});

  final String label;
  final String trailing;

  static const Color _text = Colors.white;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.white70),
        ],
      ),
    );
  }
}
