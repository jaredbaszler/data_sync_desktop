# Google Places API Cost Optimization Plan
**Date:** 2026-01-29
**Project:** data_sync_desktop (Aviation Business Discovery)

---

## Summary

Analyze API costs using the **New Places API pricing** (tier-based billing where requesting one field from a tier = full tier cost).

**FINAL DECISION:** Option A - Simple 10-Mile Radius + Caching (~$1,912/year for 1,000 airports)

---

## New Places API Pricing (Per 1,000 Requests)

| Tier | Nearby Search | Place Details | Volume Discount (100K+) |
|------|---------------|---------------|-------------------------|
| **Essentials** | N/A | $5.00 | $4.00 |
| **Pro** | $32.00 | $17.00 | $13.60 |
| **Enterprise** | $35.00 | $20.00 | $16.00 |
| **Enterprise + Atmosphere** | $40.00 | $25.00 | $20.00 |

### Field-to-Tier Mapping (Key Fields)

| Tier | Fields That Trigger This Tier |
|------|-------------------------------|
| **Essentials** | `formattedAddress`, `location`, `types`, `plusCode`, `addressComponents` |
| **Pro** | `displayName`, `businessStatus`, `googleMapsUri`, `utcOffsetMinutes` |
| **Enterprise** | `rating`, `websiteUri`, `nationalPhoneNumber`, `internationalPhoneNumber`, `regularOpeningHours`, `userRatingCount`, `priceLevel` |
| **Enterprise + Atmosphere** | `reviews`, `editorialSummary`, `parkingOptions`, `delivery`, `dineIn`, etc. |

**Critical:** If you request even ONE field from Enterprise tier, you pay the full Enterprise price.

---

## Your Current Usage Analysis

