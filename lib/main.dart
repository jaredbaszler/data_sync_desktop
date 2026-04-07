import 'dart:io';

import 'package:args/args.dart';
import 'package:excel/excel.dart' as xl;

import 'src/categorization/category_service.dart';
import 'src/categorization/far_lookup.dart';
import 'src/categorization/fbo_import.dart';
import 'src/categorization/website_crawler.dart';
import 'src/database/business_contacts_repository.dart';
import 'src/database/businesses_repository.dart';
import 'src/database/cache_repository.dart';
import 'src/database/airports_repository.dart';
import 'src/database/mongodb_client.dart';
import 'src/google/geocoding_service.dart';
import 'src/google/places_api.dart';
import 'src/google/places_api_cache.dart';
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
    ..addFlag('skip-crawl', help: 'Skip website crawling for categorization', defaultsTo: false)
    ..addFlag('enrich-far-145',
        help: 'Enrich database from FAA 145 file (first 25 rows for testing)', defaultsTo: false)
    ..addFlag('import-fbos',
        help: 'Import FBO businesses from scraped GlobalAir data', defaultsTo: false)
    ..addOption('fbo-limit',
        help: 'Max FBOs to import (0 = all). Use for test runs before full import.', defaultsTo: '0')
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

  // Set up website crawler (unless --skip-crawl)
  final skipCrawl = options['skip-crawl'] as bool;
  final websiteCrawler = skipCrawl ? null : WebsiteCrawler();

  // Connect to MongoDB
  final mongoClient = MongoDbClient(config);
  await mongoClient.connect();

  try {
    final airportsRepo = AirportsRepository(mongoClient);
    final businessesRepo = BusinessesRepository(mongoClient, collectionName: config.mongodbCollection);
    final contactsRepo = BusinessContactsRepository(mongoClient);

    // Handle airport import mode
    if (options['import-airports'] as bool) {
      await _importAirports(airportsRepo, mongoClient);
      return;
    }

    // Handle FBO import mode
    if (options['import-fbos'] as bool) {
      await airportsRepo.ensureIndexes();
      await businessesRepo.ensureIndexes();
      await contactsRepo.ensureIndexes();
      // Reconnect after ensureIndexes — a failed index creation (e.g. duplicate
      // placeId=null on an existing non-sparse index) can leave the driver in a
      // broken state even though the error was caught and logged.
      await mongoClient.reconnect();
      final allAirports = await airportsRepo.getEnabledAirports();
      final fboLimit = int.tryParse(options['fbo-limit'] as String) ?? 0;
      final geocoder = GeocodingService(
        config.googlePlacesApiKey,
        cacheFilePath: 'assets/db_code lookups/fbo_geocode_cache.json',
      );
      final fboService = FboImportService();
      await fboService.importFromJson(
        ['assets/globalair_fbos.json', 'assets/charterhub_fbos.json', 'assets/airnav_fbos.json', 'assets/aopa_fbos.json'],
        businessesRepo,
        contactsRepo,
        allAirports,
        mongoClient,
        geocoder,
        maxRows: fboLimit > 0 ? fboLimit : null,
      );
      return;
    }

    // Ensure indexes
    await airportsRepo.ensureIndexes();
    await businessesRepo.ensureIndexes();
    await contactsRepo.ensureIndexes();

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

    final enrichFar145 = options['enrich-far-145'] as bool;

    if (Directory(farDir).existsSync()) {
      await farLookup.loadFarFiles(farDir);

      // Geocode FAR entries so GPS proximity can be used in matching.
      // Cached results are loaded from disk — only new addresses hit the API.
      final geocoder = GeocodingService(config.googlePlacesApiKey);
      await farLookup.geocodeEntries(geocoder);

      // Enrich database from FAA 145 if flag is set
      if (enrichFar145) {
        // Reconnect to MongoDB in case connection dropped during geocoding
        await mongoClient.reconnect();
        final allAirports = await airportsRepo.getEnabledAirports();
        await farLookup.enrichDatabaseFromFar145(businessesRepo, contactsRepo, allAirports, mongoClient);
        print('FAA 145 enrichment complete. Exiting.');
        return;
      }
    } else {
      print('WARNING: FAR lookup directory not found at $farDir');
    }

    // Configure search keywords
    final keywords = (options['keywords'] as List<String>).isNotEmpty
        ? options['keywords'] as List<String>
        : defaultSearchKeywords;

    // Set up Places API and its persistent response cache
    final placesApi = PlacesApi.fromConfig(config);
    final placesCache = PlacesApiCache();
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

      var dbConnectionLost = false;
      try {
        for (final keyword in keywords) {
          String? nextPageToken;
          var pageNum = 1;

          while (pageNum <= 3) {
            try {
              // Check nearby cache before hitting the API
              final cachedPage = placesCache.getNearby(airport.icaoCode, keyword, pageNum);
              NearbySearchResponse response;
              bool fromCache;

              if (cachedPage != null) {
                fromCache = true;
                final rawResults =
                    (cachedPage['results'] as List).cast<Map<String, dynamic>>();
                response = NearbySearchResponse(
                  results: rawResults.map(NearbyResult.fromJson).toList(),
                  nextPageToken: null,
                  status: 'OK',
                );
              } else {
                fromCache = false;
                response = await withRetry(() => placesApi.searchNearby(
                      latitude: airport.latitude,
                      longitude: airport.longitude,
                      radiusMeters: radiusMeters,
                      keyword: keyword,
                      pageToken: nextPageToken,
                    ));
                placesCache.storeNearby(airport.icaoCode, keyword, pageNum,
                    response.results, response.nextPageToken != null);
              }

              for (final result in response.results) {
                if (result.placeId == null) continue;

                // Deduplicate within this airport run
                if (seenPlaceIds.contains(result.placeId)) continue;
                seenPlaceIds.add(result.placeId!);

                // --- Match existing record (placeId → GPS → address) ---
                Business? existing = await businessesRepo.findByPlaceId(result.placeId!);

                // GPS fallback: nearby search already includes lat/lng, no extra API call needed
                if (existing == null && result.lat != null && result.lng != null) {
                  final byCoords =
                      await businessesRepo.findByCoordinates(result.lat!, result.lng!);
                  if (byCoords != null) {
                    await businessesRepo.updatePlaceId(byCoords.placeId!, result.placeId!);
                    existing = byCoords;
                    print('    [match] GPS: "${byCoords.name}" → "${result.name}"');
                  }
                }

                // Refresh check for placeId / GPS matches
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

                // Fetch full place details (check cache first)
                try {
                  Map<String, dynamic>? rawDetails =
                      placesCache.getDetails(result.placeId!);
                  if (rawDetails == null) {
                    rawDetails = await withRetry(
                      () => placesApi.getPlaceDetailsRaw(result.placeId!),
                    );
                    if (rawDetails != null) {
                      placesCache.storeDetails(result.placeId!, rawDetails);
                    }
                  }
                  final details =
                      rawDetails != null ? PlaceDetailsResult.fromJson(rawDetails) : null;

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

                  // Address fallback: only available after fetching details
                  if (existing == null && details.streetAddress.isNotEmpty) {
                    final byAddr = await businessesRepo.findByAddress(
                        details.streetAddress, details.city);
                    if (byAddr != null) {
                      await businessesRepo.updatePlaceId(byAddr.placeId!, result.placeId!);
                      await businessesRepo.appendAirportCode(result.placeId!, airport.icaoCode);
                      existing = byAddr;
                      print('    [match] Address: "${byAddr.name}" → "${result.name}"');
                    }
                  }

                  // If existing (by any method), merge airport codes and search terms
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
                  await _categorizeBusiness(business, categoryService, farLookup, websiteCrawler);

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
              if (fromCache) {
                // Continue only if the next page is also in cache
                final hasNextPage = cachedPage!['has_next_page'] as bool? ?? false;
                if (!hasNextPage ||
                    placesCache.getNearby(airport.icaoCode, keyword, pageNum + 1) == null) {
                  break;
                }
              } else {
                nextPageToken = response.nextPageToken;
                if (nextPageToken == null) break;
                // Need a short delay for Google to process the page token
                await Future.delayed(const Duration(milliseconds: 2000));
              }
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
      } catch (e) {
        // Catch MongoDB connection drops that escape the inner PlacesApiException handlers
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('connection') ||
            errStr.contains('socket') ||
            errStr.contains('closed') ||
            errStr.contains('mongo')) {
          print('  MongoDB connection lost during ${airport.icaoCode}, reconnecting...');
          cache.logError(airportCode: airport.icaoCode, placeId: null, error: 'DB connection lost: $e');
          try {
            await mongoClient.reconnect();
          } catch (reconnectErr) {
            print('  Reconnect failed: $reconnectErr');
          }
          dbConnectionLost = true;
        } else {
          rethrow;
        }
      }

      // Skip summary and checkpoint if connection was lost mid-airport
      if (dbConnectionLost) continue;

      totalNewBusinesses += airportNewCount;
      totalSkipped += airportSkipCount;

      print('  Airport summary: $airportNewCount new/updated, $airportSkipCount skipped');

      // Flush API caches to disk after each airport
      await placesCache.saveCaches();

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
    websiteCrawler?.close();
    await mongoClient.close();
  }
}

/// Apply categorization (search terms + FAR lookup + website crawl) to a business
Future<void> _categorizeBusiness(
  Business business,
  CategoryService categoryService,
  FarLookupService farLookup,
  WebsiteCrawler? websiteCrawler,
) async {
  final name = business.name ?? '';
  final types = business.googleListingTypes?.split(',') ?? [];
  final city = business.city;
  final state = business.state;
  final street = business.address;
  final lat = business.latitude;
  final lng = business.longitude;

  // 1. Auto-categorize using search terms from category dictionary
  final searchTermMatches = categoryService.categorizeBySearchTerms(name, types);

  // 2. FAR file lookup (name → address → GPS proximity)
  // Include business DBAs in the name matching for better coverage
  final bizDbas = [
    if (business.dba1 != null && business.dba1!.isNotEmpty) business.dba1!,
    if (business.dba2 != null && business.dba2!.isNotEmpty) business.dba2!,
    if (business.dba3 != null && business.dba3!.isNotEmpty) business.dba3!,
  ];
  final farMatches = farLookup.findMatches(
    name,
    city,
    state,
    street: street,
    lat: lat,
    lng: lng,
    businessDbas: bizDbas,
  );

  // 3. Website content crawl (only if URL available and crawler enabled)
  var websiteMatches = <CategoryMatch>[];
  final url = business.websiteURL;
  if (websiteCrawler != null && url != null && url.isNotEmpty) {
    final pageText = await websiteCrawler.fetchPageText(url);
    if (pageText != null && pageText.isNotEmpty) {
      websiteMatches = categoryService.categorizeByWebsiteContent(pageText);
      if (websiteMatches.isNotEmpty) {
        print('    [crawl] ${websiteMatches.length} category match(es) from $url');
      }
    }
  }

  // 4. Combine: FAR first (authoritative), then search terms, then website (supplemental)
  final allMatches = <CategoryMatch>{
    ...farMatches,
    ...searchTermMatches,
    ...websiteMatches,
  }.toList();

  // 5. Store db codes only — search terms live in the business_category table, not here
  business.dbCode = allMatches.isNotEmpty ? allMatches[0].code : null;
  business.dbCode3 = allMatches.length > 1 ? allMatches[1].code : null;
  business.dbCode4 = allMatches.length > 2 ? allMatches[2].code : null;
  business.dbCode5 = allMatches.length > 3 ? allMatches[3].code : null;
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
