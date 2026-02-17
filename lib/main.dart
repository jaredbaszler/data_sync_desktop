import 'dart:io';

import 'package:args/args.dart';
import 'package:excel/excel.dart' as xl;

import 'src/categorization/category_service.dart';
import 'src/categorization/far_lookup.dart';
import 'src/database/businesses_repository.dart';
import 'src/database/cache_repository.dart';
import 'src/database/airports_repository.dart';
import 'src/database/mongodb_client.dart';
import 'src/google/places_api.dart';
import 'src/models/airport.dart';
import 'src/models/business.dart';
import 'src/models/category_code.dart';
import 'src/utils/config.dart';

// Default search keywords for aviation businesses
const defaultSearchKeywords = [
  'aviation',
  'flight school',
  'FBO',
  'aircraft maintenance',
  'hangar',
  'airplane',
  'helicopter',
  'avionics',
  'pilot training',
  'aircraft rental',
];

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('limit', abbr: 'l', help: 'Max airports to process', defaultsTo: '0')
    ..addOption('airport', abbr: 'a', help: 'Process a single airport by ICAO code')
    ..addMultiOption('keywords',
        abbr: 'k', help: 'Search keywords (default: aviation-related terms)')
    ..addFlag('refresh-stale', help: 'Refresh businesses older than 30 days', defaultsTo: false)
    ..addFlag('refresh-all', help: 'Refresh all businesses (ignore cache)', defaultsTo: false)
    ..addFlag('resume', help: 'Resume from last checkpoint', defaultsTo: false)
    ..addFlag('import-airports',
        help: 'Import airport data from Excel to MongoDB', defaultsTo: false)
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(args);
  } catch (e) {
    print('Error: $e');
    print('\nUsage: dart run bin/run.dart [options]');
    print(parser.usage);
    exit(1);
  }

  if (options['help'] as bool) {
    print('Aviation Business Data Sync CLI');
    print('Syncs Google Places aviation business data to MongoDB.\n');
    print('Usage: dart run bin/run.dart [options]\n');
    print(parser.usage);
    exit(0);
  }

  // Load configuration
  final config = Config.fromEnvironment();
  print('Configuration loaded');

  // Connect to MongoDB
  final mongoClient = MongoDbClient(config);
  await mongoClient.connect();

  try {
    final airportsRepo = AirportsRepository(mongoClient);
    final businessesRepo = BusinessesRepository(mongoClient, collectionName: config.mongodbCollection);

    // Handle airport import mode
    if (options['import-airports'] as bool) {
      await _importAirports(airportsRepo, mongoClient);
      return;
    }

    // Ensure indexes
    await airportsRepo.ensureIndexes();
    await businessesRepo.ensureIndexes();

    // Load categorization data
    final categoryService = CategoryService();
    final farLookup = FarLookupService(categoryService);

    const categoryFile = 'assets/db_code lookups/Business Category and Search.xlsx';
    const farDir = 'assets/db_code lookups/';

    if (File(categoryFile).existsSync()) {
      await categoryService.loadCategoryDictionary(categoryFile);
    } else {
      print('WARNING: Category dictionary not found at $categoryFile');
    }

    if (Directory(farDir).existsSync()) {
      await farLookup.loadFarFiles(farDir);
    } else {
      print('WARNING: FAR lookup directory not found at $farDir');
    }

    // Configure search keywords
    final keywords = (options['keywords'] as List<String>).isNotEmpty
        ? options['keywords'] as List<String>
        : defaultSearchKeywords;

    // Set up Places API
    final placesApi = PlacesApi.fromConfig(config);
    final radiusMeters = PlacesApi.milesToMeters(config.searchRadiusMiles);

    // Parse options
    final limit = int.tryParse(options['limit'] as String) ?? 0;
    final singleAirport = options['airport'] as String?;
    final shouldResume = options['resume'] as bool;
    final refreshStale = options['refresh-stale'] as bool;
    final refreshAll = options['refresh-all'] as bool;

    // Load checkpoint if resuming
    final cache = CacheRepository();
    if (shouldResume) {
      await cache.loadCheckpoint();
    }

    // Get airports to process
    List<Airport> airports;
    if (singleAirport != null) {
      final airport = await airportsRepo.getByIcaoCode(singleAirport);
      if (airport == null) {
        print('Airport $singleAirport not found in database');
        exit(1);
      }
      airports = [airport];
    } else {
      airports = await airportsRepo.getEnabledAirports(limit: limit > 0 ? limit : null);
    }

    // Apply debug airport filter from .env.local
    if (singleAirport == null && config.debugAirports.isNotEmpty) {
      airports = airports.where((a) => config.debugAirports.contains(a.icaoCode)).toList();
      print('[DEBUG] Filtering to ${config.debugAirports.length} airport(s): ${config.debugAirports.join(", ")}');
    }

    if (airports.isEmpty) {
      print('No airports found to process. Run with --import-airports first.');
      exit(0);
    }

    print('\nStarting sync for ${airports.length} airports');
    print('Search keywords: ${keywords.join(", ")}');
    print('Search radius: ${config.searchRadiusMiles} miles ($radiusMeters meters)');
    print('---');

    // Skip to resume point if resuming
    var startIndex = 0;
    if (shouldResume && cache.lastAirportCode != null) {
      final resumeIndex = airports.indexWhere((a) => a.icaoCode == cache.lastAirportCode);
      if (resumeIndex >= 0) {
        startIndex = resumeIndex + 1;
        print('Resuming after airport ${cache.lastAirportCode} (index $startIndex)');
      }
    }

    var totalNewBusinesses = 0;
    var totalSkipped = 0;
    var totalUpdated = 0;

    for (var i = startIndex; i < airports.length; i++) {
      final airport = airports[i];
      print('\n[${i + 1}/${airports.length}] Processing ${airport.icaoCode} - ${airport.name}');

      var airportNewCount = 0;
      var airportSkipCount = 0;

      // Track all Place IDs seen for this airport to deduplicate across keywords
      final seenPlaceIds = <String>{};

      for (final keyword in keywords) {
        String? nextPageToken;
        var pageNum = 1;

        while (pageNum <= 3) {
          try {
            final response = await withRetry(() => placesApi.searchNearby(
                  latitude: airport.latitude,
                  longitude: airport.longitude,
                  radiusMeters: radiusMeters,
                  keyword: keyword,
                  pageToken: nextPageToken,
                ));

            for (final result in response.results) {
              if (result.placeId == null) continue;

              // Deduplicate within this airport run
              if (seenPlaceIds.contains(result.placeId)) continue;
              seenPlaceIds.add(result.placeId!);

              // Check if business exists and needs refresh
              final existing = await businessesRepo.findByPlaceId(result.placeId!);

              if (existing != null) {
                // Append airport code if not already there
                await businessesRepo.appendAirportCode(result.placeId!, airport.icaoCode);

                if (!refreshAll) {
                  final needsUpdate = await businessesRepo.needsRefresh(
                    result.placeId!,
                    forceStale: refreshStale,
                  );
                  if (!needsUpdate) {
                    airportSkipCount++;
                    continue;
                  }
                }
                totalUpdated++;
              }

              // Fetch full place details
              try {
                final details = await withRetry(
                  () => placesApi.getPlaceDetails(result.placeId!),
                );

                if (details == null) {
                  cache.logError(
                    airportCode: airport.icaoCode,
                    placeId: result.placeId,
                    businessName: result.name,
                    error: 'Place details returned null',
                  );
                  continue;
                }

                // Convert to business model
                final business = details.toBusiness(
                  airportCode: airport.icaoCode,
                  searchKeyword: keyword,
                );

                // If existing, merge airport codes and search terms
                if (existing != null) {
                  final existingCodes = existing.airportCode ?? '';
                  if (!existingCodes.contains(airport.icaoCode)) {
                    business.airportCode =
                        existingCodes.isEmpty ? airport.icaoCode : '$existingCodes,${airport.icaoCode}';
                  } else {
                    business.airportCode = existingCodes;
                  }

                  // Merge search terms
                  final existingTerms = existing.searchTerms ?? '';
                  if (!existingTerms.contains(keyword)) {
                    business.searchTerms =
                        existingTerms.isEmpty ? keyword : '$existingTerms,$keyword';
                  } else {
                    business.searchTerms = existingTerms;
                  }
                }

                // Run categorization
                _categorizeBusiness(business, categoryService, farLookup);

                // Upsert to MongoDB
                await businessesRepo.upsertByPlaceId(business);
                airportNewCount++;

                print('  + ${result.name} (${result.placeId})');
              } on PlacesApiException catch (e) {
                cache.logError(
                  airportCode: airport.icaoCode,
                  placeId: result.placeId,
                  businessName: result.name,
                  error: e.toString(),
                );
                if (e.statusCode == 401 || e.statusCode == 403) {
                  print('FATAL: API authentication error. Aborting.');
                  await cache.saveErrorLog();
                  exit(1);
                }
              }
            }

            // Handle pagination
            nextPageToken = response.nextPageToken;
            if (nextPageToken == null) break;

            // Need a short delay for Google to process the page token
            await Future.delayed(const Duration(milliseconds: 2000));
            pageNum++;
          } on PlacesApiException catch (e) {
            cache.logError(
              airportCode: airport.icaoCode,
              placeId: null,
              error: 'Nearby search failed for keyword "$keyword": $e',
            );
            if (e.statusCode == 401 || e.statusCode == 403) {
              print('FATAL: API authentication error. Aborting.');
              await cache.saveErrorLog();
              exit(1);
            }
            break; // Skip to next keyword on error
          }
        }
      }

      totalNewBusinesses += airportNewCount;
      totalSkipped += airportSkipCount;

      print('  Airport summary: $airportNewCount new/updated, $airportSkipCount skipped');

      // Mark airport as processed
      await airportsRepo.markProcessed(airport.icaoCode);

      // Save checkpoint every 10 airports
      if ((i + 1) % 10 == 0) {
        await cache.saveCheckpoint(
          lastAirportCode: airport.icaoCode,
          airportsProcessed: i + 1,
          businessesFound: totalNewBusinesses,
          businessesSkipped: totalSkipped,
        );
        print('  [Checkpoint saved at airport ${i + 1}]');
      }
    }

    // Final summary
    print('\n${'=' * 40}');
    print('Sync Complete');
    print('  Airports processed: ${airports.length - startIndex}');
    print('  Businesses new/updated: $totalNewBusinesses');
    print('  Businesses skipped (cached): $totalSkipped');
    print('  Businesses refreshed: $totalUpdated');
    print('  Errors: ${cache.errorCount}');
    print('=' * 40);

    // Save error log and clear checkpoint
    await cache.saveErrorLog();
    await cache.clearCheckpoint();
  } finally {
    await mongoClient.close();
  }
}

