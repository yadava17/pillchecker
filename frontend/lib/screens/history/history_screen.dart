import 'package:flutter/material.dart';

import 'package:pillchecker/backend/models/history_entry.dart';
import 'package:pillchecker/backend/services/adherence_service.dart';

/// Read-only adherence history from SQLite ([adherence_logs] + dose_events).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final AdherenceService _adherence = AdherenceService();
  List<HistoryEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _adherence.fetchHistory(limit: 300);
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmt(DateTime d) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour;
    final am = h < 12;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${months[d.month - 1]} ${d.day}, ${d.year} • $h12:${d.minute.toString().padLeft(2, '0')} ${am ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xffcf5c71);
    const topBar = Color(0xFFFF6D87);
    const divider = Color.fromARGB(255, 158, 52, 69);
    const card = Color(0xFF98404F);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(left: 0, right: 0, top: 0, child: Container(height: 115, color: topBar)),
            Positioned(left: 0, right: 0, top: 115, child: Container(height: 5, color: divider)),
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
              top: 120,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _entries.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 80),
                                Center(
                                  child: Text(
                                    'No history yet.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 18,
                                      fontFamily: 'Amaranth',
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _entries.length,
                              itemBuilder: (context, i) {
                                final e = _entries[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: card,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.medicationName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'Amaranth',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Planned: ${_fmt(e.plannedAtLocal)}',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.85),
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (e.loggedAtLocal != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Logged: ${_fmt(e.loggedAtLocal!)}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Text(
                                          e.displayStatus,
                                          style: TextStyle(
                                            color: e.isOverridden
                                                ? const Color(0xFFFFDF59)
                                                : const Color(0xFF59FF56),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'Amaranth',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
            const Positioned(
              top: 36,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'History',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: card,
                    fontFamily: 'Amaranth',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
