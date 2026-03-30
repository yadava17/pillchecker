import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pillchecker/backend/repositories/rxnorm_cache_repository.dart';
import 'package:pillchecker/backend/rxnorm/medication_details.dart';
import 'package:pillchecker/backend/rxnorm/medication_summary.dart';
import 'package:pillchecker/backend/rxnorm/rxnav_api_client.dart';
import 'package:pillchecker/backend/services/rxnorm_medication_service.dart';

void main() {
  group('RxNormMedicationService', () {
    test('search returns summaries when RxNav responds', () async {
      final mock = MockClient((request) async {
        if (request.url.path.contains('approximateTerm')) {
          return http.Response(
            '{"approximateGroup":{"candidate":[]}}',
            200,
          );
        }
        expect(request.url.path, contains('drugs.json'));
        return http.Response(
          '''
{"drugGroup":{"conceptGroup":[{"conceptProperties":[
  {"rxcui":"161","name":"acetaminophen 500 MG Oral Tablet","tty":"SCD"}
]}]}}
''',
          200,
        );
      });
      final svc = RxNormMedicationService(
        apiClient: RxNavApiClient(httpClient: mock),
        cache: MemoryRxNormMedicationCache(),
      );
      addTearDown(svc.dispose);
      final o = await svc.searchMedications('acetaminophen');
      expect(o.hadNetworkError, isFalse);
      expect(o.items, isNotEmpty);
      expect(o.items.first.rxcui, '161');
    });

    test('search empty query returns nothing', () async {
      final svc = RxNormMedicationService(cache: MemoryRxNormMedicationCache());
      addTearDown(svc.dispose);
      final o = await svc.searchMedications('a');
      expect(o.items, isEmpty);
      expect(o.hadNetworkError, isFalse);
    });

    test('API failure falls back to cached search', () async {
      final cache = MemoryRxNormMedicationCache();
      await cache.saveSearchResults('ibuprofen', [
        const MedicationSummary(
          id: '1',
          rxcui: '1',
          displayName: 'Ibuprofen 200 MG Oral Tablet',
        ),
      ]);
      final mock = MockClient((_) async {
        throw const SocketException('offline');
      });
      final svc = RxNormMedicationService(
        apiClient: RxNavApiClient(
          httpClient: mock,
          timeout: const Duration(milliseconds: 200),
        ),
        cache: cache,
      );
      addTearDown(svc.dispose);
      final o = await svc.searchMedications('ibuprofen');
      expect(o.hadNetworkError, isTrue);
      expect(o.servedFromCache, isTrue);
      expect(o.items.single.displayName, contains('Ibuprofen'));
    });

    test('getMedicationDetails uses cache when API throws', () async {
      final cache = MemoryRxNormMedicationCache();
      await cache.saveDetails(
        const MedicationDetails(
          id: '161',
          rxcui: '161',
          displayName: 'Cached acetaminophen',
        ),
      );
      final mock = MockClient((_) async {
        throw const SocketException('offline');
      });
      final svc = RxNormMedicationService(
        apiClient: RxNavApiClient(
          httpClient: mock,
          timeout: const Duration(milliseconds: 200),
        ),
        cache: cache,
      );
      addTearDown(svc.dispose);
      final d = await svc.getMedicationDetails('161');
      expect(d, isNotNull);
      expect(d!.displayName, 'Cached acetaminophen');
      expect(d.isFromCache, isTrue);
    });

    test('getMedicationDetails returns null when offline and no cache', () async {
      final mock = MockClient((_) async {
        throw const SocketException('offline');
      });
      final svc = RxNormMedicationService(
        apiClient: RxNavApiClient(
          httpClient: mock,
          timeout: const Duration(milliseconds: 200),
        ),
        cache: MemoryRxNormMedicationCache(),
      );
      addTearDown(svc.dispose);
      final d = await svc.getMedicationDetails('99999');
      expect(d, isNull);
    });
  });
}
