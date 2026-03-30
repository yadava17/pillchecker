import 'dart:math' as math;
import 'package:flutter/material.dart';

class DoseProgressSideBar extends StatelessWidget {
  const DoseProgressSideBar({
    super.key,
    required this.totalDoses,
    required this.activeDoseIndex,
    required this.checkedMask,
    this.height = 68,
  });

  final int totalDoses; // 2..6 for your use case
  final int activeDoseIndex; // current dose window index
  final int checkedMask; // bitmask from HomeScreen check map
  final double height;

  int _bitCount(int x) {
    var n = 0;
    while (x != 0) {
      x &= (x - 1);
      n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final doses = totalDoses.clamp(2, 6);
    final checkedCount = _bitCount(checkedMask).clamp(0, doses);
    final complete = checkedCount >= doses;
    final safeDoseIndex = activeDoseIndex.clamp(0, doses - 1);

    final label = complete
        ? 'Completed all doses!'
        : 'Dose ${safeDoseIndex + 1}/$doses';

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color.fromARGB(100, 255, 255, 255),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color.fromARGB(100, 255, 255, 255),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(46, 46),
                  painter: _DosePiePainter(
                    totalDoses: doses,
                    checkedMask: checkedMask,
                  ),
                ),
                if (complete)
                  const Icon(
                    Icons.check_rounded,
                    size: 24,
                    color: Colors.white,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: complete ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                fontFamily: 'Amaranth',
                fontSize: complete ? 16 : 18,
                color: const Color(0xFF98404F),
                fontWeight: FontWeight.w700,
                height: complete ? 0.95 : 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DosePiePainter extends CustomPainter {
  _DosePiePainter({required this.totalDoses, required this.checkedMask});

  final int totalDoses;
  final int checkedMask;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final sliceSweep = (math.pi * 2) / totalDoses;
    const startAngleBase = -math.pi / 2;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < totalDoses; i++) {
      final filled = (checkedMask & (1 << i)) != 0;

      fillPaint.color = filled
          ? const Color(0xFF59FF56)
          : const Color.fromARGB(90, 255, 255, 255);

      canvas.drawArc(
        rect,
        startAngleBase + (sliceSweep * i),
        sliceSweep,
        true,
        fillPaint,
      );
    }

    int checkedCount = 0;
    int tempMask = checkedMask;
    while (tempMask != 0) {
      tempMask &= (tempMask - 1);
      checkedCount++;
    }
    final complete = checkedCount >= totalDoses;

    if (!complete) {
      final dividerPaint = Paint()
        ..color = const Color(0xFF98404F)
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke;

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
          ..strokeWidth = 1.7
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DosePiePainter oldDelegate) {
    return oldDelegate.totalDoses != totalDoses ||
        oldDelegate.checkedMask != checkedMask;
  }
}
