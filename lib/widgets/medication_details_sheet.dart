import 'package:flutter/material.dart';

import 'package:pillchecker/backend/rxnorm/medication_details.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';

/// Review RxNorm-backed fields before adding to the wheel.
class MedicationDetailsSheet extends StatefulWidget {
  const MedicationDetailsSheet({
    super.key,
    required this.service,
    required this.rxcui,
    required this.fallbackName,
  });

  final RxNormMedicationService service;
  final String rxcui;
  final String fallbackName;

  @override
  State<MedicationDetailsSheet> createState() => _MedicationDetailsSheetState();
}

class _MedicationDetailsSheetState extends State<MedicationDetailsSheet> {
  late Future<MedicationDetails?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.service.getMedicationDetails(
      widget.rxcui,
      fallbackName: widget.fallbackName,
    );
  }

  String _na(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? 'Not available' : t;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return FutureBuilder<MedicationDetails?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final d = snap.data;
              if (d == null) {
                return _Unavailable(
                  onRetry: () => setState(_reload),
                  onClose: () => Navigator.pop(context),
                );
              }
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      children: [
                        Text(
                          d.displayName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (d.isFromCache)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Showing saved details (offline or last successful lookup).',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        _row('Generic name', _na(d.genericName)),
                        _row('Brand name', _na(d.brandName)),
                        _row('Strength', _na(d.strength)),
                        _row('Dose form', _na(d.doseForm)),
                        _row(
                          'Active ingredient(s)',
                          d.ingredients.isEmpty
                              ? 'Not available'
                              : d.ingredients.join(', '),
                        ),
                        if (d.synonyms.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Also known as',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.synonyms.take(12).join(', '),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _row('Clinical ID (RxCUI)', d.rxcui),
                        const SizedBox(height: 8),
                        Text(
                          d.userFriendlyInfoText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.black87,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context, d),
                              child: const Text('Use this medication'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.onRetry,
    required this.onClose,
  });

  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(
            'Medication details are unavailable right now. Please try again when you\'re online.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onClose,
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
