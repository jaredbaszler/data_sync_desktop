import 'dart:io';

import 'package:excel/excel.dart';

import '../models/category_code.dart';
import '../models/far_entry.dart';
import 'category_service.dart';
import 'name_matcher.dart';

class FarLookupService {
  final CategoryService categoryService;
  final List<FarEntry> _entries = [];

  FarLookupService(this.categoryService);

  List<FarEntry> get entries => List.unmodifiable(_entries);

  /// Known FAR file name patterns mapped to their dbCode
  static const _farFilePatterns = {
    'far 135': 'P135',
    'far 141': 'FLT141',
    'far 142': 'FLT142',
    'far 145': 'P145',
    'far 147': 'P147',
  };

  /// Load all FAR Excel files from a directory
  Future<void> loadFarFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw FileSystemException('FAR lookup directory not found', directoryPath);
    }

    _entries.clear();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.xlsx'))
        .where((f) => f.path.toLowerCase().contains('far'))
        .toList();

    for (final file in files) {
      final farType = _detectFarType(file.path);
      if (farType == null) {
        print('  Skipping unrecognized FAR file: ${file.path}');
        continue;
      }

      await _loadFarFile(file, farType);
    }

    print('Loaded ${_entries.length} FAR entries from ${files.length} files');
  }

  String? _detectFarType(String filePath) {
    final lower = filePath.toLowerCase();
    for (final entry in _farFilePatterns.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  Future<void> _loadFarFile(File file, String farType) async {
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    // Find column indices from header row
    final headerRow = sheet.rows.first;
    final colMap = _mapColumns(headerRow);

    var count = 0;

    // Skip header row
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final name = _cellValue(row, colMap['name']);
      if (name.isEmpty) continue;

      // Collect dbCode1 through dbCode5
      final dbCodes = <String>[];
      for (var i = 1; i <= 5; i++) {
        final code = _cellValue(row, colMap['dbcode$i']);
        if (code.isNotEmpty) dbCodes.add(code);
      }

      // If no explicit codes found, use the farType itself
      if (dbCodes.isEmpty) {
        dbCodes.add(farType);
      }

      _entries.add(FarEntry(
        name: name,
        dba1: _cellValueOrNull(row, colMap['dba1']),
        dba2: _cellValueOrNull(row, colMap['dba2']),
        dba3: _cellValueOrNull(row, colMap['dba3']),
        street1: _cellValueOrNull(row, colMap['street1']),
        city: _cellValueOrNull(row, colMap['city']),
        state: _cellValueOrNull(row, colMap['state']),
        zipCode: _cellValueOrNull(row, colMap['zipcode']),
        airportCode: _cellValueOrNull(row, colMap['airportcode']),
        dbCodes: dbCodes,
        farType: farType,
      ));
      count++;
    }

    print('  Loaded $count entries from ${file.uri.pathSegments.last} ($farType)');
  }

  Map<String, int?> _mapColumns(List<Data?> headerRow) {
    final map = <String, int?>{};

    for (var i = 0; i < headerRow.length; i++) {
      final header = headerRow[i]?.value?.toString().toLowerCase().trim() ?? '';

      if (header.contains('name') && !header.contains('dba')) {
        map.putIfAbsent('name', () => i);
      } else if (header == 'dba1' || header == 'dba 1') {
        map['dba1'] = i;
      } else if (header == 'dba2' || header == 'dba 2') {
        map['dba2'] = i;
      } else if (header == 'dba3' || header == 'dba 3') {
        map['dba3'] = i;
      } else if (header.contains('street') || header.contains('address')) {
        map.putIfAbsent('street1', () => i);
      } else if (header == 'city') {
        map['city'] = i;
      } else if (header == 'state') {
        map['state'] = i;
      } else if (header.contains('zip')) {
        map.putIfAbsent('zipcode', () => i);
      } else if (header.contains('airport')) {
        map.putIfAbsent('airportcode', () => i);
      } else if (header.contains('dbcode')) {
        // Map dbCode1 through dbCode5
        final match = RegExp(r'dbcode\s*(\d)').firstMatch(header);
        if (match != null) {
          map['dbcode${match.group(1)}'] = i;
        } else {
          // Generic dbCode - assign to first available slot
          for (var j = 1; j <= 5; j++) {
            if (!map.containsKey('dbcode$j')) {
              map['dbcode$j'] = i;
              break;
            }
          }
        }
      }
    }

    return map;
  }

  /// Find FAR matches for a business using fuzzy name + location matching.
  /// Returns CategoryMatch entries with codes from matched FAR entries.
  List<CategoryMatch> findMatches(String businessName, String? city, String? state) {
    final matches = <CategoryMatch>{};

    for (final entry in _entries) {
      // Must match state exactly
      if (!NameMatcher.statesMatch(state, entry.state)) continue;

      // Must match city with some fuzziness
      if (!NameMatcher.citiesMatch(city, entry.city)) continue;

      // Check name similarity against all name variants
      bool nameMatched = false;
      for (final entryName in entry.allNames) {
        if (NameMatcher.namesMatch(businessName, entryName)) {
          nameMatched = true;
          break;
        }
      }

      if (!nameMatched) continue;

      // Add all codes from this FAR entry
      for (final code in entry.dbCodes) {
        final category = categoryService.getByCode(code);
        matches.add(CategoryMatch(
          code: code,
          searchTerms: category?.searchTerms ?? code,
          source: 'far',
        ));
      }
    }

    return matches.toList();
  }

  String _cellValue(List<Data?> row, int? col) {
    if (col == null || col >= row.length) return '';
    final cell = row[col];
    if (cell == null || cell.value == null) return '';
    final val = cell.value.toString().trim();
    return (val == 'null' || val == 'NaN') ? '' : val;
  }

  String? _cellValueOrNull(List<Data?> row, int? col) {
    final val = _cellValue(row, col);
    return val.isEmpty ? null : val;
  }
}
