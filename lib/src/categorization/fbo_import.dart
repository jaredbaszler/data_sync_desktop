import 'dart:convert';
import 'dart:io';

import '../database/business_contacts_repository.dart';
import '../database/businesses_repository.dart';
import '../database/mongodb_client.dart';
import '../google/geocoding_service.dart';
import '../models/airport.dart';
import '../models/business.dart';
import '../models/business_contact.dart';
import 'name_matcher.dart';

class FboImportService {
  static const _dbCode = 'FBO';

  /// Import FBOs from one or more scraped JSON files into the database.
  /// Multiple files are merged and deduplicated by name+city+state before import.
  Future<void> importFromJson(
    List<String> jsonPaths,
    BusinessesRepository businessesRepo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
    MongoDbClient mongoClient,
    GeocodingService geocoder, {
    int? maxRows,
  }) async {
    final allLoaded = <Map<String, dynamic>>[];

    for (final jsonPath in jsonPaths) {
      final file = File(jsonPath);
      if (!file.existsSync()) {
        print('  Skipping missing file: $jsonPath');
        continue;
      }
      final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      final loaded = raw.cast<Map<String, dynamic>>();
      print('Loaded ${loaded.length} FBO entries from $jsonPath');
      allLoaded.addAll(loaded);
    }

    if (allLoaded.isEmpty) {
      print('ERROR: No FBO data files found. Run the scraper scripts first.');
      return;
    }

    // Deduplicate across sources: prefer GlobalAir entries (richer fields),
    // merge in any unique fields from secondary sources.
    var entries = _mergeAndDeduplicate(allLoaded);
    print('After deduplication: ${entries.length} unique FBO entries (${allLoaded.length - entries.length} duplicates removed)');

    if (maxRows != null && maxRows > 0) {
      entries = entries.take(maxRows).toList();
      print('TEST MODE: Limiting to first $maxRows entries.');
    }

    // Assign airport codes to any entries missing one (e.g. ChartHub-only records)
    // by geocoding the address and finding the nearest airport within 10 miles.
    await _assignMissingAirportCodes(entries, allAirports, geocoder);
    await geocoder.saveCache();

    // Filter out entries with no name or state
    final valid = entries.where((e) => (e['name'] as String? ?? '').isNotEmpty).toList();
    final skipped = entries.length - valid.length;
    if (skipped > 0) print('Skipping $skipped entries with no name.');

    // Group by state for efficient DB queries
    final byState = <String, List<Map<String, dynamic>>>{};
    for (final e in valid) {
      final state = (e['state'] as String? ?? '').trim().toUpperCase();
      byState.putIfAbsent(state, () => []).add(e);
    }

    var added = 0;
    var updated = 0;
    var errored = 0;
    final failedEntries = <Map<String, dynamic>>[];

    for (final stateEntry in byState.entries) {
      final state = stateEntry.key;
      final fbos = stateEntry.value;

      List<Business> existing;
      try {
        existing = await businessesRepo.findByState(state);
      } catch (e) {
        print('  [!] DB error loading state $state: $e — reconnecting...');
        try {
          await mongoClient.reconnect();
          existing = await businessesRepo.findByState(state);
        } catch (e2) {
          print('  [!] Reconnect failed for $state: $e2 — skipping state.');
          failedEntries.addAll(fbos);
          errored += fbos.length;
          continue;
        }
      }

      for (final fbo in fbos) {
        try {
          final result = await _processEntry(fbo, existing, businessesRepo, contactsRepo, allAirports);
          if (result == 'added') {
            added++;
            print('  [+] NEW  "${fbo['name']}" | ${fbo['city']}, ${fbo['state']} (${fbo['airportCode']})');
          } else if (result == 'updated') {
            updated++;
            print('  [~] UPD  "${fbo['name']}" | ${fbo['city']}, ${fbo['state']}');
          }
        } catch (e) {
          final errMsg = e.toString();
          if (errMsg.contains('No master connection') || errMsg.contains('connection')) {
            try {
              await mongoClient.reconnect();
              final result = await _processEntry(fbo, existing, businessesRepo, contactsRepo, allAirports);
              if (result == 'added') { added++; } else if (result == 'updated') { updated++; }
            } catch (e2) {
              print('  [!] ERROR "${fbo['name']}": $e2');
              failedEntries.add(fbo);
              errored++;
            }
          } else {
            print('  [!] ERROR "${fbo['name']}": $e');
            failedEntries.add(fbo);
            errored++;
          }
        }
      }
    }

    // Retry failed entries
    var retrySucceeded = 0;
    var retryFailed = 0;
    if (failedEntries.isNotEmpty) {
      print('\n${'─' * 60}');
      print('Retrying ${failedEntries.length} failed entries...');
      try { await mongoClient.reconnect(); } catch (_) {}

      for (final fbo in failedEntries) {
        try {
          final state = (fbo['state'] as String? ?? '').trim().toUpperCase();
          final existing = state.isNotEmpty
              ? await businessesRepo.findByState(state)
              : <Business>[];
          final result = await _processEntry(fbo, existing, businessesRepo, contactsRepo, allAirports);
          if (result == 'added') { added++; } else if (result == 'updated') { updated++; }
          retrySucceeded++;
        } catch (e) {
          print('  [!] Retry failed "${fbo['name']}": $e');
          retryFailed++;
        }
      }
    }

    // Summary
    print('\n${'=' * 60}');
    print('FBO Import Complete');
    print('=' * 60);
    print('Total entries processed: ${valid.length}');
    print('  ├─ Matched existing (updated): $updated');
    print('  └─ New records inserted:       $added');
    if (errored > 0) {
      print('Errors encountered:   $errored');
      print('  ├─ Retry succeeded: $retrySucceeded');
      print('  └─ Retry failed:    $retryFailed');
    }
    print('=' * 60);
  }

