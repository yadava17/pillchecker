import 'package:flutter/material.dart';

class PillInfoPanel extends StatelessWidget {
  const PillInfoPanel({
    super.key,
    required this.pillName,
    required this.doseTimesLabel,
    required this.onClose,
    required this.onEdit,
  });

  final String pillName;
  final List<String> doseTimesLabel; // already formatted strings like "8:00 AM"
  final VoidCallback onClose;
  final VoidCallback onEdit;

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
            // Header row
            Row(
              children: [
                // ✅ Pill icon (placeholder asset for now)
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

                // ✅ X only (no extra Close button needed)
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: white),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ✅ Placeholder DB info box (bigger / main content)
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
                style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.25),
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

            // ✅ Smaller configured-times box
            Container(
              width: double.infinity,
              height: 120, // <-- smaller than before; tweak if you want
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
                  : ListView.separated(
                      itemCount: doseTimesLabel.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => Text(
                        '• ${doseTimesLabel[i]}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 40),

            // ✅ Only Edit button (full width)
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
