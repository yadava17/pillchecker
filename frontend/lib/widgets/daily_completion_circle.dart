import 'dart:math' as math;
import 'package:flutter/material.dart';

class DailyCompletionCircle extends StatefulWidget {
  const DailyCompletionCircle({
    super.key,
    required this.done,
    required this.size,
    this.baseColor = const Color(0xFFE72447), // red
    this.fillColor = const Color(0xFF59FF56), // green
    this.duration = const Duration(milliseconds: 650),
  });

  final bool done;
  final double size;
  final Color baseColor;
  final Color fillColor;
  final Duration duration;

  @override
  State<DailyCompletionCircle> createState() => _DailyCompletionCircleState();
}

class _DailyCompletionCircleState extends State<DailyCompletionCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();

    // If already done when built, show final (filled) state instantly.
    if (widget.done) {
      _ctrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant DailyCompletionCircle oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If we just became done, play fill animation.
    if (!oldWidget.done && widget.done) {
      _ctrl.value = 0.0;
      _ctrl.forward();
    }

    // If we reset back to not done, snap back to empty.
    if (oldWidget.done && !widget.done) {
      _ctrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final p = widget.done ? _ctrl.value : 0.0;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _DailyFillPainter(
              progress: p,
              baseColor: widget.baseColor,
              fillColor: widget.fillColor,
            ),
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: (p >= 0.999) ? 1.0 : 0.0,
                child: Icon(
                  Icons.check,
                  size: widget.size * 0.55,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DailyFillPainter extends CustomPainter {
  _DailyFillPainter({
    required this.progress,
    required this.baseColor,
    required this.fillColor,
  });

  final double progress; // 0..1
  final Color baseColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    // Base red
    canvas.drawCircle(c, r, Paint()..color = baseColor);

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;

    // Full fill: paint solid green (no seam)
    if (p >= 0.999) {
      canvas.drawCircle(c, r, Paint()..color = fillColor);
      return;
    }

    // Pie fill
    final rect = Rect.fromCircle(center: c, radius: r);
    final start = -math.pi / 2;
    final sweep = (math.pi * 2) * p;

    canvas.drawArc(rect, start, sweep, true, Paint()..color = fillColor);
  }

  @override
  bool shouldRepaint(covariant _DailyFillPainter old) {
    return old.progress != progress ||
        old.baseColor != baseColor ||
        old.fillColor != fillColor;
  }
}
