import 'package:flutter/material.dart';

import 'package:pillchecker/backend/models/history_entry.dart';
import 'package:pillchecker/backend/services/adherence_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.adherenceService});

  final AdherenceService adherenceService;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _bg = Color(0xffcf5c71);
  static const Color _topBar = Color(0xFFFF6D87);
  static const Color _divider = Color.fromARGB(255, 158, 52, 69);
  static const Color _card = Color(0xFF98404F);
  static const Color _statusGreen = Color(0xFF59FF56);

  late Future<List<HistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.adherenceService.fetchHistory();
  }

  Future<void> _refresh() async {
    final next = widget.adherenceService.fetchHistory();
    setState(() => _future = next);
    await next;
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year} $hh:$mm $ampm';
  }

  Color _statusColor(String label) {
    if (label == 'Missed') return _statusGreen;
    if (label.startsWith('Taken')) return _statusGreen;
    return Colors.white;
  }

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
              child: Container(height: 74, color: _topBar),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 74,
              child: Container(height: 4, color: _divider),
            ),
            Positioned(
              top: 12,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                color: const Color.fromARGB(255, 60, 59, 59),
                iconSize: 30,
              ),
            ),
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'History',
                  style: TextStyle(
                    color: Color.fromARGB(255, 60, 59, 59),
                    fontSize: 30,
                    fontFamily: 'Amaranth',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: 82,
              child: FutureBuilder<List<HistoryEntry>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Could not load history.',
                              style: TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _refresh,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final items = snap.data ?? const <HistoryEntry>[];
                  if (items.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'No adherence history yet.\nTaken, missed, and overridden doses will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final e = items[i];
                        final status = e.displayStatus;
                        final logged = e.loggedAtLocal != null
                            ? _fmt(e.loggedAtLocal!)
                            : null;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.medicationName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontFamily: 'Amaranth',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Planned: ${_fmt(e.plannedAtLocal)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (logged != null)
                                Text(
                                  'Logged: $logged',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                status,
                                style: TextStyle(
                                  color: _statusColor(status),
                                  fontSize: 20,
                                  fontFamily: 'Amaranth',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
