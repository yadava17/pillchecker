import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Thin HTTP adapter for RxNav REST — no domain types here.
/// https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.getAllRelatedInfo.html
class RxNavApiClient {
  RxNavApiClient({
    http.Client? httpClient,
    this.baseUrl = 'https://rxnav.nlm.nih.gov/REST',
    this.timeout = const Duration(seconds: 12),
  }) : _client = httpClient ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  Uri _u(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl/$p').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>?> getJson(String path,
      [Map<String, String>? query]) async {
    try {
      final res = await _client.get(_u(path, query)).timeout(timeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on HttpException {
      rethrow;
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }

  /// GET /drugs.json?name=...
  Future<Map<String, dynamic>?> drugsByName(String name) =>
      getJson('drugs.json', {'name': name});

  /// GET /approximateTerm.json?term=...
  Future<Map<String, dynamic>?> approximateTerm(String term) =>
      getJson('approximateTerm.json', {'term': term});

  /// GET /rxcui/{rxcui}/allProperties.json?prop=ALL
  /// [prop] is required by RxNav; `ALL` returns names, attributes, and codes.
  Future<Map<String, dynamic>?> allProperties(String rxcui) =>
      getJson('rxcui/$rxcui/allProperties.json', {'prop': 'ALL'});

  /// GET /rxcui/{rxcui}/related.json?tty=...
  Future<Map<String, dynamic>?> related(
    String rxcui, {
    required String tty,
  }) =>
      getJson('rxcui/$rxcui/related.json', {'tty': tty});

  void dispose() {
    _client.close();
  }
}
