import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pillchecker/backend/rxnorm/medication_summary.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';
import 'package:pillchecker/models/pill_search_item.dart';

class PillSearchPanel extends StatefulWidget {
  const PillSearchPanel({
    super.key,
    required this.rxNormService,
    required this.placeholderItems,
    required this.onPickCustom,
    required this.onPickItem,
    required this.onClose,
    required this.disabledNamesLower,
    this.initialQuery = '',
  });

  final RxNormMedicationService rxNormService;

  /// Bundled on-device names — filtered for any query length; merged with
  /// RxNorm results when online. Works fully offline without internet.
  final List<PillSearchItem> placeholderItems;

  final VoidCallback onPickCustom;
  final ValueChanged<PillSearchItem> onPickItem;
  final VoidCallback onClose;
  final String initialQuery;
  final Set<String> disabledNamesLower;

  @override
  State<PillSearchPanel> createState() => _PillSearchPanelState();
}

class _PillSearchPanelState extends State<PillSearchPanel> {
  static const cardColor = Color(0xFF98404F);
  static const white = Color(0xFFFFFFFF);

  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialQuery,
  );

  Timer? _debounce;
  bool _loading = false;
  List<MedicationSummary> _rxResults = [];
  bool _servedFromCache = false;
  bool _hadNetworkError = false;

  String get _q => _ctrl.text.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {});
    _debounce?.cancel();
    final query = _q;
    if (query.length < 2) {
      setState(() {
        _loading = false;
        _rxResults = [];
        _servedFromCache = false;
        _hadNetworkError = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _rxResults = [];
    });
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      final outcome = await widget.rxNormService.searchMedications(query);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rxResults = outcome.items;
        _servedFromCache = outcome.servedFromCache;
        _hadNetworkError = outcome.hadNetworkError;
      });
    });
  }

  List<PillSearchItem> get _placeholderFiltered {
    final q = _q.toLowerCase();
    if (q.isEmpty) return widget.placeholderItems;
    return widget.placeholderItems
        .where((p) => p.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  /// Same filter as [_placeholderFiltered] but only used when [useRx] (2+ chars).
  List<PillSearchItem> get _offlineLongQueryMatches => _placeholderFiltered;

  List<PillSearchItem> get _rxAsItems {
    return _rxResults.map((m) {
      final sub = m.subtitle ??
          [
            if (m.genericName != null) m.genericName,
            if (m.strength != null) m.strength,
            if (m.doseForm != null) m.doseForm,
          ].whereType<String>().join(' • ');
      return PillSearchItem(
        name: m.displayName,
        suggestedTimesPerDay: 2,
        info: '',
        rxcui: m.rxcui,
        searchSubtitle: sub.isEmpty ? null : sub,
        isFromCache: _servedFromCache,
      );
    }).toList();
  }

  /// RxNorm rows first, then on-device suggestions that are not duplicates.
  List<PillSearchItem> get _mergedRxAndOffline {
    final rx = _rxAsItems;
    final seen = rx.map((e) => e.name.trim().toLowerCase()).toSet();
    final out = [...rx];
    for (final o in _offlineLongQueryMatches) {
      final k = o.name.trim().toLowerCase();
      if (seen.add(k)) out.add(o);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final useRx = q.length >= 2;
    final items = useRx ? _mergedRxAndOffline : _placeholderFiltered;
    final hasOfflineMatches = _offlineLongQueryMatches.isNotEmpty;
    final showOfflineOnlyBanner =
        useRx && _hadNetworkError && _rxResults.isEmpty && hasOfflineMatches;
    final showNoMatchesBanner = useRx &&
        !_loading &&
        items.isEmpty &&
        !hasOfflineMatches;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: cardColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              autofocus: false,
                              decoration: const InputDecoration(
                                hintText: 'Search medicines…',
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => _onQueryChanged(),
                            ),
                          ),
                          if (_ctrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _ctrl.clear();
                                _onQueryChanged();
                              },
                              child: const Icon(Icons.close, color: cardColor),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _iconBtn(icon: Icons.close, onTap: widget.onClose),
                ],
              ),
              const SizedBox(height: 10),
              if (showOfflineOnlyBanner)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Offline — showing built-in medication names below. Pick one to add, or use Custom pill.',
                      style: TextStyle(
                        color: Colors.teal.shade900,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              if (useRx && _servedFromCache && _rxResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Showing saved search results — connect to refresh from the medicine directory.',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 18),
                  children: [
                    _resultTile(
                      title: 'Custom pill',
                      subtitle: 'Enter details yourself (no online lookup)',
                      leading: const Icon(Icons.add, color: white),
                      onTap: widget.onPickCustom,
                    ),
                    const SizedBox(height: 10),
                    if (useRx && _loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (showNoMatchesBanner)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _hadNetworkError
                              ? 'Can\'t reach the online medicine directory. No on-device names matched — try a different spelling, or add a Custom pill.'
                              : 'No matches from the online directory or on-device list. Try another spelling or use Custom pill.',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    if (!useRx)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Type at least 2 letters to search (on-device + online when available), or pick below.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    for (final p in items) ...[
                      Builder(
                        builder: (_) {
                          final isDup = widget.disabledNamesLower.contains(
                            p.name.trim().toLowerCase(),
                          );
                          final subtitle = useRx
                              ? (isDup
                                  ? 'Already added'
                                  : (p.isRxNorm
                                      ? (p.searchSubtitle ??
                                          (p.isFromCache
                                              ? 'Saved lookup • tap to review'
                                              : 'Online directory • tap to review'))
                                      : 'On-device suggestion • tap to add'))
                              : (isDup
                                  ? 'Already added'
                                  : '${p.suggestedTimesPerDay}× per day • Tap to add');

                          return Opacity(
                            opacity: isDup ? 0.45 : 1.0,
                            child: _resultTile(
                              title: p.name,
                              subtitle: subtitle,
                              leading: Image.asset(
                                'assets/images/pill_placeholder.png',
                                width: 34,
                                height: 34,
                                fit: BoxFit.contain,
                              ),
                              onTap: isDup ? () {} : () => widget.onPickItem(p),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (!useRx && items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Text(
                          'No on-device names match. Type more letters or use Custom pill.',
                          style: TextStyle(color: Colors.white70),
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

  Widget _resultTile({
    required String title,
    required String subtitle,
    required Widget leading,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          decoration: BoxDecoration(
            color: cardColor.withOpacity(0.88),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: leading,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: cardColor),
        ),
      ),
    );
  }
}
