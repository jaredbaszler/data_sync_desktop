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

class CharterImportService {
  static const _dbCode = 'P135';

  /// Import Part 135 charter operators from the merged JSON file.
  /// Run merge_charter_operators.js first to produce assets/charter_operators.json.
  Future<void> importFromJson(
    String jsonPath,
    BusinessesRepository businessesRepo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
    MongoDbClient mongoClient,
    GeocodingService geocoder, {
    int? maxRows,
  }) async {
    final file = File(jsonPath);
    if (!file.existsSync()) {
      print('ERROR: $jsonPath not found. Run node scripts/merge_charter_operators.js first.');
      return;
    }

    final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    var entries = raw.cast<Map<String, dynamic>>();
    print('Loaded ${entries.length} charter operator entries from $jsonPath');

    if (maxRows != null && maxRows > 0) {
      entries = entries.take(maxRows).toList();
      print('TEST MODE: Limiting to first $maxRows entries.');
    }

    // Geocode FAA-only entries that have no airport code
    await _geocodeMissingAirports(entries, allAirports, geocoder);
    await geocoder.saveCache();

    final valid = entries.where((e) => (e['name'] as String? ?? '').isNotEmpty).toList();
    final skipped = entries.length - valid.length;
    if (skipped > 0) print('Skipping $skipped entries with no name.');

    // Group by state for efficient DB queries
    final byState = <String, List<Map<String, dynamic>>>{};
    for (final e in valid) {
      final state = (e['state'] as String? ?? '').trim().toUpperCase();
      byState.putIfAbsent(state, () => []).add(e);
    }

    var added   = 0;
    var updated = 0;
    var errored = 0;
    final failedEntries = <Map<String, dynamic>>[];

    for (final stateEntry in byState.entries) {
      final state    = stateEntry.key;
      final charters = stateEntry.value;

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
          failedEntries.addAll(charters);
          errored += charters.length;
          continue;
        }
      }