Your code requests these fields (from [main.dart lines 17-24](lib/main.dart#L17-L24)):

| Field You Request | Maps To (New API) | Tier |
|-------------------|-------------------|------|
| `rating` | `rating` | **Enterprise** |
| `website` | `websiteUri` | **Enterprise** |
| `formatted_phone_number` | `nationalPhoneNumber` | **Enterprise** |
| `international_phone_number` | `internationalPhoneNumber` | **Enterprise** |
| `opening_hours` | `regularOpeningHours` | **Enterprise** |
| `user_ratings_total` | `userRatingCount` | **Enterprise** |
| `review` | `reviews` | **Enterprise + Atmosphere** |

**Result:** You're paying **Enterprise + Atmosphere** tier because you request `reviews`.

---

## Key Finding: Reviews Trigger Highest Tier

If you remove the `review` field request, you drop from Enterprise+Atmosphere ($25/1000) to Enterprise ($20/1000) for Place Details - a **20% savings**.

### Current Fields Triggering Each Tier:
- **Enterprise + Atmosphere** ($25): `review` (reviews data)
- **Enterprise** ($20): `rating`, `website`, `phone`, `opening_hours`
- **Pro** ($17): `businessStatus`, `url` (googleMapsUri)
- **Essentials** ($5): `formatted_address`, `geometry`, `types`

---

## Place ID Caching Optimization

Deduplication exists (lines 612-623) but is **in-memory only**. Resets each run, missing cross-run savings.

**Solution:** Add persistent Place ID caching to skip businesses already in database on repeat runs.

---

## Cost Projections (New API Pricing)

### Assumptions
- ~100 airports currently, scaling to 1,000+
- ~75 businesses found per airport (based on April 2022 data)
- Nearby Search: ~2.5 pages average per airport
- Place Details: 1 call per business

### Current Approach (Enterprise + Atmosphere Tier)

| Scale | Nearby Search | Place Details | Total |
|-------|---------------|---------------|-------|
| 100 airports | 250 calls × $0.040 = $10 | 7,500 calls × $0.025 = $188 | **~$198** |
| 500 airports | 1,250 calls × $0.040 = $50 | 37,500 calls × $0.025 = $938 | **~$988** |
| 1,000 airports | 2,500 calls × $0.040 = $100 | 75,000 calls × $0.025 = $1,875 | **~$1,975** |
| 2,500 airports | 6,250 calls × $0.035* = $219 | 187,500 calls × $0.020* = $3,750 | **~$3,969** |

*Volume discounts kick in at 100K+ requests

### After Removing `reviews` (Drop to Enterprise Tier) ✓ CONFIRMED

| Scale | Nearby Search | Place Details | Total | Savings vs Current |
|-------|---------------|---------------|-------|---------------------|
| 100 airports | 250 × $0.035 = $9 | 7,500 × $0.020 = $150 | **~$159** | **$39 (20%)** |
| 500 airports | 1,250 × $0.035 = $44 | 37,500 × $0.020 = $750 | **~$794** | **$194 (20%)** |
| 1,000 airports | 2,500 × $0.035 = $88 | 75,000 × $0.020 = $1,500 | **~$1,588** | **$387 (20%)** |
| 2,500 airports | 6,250 × $0.028* = $175 | 187,500 × $0.016* = $3,000 | **~$3,175** | **$794 (20%)** |

*Volume discounts at 100K+ requests

---

## Alternatives Considered

### Option 1: Remove `reviews` Field ✓ SELECTED
- Drop from Enterprise+Atmosphere ($25/1000) to Enterprise ($20/1000)
- Lose: Individual review text
- Keep: Rating, review count, phone, website, hours
- **Savings: 20%**

### Option 2: Persistent Place ID Cache ✓ SELECTED
- Store processed Place IDs in JSON file
- Skip Place Details for businesses seen in previous runs
- Businesses near multiple airports only fetched once
- **Savings: ~84% on repeat runs**

### Option 3: Drop to Pro Tier ✗ REJECTED
- Would need to remove: rating, phone, website, hours
- Not acceptable - need this data

### Option 4: Use Nearby Search Data Where Possible
- Nearby Search already returns `rating` and `userRatingCount`
- But still need Place Details for phone/website/address
- Doesn't change the tier you pay

### Option 5: 9-Point Grid Search ✗ NOT SELECTED (for now)
- Would increase coverage from 60 to ~300 businesses/airport
- Cost: ~$11,580/year vs $1,912/year
- Can revisit if need more comprehensive coverage

---

## Final Decision: Option A - Simple 10-Mile Radius + Caching

**Cost: ~$1,912/year for 1,000 airports (4 runs)**

Features to implement:
1. ✅ Remove `reviews` field (drop to Enterprise tier)
2. ✅ Change radius from 5mi to 10mi
3. ✅ Add persistent Place ID caching

---

## Option A vs Option B Comparison

| Factor | Option A: Simple 10mi | Option B: Grid + Cache |
|--------|----------------------|------------------------|
| First run | $1,288 | $6,945 |
| Repeat run (with cache) | $208 | $1,545 |
| Annual (4 runs) | **$1,912** | $11,580 |
| Businesses found | ~60K | ~300K |
| Coverage | Top 60/airport | Comprehensive |

---

## Implementation Steps

### Step 1: Remove `review` from Atmosphere field list

**File:** [lib/main.dart line 24](lib/main.dart#L24)

```dart
// FROM:
const detailsSearchAtmosphereList = 'price_level,rating,review,user_ratings_total';

// TO:
const detailsSearchAtmosphereList = 'price_level,rating,user_ratings_total';
```

### Step 2: Change radius from 5mi to 10mi

**File:** [lib/main.dart line 365](lib/main.dart#L365)

```dart
// FROM:
final radius = 5.0.milesToMeters();

// TO:
final radius = 10.0.milesToMeters();
```

### Step 3: Add persistent Place ID caching

**File:** [lib/main.dart](lib/main.dart)

Add at top of `googleSearchNearby()` function:
```dart
// Load cache from file
final cacheFile = File('assets/place_id_cache.json');
if (await cacheFile.exists()) {
  final cacheJson = jsonDecode(await cacheFile.readAsString());
  placeIDs = Map<String, int>.from(cacheJson);
  print('Loaded ${placeIDs.length} cached Place IDs');
}
```

Add before the file save at end of function:
```dart
// Save cache to file
await cacheFile.writeAsString(jsonEncode(placeIDs));
print('Saved ${placeIDs.length} Place IDs to cache');
```

Modify the Place Details call (around line 721) to skip cached entries:
```dart
// Only call Place Details for new businesses (not in cache from previous runs)
if (!placeIDs.containsKey(nearbyResult.placeId)) {
  await getPlaceDetails(writeSheet, readSheet, writeIndex, nearbyResult.placeId);
}
```

### Step 4: Add cache status tracking (optional)

Track which businesses are cached vs newly fetched for reporting:
```dart
var newBusinessCount = 0;
var cachedBusinessCount = 0;
// Increment appropriately in the loop
print('New: $newBusinessCount, Cached: $cachedBusinessCount');
```

### Step 5: Add cache date tracking

Track when each Place ID was first cached to know data freshness:
```dart
// Global map to track dates
Map<String, String> placeIDDates = <String, String>{};

// When adding new Place ID:
placeIDDates.putIfAbsent(nearbyResult.placeId, () => DateTime.now().toIso8601String().split('T')[0]);

// Save both maps together:
final cacheData = {
  'placeIDs': placeIDs,
  'placeIDDates': placeIDDates,
  'lastUpdated': DateTime.now().toIso8601String(),
};
```

---

## Cache File Structure

The cache file `assets/place_id_cache.json` uses this format:
```json
{
  "placeIDs": {
    "ChIJ_abc123": 2,
    "ChIJ_xyz789": 3
  },
  "placeIDDates": {
    "ChIJ_abc123": "2026-01-29",
    "ChIJ_xyz789": "2026-01-29"
  },
  "lastUpdated": "2026-01-29T14:30:00.000Z"
}
```

This allows you to:
- See when each business was first cached
- Identify stale data that may need refreshing
- Track when the cache was last updated

---

## Files to Modify

| File | Changes |
|------|---------|
| [lib/main.dart](lib/main.dart) | Line 24 (remove `review`), Line 365 (radius), cache logic with dates |
| New: `assets/place_id_cache.json` | Auto-created by cache logic |

---

## Verification

1. **Test with 2-3 airports first** - Verify search works correctly
2. **Check API console** - Confirm costs match projections
3. **Run twice** - Verify cache reduces Place Details calls on second run
4. **Check Excel output** - Ensure all data columns still populated

---

## Sources

- [Google Maps Platform Pricing](https://developers.google.com/maps/billing-and-pricing/pricing#places-pricing)
- [Place Data Fields (Tier Reference)](https://developers.google.com/maps/documentation/places/web-service/data-fields)
- [Places API Usage and Billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing)
