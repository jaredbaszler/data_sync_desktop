# Major Refactor: Flutter Desktop → Headless CLI + MongoDB

**Date:** 2026-01-29
**Status:** Planning

---

## Goals
1. **Better Data Management**: Replace Excel with MongoDB Atlas
2. **Workflow Automation**: On-demand runs via GitHub Actions
3. **Scope**: Major refactor

## Decisions Made
- **MongoDB**: Atlas (cloud-hosted)
- **Airport Data**: Start with current Excel (~100 airports), expand later
- **Schedule**: On-demand manual trigger (not scheduled cron)

---

## Architecture

### Current
```
Flutter Desktop App (Windows only)
  ↓
Excel File I/O (read airports, write results)
  ↓
Google Places API
  ↓
Excel File Output (local file)
```

### Target
```
Headless Dart CLI (Linux-compatible for GitHub Actions)
  ↓
MongoDB Atlas (read airports, write results)
  ↓
Google Places API
  ↓
MongoDB Atlas (persistent storage)
  ↓
GitHub Actions (manual trigger via workflow_dispatch)
```

---

## Implementation Phases

### Phase 1: Project Setup (4-6 hours)
- [ ] Create new Dart CLI project (or convert existing)
- [ ] Remove Flutter dependencies from pubspec.yaml
- [ ] Add new dependencies: `mongo_dart`, `dotenv`, `args`, `string_similarity`
- [ ] Set up environment variable configuration
- [ ] Create `.env.example` template

### Phase 2: MongoDB Data Layer (10-12 hours)
- [ ] Create new `airports` collection in MongoDB Atlas
- [ ] Import airport data from `airport-codes_csv.xlsx` (use `Ident` column as ICAO code)
- [ ] Create MongoDB connection class in Dart
- [ ] Implement repository classes for airports and businesses
- [ ] Add indexes: `{ placeId: 1 }` (unique), `{ airportCode: 1 }`

### Phase 3: Refactor Core Logic (16-20 hours)
- [ ] Extract Google Places API functions to separate file
- [ ] Remove Flutter-specific code (rootBundle, WidgetsFlutterBinding)
- [ ] Replace Excel read operations with MongoDB queries
- [ ] Replace Excel write operations with MongoDB upserts
- [ ] **Implement multi-keyword search** (aviation, FBO, flight school, etc.)
- [ ] **Implement auto-categorization** (dbCode, dbCode3-5 fields)
- [ ] **Load category code dictionary** from `Business Category and Search.xlsx`
- [ ] **Implement FAR lookup service** (load 6 FAR Excel files, fuzzy name + city/state matching)
- [ ] **Implement search-term-based categorization** (match business name/types against category search terms)
- [ ] **Integrate FAR lookup + categorization into sync workflow** (combine codes, store in dbCode + searchValue fields)
- [ ] Implement data refresh logic (30/90 day thresholds)
- [ ] Add retry logic with exponential backoff for API calls
- [ ] Implement checkpoint/resume system for interrupted runs
- [ ] Add CLI argument parsing (--refresh-stale, --resume, --limit, --keywords)

### Phase 4: GitHub Actions Setup (4-6 hours)
- [ ] Create workflow file for manual trigger
- [ ] Configure secrets (GOOGLE_PLACES_API_KEY, MONGODB_URI)
- [ ] Test workflow execution
- [ ] Add workflow badge to README

### Phase 5: Testing & Verification (6-8 hours)
- [ ] Test locally with MongoDB Atlas connection
- [ ] Verify data integrity after migration
- [ ] Run full workflow in GitHub Actions
- [ ] Compare results with previous Excel output

---

## MongoDB Schema (EXISTING - `avtopia_business` collection)

You already have an existing MongoDB collection. We'll map to it instead of creating a new schema.

### Field Mapping: Excel Columns → MongoDB Fields

