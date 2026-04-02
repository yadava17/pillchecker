import 'dart:io' show Platform;
import 'package:flutter/material.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  static const Color _bg = Color(0xffcf5c71);
  static const Color _topBar = Color(0xFFFF6D87);
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);

  static const List<String> _names = [
    'Jacob Cavell',
    'Aaditya Yadav',
    'Tamer Zidan',
    'Terence Bazzell',
    'Siddhant Yadav',
  ];

  @override
  Widget build(BuildContext context) {
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
              top: Platform.isAndroid ? 10 : 0,
              left: Platform.isAndroid ? 112 : 82,
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
            Positioned(
              top: Platform.isAndroid ? 23 : 34,
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
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                color: const Color.fromARGB(255, 60, 59, 59),
                iconSize: 40,
              ),
            ),
            Positioned.fill(
              top: 65,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 70, 18, 18),
                children: [
                  const Text(
                    'Credits',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _card,
                      fontFamily: 'Amaranth',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Team PillChecker',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (int i = 0; i < _names.length; i++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              _names[i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (i < _names.length - 1)
                            Divider(
                              height: 1,
                              color: Colors.white.withOpacity(0.16),
                            ),
                        ],
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'Thank you for using PillChecker!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
    );
  }
}