  /// Match an FBO entry against existing businesses, then insert or update.
  /// Returns 'added', 'updated', or 'skipped'.
  Future<String> _processEntry(
    Map<String, dynamic> fbo,
    List<Business> existing,
    BusinessesRepository repo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
  ) async {
    final name = fbo['name'] as String? ?? '';
    final city = fbo['city'] as String? ?? '';
    final airportCode = fbo['airportCode'] as String? ?? '';

    // Try to find a matching existing business
    Business? match;
    for (final biz in existing) {
      // Tier 1: name + city match
      if (NameMatcher.citiesMatch(city, biz.city ?? '') &&
          NameMatcher.namesMatch(name, biz.name ?? '')) {
        match = biz;
        break;
      }
    }
    if (match == null) {
      for (final biz in existing) {
        // Tier 2: airport code match + name similarity
        if (airportCode.isNotEmpty &&
            (biz.airportCode ?? '').contains(airportCode) &&
            NameMatcher.namesMatch(name, biz.name ?? '')) {
          match = biz;
          break;
        }
      }
    }

    if (match != null) {
      await _enrichExisting(match, fbo, repo);
      return 'updated';
    } else {
      await _insertNew(fbo, allAirports, repo, contactsRepo);
      return 'added';
    }
  }

  Future<void> _enrichExisting(
    Business biz,
    Map<String, dynamic> fbo,
    BusinessesRepository repo,
  ) async {
    final updates = <String, dynamic>{};

    // Merge dbCode — add FBO code if not already present
    final existingCodes = _allCodes(biz);
    if (!existingCodes.contains(_dbCode)) {
      final merged = [_dbCode, ...existingCodes];
      updates['dbCode'] = merged.isNotEmpty ? merged[0] : null;
      updates['dbCode3'] = merged.length > 1 ? merged[1] : null;
      updates['dbCode4'] = merged.length > 2 ? merged[2] : null;
      updates['dbCode5'] = merged.length > 3 ? merged.sublist(3).join(',') : null;
    }

    // Backfill missing fields from enriched data
    final website = fbo['websiteURL'] as String? ?? '';
    if (website.isNotEmpty && (biz.websiteURL == null || biz.websiteURL!.isEmpty)) {
      updates['websiteURL'] = website;
    }
    final address = fbo['address'] as String? ?? '';
    if (address.isNotEmpty && (biz.address == null || biz.address!.isEmpty)) {
      updates['address'] = address;
    }
    final phone = fbo['phone'] as String? ?? '';
    if (phone.isNotEmpty && (biz.formattedPhoneNumber == null || biz.formattedPhoneNumber!.isEmpty)) {
      updates['formattedPhoneNumber'] = phone;
      updates['mobileNo'] = phone;
    }
    final zip = _parseZip(fbo['cityStateZip'] as String? ?? '');
    if (zip.isNotEmpty && (biz.zipCode == null || biz.zipCode!.isEmpty)) {
      updates['zipCode'] = zip;
    }

    if (updates.isEmpty) return;
    updates['updatedAt'] = DateTime.now();

    await repo.updateFields(biz, updates);
  }

