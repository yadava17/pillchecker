import 'package:flutter/material.dart';
import 'package:rive/rive.dart';
import 'dart:async';

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
    this.closeRequestToken = 0,
    this.forceCloseDayIndex,
    this.reloadAfterManualReverse = true,

    /// Runtime speed boost for open animations.
    /// 1.0 = normal speed. 2.0 = about twice as fast.
    /// Keep this at 1.0 for the normal HomeScreen pillbox.
    this.openSpeedMultiplier = 1.0,
    this.openFinishSnapSeconds = 0.0,

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

  /// Increment this from HomeScreen when you want the current open tab to close.
  final int closeRequestToken;

  /// Which day to close when [closeRequestToken] changes. 0..6 = Sun..Sat.
  final int? forceCloseDayIndex;

  /// If manual reverse does not visibly close, reload the Rive widget closed.
  final bool reloadAfterManualReverse;

  /// Runtime speed boost for open animations.
  /// 1.0 = normal speed. 2.0 = about twice as fast.
  final double openSpeedMultiplier;

  /// Extra controller advance after each open animation.
  /// This helps force a flap into its final open pose before the next trigger.
  final double openFinishSnapSeconds;

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

  Timer? _reverseTimer;
  Timer? _snapClosedTimer;
  Timer? _openSpeedTimer;
  final List<Timer> _openTimers = <Timer>[];
  int _riveReloadToken = 0;

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
    _reverseTimer?.cancel();
    _snapClosedTimer?.cancel();
    _openSpeedTimer?.cancel();
    _cancelOpenTimers();
    _loader.dispose();
    super.dispose();
  }

  void _cancelOpenTimers() {
    for (final timer in _openTimers) {
      timer.cancel();
    }
    _openTimers.clear();
  }

  @override
  void didUpdateWidget(covariant WeeklyPillboxOrganizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final closeRequested =
        oldWidget.closeRequestToken != widget.closeRequestToken &&
        widget.forceCloseDayIndex != null;

    if (closeRequested) {
      debugPrint(
        'Rive forced close request: day=${widget.forceCloseDayIndex} '
        'token=${widget.closeRequestToken}',
      );

      _closeOrReverseDay(widget.forceCloseDayIndex!);

      // HomeScreen is requesting a closed pillbox state.
      _lastOpenDays = <int>{};
      return;
    }

    if (!_setEquals(oldWidget.openDays, widget.openDays)) {
      _applyOpenSet(widget.openDays, previousOverride: oldWidget.openDays);
    }
  }

  void _forceReloadClosedAfter(Duration delay) {
    _snapClosedTimer?.cancel();

    _snapClosedTimer = Timer(delay + const Duration(milliseconds: 180), () {
      if (!mounted) return;

      debugPrint('Rive: forcing closed reload fallback');

      setState(() {
        _riveReloadToken++;
        _controller = null;
        _sm = null;
        _lastOpenDays = <int>{};
      });
    });
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
  void closeDay(int dayIndex) => _closeOrReverseDay(dayIndex);

  bool _fire(String triggerName) {
    final sm = _sm;
    if (sm == null) return false;

    final trig = sm.trigger(triggerName);
    if (trig == null) {
      debugPrint('Rive: trigger not found: $triggerName');
      return false;
    }

    trig.fire();
    return true;
  }

  void _fireOpenDaysStaggered(Set<int> days) {
    _cancelOpenTimers();

    final ordered = days.where((idx) => idx >= 0 && idx <= 6).toList()..sort();

    final multiplier = widget.openSpeedMultiplier <= 1.0
        ? 1.0
        : widget.openSpeedMultiplier;

    // Rive timeline says the open animation is 00:00:35.
    // Treat this as 35 frames at 24 FPS, not 60 FPS.
    // 35 / 24 = ~1.458s normal speed.
    const openAnimFrames = 35.0;
    const riveTimelineFps = 24.0;

    final baseAnimMs = ((openAnimFrames / riveTimelineFps) * 1000).round();

    // Wall-clock time after runtime speed boost.
    final boostedAnimMs = (baseAnimMs / multiplier).round();

    // Tiny guard so the next trigger doesn't interrupt the last frame.
    const guardMs = 60;

    final stepMs = boostedAnimMs + guardMs;

    for (int i = 0; i < ordered.length; i++) {
      final idx = ordered[i];

      final timer = Timer(Duration(milliseconds: i * stepMs), () {
        if (!mounted) return;

        final triggerName = '${_day3[idx]}_OPEN';
        final worked = _fire(triggerName);

        if (worked) {
          _boostForwardOpenAnimation(
            estimatedNormalDuration: Duration(milliseconds: baseAnimMs),
          );

          widget.onOpenFired?.call(idx);
        }
      });

      _openTimers.add(timer);
    }
  }

  void _reverseCurrentRiveMotion({
    Duration duration = const Duration(milliseconds: 650),
  }) {
    final controller = _controller;
    if (controller == null) {
      debugPrint('Rive reverse skipped: controller is null');
      return;
    }

    _reverseTimer?.cancel();

    final stopwatch = Stopwatch()..start();
    var lastElapsed = Duration.zero;

    // Do NOT set controller.active = false here.
    // The normal Rive tick may still advance forward, so we push backward harder.
    const reverseSpeedMultiplier = 2.25;

    debugPrint('Rive reverse START duration=${duration.inMilliseconds}ms');

    _reverseTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final elapsed = stopwatch.elapsed;
      final delta = elapsed - lastElapsed;
      lastElapsed = elapsed;

      final dtSeconds = delta.inMicroseconds / Duration.microsecondsPerSecond;

      try {
        controller.advance(-dtSeconds * reverseSpeedMultiplier);
        controller.scheduleRepaint();
      } catch (e) {
        debugPrint('Rive reverse failed: $e');
        timer.cancel();
        return;
      }

      if (elapsed >= duration) {
        timer.cancel();

        try {
          controller.advance(0);
          controller.scheduleRepaint();
        } catch (_) {}

        debugPrint('Rive reverse END');
      }
    });
  }

  void _boostForwardOpenAnimation({required Duration estimatedNormalDuration}) {
    final controller = _controller;
    if (controller == null) {
      debugPrint('Rive speed boost skipped: controller is null');
      return;
    }

    final multiplier = widget.openSpeedMultiplier;

    // 1.0 means no boost. This keeps the normal HomeScreen pillbox untouched.
    if (multiplier <= 1.0) return;

    _openSpeedTimer?.cancel();

    // Flutter/Rive is already advancing normally at 1x.
    // We only add the EXTRA amount.
    final extraSpeed = multiplier - 1.0;

    final boostedDurationMs =
        (estimatedNormalDuration.inMilliseconds / multiplier).round();

    final boostDuration = Duration(
      milliseconds: boostedDurationMs.clamp(
        120,
        estimatedNormalDuration.inMilliseconds,
      ),
    );

    final stopwatch = Stopwatch()..start();
    var lastElapsed = Duration.zero;

    _openSpeedTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final elapsed = stopwatch.elapsed;
      final delta = elapsed - lastElapsed;
      lastElapsed = elapsed;

      final dtSeconds = delta.inMicroseconds / Duration.microsecondsPerSecond;

      try {
        controller.advance(dtSeconds * extraSpeed);
        controller.scheduleRepaint();
      } catch (e) {
        debugPrint('Rive open speed boost failed: $e');
        timer.cancel();
        return;
      }

      if (elapsed >= boostDuration) {
        timer.cancel();

        try {
          controller.advance(0);
          controller.scheduleRepaint();
        } catch (_) {}
      }
    });
  }

  void _snapCurrentOpenAnimationToEnd() {
    final controller = _controller;
    if (controller == null) return;

    final snapSeconds = widget.openFinishSnapSeconds;
    if (snapSeconds <= 0) return;

    try {
      controller.advance(snapSeconds);
      controller.scheduleRepaint();
    } catch (e) {
      debugPrint('Rive open finish snap failed: $e');
    }
  }

  void _closeOrReverseDay(int dayIndex) {
    if (dayIndex < 0 || dayIndex > 6) return;

    final closeName = '${_day3[dayIndex]}_CLOSE';
    final closeWorked = _fire(closeName);

    if (closeWorked) {
      debugPrint('Rive close trigger fired: $closeName');
      return;
    }

    debugPrint(
      'Rive close trigger missing: $closeName — trying manual reverse',
    );

    _reverseCurrentRiveMotion(duration: widget.openAnimDuration);

    // Safety fallback: if the runtime does not visually reverse the state machine,
    // reload the Rive widget back to its default closed state before it shrinks.
    if (widget.reloadAfterManualReverse) {
      _forceReloadClosedAfter(widget.openAnimDuration);
    }
  }

  void _applyOpenSet(
    Set<int> desired, {
    bool initial = false,
    Set<int>? previousOverride,
  }) {
    if (_sm == null) return;

    final previous = previousOverride ?? _lastOpenDays;

    final toOpen = <int>{...desired}..removeAll(previous);
    final toClose = <int>{...previous}..removeAll(desired);

    debugPrint(
      'Rive openDays change: previous=$previous desired=$desired '
      'toOpen=$toOpen toClose=$toClose initial=$initial',
    );

    _cancelOpenTimers();

    if (widget.autoCloseOthers) {
      for (final idx in toClose) {
        _closeOrReverseDay(idx);
      }
    }

    // If only one tab is opening, keep normal behavior for the main HomeScreen pillbox.
    if (toOpen.length <= 1) {
      for (final idx in toOpen) {
        if (idx < 0 || idx > 6) continue;

        final triggerName = '${_day3[idx]}_OPEN';
        final worked = _fire(triggerName);

        debugPrint(
          'Rive single open: day=$idx trigger=$triggerName worked=$worked',
        );

        if (worked) {
          _boostForwardOpenAnimation(
            estimatedNormalDuration: widget.openAnimDuration,
          );
          widget.onOpenFired?.call(idx);
        }
      }
    } else {
      // Multiple tabs need time between triggers or Rive may ignore/overwrite them.
      _fireOpenDaysStaggered(toOpen);
    }

    _lastOpenDays = Set<int>.from(desired);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: RiveWidgetBuilder(
        key: ValueKey('pillbox_rive_reload_$_riveReloadToken'),
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
