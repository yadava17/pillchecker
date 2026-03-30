import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';

class PillWheel extends StatefulWidget {
  const PillWheel({
    super.key,
    required this.displayPillCount,
    required this.realPillCount,
    required this.controller,
    required this.onAddPressed,
    required this.scrollEnabled,
    required this.addEnabled,
    required this.onSelectedChanged,
    required this.onDeleteCentered,
  });

  final int displayPillCount; // (not counting +)
  final int realPillCount; // (not counting +)
  final FixedExtentScrollController controller;
  final VoidCallback onAddPressed;
  final bool scrollEnabled;
  final bool addEnabled;

  final ValueChanged<int> onSelectedChanged;
  final VoidCallback onDeleteCentered;

  @override
  State<PillWheel> createState() => _PillWheelState();
}

class _NoOverscrollBehavior extends ScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // no glow / stretch
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

class _PillWheelState extends State<PillWheel> {
  int _selectedIndex = 1;
  double _currentItem = 1.0;

  // Which wheel index is currently being held for delete UI
  int? _holdIndex;
  Timer? _holdTimer;

  // DO NOT CHANGE
  static const double _itemExtent = 75;

  // How long user must hold before delete triggers
  static const Duration _deleteHoldDuration = Duration(milliseconds: 900);

  @override
  void didUpdateWidget(covariant PillWheel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the wheel count changed (delete/add), resync indices safely
    if (oldWidget.displayPillCount != widget.displayPillCount ||
        oldWidget.realPillCount != widget.realPillCount) {
      final totalCount = 1 + widget.displayPillCount;
      final maxIndex = (totalCount - 1).clamp(0, 999999);

      final safeSelected = widget.controller.selectedItem.clamp(0, maxIndex);

      setState(() {
        _selectedIndex = safeSelected;
        _currentItem = safeSelected.toDouble();
        _holdIndex = null; // if you're using the hold-to-delete indicator
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.controller.initialItem;
    _currentItem = _selectedIndex.toDouble();
  }

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_holdIndex != null) {
      setState(() => _holdIndex = null);
    }
  }

  void _startHoldToDelete(int index, {required bool isCentered}) {
    if (!isCentered) return;

    // show indicator immediately
    setState(() => _holdIndex = index);

    _holdTimer?.cancel();
    _holdTimer = Timer(_deleteHoldDuration, () {
      if (!mounted) return;

      // Only trigger if still holding the same centered pill
      if (_holdIndex == index && _selectedIndex == index) {
        widget.onDeleteCentered();
      }

      // remove indicator after triggering
      _cancelHold();
    });
  }

  void _snapTo(int index) {
    // Ignore if it’s already centered
    if (index == _selectedIndex) return;

    // Animate wheel to that item
    widget.controller.animateToItem(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = 1 + widget.displayPillCount; // index 0 is "+"

    return RotatedBox(
      quarterTurns: 3,
      child: ScrollConfiguration(
        behavior: const _NoOverscrollBehavior(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final totalCount = 1 + widget.displayPillCount;
            final maxIndex = (totalCount - 1).clamp(0, 999999);

            final raw = widget.controller.offset / _itemExtent;
            final current = raw.clamp(0.0, maxIndex.toDouble());

            if ((current - _currentItem).abs() > 0.0001) {
              setState(() => _currentItem = current);
            }

            // scrolling cancels hold-to-delete
            if (_holdIndex != null) _cancelHold();

            return false;
          },
          child: ListWheelScrollView.useDelegate(
            controller: widget.controller,
            physics: widget.scrollEnabled
                ? const FixedExtentScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  )
                : const NeverScrollableScrollPhysics(),
            itemExtent: _itemExtent,
            perspective: 0.0001,
            diameterRatio: 100,
            onSelectedItemChanged: (index) {
              setState(() => _selectedIndex = index);
              widget.onSelectedChanged(index);

              // selection change cancels hold-to-delete
              if (_holdIndex != null) _cancelHold();
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: 1 + widget.displayPillCount, // index 0 is "+"
              builder: (context, index) {
                final d = (index - _currentItem).abs();

                // KEEP YOUR ANGLE / CURVE EXACTLY
                final riseRaw = math.min(d, 3.0) * 35.0 * d;
                const maxAwayFromCenter = 250.0;
                final rise = riseRaw.clamp(0.0, maxAwayFromCenter);

                const neighborGap = 24.0;
                final gapFactor = (1.0 - (d - 1.0).abs()).clamp(0.0, 1.0);
                final riseWithGap = rise + neighborGap * gapFactor;

                const neighborPushX = 14.0;
                final side = (index - _currentItem).sign;
                final xPush = neighborPushX * gapFactor * side;

                final offset = Offset(-riseWithGap, xPush);

                final scale = (1.0 - d * 0.24).clamp(0.75, 1.0);
                final baseBoostedScale = (scale * 1.5) * 1.1.clamp(0.75, 1.15);

                // ✅ Android-only shrink (tweak this number: 0.9 = 10% smaller, 0.8 = 20% smaller)
                final androidWheelScale = Platform.isAndroid ? 0.9 : 1.0;

                final boostedScale = baseBoostedScale * androidWheelScale;

                // Determine if this pill circle is "real" (has icon) or "empty slot"
                final pillSlotIndex = index - 1; // 0..displayPillCount-1
                final isRealPill =
                    (index > 0) && (pillSlotIndex < widget.realPillCount);

                final isCentered = index == _selectedIndex;
                final isHolding = _holdIndex == index;

                // "+" circle
                if (index == 0) {
                  final plusCircle = Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFB4B4B4),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add,
                        size: 34,
                        color: Color(0xFF98404F),
                      ),
                    ),
                  );

                  final plusWrapped = GestureDetector(
                    onTap: widget.addEnabled ? widget.onAddPressed : null,
                    child: plusCircle,
                  );

                  return Transform.translate(
                    offset: offset,
                    child: Transform.scale(
                      scale: boostedScale,
                      child: RotatedBox(
                        quarterTurns: -1,
                        child: Center(child: plusWrapped),
                      ),
                    ),
                  );
                }

                // Pill / empty slot circle
                // ✅ Ring is INSIDE the 70x70 via border, so it won't get clipped by itemExtent.
                Widget circleCore = Stack(
                  alignment: Alignment.center,
                  children: [
                    // Base circle (NO border ever)
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCentered
                            ? const Color(0xFF98404F)
                            : const Color(0xFF8C1C2F),
                      ),
                      child: isRealPill
                          ? Center(
                              child: Image.asset(
                                'assets/images/pill_placeholder.png',
                                width: 50,
                                height: 50,
                                fit: BoxFit.contain,
                              ),
                            )
                          : null,
                    ),

                    // Ring overlay (ONLY visible while holding)
                    AnimatedOpacity(
                      duration: const Duration(
                        milliseconds: 260,
                      ), // longer fade
                      curve: Curves.easeInOut,
                      opacity: isHolding ? 1.0 : 0.0,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 2, // thin ring
                            color: const Color(0xFFFFDF59),
                          ),
                        ),
                      ),
                    ),
                  ],
                );

                // Keep your pop (slightly longer)
                circleCore = AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  scale: isHolding ? 1.06 : 1.0,
                  child: circleCore,
                );

                // Tap-to-center for any non-centered item.
                // Hold-to-delete only for centered REAL pills.
                circleCore = GestureDetector(
                  behavior: HitTestBehavior.opaque,

                  // ✅ tap selects/canters the pill if it's not centered
                  onTap: () {
                    if (!isCentered) _snapTo(index);
                  },

                  // ✅ hold-to-delete ONLY if it's a real pill AND currently centered
                  onTapDown: isRealPill && isCentered
                      ? (_) => _startHoldToDelete(index, isCentered: true)
                      : null,
                  onTapUp: isRealPill && isCentered
                      ? (_) => _cancelHold()
                      : null,
                  onTapCancel: isRealPill && isCentered ? _cancelHold : null,

                  child: circleCore,
                );

                return Transform.translate(
                  offset: offset,
                  child: Transform.scale(
                    scale: boostedScale,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: Center(child: circleCore),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
