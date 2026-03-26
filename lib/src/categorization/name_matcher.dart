import 'dart:math';

import 'package:string_similarity/string_similarity.dart';

class NameMatcher {
  /// Normalize a business name for comparison:
  /// lowercase, strip common suffixes, remove punctuation
  static String normalize(String name) {
    var n = name.toLowerCase().trim();

    // Remove common business suffixes
    final suffixes = [
      'llc',
      'l.l.c.',
      'inc.',
      'inc',
      'incorporated',
      'corp.',
      'corp',
      'corporation',
      'co.',
      'co',
      'company',
      'ltd.',
      'ltd',
      'limited',
      'lp',
      'l.p.',
      'dba',
      'd/b/a',
      'pllc',
    ];

    for (final suffix in suffixes) {
      // Remove suffix at the end or preceded by comma/space
      n = n.replaceAll(RegExp('\\s*,?\\s*$suffix\\s*\$', caseSensitive: false), '');
    }

    // Remove punctuation
    n = n.replaceAll(RegExp(r'[^\w\s]'), '');
    // Collapse whitespace
    n = n.replaceAll(RegExp(r'\s+'), ' ').trim();

    return n;
  }

  /// Check if two business names match with a given similarity threshold (0.0 to 1.0).
  /// Returns true if similarity exceeds threshold.
  static bool namesMatch(String name1, String name2, {double threshold = 0.8}) {
    final n1 = normalize(name1);
    final n2 = normalize(name2);

    if (n1.isEmpty || n2.isEmpty) return false;
    if (n1 == n2) return true;

    // Check if one contains the other
    if (n1.contains(n2) || n2.contains(n1)) return true;

    // Use string similarity (Dice coefficient)
    final similarity = StringSimilarity.compareTwoStrings(n1, n2);
    return similarity >= threshold;
  }

  /// Check if a city matches (case-insensitive, with some fuzzy tolerance)
  static bool citiesMatch(String? city1, String? city2) {
    if (city1 == null || city2 == null) return false;
    final c1 = city1.toLowerCase().trim();
    final c2 = city2.toLowerCase().trim();
    if (c1.isEmpty || c2.isEmpty) return false;
    if (c1 == c2) return true;

    // Fuzzy city match (one contains the other for names like "North Hollywood" vs "Hollywood")
    if (c1.contains(c2) || c2.contains(c1)) return true;

    final similarity = StringSimilarity.compareTwoStrings(c1, c2);
    return similarity >= 0.7;
  }

  /// Check if states match (exact, case-insensitive)
  static bool statesMatch(String? state1, String? state2) {
    if (state1 == null || state2 == null) return false;
    return state1.trim().toLowerCase() == state2.trim().toLowerCase();
  }

  /// Check if two street addresses match, normalizing common abbreviations
  /// (e.g. "Street" → "st", "Boulevard" → "blvd").
  static bool streetsMatch(String? street1, String? street2) {
    if (street1 == null || street2 == null) return false;
    final s1 = _normalizeStreet(street1);
    final s2 = _normalizeStreet(street2);
    if (s1.isEmpty || s2.isEmpty) return false;
    if (s1 == s2) return true;
    if (s1.contains(s2) || s2.contains(s1)) return true;
    final similarity = StringSimilarity.compareTwoStrings(s1, s2);
    return similarity >= 0.85;
  }

  static String _normalizeStreet(String street) {
    var s = street.toLowerCase().trim();
    // Expand or contract common directional / type abbreviations to a canonical form
    final replacements = {
      r'\bstreet\b': 'st',
      r'\bavenue\b': 'ave',
      r'\bboulevard\b': 'blvd',
      r'\bdrive\b': 'dr',
      r'\broad\b': 'rd',
      r'\blane\b': 'ln',
      r'\bcourt\b': 'ct',
      r'\bplace\b': 'pl',
      r'\bcircle\b': 'cir',
      r'\bhighway\b': 'hwy',
      r'\bparkway\b': 'pkwy',
      r'\bnorth\b': 'n',
      r'\bsouth\b': 's',
      r'\beast\b': 'e',
      r'\bwest\b': 'w',
    };
    for (final entry in replacements.entries) {
      s = s.replaceAll(RegExp(entry.key), entry.value);
    }
    // Remove punctuation and collapse whitespace
    s = s.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Calculate distance in miles between two GPS points using haversine formula
  static double distanceMiles(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMiles = 3958.8;
    final dLatRad = _toRadians(lat2 - lat1);
    final dLngRad = _toRadians(lng2 - lng1);
    final a = sin(dLatRad / 2) * sin(dLatRad / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLngRad / 2) *
            sin(dLngRad / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMiles * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
