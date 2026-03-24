import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Geocodes street addresses to GPS coordinates using the Google Geocoding API.
/// Results are persisted to a JSON cache file so each address is only geocoded once.
class GeocodingService {
  final String apiKey;
  final String _cacheFilePath;
  final Map<String, List<double>> _cache = {};
  bool _dirty = false;

  GeocodingService(
    this.apiKey, {
    String cacheFilePath = 'assets/db_code lookups/far_geocode_cache.json',
  }) : _cacheFilePath = cacheFilePath {
    _loadCache();
  }

  void _loadCache() {
    final file = File(_cacheFilePath);
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final coords = (entry.value as List).map((v) => (v as num).toDouble()).toList();
        _cache[entry.key] = coords;
      }
      print('Loaded ${_cache.length} cached geocode result(s) from $_cacheFilePath');
    } catch (_) {
      // Corrupt cache file — start fresh
    }
  }

  /// Return cached coordinates for an address without making an API call.
  /// Returns null if the address has not been geocoded yet.
  List<double>? getCached(String? street, String? city, String? state) {
    if (street == null || street.trim().isEmpty) return null;
    final key =
        '${street.trim()}|${city?.trim() ?? ''}|${state?.trim() ?? ''}'.toLowerCase();
    return _cache[key];
  }

  /// Persist any new geocode results to disk.
  Future<void> saveCache() async {
    if (!_dirty) return;
    final file = File(_cacheFilePath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_cache));
    _dirty = false;
  }

  /// Geocode [street] + [city] + [state] to `[lat, lng]`.
  /// Returns null if geocoding fails or no result is found.
  /// Cached results are returned immediately without an API call.
  Future<List<double>?> geocode(String? street, String? city, String? state) async {
    if (street == null || street.trim().isEmpty) return null;

    final key =
        '${street.trim()}|${city?.trim() ?? ''}|${state?.trim() ?? ''}'.toLowerCase();

    if (_cache.containsKey(key)) return _cache[key];

    final parts = [
      street.trim(),
      if (city != null && city.isNotEmpty) city.trim(),
      if (state != null && state.isNotEmpty) state.trim(),
    ];

    final encodedAddress = Uri.encodeComponent(parts.join(', '));
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return null;

      final results = json['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final location =
          ((results[0] as Map)['geometry'] as Map)['location'] as Map;
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();

      _cache[key] = [lat, lng];
      _dirty = true;
      return [lat, lng];
    } catch (_) {
      return null;
    }
  }
}
