import 'package:flutter/material.dart';

import 'package:pillchecker/backend/rxnorm/medication_details.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';

class PillInfoPanel extends StatefulWidget {
  const PillInfoPanel({
    super.key,
    required this.pillName,
    required this.doseTimesLabel,
    required this.onClose,
    required this.onEdit,
    this.onDelete,
    required this.rxNormService,
    this.supplyTrackingOn = false,
    this.supplyLeft = 0,
  });

  final String pillName;
  final List<String> doseTimesLabel; // already formatted strings like "8:00 AM"
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final RxNormMedicationService rxNormService;
  final bool supplyTrackingOn;
  final int supplyLeft;

  @override
  State<PillInfoPanel> createState() => _PillInfoPanelState();
}

class _PillInfoPanelState extends State<PillInfoPanel> {
  late Future<MedicationDetails?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  @override
  void didUpdateWidget(covariant PillInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pillName != widget.pillName) {
      _detailsFuture = _loadDetails();
    }
  }

  Future<MedicationDetails?> _loadDetails() async {
    final q = widget.pillName.trim();
    if (q.length < 2) return null;

    // We don’t rely on storing rxcui. We search by name and then fetch details
    // for the best match. RxNorm caching keeps this usable offline.
    final outcome = await widget.rxNormService.searchMedications(q);
    if (outcome.items.isEmpty) return null;

    final first = outcome.items.first;
    return widget.rxNormService.getMedicationDetails(
      first.rxcui,
      fallbackName: widget.pillName,
    );
  }

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
                    widget.pillName,
                    style: const TextStyle(
                      color: white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
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
                      child: FutureBuilder<MedicationDetails?>(
                        future: _detailsFuture,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                              height: 38,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }

                          final d = snap.data;
                          if (d == null) {
                            return const Text(
                              'RxNorm details not available right now.\n\n'
                              'This pill may not match RxNorm results (or you need internet).',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                                height: 1.25,
                              ),
                            );
                          }

                          return Text(
                            d.userFriendlyInfoText,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          );
                        },
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
                      child: widget.doseTimesLabel.isEmpty
                          ? const Text(
                              'No times set.',
                              style: TextStyle(color: Colors.white70),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final t in widget.doseTimesLabel)
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

                    if (widget.supplyTrackingOn)
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
                              widget.supplyLeft.toString(),
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
                  onTap: widget.onEdit,
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
            if (widget.onDelete != null) const SizedBox(height: 10),
            if (widget.onDelete != null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade100,
                    side: BorderSide(
                      color: Colors.red.shade200,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Delete medicine',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