| Excel Column (WriteCols) | MongoDB Field | Type |
|--------------------------|---------------|------|
| `accountName` (3) | `name` | string |
| `dba1` (4) | `dba1` | string |
| `dba2` (5) | `dba2` | string |
| `dba3` (6) | `dba3` | string |
| `shipStreet1` (7) | `address` | string |
| `shipStreet2` (8) | `addressTwo` | string |
| `shipCity` (9) | `city` | string |
| `shipState` (10) | `state` | string |
| `shipZip` (11) | `zipCode` | string |
| `shipCountry` (12) | `country` | string |
| `phone` (13) | `mobileNo` | string |
| `website` (14) | `websiteURL` | string |
| `airportCode` (15) | `airportCode` | string |
| `ignoreEntry` (1) | `ignore` | bool |
| `manualEntry` (2) | `manual` | bool |
| `googlePlaceID` (32) | `placeId` | string |
| `googleCompanyName` (30) | `syncName` | string |
| `googleBusinessStatus` (31) | `businessStatus` | string |
| `googleFormattedAddress` (33) | `fullAddress` | string |
| `googleLatitude` (38) | `location.coordinates[1]` | double |
| `googleLongitude` (39) | `location.coordinates[0]` | double |
| `googleVicinity` (48) | `vicinity` | string |
| `googleBusinessURL` (49) | `businessUrl` | string |
| `googleMapsURL` (27) | `mapUrl` | string |
| `googleIcon` (43) | `image` | string |
| `googleRating` (50) | `rating` | double |
| `googleNumReviews` (51) | `businessReviewCount` | int |
| `googleGlobalCode` (53) | `globalCode` | string |
| `googleCompoundCode` (54) | `compoundCode` | string |
| `googleInternationalPhoneNumber` (45) | `internationalNo` | string |
| `busCat1-5` (16-20) | `searchValue1-5` | string |
| N/A | `isGoogleData` | int (set to 1) |
| N/A | `newData` | bool (set to true) |
| N/A | `createdAt` | date (auto) |
| N/A | `updatedAt` | date (auto) |
| N/A | `sequenceId` | int (auto-increment) |

### Key MongoDB Fields (from existing schema)

```json
{
  "_id": ObjectId,
  "name": "Aviation Company LLC",
  "placeId": "ChIJ_abc123",
  "airportCode": "BUR",
  "address": "123 Airport Way",
  "city": "Burbank",
  "state": "CA",
  "zipCode": "91505",
  "country": "US",
  "mobileNo": "818-555-1234",
  "websiteURL": "https://example.com",
  "businessStatus": "OPERATIONAL",
  "rating": 4.5,
  "businessReviewCount": 123,
  "location": {
    "address": "123 Airport Way, Burbank, CA",
    "coordinates": [-118.3585, 34.2006]  // [lng, lat] - GeoJSON format
  },
  "globalCode": "8553XMQX+XX",
  "compoundCode": "XMQX+XX Burbank",
  "isGoogleData": 1,
  "newData": true,
  "createdAt": ISODate("2026-01-29T14:00:00Z"),
  "updatedAt": ISODate("2026-01-29T14:00:00Z")
}
```

