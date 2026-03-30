import 'package:flutter/material.dart';

class PillInfoPanel extends StatelessWidget {
  const PillInfoPanel({
    super.key,
    required this.pillName,
    required this.doseTimesLabel,
    required this.onClose,
    required this.onEdit,
    this.supplyTrackingOn = false,
    this.supplyLeft = 0,
  });

  final String pillName;
  final List<String> doseTimesLabel; // already formatted strings like "8:00 AM"
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final bool supplyTrackingOn;
  final int supplyLeft;

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF98404F);
    const white = Color(0xFFFFFFFF);
    const green = Color(0xFF59FF56);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(26),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header row (UNCHANGED)
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/images/pill_placeholder.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pillName,
                    style: const TextStyle(
                      color: white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: white),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ✅ Scrollable content area
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'Placeholder: Pill info will go here (RxNorm / DB later).\n\n'
                        '• Generic name\n'
                        '• Brand names\n'
                        '• Warnings / interactions\n'
                        '• Notes',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Configured for:',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Replace fixed-height box with "shrink-safe" list
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: doseTimesLabel.isEmpty
                          ? const Text(
                              'No times set.',
                              style: TextStyle(color: Colors.white70),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final t in doseTimesLabel)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      '• $t',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 14),

                    if (supplyTrackingOn)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.medication_rounded,
                              color: Colors.white.withOpacity(0.85),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Supply left:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              supplyLeft.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ✅ Pinned Edit button (always visible)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: Material(
                color: green,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onEdit,
                  child: const Center(
                    child: Text(
                      'Edit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