  Future<void> _insertNew(
    Map<String, dynamic> fbo,
    List<Airport> allAirports,
    BusinessesRepository repo,
    BusinessContactsRepository contactsRepo,
  ) async {
    final name = fbo['name'] as String? ?? '';
    final city = fbo['city'] as String? ?? '';
    final state = fbo['state'] as String? ?? '';
    final airportCode = fbo['airportCode'] as String? ?? '';
    final websiteURL = fbo['websiteURL'] as String? ?? '';
    final address = fbo['address'] as String? ?? '';
    final phone = fbo['phone'] as String? ?? '';
    final manager = fbo['manager'] as String? ?? '';
    final zip = _parseZip(fbo['cityStateZip'] as String? ?? '');

    // FBOs serve a single airport — look up GPS coords for that airport only.
    Airport? primaryAirport;
    if (airportCode.isNotEmpty) {
      try {
        primaryAirport = allAirports.firstWhere(
          (a) => a.icaoCode.toUpperCase() == airportCode.toUpperCase() ||
                 (a.iataCode ?? '').toUpperCase() == airportCode.toUpperCase(),
        );
      } catch (_) {} // not found — GPS will be null
    }

    final biz = Business(
      name: name,
      address: address.isNotEmpty ? address : null,
      city: city,
      state: state,
      zipCode: zip.isNotEmpty ? zip : null,
      country: 'US',
      websiteURL: websiteURL.isNotEmpty ? websiteURL : null,
      formattedPhoneNumber: phone.isNotEmpty ? phone : null,
      mobileNo: phone.isNotEmpty ? phone : null,
      airportCode: airportCode.isNotEmpty ? airportCode : null,
      dbCode: _dbCode,
      isGoogleData: 0,
      ignore: false,
      manual: false,
      latitude: primaryAirport?.latitude,
      longitude: primaryAirport?.longitude,
    );

    final sequenceId = await repo.insertNew(biz);

    // Store manager as a contact if present (linked via sequenceId)
    if (manager.isNotEmpty) {
      final contact = BusinessContact(
        name: manager,
        role: 'Manager',
        phoneNumbers: phone.isNotEmpty
            ? [PhoneNumber(number: phone, type: 'main')]
            : null,
      );
      await contactsRepo.insertOne(contact, businessSequenceId: sequenceId);
    }
  }

  /// Merge entries from multiple sources, deduplicating by normalized name+city+state.
  /// GlobalAir entries take priority (richer fields); ChartHub fields backfill gaps.
  List<Map<String, dynamic>> _mergeAndDeduplicate(List<Map<String, dynamic>> entries) {
    // Key: normalized "name|city|state"
    final seen = <String, Map<String, dynamic>>{};

    // Process GlobalAir first so its entries are the primary record
    final globalAir = entries.where((e) => (e['source'] as String? ?? '') == 'globalair').toList();
    final others = entries.where((e) => (e['source'] as String? ?? '') != 'globalair').toList();

    for (final e in [...globalAir, ...others]) {
      final key = _dedupKey(e);
      if (!seen.containsKey(key)) {
        seen[key] = Map<String, dynamic>.from(e);
      } else {
        // Backfill any missing fields from the secondary source
        final primary = seen[key]!;
        e.forEach((k, v) {
          if (v != null && v != '' && (primary[k] == null || primary[k] == '')) {
            primary[k] = v;
          }
        });
        // Merge fuelPrices from ChartHub if primary has none
        if ((primary['fuelPrices'] == null || (primary['fuelPrices'] as List?)?.isEmpty == true) &&
            e['fuelPrices'] != null) {
          primary['fuelPrices'] = e['fuelPrices'];
        }
      }
    }

    return seen.values.toList();
  }