      for (final charter in charters) {
        try {
          final result = await _processEntry(charter, existing, businessesRepo, contactsRepo, allAirports);
          if (result == 'added') {
            added++;
            print('  [+] NEW  "${charter['name']}" | ${charter['city']}, ${charter['state']}');
          } else if (result == 'updated') {
            updated++;
            print('  [~] UPD  "${charter['name']}" | ${charter['city']}, ${charter['state']}');
          }
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('No master connection') || msg.contains('connection')) {
            try {
              await mongoClient.reconnect();
              final result = await _processEntry(charter, existing, businessesRepo, contactsRepo, allAirports);
              if (result == 'added') { added++; } else if (result == 'updated') { updated++; }
            } catch (e2) {
              print('  [!] ERROR "${charter['name']}": $e2');
              failedEntries.add(charter);
              errored++;
            }
          } else {
            print('  [!] ERROR "${charter['name']}": $e');
            failedEntries.add(charter);
            errored++;
          }
        }
      }
    }

    // Retry failed entries
    var retryOk = 0;
    var retryFail = 0;
    if (failedEntries.isNotEmpty) {
      print('\n${'─' * 60}');
      print('Retrying ${failedEntries.length} failed entries...');
      try { await mongoClient.reconnect(); } catch (_) {}

      for (final charter in failedEntries) {
        try {
          final state = (charter['state'] as String? ?? '').trim().toUpperCase();
          final existing = state.isNotEmpty ? await businessesRepo.findByState(state) : <Business>[];
          final result = await _processEntry(charter, existing, businessesRepo, contactsRepo, allAirports);
          if (result == 'added') { added++; } else if (result == 'updated') { updated++; }
          retryOk++;
        } catch (e) {
          print('  [!] Retry failed "${charter['name']}": $e');
          retryFail++;
        }
      }
    }

    print('\n${'=' * 60}');
    print('Charter Operator Import Complete');
    print('=' * 60);
    print('Total entries processed: ${valid.length}');
    print('  ├─ Matched existing (updated): $updated');
    print('  └─ New records inserted:       $added');
    if (errored > 0) {
      print('Errors:              $errored');
      print('  ├─ Retry OK:       $retryOk');
      print('  └─ Retry failed:   $retryFail');
    }
    print('=' * 60);
  }

  Future<String> _processEntry(
    Map<String, dynamic> charter,
    List<Business> existing,
    BusinessesRepository repo,
    BusinessContactsRepository contactsRepo,
    List<Airport> allAirports,
  ) async {
    final name        = charter['name'] as String? ?? '';
    final city        = charter['city'] as String? ?? '';
    final airportCode = charter['airportCode'] as String? ?? '';
    final dbaNames    = _dbaList(charter);

    Business? match;

    // Tier 1: name + city
    for (final biz in existing) {
      if (NameMatcher.citiesMatch(city, biz.city ?? '') && _nameOrDbaMatch(name, dbaNames, biz)) {
        match = biz;
        break;
      }
    }

    // Tier 2: airport code + name (for records with known airport)
    if (match == null && airportCode.isNotEmpty) {
      for (final biz in existing) {
        if ((biz.airportCode ?? '').contains(airportCode) && _nameOrDbaMatch(name, dbaNames, biz)) {
          match = biz;
          break;
        }
      }
    }

    // Tier 3: name-only (state already filtered, city may differ for multi-location operators)
    if (match == null) {
      for (final biz in existing) {
        if (NameMatcher.namesMatch(name, biz.name ?? '')) {
          match = biz;
          break;
        }
      }
    }

    if (match != null) {
      await _enrichExisting(match, charter, repo);
      return 'updated';
    } else {
      await _insertNew(charter, allAirports, repo, contactsRepo);
      return 'added';
    }
  }

  bool _nameOrDbaMatch(String name, List<String> dbaNames, Business biz) {
    final bizNames = [
      biz.name ?? '',
      biz.dba1 ?? '',
      biz.dba2 ?? '',
      biz.dba3 ?? '',
    ].where((s) => s.isNotEmpty).toList();

    final candidateNames = [name, ...dbaNames];
    for (final cn in candidateNames) {
      for (final bn in bizNames) {
        if (NameMatcher.namesMatch(cn, bn)) return true;
      }
    }
    return false;
  }

  Future<void> _enrichExisting(
    Business biz,
    Map<String, dynamic> charter,
    BusinessesRepository repo,
  ) async {
    final updates = <String, dynamic>{};

    // Add P135 dbCode if not already present
    final existingCodes = _allCodes(biz);
    if (!existingCodes.contains(_dbCode)) {
      final merged = [_dbCode, ...existingCodes];
      updates['dbCode']  = merged.isNotEmpty ? merged[0] : null;
      updates['dbCode3'] = merged.length > 1 ? merged[1] : null;
      updates['dbCode4'] = merged.length > 2 ? merged[2] : null;
      updates['dbCode5'] = merged.length > 3 ? merged.sublist(3).join(',') : null;
    }

    // Backfill missing fields
    _backfillString(updates, 'websiteURL', charter['website'], biz.websiteURL);
    _backfillString(updates, 'address', charter['address'], biz.address);
    _backfillString(updates, 'formattedPhoneNumber', charter['phone'], biz.formattedPhoneNumber);
    _backfillString(updates, 'mobileNo', charter['phone'], biz.mobileNo);
    _backfillString(updates, 'zipCode', charter['zip'], biz.zipCode);

    // Store FAA cert number in syncName
    final certNum = charter['certNumber'] as String? ?? '';
    if (certNum.isNotEmpty && (biz.syncName == null || biz.syncName!.isEmpty)) {
      updates['syncName'] = certNum;
    }

    // Backfill DBA names — fill empty slots without duplicating existing values
    final dbas = _dbaList(charter);
    if (dbas.isNotEmpty) {
      final slotKeys   = ['dba1', 'dba2', 'dba3'];
      final slotValues = [biz.dba1 ?? '', biz.dba2 ?? '', biz.dba3 ?? ''];
      final existing   = slotValues.where((v) => v.isNotEmpty)
          .map((v) => v.toLowerCase()).toSet();
      final toAdd = dbas
          .where((d) => !existing.contains(d.toLowerCase()))
          .toList();
      var addIdx = 0;
      for (var i = 0; i < 3 && addIdx < toAdd.length; i++) {
        if (slotValues[i].isEmpty) {
          updates[slotKeys[i]] = toAdd[addIdx++];
        }
      }
    }

    if (updates.isEmpty) return;
    updates['updatedAt'] = DateTime.now();
    await repo.updateFields(biz, updates);
  }

  Future<void> _insertNew(
    Map<String, dynamic> charter,
    List<Airport> allAirports,
    BusinessesRepository repo,
    BusinessContactsRepository contactsRepo,
  ) async {
    final name        = charter['name'] as String? ?? '';
    final city        = charter['city'] as String? ?? '';
    final state       = charter['state'] as String? ?? '';
    final airportCode = charter['airportCode'] as String? ?? '';
    final phone       = charter['phone'] as String? ?? '';
    final website     = charter['website'] as String? ?? '';
    final address     = charter['address'] as String? ?? '';
    final zip         = charter['zip'] as String? ?? '';
    final certNumber  = charter['certNumber'] as String? ?? '';
    final dbas        = _dbaList(charter);

    // Resolve GPS — look up airport coordinates if no direct coords
    double? lat;
    double? lng;
    if (airportCode.isNotEmpty) {
      try {
        final airport = allAirports.firstWhere(
          (a) => a.icaoCode.toUpperCase() == airportCode.toUpperCase() ||
                 (a.iataCode ?? '').toUpperCase() == airportCode.toUpperCase(),
        );
        lat = airport.latitude;
        lng = airport.longitude;
      } catch (_) {}
    }

    // Codes: P135 first slot
    final codes = [_dbCode];
    // Also assign argus-based supplemental code if available
    final argus = (charter['argusRating'] as String? ?? '').toLowerCase();
    if (argus == 'platinum' || argus == 'gold') codes.add('ARGUS');

    final biz = Business(
      name:                  name,
      dba1:                  dbas.isNotEmpty ? dbas[0] : null,
      dba2:                  dbas.length > 1 ? dbas[1] : null,
      dba3:                  dbas.length > 2 ? dbas[2] : null,
      address:               address.isNotEmpty ? address : null,
      city:                  city,
      state:                 state,
      zipCode:               zip.isNotEmpty ? zip : null,
      country:               'US',
      websiteURL:            website.isNotEmpty ? website : null,
      formattedPhoneNumber:  phone.isNotEmpty ? phone : null,
      mobileNo:              phone.isNotEmpty ? phone : null,
      airportCode:           airportCode.isNotEmpty ? airportCode : null,
      dbCode:                codes.isNotEmpty ? codes[0] : null,
      dbCode3:               codes.length > 1 ? codes[1] : null,
      syncName:              certNumber.isNotEmpty ? certNumber : null,
      isGoogleData:          0,
      ignore:                false,
      manual:                false,
      latitude:              lat,
      longitude:             lng,
    );

    final sequenceId = await repo.insertNew(biz);

    // Insert contacts from FAA personnel data
    await _insertContacts(charter, phone, sequenceId, contactsRepo);
  }

  Future<void> _insertContacts(
    Map<String, dynamic> charter,
    String bizPhone,
    int sequenceId,
    BusinessContactsRepository contactsRepo,
  ) async {
    final email = charter['email'] as String? ?? '';

    // Personnel roles from FAA data — names are stored as "LASTNAME, FIRSTNAME"
    final personnel = <String, String>{
      'CEO':                    charter['ceo']        as String? ?? '',
      'Director of Operations': charter['dirOps']     as String? ?? '',
      'Director of Maintenance':charter['dirMaint']   as String? ?? '',
      'Chief Pilot':            charter['chiefPilot'] as String? ?? '',
    };

    var first = true;
    for (final role in personnel.entries) {
      final rawName = role.value.trim();
      if (rawName.isEmpty) continue;

      // Only the first contact gets the business-level email/phone
      await contactsRepo.insertOne(
        BusinessContact(
          name:    _formatPersonName(rawName),
          role:    role.key,
          email:   first && email.isNotEmpty ? email : null,
          phoneNumbers: first && bizPhone.isNotEmpty
              ? [PhoneNumber(number: bizPhone, type: 'main')]
              : null,
        ),
        businessSequenceId: sequenceId,
      );
      first = false;
    }

    // If no personnel found but we have email/phone, insert a generic contact
    if (first && (email.isNotEmpty || bizPhone.isNotEmpty)) {
      await contactsRepo.insertOne(
        BusinessContact(
          name:  charter['name'] as String? ?? '',
          role:  'Business',
          email: email.isNotEmpty ? email : null,
          phoneNumbers: bizPhone.isNotEmpty
              ? [PhoneNumber(number: bizPhone, type: 'main')]
              : null,
        ),
        businessSequenceId: sequenceId,
      );
    }
  }

  /// FAA stores names as "LASTNAME, FIRSTNAME MIDDLE" — convert to "Firstname Lastname"
  String _formatPersonName(String raw) {
    final parts = raw.split(',');
    if (parts.length < 2) return _titleCase(raw.trim());
    final last  = parts[0].trim();
    final first = parts[1].trim().split(' ').first; // take only first given name
    return '${_titleCase(first)} ${_titleCase(last)}';
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Geocode charter entries that have no airport code using city+state address.
  Future<void> _geocodeMissingAirports(
    List<Map<String, dynamic>> entries,
    List<Airport> allAirports,
    GeocodingService geocoder,
  ) async {
    final missing = entries.where((e) => (e['airportCode'] as String? ?? '').isEmpty).toList();
    if (missing.isEmpty) return;

    print('\nGeocoding ${missing.length} charters with no airport code...');
    var assigned = 0;
    var failed   = 0;

    for (final e in missing) {
      final address = e['address'] as String? ?? '';
      final city    = e['city']    as String? ?? '';
      final state   = e['state']   as String? ?? '';
      if (city.isEmpty && address.isEmpty) { failed++; continue; }

      final coords = await geocoder.geocode(
        address.isNotEmpty ? address : null,
        city.isNotEmpty    ? city    : null,
        state.isNotEmpty   ? state   : null,
      );
      if (coords == null) { failed++; continue; }

      final lat = coords[0];
      final lng = coords[1];

      Airport? nearest;
      double nearestDist = double.infinity;
      for (final airport in allAirports) {
        final dist = NameMatcher.distanceMiles(lat, lng, airport.latitude, airport.longitude);
        if (dist < nearestDist) { nearestDist = dist; nearest = airport; }
      }

      // Charters may be further from airports than FBOs — allow up to 25 miles
      if (nearest != null && nearestDist <= 25.0) {
        final code = nearest.icaoCode.isNotEmpty ? nearest.icaoCode : (nearest.iataCode ?? '');
        if (code.isNotEmpty) {
          e['airportCode'] = code;
          assigned++;
        } else {
          failed++;
        }
      } else {
        failed++;
      }
    }

    print('Airport geocoding: $assigned assigned, $failed could not resolve.\n');
  }

  void _backfillString(Map<String, dynamic> updates, String field, dynamic newVal, String? existing) {
    final s = (newVal as String? ?? '').trim();
    if (s.isNotEmpty && (existing == null || existing.isEmpty)) {
      updates[field] = s;
    }
  }

  List<String> _dbaList(Map<String, dynamic> charter) {
    final raw = charter['dbaNames'];
    if (raw is List) return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    return [];
  }

  List<String> _allCodes(Business biz) {
    final codes = <String>[];
    if (biz.dbCode != null  && biz.dbCode!.isNotEmpty)  codes.add(biz.dbCode!);
    if (biz.dbCode3 != null && biz.dbCode3!.isNotEmpty) codes.add(biz.dbCode3!);
    if (biz.dbCode4 != null && biz.dbCode4!.isNotEmpty) codes.add(biz.dbCode4!);
    if (biz.dbCode5 != null && biz.dbCode5!.isNotEmpty) {
      codes.addAll(biz.dbCode5!.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty));
    }
    return codes;
  }
}