/// Apply categorization (search terms + FAR lookup) to a business
void _categorizeBusiness(
  Business business,
  CategoryService categoryService,
  FarLookupService farLookup,
) {
  final name = business.name ?? '';
  final types = business.googleListingTypes?.split(',') ?? [];
  final city = business.city;
  final state = business.state;

  // 1. Auto-categorize using search terms from category dictionary
  final searchTermMatches = categoryService.categorizeBySearchTerms(name, types);

  // 2. FAR file lookup (fuzzy name + city/state)
  final farMatches = farLookup.findMatches(name, city, state);

  // 3. Combine (FAR codes first as they're authoritative, deduplicate)
  final allMatches = <CategoryMatch>{...farMatches, ...searchTermMatches}.toList();

  // 4. Store codes + search terms in paired fields
  business.dbCode = allMatches.isNotEmpty ? allMatches[0].code : null;
  business.dbCode3 = allMatches.length > 1 ? allMatches[1].code : null;
  business.dbCode4 = allMatches.length > 2 ? allMatches[2].code : null;
  business.dbCode5 = allMatches.length > 3 ? allMatches[3].code : null;

  business.searchValue1 = allMatches.isNotEmpty ? allMatches[0].searchTerms : null;
  business.searchValue2 = allMatches.length > 1 ? allMatches[1].searchTerms : null;
  business.searchValue3 = allMatches.length > 2 ? allMatches[2].searchTerms : null;
  business.searchValue4 = allMatches.length > 3 ? allMatches[3].searchTerms : null;
  business.searchValue5 = allMatches.length > 4 ? allMatches[4].searchTerms : null;
}

