import 'dart:math' as math;
import 'package:flutter/material.dart';

class PillCheckButton extends StatefulWidget {
  const PillCheckButton({
    super.key,
    required this.checked,
    required this.onChecked,
    this.size = 135,
    this.baseColor = const Color(0xFFFF002E), // bright red
    this.fillColor = const Color(0xFF59FF56), // ✅ match outer green (#59FF56)
  });

  final bool checked;
  final VoidCallback onChecked;
  final double size;
  final Color baseColor;
  final Color fillColor;

  @override
  State<PillCheckButton> createState() => _PillCheckButtonState();
}

class _PillCheckButtonState extends State<PillCheckButton>
    with TickerProviderStateMixin {
  // Hold-to-fill controller (~2s)
  late final AnimationController _holdCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  // Pop when completed
  late final AnimationController _popCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  bool _isHolding = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();

    // ✅ If already checked on startup, show it in the fully "popped" final state
    if (widget.checked) {
      _holdCtrl.value = 1.0;
      _popCtrl.value = 1.0; // THIS is the missing piece
      _fired = true;
    }

    _holdCtrl.addStatusListener((status) async {
      if (status == AnimationStatus.completed && !_fired && !widget.checked) {
        _fired = true;

        widget.onChecked();

        _popCtrl.value = 0;
        await _popCtrl.forward();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PillCheckButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If parent resets checked -> clear animations
    if (oldWidget.checked && !widget.checked) {
      _fired = false;
      _isHolding = false;
      _holdCtrl.value = 0;
      _popCtrl.value = 0;
    }

    if (!oldWidget.checked && widget.checked) {
      _holdCtrl.value = 1.0;
      _popCtrl.value = 1.0; // ✅ keep same final size even after rebuilds
    }

    // If parent sets checked true, force full fill
    if (!oldWidget.checked && widget.checked) {
      _holdCtrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _popCtrl.dispose();
    super.dispose();
  }

  void _startHold() {
    if (widget.checked) return;
    _isHolding = true;
    _fired = false;

    // fill up while holding
    _holdCtrl.forward();
    setState(() {});
  }

  void _endHold() {
    if (widget.checked) return;

    _isHolding = false;

    // if not finished, drain back down
    if (_holdCtrl.value < 1.0) {
      _holdCtrl.reverseDuration = const Duration(milliseconds: 350);
      _holdCtrl.reverse();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final popScale = Tween<double>(begin: 1.0, end: 1.16).animate(
      // ✅ bigger pop
      CurvedAnimation(parent: _popCtrl, curve: Curves.easeOutBack),
    );

    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _endHold(),
      onTapCancel: _endHold,
      child: AnimatedBuilder(
        animation: Listenable.merge([_holdCtrl, _popCtrl]),
        builder: (context, _) {
          final progress = widget.checked ? 1.0 : _holdCtrl.value;

          // If your dark red ring is 155 and this button is 135:
          // 155 / 135 = 1.148...
          const coverScale = 155.0 / 135.0; // adjust if you change sizes later

          final baseScale = widget.checked ? coverScale : 1.0;

          // When checked, still allow the pop to add on top of the cover scale
          final scaleValue = widget.checked
              ? (baseScale * popScale.value)
              : 1.0;

          return Transform.scale(
            scale: scaleValue,
            child: SizedBox(
              width: widget.size,
              height: widget.size,

              child: CustomPaint(
                painter: _PieFillPainter(
                  progress: progress,
                  baseColor: widget.baseColor,
                  fillColor: widget.fillColor,
                ),
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: (progress >= 1.0) ? 1.0 : 0.0,
                    child: CustomPaint(
                      size: Size(widget.size * 0.55, widget.size * 0.55),
                      painter: _CheckPainter(), // ✅ thicker check
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PieFillPainter extends CustomPainter {
  _PieFillPainter({
    required this.progress,
    required this.baseColor,
    required this.fillColor,
  });

  final double progress;
  final Color baseColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    // Base (red)
    canvas.drawCircle(c, r, Paint()..color = baseColor);

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;

    // ✅ If full, just paint solid green to guarantee it covers all red (no seam)
    if (p >= 0.999) {
      canvas.drawCircle(c, r, Paint()..color = fillColor);
      return;
    }

    // Fill pie while holding
    final rect = Rect.fromCircle(center: c, radius: r);
    final start = -math.pi / 2;
    final sweep = (math.pi * 2) * p;

    canvas.drawArc(rect, start, sweep, true, Paint()..color = fillColor);
  }

  @override
  bool shouldRepaint(covariant _PieFillPainter old) {
    return old.progress != progress ||
        old.baseColor != baseColor ||
        old.fillColor != fillColor;
  }
}

class _CheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ✅ Thick white checkmark
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          size.width *
          0.16 // thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Simple check shape (relative)
    path.moveTo(size.width * 0.12, size.height * 0.55);
    path.lineTo(size.width * 0.40, size.height * 0.78);
    path.lineTo(size.width * 0.88, size.height * 0.22);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
