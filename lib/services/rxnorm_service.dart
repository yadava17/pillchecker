import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../models/pill_info.dart';

class RxNormService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  static const String _baseUrl = 'https://rxnav.nlm.nih.gov/REST';

  Future<PillInfo?> searchMedication(String medicationName) async {
    final cached = await _db.getPillInfo(medicationName);
    if (cached != null) {
      return cached;
    }

    try {
      final rxcui = await _getRxcui(medicationName);
      if (rxcui == null) {
        return null;
      }

      final properties = await _getMedicationProperties(rxcui);

      final pillInfo = PillInfo(
        medicationName: medicationName,
        rxcui: rxcui,
        genericName: properties['genericName'],
        brandName: properties['brandName'],
        description: properties['description'],
        safetyNotes: properties['safetyNotes'],
      );

      await _db.insertPillInfo(pillInfo);

      return pillInfo;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getRxcui(String medicationName) async {
    final url = Uri.parse(
      '$_baseUrl/rxcui.json?name=${Uri.encodeComponent(medicationName)}',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final idGroup = data['idGroup'];

        if (idGroup != null && idGroup['rxnormId'] != null) {
          final rxnormIds = idGroup['rxnormId'] as List;
          if (rxnormIds.isNotEmpty) {
            return rxnormIds.first.toString();
          }
        }
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  Future<Map<String, String?>> _getMedicationProperties(String rxcui) async {
    final url = Uri.parse('$_baseUrl/rxcui/$rxcui/properties.json');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final properties = data['properties'];

        if (properties != null) {
          return {
            'genericName': properties['synonym'] as String?,
            'brandName': properties['brandName'] as String?,
            'description': properties['fullName'] as String?,
            'safetyNotes': null,
          };
        }
      }
    } catch (e) {
      return {
        'genericName': null,
        'brandName': null,
        'description': null,
        'safetyNotes': null,
      };
    }

    return {
      'genericName': null,
      'brandName': null,
      'description': null,
      'safetyNotes': null,
    };
  }

  Future<List<String>> getSuggestions(String query) async {
    if (query.length < 2) return [];

    final url = Uri.parse(
      '$_baseUrl/spellingsuggestions.json?name=${Uri.encodeComponent(query)}',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final suggestionGroup = data['suggestionGroup'];

        if (suggestionGroup != null &&
            suggestionGroup['suggestionList'] != null) {
          final suggestions =
              suggestionGroup['suggestionList']['suggestion'] as List?;
          if (suggestions != null) {
            return suggestions.map((s) => s.toString()).toList();
          }
        }
      }
    } catch (e) {
      return [];
    }

    return [];
  }
}