/// Import airport data from CSV into MongoDB
Future<void> _importAirports(AirportsRepository airportsRepo, MongoDbClient mongoClient) async {
  const filePath = 'assets/airport-codes.csv';
  final file = File(filePath);
  if (!file.existsSync()) {
    print('Airport file not found at $filePath');
    exit(1);
  }

  print('Importing airports from $filePath...');

  final lines = file.readAsLinesSync();
  if (lines.isEmpty) {
    print('ERROR: CSV file is empty');
    exit(1);
  }

  // Parse header row
  final headers = _parseCsvLine(lines[0]).map((h) => h.toLowerCase().trim()).toList();
  print('Found ${headers.length} columns: ${headers.join(", ")}');

  // Find column indices
  int? identCol, nameCol, stateCol, countryCol, latCol, lngCol;
  int? iataCol, localCodeCol, gpsCodeCol;

  for (var i = 0; i < headers.length; i++) {
    final h = headers[i];
    if (h == 'ident') identCol = i;
    if (h == 'name') nameCol = i;
    if (h == 'iso_region' || h == 'region' || h == 'state') stateCol = i;
    if (h == 'iso_country' || h == 'country') countryCol = i;
    if (h == 'latitude_deg' || h == 'latitude' || h == 'latitude_decimal_degrees') latCol = i;
    if (h == 'longitude_deg' || h == 'longitude' || h == 'longitude_decimal_degrees') lngCol = i;
    if (h == 'iata_code') iataCol = i;
    if (h == 'local_code') localCodeCol = i;
    if (h == 'gps_code') gpsCodeCol = i;
  }

  if (identCol == null || latCol == null || lngCol == null) {
    print('ERROR: Could not find required columns (ident, latitude, longitude)');
    print('Available columns: ${headers.join(", ")}');
    exit(1);
  }

  var importCount = 0;
  var skipCount = 0;

  for (var rowIndex = 1; rowIndex < lines.length; rowIndex++) {
    final line = lines[rowIndex].trim();
    if (line.isEmpty) continue;

    final fields = _parseCsvLine(line);

    String field(int? col) {
      if (col == null || col >= fields.length) return '';
      final val = fields[col].trim();
      return (val == 'null' || val == 'NaN') ? '' : val;
    }

    final ident = field(identCol);
    if (ident.isEmpty) continue;

    final lat = double.tryParse(field(latCol));
    final lng = double.tryParse(field(lngCol));

    if (lat == null || lng == null) {
      skipCount++;
      continue;
    }

    final country = field(countryCol);

    // Only import US airports
    if (country.toUpperCase() != 'US') {
      skipCount++;
      continue;
    }

    final name = field(nameCol);
    final stateRaw = field(stateCol);
    final iata = field(iataCol).isEmpty ? null : field(iataCol);
    final localCode = field(localCodeCol).isEmpty ? null : field(localCodeCol);
    final gpsCode = field(gpsCodeCol).isEmpty ? null : field(gpsCodeCol);

    // Extract state abbreviation from iso_region (e.g., "US-CA" -> "CA")
    String? stateAbbr;
    if (stateRaw.contains('-')) {
      stateAbbr = stateRaw.split('-').last;
    } else if (stateRaw.length == 2) {
      stateAbbr = stateRaw;
    } else if (stateRaw.isNotEmpty) {
      stateAbbr = stateRaw;
    }

    final airport = Airport(
      icaoCode: ident,
      iataCode: iata,
      faaCode: localCode,
      gpsCode: gpsCode,
      name: name,
      state: stateAbbr,
      country: country,
      latitude: lat,
      longitude: lng,
    );

    // Retry with reconnect on connection failure
    var imported = false;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await airportsRepo.upsertAirport(airport);
        imported = true;
        break;
      } catch (e) {
        print('  Connection error at $ident, reconnecting (attempt $attempt/3)...');
        try {
          await mongoClient.reconnect();
        } catch (reconnectErr) {
          print('  Reconnect failed, waiting 5s before retry...');
          await Future.delayed(const Duration(seconds: 5));
          await mongoClient.reconnect();
        }
      }
    }
    if (!imported) {
      print('  SKIPPED $ident after 3 failed attempts');
      skipCount++;
      continue;
    }
    importCount++;

    if (importCount % 500 == 0) {
      print('  Imported $importCount airports...');
    }
  }

  print('Import complete: $importCount airports imported, $skipCount skipped');
  print('Total airports in DB: ${await airportsRepo.count()}');
}

/// Parse a CSV line, handling quoted fields with commas
List<String> _parseCsvLine(String line) {
  final fields = <String>[];
  var current = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        current.write('"');
        i++; // skip escaped quote
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      fields.add(current.toString());
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  fields.add(current.toString());
  return fields;
}

String _cellStr(List<dynamic> row, int? col) {
  if (col == null || col >= row.length) return '';
  final cell = row[col];
  if (cell == null) return '';
  final val = (cell is xl.Data) ? cell.value?.toString() : cell.toString();
  if (val == null || val.trim() == 'null' || val.trim() == 'NaN') return '';
  return val.trim();
}

String? _cellStrOrNull(List<dynamic> row, int? col) {
  final val = _cellStr(row, col);
  return val.isEmpty ? null : val;
}