  String _dedupKey(Map<String, dynamic> e) {
    final name = NameMatcher.normalize(e['name'] as String? ?? '');
    final city = NameMatcher.normalize(e['city'] as String? ?? '');
    final state = (e['state'] as String? ?? '').toUpperCase();
    return '$name|$city|$state';
  }

  /// Geocode any entries missing an airportCode, then assign the nearest airport
  /// within 10 miles. FBOs are on-airport so 10 miles is a generous but safe radius.
  Future<void> _assignMissingAirportCodes(
    List<Map<String, dynamic>> entries,
    List<Airport> allAirports,
    GeocodingService geocoder,
  ) async {
    final missing = entries.where((e) => (e['airportCode'] as String? ?? '').isEmpty).toList();
    if (missing.isEmpty) return;

    print('\nGeocoding ${missing.length} FBOs with no airport code...');
    var assigned = 0;
    var failed = 0;

    for (final e in missing) {
      final address = e['address'] as String? ?? '';
      final city = e['city'] as String? ?? '';
      final state = e['state'] as String? ?? '';
      if (address.isEmpty && city.isEmpty) { failed++; continue; }

      final coords = await geocoder.geocode(
        address.isNotEmpty ? address : null,
        city.isNotEmpty ? city : null,
        state.isNotEmpty ? state : null,
      );
      if (coords == null) { failed++; continue; }

      final lat = coords[0];
      final lng = coords[1];

      // Find nearest airport within 10 miles
      Airport? nearest;
      double nearestDist = double.infinity;
      for (final airport in allAirports) {
        final dist = NameMatcher.distanceMiles(lat, lng, airport.latitude, airport.longitude);
        if (dist < nearestDist) {
          nearestDist = dist;
          nearest = airport;
        }
      }

      if (nearest != null && nearestDist <= 10.0) {
        final code = nearest.icaoCode.isNotEmpty ? nearest.icaoCode : (nearest.iataCode ?? '');
        if (code.isNotEmpty) {
          e['airportCode'] = code;
          assigned++;
          print('  [geo] "${e['name']}" → $code (${nearestDist.toStringAsFixed(1)} mi)');
        } else {
          failed++;
        }
      } else {
        failed++;
        print('  [geo] "${e['name']}" → no airport within 10mi (nearest: ${nearestDist.toStringAsFixed(1)} mi)');
      }
    }

    print('Airport geocoding: $assigned assigned, $failed could not resolve.\n');
  }

  /// Extract zip code from a "City, ST 12345" or "Airport, City, ST 12345" string.
  String _parseZip(String cityStateZip) {
    final match = RegExp(r'\b(\d{5}(?:-\d{4})?)\b').firstMatch(cityStateZip);
    return match?.group(1) ?? '';
  }

  List<String> _allCodes(Business biz) {
    final codes = <String>[];
    if (biz.dbCode != null && biz.dbCode!.isNotEmpty) codes.add(biz.dbCode!);
    if (biz.dbCode3 != null && biz.dbCode3!.isNotEmpty) codes.add(biz.dbCode3!);
    if (biz.dbCode4 != null && biz.dbCode4!.isNotEmpty) codes.add(biz.dbCode4!);
    if (biz.dbCode5 != null && biz.dbCode5!.isNotEmpty) {
      codes.addAll(biz.dbCode5!.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty));
    }
    return codes;
  }
}
