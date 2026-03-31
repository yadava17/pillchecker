import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// Weekly pillbox organizer driven by a Rive State Machine (Rive runtime 0.14+).
///
/// Assumptions (based on what you told me):
/// - You have a State Machine in the .riv (recommended).
/// - You created trigger inputs named: "SUN_OPEN", "MON_OPEN", ... (3-letter day, OPEN).
///
/// Optional (highly recommended):
/// - Also create close triggers: "SUN_CLOSE", "MON_CLOSE", ...
///   If you don't, Flutter *cannot* magically reverse a trigger-driven state machine.
///   (Reversing is only a thing for direct timeline playback; 0.14 discourages that.)
class WeeklyPillboxOrganizer extends StatefulWidget {
  const WeeklyPillboxOrganizer({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,

    /// State machine name inside Rive.
    /// If you only have 1 state machine, you can leave this null
    /// and we’ll just use the controller’s selected machine if available.
    this.stateMachineName,

    /// If provided, this set controls which days should be open.
    /// Example: {0, 2} => Sunday + Tuesday open.
    this.openDays = const <int>{},

    /// If true, will attempt to close days not in [openDays] (requires CLOSE triggers).
    this.autoCloseOthers = true,

    this.onOpenFired,
    this.openAnimDuration = const Duration(milliseconds: 650),
  });

  final void Function(int dayIndex)? onOpenFired;
  final Duration openAnimDuration;

  final double? width;
  final double? height;
  final BoxFit fit;

  final String? stateMachineName;

  /// 0..6 => Sun..Sat
  final Set<int> openDays;

  final bool autoCloseOthers;

  @override
  State<WeeklyPillboxOrganizer> createState() => WeeklyPillboxOrganizerState();
}

class WeeklyPillboxOrganizerState extends State<WeeklyPillboxOrganizer> {
  static const _assetPath = 'assets/rive/pillbox.riv';

  late final FileLoader _loader = FileLoader.fromAsset(
    _assetPath,
    riveFactory: Factory.rive,
  );

  RiveWidgetController? _controller;

  // In 0.14.x we don't cache TriggerInput objects.
  // We'll just call sm.trigger(name) when we need it.
  StateMachine? _sm;

  // Track last applied open set so we only fire on changes
  Set<int> _lastOpenDays = <int>{};

  static const List<String> _day3 = [
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];

  @override
  void initState() {
    super.initState();
    _lastOpenDays = Set<int>.from(widget.openDays);
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WeeklyPillboxOrganizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If openDays changed, apply once we're loaded.
    if (!_setEquals(oldWidget.openDays, widget.openDays)) {
      _applyOpenSet(widget.openDays);
    }
  }

  bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  void _onLoaded(RiveWidgetController controller) {
    _controller = controller;

    final sm = controller.stateMachine;
    if (sm == null) return;

    _sm = sm;

    _lastOpenDays = <int>{};
    _applyOpenSet(widget.openDays, initial: true);
  }

  /// Public helpers (optional):
  void openDay(int dayIndex) => _fire('${_day3[dayIndex]}_OPEN');
  void closeDay(int dayIndex) => _fire('${_day3[dayIndex]}_CLOSE');

  void _fire(String triggerName) {
    final sm = _sm;
    if (sm == null) return;

    final trig = sm.trigger(triggerName);
    if (trig == null) {
      debugPrint('Rive: trigger not found: $triggerName');
      return;
    }
    trig.fire();
  }

  void _applyOpenSet(Set<int> desired, {bool initial = false}) {
    if (_sm == null) return;

    final toOpen = <int>{...desired}..removeAll(_lastOpenDays);
    final toClose = <int>{..._lastOpenDays}..removeAll(desired);

    if (widget.autoCloseOthers) {
      for (final idx in toClose) {
        if (idx < 0 || idx > 6) continue;
        _fire('${_day3[idx]}_CLOSE');
      }
    }

    for (final idx in toOpen) {
      if (idx < 0 || idx > 6) continue;
      _fire('${_day3[idx]}_OPEN');
      widget.onOpenFired?.call(idx); // ✅ notify HomeScreen
    }

    _lastOpenDays = Set<int>.from(desired);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: RiveWidgetBuilder(
        fileLoader: _loader,
        builder: (context, state) {
          return switch (state) {
            RiveLoading() => const Center(child: CircularProgressIndicator()),
            RiveFailed() => Center(child: Text('Rive failed: ${state.error}')),
            RiveLoaded() => _buildLoaded(state.controller),
          };
        },
      ),
    );
  }

  Widget _buildLoaded(RiveWidgetController controller) {
    // Run once (first time we see loaded controller)
    if (!identical(_controller, controller)) {
      _onLoaded(controller);
    }

    return RiveWidget(controller: controller, fit: Fit.contain);
  }
}
