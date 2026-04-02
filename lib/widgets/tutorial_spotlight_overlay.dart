import 'package:flutter/material.dart';

class TutorialSpotlightOverlay extends StatelessWidget {
  const TutorialSpotlightOverlay({
    super.key,
    required this.targetRect,
    required this.title,
    required this.description,
    required this.stepNumber,
    required this.totalSteps,
    required this.onNext,
    required this.onClose,
    this.onBack,
    this.isLast = false,
    this.cardAtTop = false,
  });

  final Rect targetRect;
  final String title;
  final String description;
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final bool isLast;
  final bool cardAtTop;

  @override
  Widget build(BuildContext context) {
    final holeRect = targetRect.inflate(10);

    final card = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF98404F),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tutorial $stepNumber/$totalSteps',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              fontFamily: 'Amaranth',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed: onClose,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              if (onBack != null) ...[
                TextButton(
                  onPressed: onBack,
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Material(
                color: const Color(0xFF59FF56),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onNext,
                  child: SizedBox(
                    height: 42,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        child: Text(
                          isLast ? 'Done' : 'Next',
                          style: const TextStyle(
                            color: Colors.white,
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
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(holeRect: holeRect),
            ),
          ),
          Positioned.fromRect(
            rect: holeRect,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.95),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: cardAtTop ? MediaQuery.of(context).padding.top + 16 : null,
            bottom: cardAtTop ? null : 24,
            child: card,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.holeRect});

  final Rect holeRect;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          holeRect,
          const Radius.circular(22),
        ),
      );

    final dimPath = Path.combine(PathOperation.difference, outer, hole);

    canvas.drawPath(
      dimPath,
      Paint()..color = Colors.black.withOpacity(0.72),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect;
  }
}