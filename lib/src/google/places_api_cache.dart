import 'dart:convert';
import 'dart:io';

import 'places_api.dart';

/// Persistent on-disk cache for Google Places API responses.
///
/// Two separate files are maintained:
///   - nearby cache: keyed by '{airportCode}|{keyword}|{pageNum}'
///   - details cache: keyed by placeId
///
/// Caches are loaded at construction time and written to disk only when dirty.
class PlacesApiCache {
  final String _nearbyFilePath;
  final String _detailsFilePath;

  // '{airportCode}|{keyword}|{pageNum}' → {results: [...], has_next_page: bool}
  final Map<String, Map<String, dynamic>> _nearby = {};

  // placeId → raw 'result' JSON from Place Details API
  final Map<String, Map<String, dynamic>> _details = {};

  bool _nearbyDirty = false;
  bool _detailsDirty = false;

  PlacesApiCache({
    String nearbyFilePath = 'assets/db_code lookups/places_nearby_cache.json',
    String detailsFilePath = 'assets/db_code lookups/places_details_cache.json',
  })  : _nearbyFilePath = nearbyFilePath,
        _detailsFilePath = detailsFilePath {
    _loadNearby();
    _loadDetails();
  }

  void _loadNearby() {
    final file = File(_nearbyFilePath);
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final e in data.entries) {
        _nearby[e.key] = e.value as Map<String, dynamic>;
      }
      print('Places cache: ${_nearby.length} nearby search page(s) loaded');
    } catch (_) {
      // Corrupt cache — start fresh
    }
  }

  void _loadDetails() {
    final file = File(_detailsFilePath);
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final e in data.entries) {
        _details[e.key] = e.value as Map<String, dynamic>;
      }
      print('Places cache: ${_details.length} place detail(s) loaded');
    } catch (_) {
      // Corrupt cache — start fresh
    }
  }

  String _nearbyKey(String airportCode, String keyword, int pageNum) =>
      '$airportCode|$keyword|$pageNum';

  /// Returns cached nearby search page or null if not cached.
  /// Result map contains: {results: [rawJson, ...], has_next_page: bool}
  Map<String, dynamic>? getNearby(String airportCode, String keyword, int pageNum) =>
      _nearby[_nearbyKey(airportCode, keyword, pageNum)];

  /// Store a nearby search page in the cache.
  void storeNearby(
    String airportCode,
    String keyword,
    int pageNum,
    List<NearbyResult> results,
    bool hasNextPage,
  ) {
    _nearby[_nearbyKey(airportCode, keyword, pageNum)] = {
      'results': results.map((r) => r.toJson()).toList(),
      'has_next_page': hasNextPage,
    };
    _nearbyDirty = true;
  }

  /// Returns cached raw place details JSON for [placeId], or null if not cached.
  Map<String, dynamic>? getDetails(String placeId) => _details[placeId];

  /// Store raw place details JSON (the 'result' map from the API) in the cache.
  void storeDetails(String placeId, Map<String, dynamic> rawJson) {
    _details[placeId] = rawJson;
    _detailsDirty = true;
  }

  /// Persist any dirty caches to disk.
  Future<void> saveCaches() async {
    if (_nearbyDirty) {
      await File(_nearbyFilePath).writeAsString(jsonEncode(_nearby));
      _nearbyDirty = false;
    }
    if (_detailsDirty) {
      await File(_detailsFilePath).writeAsString(jsonEncode(_details));
      _detailsDirty = false;
    }
  }
}
