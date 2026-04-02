import 'dart:math' as math;
import 'package:flutter/material.dart';

class MultiDoseOverrideDialog extends StatefulWidget {
  const MultiDoseOverrideDialog({
    super.key,
    required this.pillName,
    required this.totalDoses,
    required this.initialTakenMask,
    required this.onDone,
  });

  final String pillName;
  final int totalDoses;
  final int initialTakenMask;
  final Future<void> Function(int takenMask) onDone;

  @override
  State<MultiDoseOverrideDialog> createState() =>
      _MultiDoseOverrideDialogState();
}

class _MultiDoseOverrideDialogState extends State<MultiDoseOverrideDialog> {
  late int _takenMask;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _takenMask = widget.initialTakenMask;
  }

  void _toggleSlice(int index) {
    setState(() {
      _takenMask ^= (1 << index);
    });
  }

  int? _sliceIndexFromOffset(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final radius = math.min(size.width, size.height) / 2;

    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance > radius) return null;

    var angle = math.atan2(dy, dx) + (math.pi / 2);
    if (angle < 0) angle += math.pi * 2;

    final sliceSweep = (math.pi * 2) / widget.totalDoses;
    return (angle / sliceSweep).floor().clamp(0, widget.totalDoses - 1);
  }

  @override
  Widget build(BuildContext context) {
    const card = Color(0xFF98404F);
    const green = Color(0xFF59FF56);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Override doses',
              style: const TextStyle(
                fontFamily: 'Amaranth',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.pillName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size.square(
                    math.min(constraints.maxWidth, constraints.maxHeight),
                  );

                  return GestureDetector(
                    onTapDown: _saving
                        ? null
                        : (details) {
                            final idx = _sliceIndexFromOffset(
                              details.localPosition,
                              size,
                            );
                            if (idx != null) {
                              _toggleSlice(idx);
                            }
                          },
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: CustomPaint(
                        painter: _OverridePiePainter(
                          totalDoses: widget.totalDoses,
                          takenMask: _takenMask,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tap a slice to switch between taken and missed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    color: green,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              await widget.onDone(_takenMask);
                              if (!mounted) return;
                              Navigator.pop(context);
                            },
                      child: const SizedBox(
                        height: 52,
                        child: Center(
                          child: Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverridePiePainter extends CustomPainter {
  _OverridePiePainter({
    required this.totalDoses,
    required this.takenMask,
  });

  final int totalDoses;
  final int takenMask;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sliceSweep = (math.pi * 2) / totalDoses;
    const startAngleBase = -math.pi / 2;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final dividerPaint = Paint()
      ..color = const Color(0xFF98404F)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < totalDoses; i++) {
      final taken = (takenMask & (1 << i)) != 0;

      fillPaint.color = taken
          ? const Color(0xFF59FF56)
          : const Color(0xFFFF002E);

      final start = startAngleBase + (sliceSweep * i);
      canvas.drawArc(rect, start, sliceSweep, true, fillPaint);

      final mid = start + (sliceSweep / 2);
      final labelRadius = radius * 0.58;
      final labelOffset = Offset(
        center.dx + math.cos(mid) * labelRadius,
        center.dy + math.sin(mid) * labelRadius,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.22,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(
          labelOffset.dx - tp.width / 2,
          labelOffset.dy - tp.height / 2,
        ),
      );
    }

    for (int i = 0; i < totalDoses; i++) {
      final angle = startAngleBase + (sliceSweep * i);
      final end = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, end, dividerPaint);
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF98404F)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _OverridePiePainter oldDelegate) {
    return oldDelegate.totalDoses != totalDoses ||
        oldDelegate.takenMask != takenMask;
  }
}