# FBO Import Pipeline — Web Scraping Strategy

## Overview
Import FBO (Fixed Base Operator) businesses into the MongoDB `avtopia_business` collection by scraping online FBO directories. The pipeline is designed to support **multiple source sites** — GlobalAir.com is the first, with others to follow.

---

## Source: GlobalAir.com

**URL:** `https://www.globalair.com/directories/fbos-176.html`
**Challenge:** Site blocks simple HTTP requests (403 Forbidden) — requires headless browser (Playwright).
**Tech stack:** Node.js v24 + Playwright 1.58 (both already installed)

### Step 1: Playwright scraping script

**File:** `scripts/scrape_fbos_globalair.js`

A self-contained Node.js script that:
1. Launches a headless Chromium browser via Playwright
2. Navigates to the GlobalAir FBO directory
3. Extracts FBO listing data from the current page (name, address, city, state, zip, phone, website, airport association — whatever fields the page exposes)
4. Detects and clicks through pagination to scrape all pages
5. Writes all results to `assets/globalair_fbos.json`

**Notes:**
- Exact HTML selectors TBD until we see the rendered page structure
- Include a small delay between page navigations to be respectful
- Log progress (page number, count of FBOs scraped per page)

---

## Future Sources

Additional FBO directories can be added as separate scrape scripts following the same pattern:
- `scripts/scrape_fbos_<source>.js` → `assets/<source>_fbos.json`
- The Dart import pipeline reads all `*_fbos.json` files (or a specific one via flag)

---

## Dart Import Pipeline

### Step 2: Wire `--import-fbos` flag into CLI

**File to modify:** `lib/main.dart`

1. Add flag to ArgParser:
   ```dart
   ..addFlag('import-fbos', help: 'Import FBOs from scraped data files', defaultsTo: false)
   ```

2. Add handler (after the `--import-airports` block):
   ```dart
   if (options['import-fbos'] as bool) {
     await _importFbos(businessesRepo, airportsRepo, mongoClient);
     return;
   }
   ```

### Step 3: FBO import logic

**New file:** `lib/src/categorization/fbo_import.dart`

Keeps import logic separate from `main.dart`. Contains:
- `loadScrapedFbos(String jsonPath)` — reads a scraped JSON file
- `importFbosToDatabase(BusinessesRepository repo, List<Airport> airports, MongoDbClient client)` — main import loop with matching, airport assignment, and reporting

Uses existing:
- `BusinessesRepository.findByState()` — for duplicate detection
- `BusinessesRepository.insertNew()` — for new records
- `NameMatcher.distanceMiles()` — for airport proximity (50-mile radius)
- `Business` model with `dbCode = 'FBO'`

---

## Files to create/modify

| File | Action |
|------|--------|
| `scripts/scrape_fbos_globalair.js` | **Create** — Playwright scraping script for GlobalAir |
| `lib/src/categorization/fbo_import.dart` | **Create** — Dart import/matching logic |
| `lib/main.dart` | **Modify** — Add `--import-fbos` flag and handler |

---

## Execution flow

```
1. Scrape:   node scripts/scrape_fbos_globalair.js
             → Produces assets/globalair_fbos.json

2. Import:   dart run lib/main.dart --import-fbos
             → Reads JSON, deduplicates, assigns airports, inserts into MongoDB
```

---

## Verification
1. Run the Playwright script, confirm it paginates and captures all FBOs
2. Inspect `assets/globalair_fbos.json` — spot-check a few entries
3. Run `--import-fbos`, check console summary for adds/updates/skips
4. Query MongoDB to verify FBO records have correct fields, `dbCode = 'FBO'`, and airport codes assigned
