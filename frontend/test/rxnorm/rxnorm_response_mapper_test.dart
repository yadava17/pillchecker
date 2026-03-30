import 'package:flutter_test/flutter_test.dart';
import 'package:pillchecker/backend/rxnorm/rxnorm_response_mapper.dart';

void main() {
  group('RxNormResponseMapper', () {
    test('parseDrugsResponse extracts rxcui and display names', () {
      final json = {
        'drugGroup': {
          'conceptGroup': [
            {
              'conceptProperties': [
                {
                  'rxcui': '123',
                  'name': 'acetaminophen 500 MG Oral Tablet',
                  'tty': 'SCD',
                },
              ],
            },
          ],
        },
      };
      final list = RxNormResponseMapper.parseDrugsResponse(json, 'acetaminophen');
      expect(list, isNotEmpty);
      expect(list.first.rxcui, '123');
      expect(list.first.displayName, contains('acetaminophen'));
    });

    test('dedupe prefers higher-priority tty for same rxcui', () {
      final json = {
        'drugGroup': {
          'conceptGroup': [
            {
              'conceptProperties': [
                {
                  'rxcui': '99',
                  'name': 'low priority row',
                  'tty': 'SY',
                },
              ],
            },
            {
              'conceptProperties': [
                {
                  'rxcui': '99',
                  'name': 'acetaminophen 500 MG Oral Tablet',
                  'tty': 'SCD',
                },
              ],
            },
          ],
        },
      };
      final list = RxNormResponseMapper.parseDrugsResponse(json, 'ace');
      expect(list.length, 1);
      expect(list.first.termType, 'SCD');
    });

    test('malformed json returns empty list', () {
      expect(RxNormResponseMapper.parseDrugsResponse(null, 'x'), isEmpty);
      expect(RxNormResponseMapper.parseDrugsResponse(<String, dynamic>{}, 'x'), isEmpty);
    });
  });
}
