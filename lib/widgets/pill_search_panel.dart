import 'package:flutter/material.dart';
import 'package:pillchecker/models/pill_search_item.dart';

class PillSearchPanel extends StatefulWidget {
  const PillSearchPanel({
    super.key,
    required this.items,
    required this.onPickCustom,
    required this.onPickItem,
    required this.onClose,
    required this.disabledNamesLower,
    this.initialQuery = '',
  });

  final List<PillSearchItem> items;

  /// “Custom pill” always appears and routes to your existing flow.
  final VoidCallback onPickCustom;

  /// User tapped a placeholder/RxNorm result.
  final ValueChanged<PillSearchItem> onPickItem;

  /// Close the search overlay.
  final VoidCallback onClose;

  final String initialQuery;

  final Set<String> disabledNamesLower; // lowercase pill names already added

  @override
  State<PillSearchPanel> createState() => _PillSearchPanelState();
}

class _PillSearchPanelState extends State<PillSearchPanel> {
  static const cardColor = Color(0xFF98404F);
  static const white = Color(0xFFFFFFFF);

  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialQuery,
  );

  String get _q => _ctrl.text.trim().toLowerCase();

  List<PillSearchItem> get _filtered {
    if (_q.isEmpty) return widget.items;
    return widget.items
        .where((p) => p.name.toLowerCase().contains(_q))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          // ✅ keeps the list usable when keyboard is up
          padding: EdgeInsets.only(
            left: 0,
            right: 0,
            top: 0,
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // --- Top row: Search bar + close ---
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
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: 'Search for a pill…',
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          if (_ctrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() => _ctrl.clear()),
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

              const SizedBox(height: 14),

              // --- Results list (ALWAYS scrollable) ---
              Expanded(
                child: ListView(
                  // ✅ ALWAYS scrollable (even when short)
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  // ✅ drag list to dismiss keyboard
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 18),
                  children: [
                    _resultTile(
                      title: 'Custom pill',
                      subtitle: 'Create your own pill (manual)',
                      leading: const Icon(Icons.add, color: white),
                      onTap: widget.onPickCustom,
                    ),
                    const SizedBox(height: 10),

                    for (final p in items) ...[
                      Builder(
                        builder: (_) {
                          final isDup = widget.disabledNamesLower.contains(
                            p.name.trim().toLowerCase(),
                          );

                          return Opacity(
                            opacity: isDup ? 0.45 : 1.0,
                            child: _resultTile(
                              title: p.name,
                              subtitle: isDup
                                  ? 'Already added'
                                  : '${p.suggestedTimesPerDay}× per day • Tap to add',
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

                    if (items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Text(
                          'No matches. Try a different search.',
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
          height: 70,
          decoration: BoxDecoration(
            color: cardColor.withOpacity(0.88),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
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
              const Icon(Icons.add, color: Colors.white, size: 34),
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
