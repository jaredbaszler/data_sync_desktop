# Add Website Crawl for Better Business Categorization

## Context
Businesses are currently categorized using (1) name/Google types matching against a category dictionary, and (2) FAR file fuzzy lookup. Some businesses get miscategorized because their names don't reveal their true nature (e.g., "Sonoma Valley Airport" coded as real estate). Crawling their website would provide much richer text to match against the same category search terms.

The `websiteURL` field is already populated from Google Places API, and the `http` package is already a dependency. No new packages needed.

## Plan

### 1. Create `lib/src/categorization/website_crawler.dart` (NEW)
- `WebsiteCrawler` class with a shared `http.Client` for connection reuse
- `fetchPageText(String url)` → fetches URL with 5-second timeout, strips HTML tags/scripts/styles, returns plain text (capped at 10,000 chars), returns `null` on any error
- `close()` method to clean up the HTTP client

### 2. Add `categorizeByWebsiteContent()` to `lib/src/categorization/category_service.dart`
- New method that takes extracted website text and matches against the same category search terms
- Nearly identical to existing `categorizeBySearchTerms()` but operates on a single text blob
- Sets `source: 'website'` on matches (the `CategoryMatch.source` field already exists)

### 3. Update `_categorizeBusiness()` in `lib/main.dart`
- Make it `async` (currently sync)
- Add `WebsiteCrawler` parameter
- After existing Steps 1 & 2, add Step 3: if `business.websiteURL` is non-null, fetch page text and run website categorization
- Combine all matches: FAR first (authoritative), then search terms, then website (supplemental)
- Update the call site (~line 263) to `await`

### 4. Wire up in `main()`
- Create `WebsiteCrawler` instance near other service initializations
- Pass it to `_categorizeBusiness`
- Close it in the `finally` block
- Add `--skip-crawl` CLI flag to disable website crawling when not needed

## Files to modify
- `lib/src/categorization/website_crawler.dart` — **NEW** WebsiteCrawler class
- `lib/src/categorization/category_service.dart` — add `categorizeByWebsiteContent()` method
- `lib/main.dart` — make `_categorizeBusiness` async, wire up crawler, add `--skip-crawl` flag

## Verification
- Run with debug airports (`KBZN,KAPC,KASE`) from `.env.local`
- Confirm businesses with websites get additional/corrected category codes from website content
- Run with `--skip-crawl` and confirm website crawl is skipped
- Verify businesses without websites are unaffected