### Note on Location Field
MongoDB uses GeoJSON format: `[longitude, latitude]` (opposite of Google's `[lat, lng]`)

---

## New Collection: `airports`

Create a new collection to store airport data from `airport-codes_csv.xlsx`:

```json
{
  "_id": "KBUR",
  "icaoCode": "KBUR",
  "iataCode": "BUR",
  "faaCode": "BUR",
  "gpsCode": "KBUR",
  "name": "Hollywood Burbank Airport",
  "state": "CA",
  "country": "US",
  "latitude": 34.2006,
  "longitude": -118.3585,
  "sixtyPlusAirport": true,
  "enabled": true,
  "lastProcessed": null,
  "createdAt": ISODate("2026-01-29"),
  "updatedAt": ISODate("2026-01-29")
}
```

### Airport Code Fields (from `airport-codes_csv.xlsx`)

| Field | Source Column | Description | Notes |
|-------|-------------|-------------|-------|
| `icaoCode` | `ident` | ICAO code (international) | 4-char, US airports start with 'K' (e.g., KLAX) |
| `iataCode` | `iata_code` | IATA code (commercial) | 3-letter (LAX, JFK), nullable - only commercial airports |
| `faaCode` | `local_code` | FAA LID (US only) | 3-letter without 'K' prefix (ATL, LAX), nullable for international |
| `gpsCode` | `gps_code` | GPS/navigation code | Often same as ICAO, used for flight planning |

- `_id` uses the ICAO code (`ident`) as the primary key
- `iataCode` will be null for many small airports without commercial service
- `faaCode` will be null for international airports
- NaN values from the Excel file should be stored as null

### Airport Code on Business Records

`airportCode` on `avtopia_business` remains a single string field (no migration needed). Uses the ICAO code.

---

## Environment Variables

```env
# .env
GOOGLE_PLACES_API_KEY=AIza...
MONGODB_URI=mongodb+srv://user:pass@cluster.mongodb.net/
MONGODB_DATABASE=avtopia_devdb
MONGODB_COLLECTION=avtopia_business
SEARCH_RADIUS_MILES=10
```

**Note:** Using your existing database `avtopia_devdb` and collection `avtopia_business`

---

## New Project Structure

```
/lib
  /src
    /database
      mongodb_client.dart
      airports_repository.dart
      businesses_repository.dart
      cache_repository.dart
    /google
      places_api.dart
      nearby_search.dart
      place_details.dart
    /categorization                # NEW
      category_service.dart        # Master code dictionary + search term matching
      far_lookup.dart              # FAR file loading + fuzzy business matching
      name_matcher.dart            # Shared fuzzy matching utilities
    /models
      airport.dart
      business.dart
      category_code.dart           # NEW - CategoryCode model
      far_entry.dart               # NEW - FarEntry model
      (existing models...)
    /utils
      extensions.dart (keep existing)
      config.dart
  main.dart (CLI entry point)
/bin
  run.dart (CLI executable)
/.github
  /workflows
    sync_places.yml
pubspec.yaml
.env.example
README.md
```

---

## GitHub Actions Workflow

```yaml
# .github/workflows/sync_places.yml
name: Sync Aviation Places

on:
  workflow_dispatch:
    inputs:
      airport_filter:
        description: 'Airport code to process (leave empty for all)'
        required: false
      limit:
        description: 'Max airports to process'
        required: false
        default: '100'

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - run: dart pub get

      - name: Run sync
        env:
          GOOGLE_PLACES_API_KEY: ${{ secrets.GOOGLE_PLACES_API_KEY }}
          MONGODB_URI: ${{ secrets.MONGODB_URI }}
          MONGODB_DATABASE: ${{ secrets.MONGODB_DATABASE }}
        run: dart run bin/run.dart --limit=${{ inputs.limit }}
```

---

## Files to Modify/Create

| File | Action | Notes |
|------|--------|-------|
| `pubspec.yaml` | Modify | Remove Flutter, add mongo_dart, dotenv, args |
| `lib/main.dart` | Major rewrite | CLI entry, remove Flutter |
| `lib/src/database/*.dart` | Create | MongoDB data layer |
| `lib/src/google/*.dart` | Create | Extract API logic |
| `lib/src/categorization/*.dart` | Create | FAR lookup, category service, fuzzy matching |
| `lib/src/models/category_code.dart` | Create | CategoryCode model |
| `lib/src/models/far_entry.dart` | Create | FarEntry model |
| `lib/utils/extensions.dart` | Keep | Already framework-agnostic |
| `lib/models/*.dart` | Keep | JSON models still useful |
| `.github/workflows/sync_places.yml` | Create | GitHub Actions workflow |
| `.env.example` | Create | Environment template |
| `GooglePlacesAPIKey.txt` | Delete | Use env var |

---

## Data Migration Plan

### Step 1: Create Airports Collection
1. Import airport data from `airport-codes_csv.xlsx` (use `Ident` column as ICAO code for `_id`)
2. Transform to JSON format matching new `airports` schema
3. Import to new `airports` collection in MongoDB Atlas
4. Add indexes on `_id` (ICAO code) and `state`

### Step 2: Verify Migration
1. Count documents in both collections
2. Spot-check a few records for data integrity

---

## Estimated Total: 50-68 hours

| Phase | Hours |
|-------|-------|
| Project Setup | 4-6 |
| MongoDB Data Layer + Migration | 10-12 |
| Refactor Core Logic (search, categorization, refresh, retry) | 16-20 |
| GitHub Actions Setup | 4-6 |
| Testing & Verification | 16-24 |

---

---

## Multiple Search Keywords

### Current Behavior
Single hardcoded keyword: `"aviation"`

### New Behavior
Configurable list of search keywords to cast a wider net:

```dart
const searchKeywords = [
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
```

### Storage
- **MongoDB field:** `searchTerms`
- **Format:** Comma-separated keywords that matched this business
- **Example:** `"aviation,FBO,hangar"`

### Implementation
- Run Nearby Search for each keyword
- Deduplicate by `placeId` (same business may match multiple keywords)
- Store which keywords matched in `searchTerms` field

---

## Business Categorization + FAR Regulatory Code Lookup

### Master Code Dictionary: `Business Category and Search.xlsx`

This file is the **single source of truth** for all valid database codes. Located in `assets/db_code lookups/`, it defines 139 business category codes organized into 13 operation groups, each with pipe-delimited search terms.

All codes used in `dbCode` fields **must** come from this file. Replaces previously proposed ad-hoc codes:
- `FBO` (official code, same name)
- `FLT141` (replaces "FLIGHT_SCHOOL")
- `P145` (replaces "MAINTENANCE")
- `P135` (replaces "CHARTER")
- `HANG` (replaces "HANGAR")
- `FUELSV` (replaces "FUEL")
- `RENT` (replaces "RENTAL")
- etc. (139 total codes)

### FAR Regulatory File Lookup

Located in `assets/db_code lookups/`:

| File | Matched DB Code | Records |
|------|-----------------|---------|
| FAR 135 Charter Operators_USA ALL_Category Coded.xlsx | `P135` | ~1,267 |
| FAR 141 Pilot Flight Training_ALL USA-With category Code.xlsx | `FLT141` | ~700 |
| FAR 142 Flight Training with Category Codes.xlsx | `FLT142` | ~185 |
| FAR 145 Repair Stations_ALL USA with Category Codes.xlsx | `P145` | ~212 |
| FAR 145 _Florida_ALL_Repair Station_With category codes.xlsx | `P145` | ~640 |
| FAR 147 Aircraft mechanic Schools USA_ALL_Category Coded.xlsx | `P147` | ~222 |

Each FAR file has columns: name, dba1-3, street1, city, state, zipCode, airportCode, dbCode1-5.

### Two-Layer Categorization (runs per business during sync)

```
Google Places result
    ↓
1. Auto-categorize using search terms from Category dictionary
   (match business name/types against pipe-delimited search terms → database code)
    ↓
2. FAR file lookup using fuzzy name + city/state matching
   (match against ~3,200 FAR entries → database code)
    ↓
3. Combine all matched codes + search terms → store in dbCode & searchValue fields
```

**FAR Matching Strategy (Fuzzy Name + Location):**
1. Normalize business names (lowercase, strip "LLC", "Inc", punctuation)
2. Match criteria: Name similarity > 80% (Levenshtein) AND same state (exact) + similar city (fuzzy)
3. Check name, dba1, dba2, dba3 fields from FAR entries
4. A business can match multiple FAR files (e.g., P135 + P145)

**Search Term Categorization:**
- Match business name/types against pipe-delimited search terms from each category
- e.g., name contains "hangar" → code `HANG`
- e.g., name contains "avionics" → code `AVIONICS`

### Storage

**Database codes** → `dbCode`, `dbCode3`, `dbCode4`, `dbCode5`
**Search terms** → `searchValue1` through `searchValue5`

When a business matches a category:
1. The database code (e.g., `P135`) goes in the next available `dbCode` field
2. ALL search terms from that category go in the corresponding `searchValue` field

The `searchValue` fields pair with `dbCode` fields:
- `dbCode` → `searchValue1`
- `dbCode3` → `searchValue2`
- `dbCode4` → `searchValue3`
- `dbCode5` → `searchValue4`
- overflow → `searchValue5`

**Example:** A charter company that's also a repair station and FBO:
```json
{
  "dbCode": "P135",
  "dbCode3": "P145",
  "dbCode4": "FBO",
  "dbCode5": null,
  "searchValue1": "charter | Air Taxi | 135 | on demand charter | aircraft charter | private jet charter",
  "searchValue2": "145 | repair station | maintenance shop | aircraft maintenance",
  "searchValue3": "FBO | fixed base operator",
  "searchValue4": null,
  "searchValue5": null
}
```

### Implementation

```dart
// At startup - load reference data
final categoryService = CategoryService();
await categoryService.loadCategoryDictionary('assets/db_code lookups/Business Category and Search Copy.xlsx');

final farLookup = FarLookupService(categoryService);
await farLookup.loadFarFiles('assets/db_code lookups/');

// Per business, after fetching Google Places details:
final placeDetails = await placesApi.getDetails(placeId);

// 1. Auto-categorize using search terms from category dictionary
final searchTermMatches = categoryService.categorizeBySearchTerms(
  placeDetails.name, placeDetails.types,
);

// 2. FAR file lookup (fuzzy name + city/state)
final farMatches = farLookup.findMatches(
  placeDetails.name, placeDetails.city, placeDetails.state,
);

// 3. Combine (FAR codes first as they're authoritative)
final allMatches = <CategoryMatch>{...farMatches, ...searchTermMatches}.toList();

// 4. Store codes + search terms
business.dbCode  = allMatches.isNotEmpty ? allMatches[0].code : null;
business.dbCode3 = allMatches.length > 1 ? allMatches[1].code : null;
business.dbCode4 = allMatches.length > 2 ? allMatches[2].code : null;
business.dbCode5 = allMatches.length > 3 ? allMatches[3].code : null;

business.searchValue1 = allMatches.isNotEmpty ? allMatches[0].searchTerms : null;
business.searchValue2 = allMatches.length > 1 ? allMatches[1].searchTerms : null;
business.searchValue3 = allMatches.length > 2 ? allMatches[2].searchTerms : null;
business.searchValue4 = allMatches.length > 3 ? allMatches[3].searchTerms : null;
business.searchValue5 = allMatches.length > 4 ? allMatches[4].searchTerms : null;
```

---

## Data Refresh Strategy

### When to Refresh Business Data

| Scenario | Action |
|----------|--------|
| New Place ID (not in DB) | Fetch full details from Google |
| Existing, < 30 days old | Skip (use cached data) |
| Existing, 30-90 days old | Refresh if `--refresh-stale` flag |
| Existing, > 90 days old | Always refresh |
| Business marked `ignore: true` | Skip always |

### Implementation

```dart
// Check if business needs refresh
bool needsRefresh(Business existing, {bool forceStale = false}) {
  if (existing == null) return true;  // New business

  final daysSinceUpdate = DateTime.now().difference(existing.updatedAt).inDays;

  if (daysSinceUpdate > 90) return true;  // Stale data
  if (forceStale && daysSinceUpdate > 30) return true;  // Optional refresh

  return false;  // Use cached data
}
```

### CLI Flags
- `--refresh-stale` - Refresh businesses older than 30 days
- `--refresh-all` - Refresh all businesses (ignore cache)
- `--skip-existing` - Only process new businesses (default behavior)

---

## Error Handling & Retries

### API Error Handling

| Error Type | Strategy |
|------------|----------|
| 429 (Rate Limit) | Exponential backoff: 2s → 4s → 8s → 16s, max 3 retries |
| 500/502/503 (Server) | Retry 3 times with 5s delay |
| 400 (Bad Request) | Log error, skip business, continue |
| 401/403 (Auth) | Abort run, alert on failure |
| Network timeout | Retry 2 times, then skip |

### Implementation

```dart
Future<T> withRetry<T>(Future<T> Function() apiCall, {int maxRetries = 3}) async {
  int attempts = 0;
  while (attempts < maxRetries) {
    try {
      return await apiCall();
    } on RateLimitException {
      attempts++;
      final delay = Duration(seconds: pow(2, attempts).toInt());
      print('Rate limited. Waiting ${delay.inSeconds}s...');
      await Future.delayed(delay);
    } on ServerException {
      attempts++;
      await Future.delayed(Duration(seconds: 5));
    }
  }
  throw MaxRetriesExceeded();
}
```

### Run Recovery

- **Checkpoint system**: Save progress every 10 airports
- **Resume capability**: `--resume` flag to continue from last checkpoint
- **Error log**: Record failed businesses for manual review

### MongoDB Write Errors

| Error | Strategy |
|-------|----------|
| Duplicate key | Update existing document (upsert) |
| Connection lost | Retry connection 3 times, then abort |
| Validation error | Log error, skip document |

---

## Verification Checklist

- [ ] CLI runs locally with MongoDB Atlas
- [ ] Processes 5 test airports successfully
- [ ] Place ID caching works (second run skips cached)
- [ ] Data refresh respects age thresholds
- [ ] Retry logic handles rate limits gracefully
- [ ] Checkpoint/resume works after interruption
- [ ] GitHub Actions workflow triggers manually
- [ ] Secrets are properly configured
- [ ] Results appear in MongoDB collections
- [ ] Run logs are recorded
- [ ] Category dictionary loads all 139 codes from `Business Category and Search.xlsx`
- [ ] FAR files load (~3,200 total entries across 6 files)
- [ ] Known FAR 135 business matches → tagged with `P135`
- [ ] Known FAR 145 business matches → tagged with `P145`
- [ ] Business in multiple FAR files → multiple codes stored
- [ ] Search term matching works (e.g., "hangar" in name → `HANG`)
- [ ] Codes stored are valid codes from the category dictionary
- [ ] searchValue fields populated with full search terms from matched category
- [ ] searchValue fields pair correctly with their dbCode fields
