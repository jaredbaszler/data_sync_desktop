import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';

import '../database/business_contacts_repository.dart';
import '../database/businesses_repository.dart';
import '../database/mongodb_client.dart';
import '../google/geocoding_service.dart';
import '../models/airport.dart';
import '../models/business.dart';
import '../models/business_contact.dart';
import '../models/category_code.dart';
import '../models/far_entry.dart';
import 'category_service.dart';
import 'name_matcher.dart';

class FarLookupService {
  final CategoryService categoryService;
  final List<FarEntry> _entries = [];
  int _consolidatedCount = 0;

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

  /// Rating - Limited column: value → DB code mapping
  static const _limitedRatingCodes = {
    'aircraft fabric': 'P145INT',
    'equipment': 'P145',
    'floats': 'FLTLIM',
    'landing gear': 'LDGLIM',
    'nondestructivetst': 'P145NDT',
    'specialized service': 'LIMSSV',
    'rotor blades': 'RTRLIM',
  };

  /// Load all FAR Excel files from a directory
  Future<void> loadFarFiles(String directoryPath, {int maxFaa145Rows = 0}) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw FileSystemException('FAR lookup directory not found', directoryPath);
    }

    _entries.clear();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final lower = f.path.toLowerCase();
          return (lower.endsWith('.xlsx') || lower.endsWith('.csv')) &&
              !lower.contains(r'~$');
        })
        .where((f) {
          final lower = f.path.toLowerCase();
          return lower.contains('far') || (lower.contains('faa') && lower.contains('145'));
        })
        .toList();

    // If FAA 145 CSV exists, prefer it and skip the xlsx version
    final faa145CsvFiles = files.where((f) =>
        _isFaa145RatingFile(f.path) && f.path.toLowerCase().endsWith('.csv')).toList();
    if (faa145CsvFiles.isNotEmpty) {
      // Remove xlsx FAA 145 files (keep CSV) and old FAR 145 files
      files.removeWhere((f) {
        final lower = f.path.toLowerCase();
        if (lower.contains('faa') && lower.contains('145') && lower.endsWith('.xlsx')) return true;
        if (lower.contains('far 145') && !lower.contains('faa')) return true;
        return false;
      });
    }

    for (final file in files) {
      if (_isFaa145RatingFile(file.path)) {
        await _loadFaa145File(file, maxRows: maxFaa145Rows);
      } else {
        final farType = _detectFarType(file.path);
        if (farType == null) {
          print('  Skipping unrecognized FAR file: ${file.path}');
          continue;
        }
        await _loadFarFile(file, farType);
      }
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

  /// Check if this is an FAA 145 file (CSV or xlsx)
  bool _isFaa145RatingFile(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.contains('faa') && lower.contains('145') && !lower.contains(r'~$');
  }

  /// Load FAA 145 file from CSV with rating columns.
  /// Column order (from header row):
  /// A=Agency Name, B=DSGN_CODE, C=DBA, D=Cert_No, E=Address Line 1,
  /// F=Address Line 2, G=Address Line 3, H=City, I=State/Province, J=Country,
  /// K=Postal Code, L=Agency Phone, M=Agency Email, N=Accountable Manager,
  /// O=Acct Mgr Phone, P=Acct Mgr Email, Q=Liaison, R=Liaison Phone,
  /// S=Liaison Email, T=Rating - Accessory, U=Rating - Airframe,
  /// V=Rating - Instrument, W=Rating - Limited, X=Rating - Powerplant,
  /// Y=Rating - Propeller, Z=Rating - Radio, AA=Bilateral, AB=Update_Date,
  /// AC=(business email, no header)
  Future<void> _loadFaa145File(File file, {int maxRows = 0}) async {
    // Read as Latin-1 (Windows-1252 compatible) since Excel CSV export may contain non-UTF-8 chars
    final content = file.readAsStringSync(encoding: latin1);
    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty) return;

    // Parse header row to build column index map
    final headers = _parseCsvLine(lines[0]);
    final colMap = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      if (h == 'agency name') colMap['name'] = i;
      else if (h == 'dsgn_code') colMap['dsgn_code'] = i;
      else if (h == 'dba') colMap['dba1'] = i;
      else if (h == 'cert_no') colMap['certno'] = i;
      else if (h == 'address line 1') colMap['street1'] = i;
      else if (h == 'address line 2') colMap['street2'] = i;
      else if (h == 'address line 3') colMap['street3'] = i;
      else if (h == 'city') colMap['city'] = i;
      else if (h.contains('state')) colMap['state'] = i;
      else if (h.contains('country')) colMap['country'] = i;
      else if (h.contains('postal')) colMap['zipcode'] = i;
      else if (h == 'agency phone number') colMap['phone'] = i;
      else if (h == 'agency email') colMap['email'] = i;
      else if (h == 'accountable manager') colMap['acct_mgr_name'] = i;
      else if (h == 'accountable manager phone number') colMap['acct_mgr_phone'] = i;
      else if (h == 'accountable manager email') colMap['acct_mgr_email'] = i;
      else if (h == 'liaison') colMap['liaison_name'] = i;
      else if (h == 'liaison phone number') colMap['liaison_phone'] = i;
      else if (h == 'liaison email') colMap['liaison_email'] = i;
      else if (h == 'rating - accessory') colMap['accessory'] = i;
      else if (h == 'rating - airframe') colMap['airframe'] = i;
      else if (h == 'rating - instrument') colMap['instrument'] = i;
      else if (h == 'rating - limited') colMap['limited'] = i;
      else if (h == 'rating - powerplant') colMap['powerplant'] = i;
      else if (h == 'rating - propeller') colMap['propeller'] = i;
      else if (h == 'rating - radio') colMap['radio'] = i;
      else if (h == 'update_date') colMap['update_date'] = i;
    }
    // Last column (AC) has no header — business email
    if (headers.length > colMap.length) {
      colMap['business_email'] = headers.length - 1;
    }

    // Rating column indices for code derivation
    final ratingCols = <String, int?>{
      'accessory': colMap['accessory'],
      'airframe': colMap['airframe'],
      'instrument': colMap['instrument'],
      'limited': colMap['limited'],
      'powerplant': colMap['powerplant'],
      'propeller': colMap['propeller'],
      'radio': colMap['radio'],
    };

    var count = 0;
    var skippedNonUs = 0;
    var skippedEmpty = 0;

    // Skip header row (line 0), process data rows
    for (var i = 1; i < lines.length; i++) {
      if (maxRows > 0 && count >= maxRows) break;
      if (lines[i].trim().isEmpty) continue;

      final fields = _parseCsvLine(lines[i]);
      final name = _csvField(fields, colMap['name']);
      if (name.isEmpty) {
        skippedEmpty++;
        continue;
      }

      // Filter to UNITED STATES only
      final country = _csvField(fields, colMap['country']);
      if (!country.toLowerCase().contains('united states')) {
        skippedNonUs++;
        continue;
      }

      // Derive DB codes from rating columns
      final dbCodes = _deriveCodesFromRatingsCsv(fields, ratingCols);

      // Extract contact information
      final contacts = _extractContactsCsv(fields, colMap);

      // Concatenate address lines
      final street1 = _csvField(fields, colMap['street1']);
      final street2 = _csvField(fields, colMap['street2']);
      final street3 = _csvField(fields, colMap['street3']);

      _entries.add(FarEntry(
        name: name,
        dba1: _csvFieldOrNull(fields, colMap['dba1']),
        street1: street1.isNotEmpty ? street1 : null,
        street2: street2.isNotEmpty ? street2 : null,
        street3: street3.isNotEmpty ? street3 : null,
        city: _csvFieldOrNull(fields, colMap['city']),
        state: _csvFieldOrNull(fields, colMap['state']),
        country: _csvFieldOrNull(fields, colMap['country']),
        zipCode: _csvFieldOrNull(fields, colMap['zipcode']),
        dbCodes: dbCodes,
        farType: 'P145',
        certNo: _csvFieldOrNull(fields, colMap['certno']),
        contacts: contacts,
      ));
      count++;
    }

    // Consolidate DBA-related entries: group by city+state+zip, merge codes & names
    final beforeConsolidate = _entries.where((e) => e.farType == 'P145').length;
    _consolidateDbaEntries();
    final afterConsolidate = _entries.where((e) => e.farType == 'P145').length;
    final consolidated = beforeConsolidate - afterConsolidate;
    _consolidatedCount = consolidated;

    final maxNote = maxRows > 0 ? ' (limited to $maxRows rows for testing)' : '';
    final consolidateNote = consolidated > 0 ? ' (consolidated $consolidated DBA duplicates)' : '';
    final emptyNote = skippedEmpty > 0 ? ', $skippedEmpty empty names' : '';
    print('  Loaded $afterConsolidate FAA 145 entries from ${file.uri.pathSegments.last}$maxNote (skipped $skippedNonUs non-US$emptyNote)$consolidateNote');
  }

  /// Consolidate FAR 145 entries that are DBA relationships.
  /// Only merges entries that share the same city+state+zip AND have a name/DBA overlap.
  /// e.g. entry A's DBA matches entry B's name, or vice versa.
  void _consolidateDbaEntries() {
    final p145Entries = _entries.where((e) => e.farType == 'P145').toList();
    if (p145Entries.length < 2) return;

    // Group by normalized city+state+zip as candidates
    final groups = <String, List<FarEntry>>{};
    for (final entry in p145Entries) {
      final key = '${(entry.city ?? '').toLowerCase().trim()}'
          '|${(entry.state ?? '').toLowerCase().trim()}'
          '|${(entry.zipCode ?? '').replaceAll(RegExp(r'\s+'), '')}';
      groups.putIfAbsent(key, () => []).add(entry);
    }

    // Within each location group, only merge entries that have a name/DBA overlap
    final toRemove = <FarEntry>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;

      // Build clusters of related entries within this location group
      final merged = <int>{};  // indices already merged into another entry
      for (var i = 0; i < group.length; i++) {
        if (merged.contains(i)) continue;

        final primary = group[i];
        final related = <FarEntry>[];

        for (var j = i + 1; j < group.length; j++) {
          if (merged.contains(j)) continue;
          if (_hasNameDbaOverlap(primary, group[j])) {
            related.add(group[j]);
            merged.add(j);
          }
        }

        if (related.isEmpty) continue;

        // Merge related entries into primary
        final allCodes = <String>{...primary.dbCodes};
        final dbaNames = <String>[];

        for (final rel in related) {
          allCodes.addAll(rel.dbCodes);
          dbaNames.add(rel.name);
          for (final dba in rel.allNames.skip(1)) {
            if (!dbaNames.contains(dba)) dbaNames.add(dba);
          }
        }

        // Replace primary entry with merged version
        final primaryIndex = _entries.indexOf(primary);
        _entries[primaryIndex] = FarEntry(
          name: primary.name,
          dba1: primary.dba1 ?? (dbaNames.isNotEmpty ? dbaNames[0] : null),
          dba2: primary.dba2 ?? (dbaNames.length > 1 ? dbaNames[1] : null),
          dba3: primary.dba3 ?? (dbaNames.length > 2 ? dbaNames[2] : null),
          street1: primary.street1,
          street2: primary.street2,
          street3: primary.street3,
          city: primary.city,
          state: primary.state,
          country: primary.country,
          zipCode: primary.zipCode,
          dbCodes: allCodes.toList(),
          farType: primary.farType,
          certNo: primary.certNo,
          contacts: primary.contacts,
        );

        for (final rel in related) {
          toRemove.add(rel);
        }
      }
    }

    _entries.removeWhere((e) => toRemove.contains(e));
  }

  /// Check if two FAR entries have a name/DBA overlap (one's name matches the other's DBA or vice versa).
  bool _hasNameDbaOverlap(FarEntry a, FarEntry b) {
    final aNamesNorm = a.allNames.map((n) => NameMatcher.normalize(n)).toList();
    final bNamesNorm = b.allNames.map((n) => NameMatcher.normalize(n)).toList();

    for (final aName in aNamesNorm) {
      for (final bName in bNamesNorm) {
        if (NameMatcher.namesMatch(aName, bName)) return true;
      }
    }
    return false;
  }

  /// Derive DB codes from CSV rating column values.
  /// Fixed columns (T,U,V,X,Y,Z): any non-empty value → assign fixed code.
  /// Column W (Limited): value-mapped, supports multiple comma-separated values.
  List<String> _deriveCodesFromRatingsCsv(List<String> fields, Map<String, int?> ratingCols) {
    final codes = <String>[];

    // Fixed-code rating columns: any non-empty value → assign code
    // (includes Accessory which maps to ACYLIM)
    const allFixedRatingCodes = {
      'accessory': 'ACSLIM',
      'airframe': 'AFLIM',
      'instrument': 'INTLIM',
      'powerplant': 'PPLIM',
      'propeller': 'PRPLIM',
      'radio': 'RADLIM',
    };

    for (final entry in allFixedRatingCodes.entries) {
      final colIndex = ratingCols[entry.key];
      if (colIndex != null) {
        final val = _csvField(fields, colIndex);
        if (val.isNotEmpty) {
          codes.add(entry.value);
        }
      }
    }

    // Rating - Limited column: may contain multiple comma-separated values
    // e.g. "Landing Gear, NonDestructiveTst" → LDGLIM + P145NDT
    final limitedColIndex = ratingCols['limited'];
    if (limitedColIndex != null) {
      final rawVal = _csvField(fields, limitedColIndex).trim();
      if (rawVal.isNotEmpty) {
        final parts = rawVal.split(',').map((p) => p.trim().toLowerCase()).where((p) => p.isNotEmpty);
        for (final part in parts) {
          if (_limitedRatingCodes.containsKey(part)) {
            codes.add(_limitedRatingCodes[part]!);
          } else {
            codes.add('LIMSSV'); // Default for unknown limited values
          }
        }
      }
    }

    // If no codes derived, default to P145
    if (codes.isEmpty) {
      codes.add('P145');
    }

    return codes;
  }


  Map<String, int?> _mapColumns(List<Data?> headerRow) {
    final map = <String, int?>{};

    for (var i = 0; i < headerRow.length; i++) {
      final header = headerRow[i]?.value?.toString().toLowerCase().trim() ?? '';

      if (header == 'agency name') {
        map['name'] = i;
      } else if (header.contains('name') && !header.contains('dba') && !map.containsKey('name')) {
        map.putIfAbsent('name', () => i);
      } else if (header == 'dba' || header == 'dba1' || header == 'dba 1') {
        map['dba1'] = i;
      } else if (header == 'dba2' || header == 'dba 2') {
        map['dba2'] = i;
      } else if (header == 'dba3' || header == 'dba 3') {
        map['dba3'] = i;
      } else if (header == 'cert_no' || header == 'cert no' || header == 'certification number') {
        map['certno'] = i;
      } else if (header == 'address line 1') {
        map['street1'] = i;
      } else if (header == 'address line 2') {
        map['street2'] = i;
      } else if (header == 'address line 3') {
        map['street3'] = i;
      } else if (header.contains('street') || (header.contains('address') && !map.containsKey('street1'))) {
        map.putIfAbsent('street1', () => i);
      } else if (header == 'city') {
        map['city'] = i;
      } else if (header == 'state' || header == 'state/province') {
        map['state'] = i;
      } else if (header == 'country') {
        map['country'] = i;
      } else if (header.contains('zip') || header.contains('postal code')) {
        map.putIfAbsent('zipcode', () => i);
      } else if (header.contains('airport')) {
        map.putIfAbsent('airportcode', () => i);
      } else if (header.contains('phone')) {
        map.putIfAbsent('phone', () => i);
      } else if (header.contains('email')) {
        map.putIfAbsent('email', () => i);
      } else if (header.contains('accountable manager') && header.contains('name')) {
        map['acct_mgr_name'] = i;
      } else if (header.contains('accountable manager') && header.contains('phone')) {
        map['acct_mgr_phone'] = i;
      } else if (header.contains('accountable manager') && header.contains('email')) {
        map['acct_mgr_email'] = i;
      } else if (header.contains('liaison') && header.contains('name') && !header.contains('email')) {
        map.putIfAbsent('liaison_name', () => i);
      } else if (header.contains('liaison') && header.contains('phone')) {
        map['liaison_phone'] = i;
      } else if (header.contains('liaison') && header.contains('email')) {
        map['liaison_email'] = i;
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

  /// Populate GPS coordinates on all FAR entries.
  /// Step 1: Pre-populate from disk cache (instant, no API calls).
  /// Step 2: Geocode any remaining entries via the API and save results to cache.
  Future<void> geocodeEntries(GeocodingService geocoder) async {
    // Pre-populate from cache — no API calls, no delays
    var cacheHits = 0;
    for (final entry in _entries) {
      if (entry.street1 == null) continue;
      final cached = geocoder.getCached(entry.street1, entry.city, entry.state);
      if (cached != null) {
        entry.lat = cached[0];
        entry.lng = cached[1];
        cacheHits++;
      }
    }

    // Only entries still missing coordinates need an API call
    final needsGeocoding =
        _entries.where((e) => e.lat == null && e.street1 != null).toList();

    if (needsGeocoding.isEmpty) {
      print('FAR geocoding: all ${_entries.length} entries loaded from cache');
      return;
    }

    print('FAR geocoding: $cacheHits from cache, ${needsGeocoding.length} new via API...');
    var apiCount = 0;
    var failedCount = 0;

    for (final entry in needsGeocoding) {
      try {
        final result = await geocoder.geocode(entry.street1, entry.city, entry.state);
        if (result != null) {
          entry.lat = result[0];
          entry.lng = result[1];
          apiCount++;
        } else {
          failedCount++;
        }
      } catch (e) {
        failedCount++;
        print('  [!] Geocode error for "${entry.name}": $e');
      }
      // Throttle only real API calls to ~10 requests/second
      await Future.delayed(const Duration(milliseconds: 100));

      // Save cache every 200 entries so progress isn't lost on crash
      if ((apiCount + failedCount) % 200 == 0) {
        await geocoder.saveCache();
        print('  Geocoding progress: ${apiCount + failedCount}/${needsGeocoding.length} (saved cache)');
      }
    }

    await geocoder.saveCache();
    print('FAR geocoding complete: $cacheHits cached + $apiCount new, $failedCount failed');
  }

  /// Find FAR matches for a business using fuzzy name + location matching.
  /// State and city must match. Name OR street address OR GPS proximity must match.
  /// Returns CategoryMatch entries with codes from matched FAR entries.
  List<CategoryMatch> findMatches(
    String businessName,
    String? city,
    String? state, {
    String? street,
    double? lat,
    double? lng,
    List<String> businessDbas = const [],
  }) {
    final matches = <CategoryMatch>{};

    for (final entry in _entries) {
      // Must match state exactly
      if (!NameMatcher.statesMatch(state, entry.state)) continue;

      // Must match city with some fuzziness
      if (!NameMatcher.citiesMatch(city, entry.city)) continue;

      // Check name similarity against all name variants, including business DBAs
      bool nameMatched = false;
      final allBizNames = [businessName, ...businessDbas];
      for (final entryName in entry.allNames) {
        for (final bizName in allBizNames) {
          if (NameMatcher.namesMatch(bizName, entryName)) {
            nameMatched = true;
            break;
          }
        }
        if (nameMatched) break;
      }

      // Fallback: match by street address string if name didn't match
      final addressMatched = !nameMatched &&
          street != null &&
          entry.street1 != null &&
          NameMatcher.streetsMatch(street, entry.street1);

      // Fallback: match by GPS proximity (~55 m) if name and address didn't match
      final gpsMatched = !nameMatched &&
          !addressMatched &&
          lat != null &&
          lng != null &&
          entry.lat != null &&
          entry.lng != null &&
          (lat - entry.lat!).abs() <= 0.0005 &&
          (lng - entry.lng!).abs() <= 0.0005;

      if (!nameMatched && !addressMatched && !gpsMatched) continue;

      final source = nameMatched
          ? 'far'
          : gpsMatched
              ? 'far_gps'
              : 'far_address';

      // Add all codes from this FAR entry
      for (final code in entry.dbCodes) {
        final category = categoryService.getByCode(code);
        matches.add(CategoryMatch(
          code: code,
          searchTerms: category?.searchTerms ?? code,
          source: source,
        ));
      }
    }

    return matches.toList();
  }

  /// Enrich existing database businesses with FAR 145 data via multi-tier matching.
  /// Matches FAR entries to businesses by address, name/DBA, or GPS proximity.
  /// Updates matched businesses with derived DB codes and nearby airport codes.
  /// Creates new businesses from unmatched FAR entries.
  Future<void> enrichDatabaseFromFar145(
    BusinessesRepository businessesRepo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
    MongoDbClient mongoClient,
  ) async {
    // Filter to FAR 145 entries only
    final p145Entries = _entries.where((e) => e.farType == 'P145').toList();
    if (p145Entries.isEmpty) {
      print('No FAR 145 entries to enrich');
      return;
    }

    print('Starting FAR 145 enrichment (${p145Entries.length} entries)...\n');

    // Group by state
    final entriesByState = <String, List<FarEntry>>{};
    for (final entry in p145Entries) {
      final state = entry.state ?? 'UNKNOWN';
      entriesByState.putIfAbsent(state, () => []).add(entry);
    }

    var matchedCount = 0;
    var recordsAdded = 0;
    var recordsUpdated = 0;
    var errorCount = 0;

    // Track name|city|state keys inserted during THIS run so DBA lines don't double-match
    final insertedThisRun = <String>{};

    // Track failed entries for retry at the end
    final failedEntries = <FarEntry>[];

    // Process each state
    for (final entry in entriesByState.entries) {
      final state = entry.key;
      final stateEntries = entry.value;

      // Load all businesses in this state once (only pre-existing records)
      List<Business> dbBusinesses;
      try {
        dbBusinesses = await businessesRepo.findByState(state);
      } catch (e) {
        print('  [!] Connection lost loading state "$state", reconnecting...');
        try {
          await mongoClient.reconnect();
          dbBusinesses = await businessesRepo.findByState(state);
        } catch (retryErr) {
          print('  [!] Reconnect failed for state "$state": $retryErr. Skipping state.');
          continue;
        }
      }

      // Exclude businesses we just inserted in this run
      final existingBusinesses = dbBusinesses
          .where((b) {
            final key = '${b.name}|${b.city}|${b.state}';
            return !insertedThisRun.contains(key);
          })
          .toList();

      // Try to match each FAR entry against pre-existing businesses only
      for (final farEntry in stateEntries) {
        try {
          final result = await _matchAndEnrichEntry(
            farEntry,
            existingBusinesses,
            businessesRepo,
            contactsRepo,
            allAirports,
          );
          if (result != null) {
            matchedCount++;
            if (result['isNew'] as bool) {
              recordsAdded++;
            } else {
              recordsUpdated++;
            }
          } else {
            // No match found - create new business from FAR entry
            final newKey = await _createBusinessFromFarEntry(
              farEntry,
              businessesRepo,
              contactsRepo,
              allAirports,
            );
            if (newKey != null) insertedThisRun.add(newKey);
            recordsAdded++;
          }
        } catch (e) {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('connection') || errStr.contains('socket') ||
              errStr.contains('closed') || errStr.contains('mongo') ||
              errStr.contains('master')) {
            print('  [!] MongoDB connection lost at "${farEntry.name}", reconnecting...');
            try {
              await mongoClient.reconnect();
              print('  Reconnected. Retrying...');
              // Retry this entry once after reconnect
              try {
                final result = await _matchAndEnrichEntry(
                  farEntry, existingBusinesses, businessesRepo, contactsRepo, allAirports,
                );
                if (result != null) {
                  matchedCount++;
                  if (result['isNew'] as bool) recordsAdded++; else recordsUpdated++;
                } else {
                  final newKey = await _createBusinessFromFarEntry(
                    farEntry, businessesRepo, contactsRepo, allAirports,
                  );
                  if (newKey != null) insertedThisRun.add(newKey);
                  recordsAdded++;
                }
              } catch (retryErr) {
                print('  [!] Retry failed for "${farEntry.name}": $retryErr');
                failedEntries.add(farEntry);
                errorCount++;
              }
            } catch (reconnectErr) {
              print('  [!] Reconnect failed: $reconnectErr');
              failedEntries.add(farEntry);
              errorCount++;
            }
          } else {
            print('  [!] ERROR processing "${farEntry.name}": $e');
            failedEntries.add(farEntry);
            errorCount++;
          }
        }
      }
    }

    // ── Retry failed entries ──────────────────────────────────
    var retrySucceeded = 0;
    var retryFailed = 0;
    if (failedEntries.isNotEmpty) {
      print('\n${'─' * 60}');
      print('Retrying ${failedEntries.length} failed entries...');
      print('${'─' * 60}');

      // Fresh reconnect before retry pass
      try {
        await mongoClient.reconnect();
        print('  Reconnected to MongoDB for retry pass.');
      } catch (e) {
        print('  [!] Could not reconnect for retry: $e');
        print('  Skipping retry pass.');
        retryFailed = failedEntries.length;
        failedEntries.clear();
      }

      for (final entry in List<FarEntry>.from(failedEntries)) {
        try {
          // Reload state businesses for this entry
          final stateKey = (entry.state ?? '').trim().toUpperCase();
          final existingBusinesses = stateKey.isNotEmpty
              ? await businessesRepo.findByState(stateKey)
              : <Business>[];

          final result = await _matchAndEnrichEntry(
            entry, existingBusinesses, businessesRepo, contactsRepo, allAirports,
          );
          if (result != null) {
            matchedCount++;
            if (result['isNew'] as bool) recordsAdded++; else recordsUpdated++;
          } else {
            final newKey = await _createBusinessFromFarEntry(
              entry, businessesRepo, contactsRepo, allAirports,
            );
            if (newKey != null) insertedThisRun.add(newKey);
            recordsAdded++;
          }
          retrySucceeded++;
          print('  [✓] Retry OK: "${entry.name}"');
        } catch (e) {
          retryFailed++;
          print('  [✗] Retry FAILED: "${entry.name}": $e');
          // Try reconnect for next entry
          try { await mongoClient.reconnect(); } catch (_) {}
        }
      }
    }

    // ── Summary ──────────────────────────────────────────────
    final totalProcessed = recordsUpdated + recordsAdded;
    print('\n${'=' * 60}');
    print('FAR 145 Enrichment Complete');
    print('=' * 60);
    print('Total entries processed: $totalProcessed');
    print('  ├─ Matched existing records (updated): $recordsUpdated');
    print('  └─ New records inserted: $recordsAdded');
    if (_consolidatedCount > 0) {
      print('Consolidated (DBA merged): $_consolidatedCount');
    }
    if (errorCount > 0) {
      print('Errors encountered: $errorCount');
      print('  ├─ Retried successfully: $retrySucceeded');
      print('  └─ Still failed: $retryFailed');
    }
    print('=' * 60 + '\n');
  }

  /// Try to match a FAR entry against a list of businesses using multi-tier logic.
  /// Returns a map with 'isNew' bool if a match was found, null otherwise.
  Future<Map<String, dynamic>?> _matchAndEnrichEntry(
    FarEntry farEntry,
    List<Business> dbBusinesses,
    BusinessesRepository businessesRepo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
  ) async {
    // Tier 1: Address match (highest confidence)
    for (final biz in dbBusinesses) {
      if (_isAddressMatch(farEntry, biz)) {
        final isNew = biz.createdAt == null;
        await _enrichBusiness(biz, farEntry, allAirports, businessesRepo, contactsRepo, 'address');
        return {'isNew': isNew, 'tier': 'address'};
      }
    }

    // Tier 2: Name/DBA cross-match
    for (final biz in dbBusinesses) {
      if (_isNameDbaMatch(farEntry, biz)) {
        final isNew = biz.createdAt == null;
        await _enrichBusiness(biz, farEntry, allAirports, businessesRepo, contactsRepo, 'name');
        return {'isNew': isNew, 'tier': 'name'};
      }
    }

    // Tier 3: GPS proximity
    for (final biz in dbBusinesses) {
      if (_isGpsMatch(farEntry, biz)) {
        final isNew = biz.createdAt == null;
        await _enrichBusiness(biz, farEntry, allAirports, businessesRepo, contactsRepo, 'gps');
        return {'isNew': isNew, 'tier': 'gps'};
      }
    }

    return null;
  }

  /// Tier 1: Address match — city + street must match
  bool _isAddressMatch(FarEntry farEntry, Business biz) {
    if (farEntry.street1 == null || biz.address == null) return false;
    if (!NameMatcher.citiesMatch(farEntry.city, biz.city)) return false;
    return NameMatcher.streetsMatch(farEntry.street1, biz.address);
  }

  /// Tier 2: Name/DBA cross-match — city required, any name combination matches
  bool _isNameDbaMatch(FarEntry farEntry, Business biz) {
    if (!NameMatcher.citiesMatch(farEntry.city, biz.city)) return false;

    final farNames = farEntry.allNames;
    final bizNames = _allBusinessNames(biz);

    for (final farName in farNames) {
      for (final bizName in bizNames) {
        if (NameMatcher.namesMatch(farName, bizName)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Tier 3: GPS proximity — both have coordinates, within 55m
  bool _isGpsMatch(FarEntry farEntry, Business biz) {
    if (farEntry.lat == null || farEntry.lng == null) return false;
    if (biz.latitude == null || biz.longitude == null) return false;
    return (farEntry.lat! - biz.latitude!).abs() <= 0.0005 &&
        (farEntry.lng! - biz.longitude!).abs() <= 0.0005;
  }

  /// Enrich a business with FAR 145 data and save it.
  Future<void> _enrichBusiness(
    Business biz,
    FarEntry farEntry,
    List<Airport> allAirports,
    BusinessesRepository businessesRepo,
    BusinessContactsRepository contactsRepo,
    String tier,
  ) async {
    final isNew = biz.createdAt == null;

    // Merge DB codes
    _mergeDbCodes(biz, farEntry.dbCodes);

    // Assign nearby airport codes if we have coordinates
    if (farEntry.lat != null && farEntry.lng != null) {
      final nearbyAirports = _findNearbyAirports(
        farEntry.lat!,
        farEntry.lng!,
        allAirports,
        radiusMiles: 50,
      );
      _mergeAirportCodes(biz, nearbyAirports);
    }

    // Set updatedAt timestamp
    biz.updatedAt = DateTime.now();

    // Upsert the updated business
    if (biz.placeId != null) {
      await businessesRepo.upsertByPlaceId(biz);

      final action = isNew ? '[+] ADD' : '[~] UPDATE';
      final codes = farEntry.dbCodes.join(', ');
      final airportCount = biz.airportCode != null && biz.airportCode!.isNotEmpty
          ? biz.airportCode!.split(',').length
          : 0;
      final airports = airportCount > 0 ? ' | Airports: $airportCount' : '';
      print('  $action [$tier] "${biz.name}" ← FAR "${farEntry.name}" | Codes: $codes$airports');
    }
  }

  /// Create a new business from an unmatched FAR 145 entry.
  /// Returns the placeId of the newly created business.
  Future<String?> _createBusinessFromFarEntry(
    FarEntry farEntry,
    BusinessesRepository businessesRepo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
  ) async {
    // Concatenate address lines
    final addressParts = [
      if (farEntry.street1 != null && farEntry.street1!.isNotEmpty) farEntry.street1!,
      if (farEntry.street2 != null && farEntry.street2!.isNotEmpty) farEntry.street2!,
      if (farEntry.street3 != null && farEntry.street3!.isNotEmpty) farEntry.street3!,
    ];
    final fullAddress = addressParts.isNotEmpty ? addressParts.join(', ') : null;

    // Deduplicate codes, then assign: first 3 in own slots, overflow comma-delimited in dbCode5
    final codes = farEntry.dbCodes.toSet().toList();
    String? dbCode5;
    if (codes.length > 3) {
      dbCode5 = codes.skip(3).join(',');
    }

    // Create new business (no placeId — reserved for Google Places)
    final newBiz = Business(
      name: farEntry.name,
      dba1: farEntry.dba1,
      dba2: farEntry.dba2,
      dba3: farEntry.dba3,
      address: fullAddress,
      city: farEntry.city,
      state: farEntry.state,
      zipCode: farEntry.zipCode,
      latitude: farEntry.lat,
      longitude: farEntry.lng,
      dbCode: codes.isNotEmpty ? codes[0] : null,
      dbCode3: codes.length > 1 ? codes[1] : null,
      dbCode4: codes.length > 2 ? codes[2] : null,
      dbCode5: dbCode5,
      syncName: farEntry.certNo,
      manual: false,
      ignore: false,
    );

    // Assign nearby airport codes
    if (farEntry.lat != null && farEntry.lng != null) {
      final nearbyAirports = _findNearbyAirports(
        farEntry.lat!,
        farEntry.lng!,
        allAirports,
        radiusMiles: 50,
      );
      newBiz.airportCode = nearbyAirports.join(',');
    }

    // Insert the new business
    try {
      await businessesRepo.insertNew(newBiz);

      // Convert and insert contacts if any (no placeId to link, skip for now)
      // TODO: link contacts once a business identifier strategy is decided
      if (false && farEntry.contacts != null && farEntry.contacts!.isNotEmpty) {
        final contactsToInsert = farEntry.contacts!.map((fc) {
          final phoneNumbers = fc.phoneNumbers?.isNotEmpty == true ? fc.phoneNumbers! : null;
          return BusinessContact(
            businessPlaceId: '',
            name: fc.name,
            role: fc.role,
            email: fc.email,
            phoneNumbers: phoneNumbers != null
                ? phoneNumbers.map((p) => PhoneNumber(number: p, type: 'main')).toList()
                : null,
          );
        }).toList();

        await contactsRepo.insertMany(contactsToInsert);
      }

      final codes = farEntry.dbCodes.join(', ');
      final airportCount = newBiz.airportCode != null && newBiz.airportCode!.isNotEmpty
          ? newBiz.airportCode!.split(',').length
          : 0;
      final airports = airportCount > 0 ? ' | Airports: $airportCount' : '';
      print('  [+] NEW  [insert] "${newBiz.name}" ← FAR "${farEntry.name}" | Codes: $codes$airports');
      return '${farEntry.name}|${farEntry.city}|${farEntry.state}';
    } catch (e) {
      print('  [!] ERROR creating business from FAR "${farEntry.name}": $e');
      return null;
    }
  }

  /// Merge FAR-derived DB codes into a business (priority: FAR codes first)
  void _mergeDbCodes(Business biz, List<String> newCodes) {
    // Split comma-delimited values (dbCode5 can hold multiple codes)
    final existing = <String>[];
    for (final code in [biz.dbCode, biz.dbCode3, biz.dbCode4, biz.dbCode5]) {
      if (code != null && code.isNotEmpty) {
        existing.addAll(code.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty));
      }
    }

    final merged = <String>[...newCodes, ...existing];
    // Deduplicate while preserving FAR codes first
    final seen = <String>{};
    final unique = <String>[];
    for (final code in merged) {
      if (!seen.contains(code)) {
        unique.add(code);
        seen.add(code);
      }
    }

    // Assign to slots: first 3 get their own field, overflow comma-delimited in dbCode5
    biz.dbCode = unique.isNotEmpty ? unique[0] : null;
    biz.dbCode3 = unique.length > 1 ? unique[1] : null;
    biz.dbCode4 = unique.length > 2 ? unique[2] : null;
    if (unique.length > 3) {
      biz.dbCode5 = unique.skip(3).join(',');
    } else {
      biz.dbCode5 = null;
    }
  }

  /// Merge nearby airport codes into a business (comma-separated, deduplicated)
  void _mergeAirportCodes(Business biz, List<String> newCodes) {
    final existing = (biz.airportCode ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    final merged = <String>{...existing, ...newCodes};
    biz.airportCode = merged.join(',');
  }

  /// Find all airport codes within a given radius from a GPS point
  List<String> _findNearbyAirports(
    double lat,
    double lng,
    List<Airport> allAirports, {
    double radiusMiles = 50,
  }) {
    final nearby = <String>[];
    for (final airport in allAirports) {
      final distance = NameMatcher.distanceMiles(lat, lng, airport.latitude, airport.longitude);
      if (distance <= radiusMiles) {
        nearby.add(airport.icaoCode);
      }
    }
    return nearby;
  }

  /// Get all name variants from a business
  List<String> _allBusinessNames(Business biz) {
    return [
      if (biz.name != null && biz.name!.isNotEmpty) biz.name!,
      if (biz.dba1 != null && biz.dba1!.isNotEmpty) biz.dba1!,
      if (biz.dba2 != null && biz.dba2!.isNotEmpty) biz.dba2!,
      if (biz.dba3 != null && biz.dba3!.isNotEmpty) biz.dba3!,
    ];
  }

  /// Extract contact information from CSV FAR entry row
  List<FarContact>? _extractContactsCsv(List<String> fields, Map<String, int> colMap) {
    final contacts = <FarContact>[];

    // Agency contact (phone + email + business email from last column)
    final agencyPhone = _csvFieldOrNull(fields, colMap['phone']);
    final agencyEmail = _csvFieldOrNull(fields, colMap['email']);
    final businessEmail = _csvFieldOrNull(fields, colMap['business_email']);
    if (agencyPhone != null || agencyEmail != null || businessEmail != null) {
      contacts.add(FarContact(
        role: 'Agency',
        email: agencyEmail ?? businessEmail,
        phoneNumbers: agencyPhone != null ? [agencyPhone] : null,
      ));
      // If both agency email and business email exist and differ, add business email as separate contact
      if (businessEmail != null && agencyEmail != null && businessEmail != agencyEmail) {
        contacts.add(FarContact(
          role: 'Business',
          email: businessEmail,
        ));
      }
    }

    // Accountable Manager contact
    final acctMgrName = _csvFieldOrNull(fields, colMap['acct_mgr_name']);
    final acctMgrPhone = _csvFieldOrNull(fields, colMap['acct_mgr_phone']);
    final acctMgrEmail = _csvFieldOrNull(fields, colMap['acct_mgr_email']);
    if (acctMgrName != null || acctMgrPhone != null || acctMgrEmail != null) {
      contacts.add(FarContact(
        name: acctMgrName,
        role: 'Accountable Manager',
        email: acctMgrEmail,
        phoneNumbers: acctMgrPhone != null ? [acctMgrPhone] : null,
      ));
    }

    // Liaison contact
    final liaisonName = _csvFieldOrNull(fields, colMap['liaison_name']);
    final liaisonPhone = _csvFieldOrNull(fields, colMap['liaison_phone']);
    final liaisonEmail = _csvFieldOrNull(fields, colMap['liaison_email']);
    if (liaisonName != null || liaisonPhone != null || liaisonEmail != null) {
      contacts.add(FarContact(
        name: liaisonName,
        role: 'Liaison',
        email: liaisonEmail,
        phoneNumbers: liaisonPhone != null ? [liaisonPhone] : null,
      ));
    }

    return contacts.isNotEmpty ? contacts : null;
  }

  // --- CSV parsing helpers ---

  /// Parse a CSV line, handling quoted fields with commas inside
  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    var inQuotes = false;
    var current = StringBuffer();

    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"'); // Escaped quote
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        fields.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(c);
      }
    }
    fields.add(current.toString().trim());
    return fields;
  }

  /// Get a CSV field value by index, returns empty string if missing
  String _csvField(List<String> fields, int? col) {
    if (col == null || col >= fields.length) return '';
    final val = fields[col].trim();
    return (val == 'null' || val == 'NaN') ? '' : val;
  }

  /// Get a CSV field value by index, returns null if empty
  String? _csvFieldOrNull(List<String> fields, int? col) {
    final val = _csvField(fields, col);
    return val.isEmpty ? null : val;
  }

  // --- Excel helpers (used by other FAR file loaders) ---

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
