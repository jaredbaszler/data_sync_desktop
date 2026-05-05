// Scrape charter flight operator listings from AirCharterGuide via Tuvoli's open JSON API
// Run: node scripts/scrape_charter_operators.js
//
// Discovery: aircharterguide.com is an Angular SPA backed by an open JSON API at
//   https://aircharterguide-api.tuvoli.com/api/v1/operator/*
// The API bypasses Cloudflare protection on the public site. No Playwright needed.
//
// Endpoints:
//   1. /operator/results?dt=8&Region=north%20america&Country=us  → list (907 US operators, ~1MB)
//   2. /operator/details?companyId=X&locationId=Y&dataType=8     → fleet count, pilots, contact HTML
//   3. /operator/aircraft-fleet?companyId=X&locationId=Y&dataType=8&city=Z → aircraft table
//
// Output: assets/aircharterguide_operators.json (one entry per operator location)
// Resume: .meta file tracks last completed operator index

const https = require('https');
const fs = require('fs');
const path = require('path');

const OUTPUT_PATH = path.join(__dirname, '..', 'assets', 'aircharterguide_operators.json');
const META_PATH   = OUTPUT_PATH + '.meta';
const DELAY_MS    = 1200;
const MAX_OPERATORS = process.env.LIMIT ? parseInt(process.env.LIMIT, 10) : null;

// ─── HTTP helper ──────────────────────────────────────────────────────────────

function fetchJson(pathname, retries = 3) {
  return new Promise(async (resolve) => {
    for (let attempt = 1; attempt <= retries; attempt++) {
      const result = await new Promise((res) => {
        https.get({
          hostname: 'aircharterguide-api.tuvoli.com',
          path: pathname,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Accept': 'application/json',
            'Origin': 'https://www.aircharterguide.com',
            'Referer': 'https://www.aircharterguide.com/',
          },
        }, r => {
          if (r.statusCode === 429 || r.statusCode === 503) return res('RATE_LIMITED');
          if (r.statusCode === 404 || r.statusCode === 400) return res(null);
          if (r.statusCode !== 200) return res(null);
          let body = '';
          r.on('data', d => body += d);
          r.on('end', () => { try { res(JSON.parse(body)); } catch { res(null); } });
          r.on('error', () => res(null));
        }).on('error', () => res(null));
      });

      if (result === 'RATE_LIMITED') {
        const waitSec = attempt * 30;
        console.warn(`  [rate limited] waiting ${waitSec}s...`);
        await delay(waitSec * 1000);
        continue;
      }
      return resolve(result);
    }
    resolve(null);
  });
}

function delay(ms) {
  return new Promise(r => setTimeout(r, ms + Math.random() * (ms * 0.25)));
}

// ─── Parsers ─────────────────────────────────────────────────────────────────

// The detail endpoint returns a `contactDetails` HTML string. Parse it for
// address lines, phone, email, website.
function parseContactDetails(html) {
  if (!html) return {};
  const out = {};

  // Email — appears twice: a masked "Show Email" span and the real mailto href
  const emailMatch = html.match(/mailto:([^'"]+)/i);
  if (emailMatch) out.email = emailMatch[1].split(';')[0].trim();

  // Phone — "Tel: 603-351-5151"
  const telMatch = html.match(/Tel:\s*([\d\-\(\)\s\.ext]+)/i);
  if (telMatch) {
    const digits = telMatch[1].replace(/\D/g, '');
    if (digits.length === 10) {
      out.phone = `(${digits.slice(0,3)}) ${digits.slice(3,6)}-${digits.slice(6)}`;
    } else {
      out.phone = telMatch[1].trim();
    }
  }

  // Fax — "Fax: ..."
  const faxMatch = html.match(/Fax:\s*([\d\-\(\)\s\.]+)/i);
  if (faxMatch) {
    const digits = faxMatch[1].replace(/\D/g, '');
    if (digits.length === 10) out.fax = `(${digits.slice(0,3)}) ${digits.slice(3,6)}-${digits.slice(6)}`;
  }

  // Website — href='http...' that isn't mailto
  const siteMatch = html.match(/href=['"](https?:\/\/[^'"]+)['"][^>]*target=['"]_blank['"]/i);
  if (siteMatch) out.website = siteMatch[1];

  // Address — lines between <strong>COMPANY</strong><br /> and <strong>Tel:
  // e.g. "<strong>AIR NEW ENGLAND LLC</strong><br />62 DURHAM RD<br />PORTMOUTH, NH, United States<br /><strong>Tel:..."
  const addrMatch = html.match(/<\/strong>\s*<br\s*\/?>\s*([\s\S]*?)<strong>\s*Tel/i);
  if (addrMatch) {
    const addrLines = addrMatch[1]
      .split(/<br\s*\/?>/i)
      .map(s => s.replace(/<[^>]+>/g, '').trim())
      .filter(Boolean);
    if (addrLines.length >= 1) {
      // Last line is usually "CITY, STATE, COUNTRY" — keep street lines only
      const street = addrLines.slice(0, -1).join(', ');
      out.address = street || addrLines[0];
    }
  }

  return out;
}

// Extract long description from profileData — shape is array-like with
// numeric keys, each holding { contentStr: "<p>...</p>", IsActive, ... }
function extractDescription(profileData) {
  if (!profileData) return '';
  if (typeof profileData === 'string') return stripHtml(profileData);

  const entries = Array.isArray(profileData) ? profileData : Object.values(profileData);
  const active = entries
    .filter(e => e && e.IsActive !== false && !e.IsDeleted)
    .map(e => e.contentStr || e.LongDesc || e.Description || '')
    .filter(Boolean);
  if (active.length === 0) return '';
  return stripHtml(active.join('\n\n'));
}

function stripHtml(html) {
  return html
    .replace(/<\/p>\s*<p[^>]*>/gi, '\n\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// ─── Save helpers ────────────────────────────────────────────────────────────

function save(records) {
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(records, null, 2));
}

function saveMeta(lastIndex, totalOperators, complete = false) {
  fs.writeFileSync(META_PATH, JSON.stringify({ lastIndex, totalOperators, complete }));
}

// ─── Main ─────────────────────────────────────────────────────────────────────

(async () => {
  console.log('Fetching operator list (single API call)...');
  const list = await fetchJson('/api/v1/operator/results?dt=8&Region=north%20america&Country=us');
  if (!list?.data?.length) {
    console.error('ERROR: Could not fetch operator list.');
    process.exit(1);
  }
  const operators = list.data;
  console.log(`  Total US operators: ${operators.length}`);
  console.log(`  Sample: ${operators[0].BusName1} (CompanyID ${operators[0].CompanyID}, LocationID ${operators[0].LocationID})`);

  // Resume support
  let records = [];
  let startIdx = 0;

  if (fs.existsSync(OUTPUT_PATH)) {
    try {
      const existing = JSON.parse(fs.readFileSync(OUTPUT_PATH, 'utf-8'));
      if (Array.isArray(existing)) records = existing;
    } catch { records = []; }
  }

  if (fs.existsSync(META_PATH)) {
    try {
      const meta = JSON.parse(fs.readFileSync(META_PATH, 'utf-8'));
      if (meta.complete) {
        console.log(`Scrape already complete. ${records.length} operators saved.`);
        process.exit(0);
      }
      if (typeof meta.lastIndex === 'number') {
        startIdx = meta.lastIndex + 1;
        console.log(`Resuming from index ${startIdx}/${operators.length}, ${records.length} operators already saved.`);
      }
    } catch {}
  }

  const endIdx = MAX_OPERATORS ? Math.min(startIdx + MAX_OPERATORS, operators.length) : operators.length;
  if (MAX_OPERATORS) console.log(`  LIMIT=${MAX_OPERATORS}, processing ${startIdx}..${endIdx - 1}`);

  let succeeded = 0;
  let failed = 0;
  let withFleet = 0;

  for (let i = startIdx; i < endIdx; i++) {
    const op = operators[i];
    const { CompanyID, LocationID, BusName1, City } = op;

    try {
      const detailPath = `/api/v1/operator/details?companyId=${CompanyID}&locationId=${LocationID}&dataType=8`;
      const detail = await fetchJson(detailPath);
      await delay(DELAY_MS);

      const cityParam = encodeURIComponent((City || '').toLowerCase());
      const fleetPath = `/api/v1/operator/aircraft-fleet?companyId=${CompanyID}&locationId=${LocationID}&dataType=8&city=${cityParam}`;
      const fleet = await fetchJson(fleetPath);

      // Build combined record
      const contact = parseContactDetails(detail?.contactDetails);

      const aircraft = (fleet?.data || []).map(a => ({
        aircraftId: a.AircraftID,
        category: a.CategoryName || '',
        manufacturer: a.ManufacturerName || '',
        typeName: a.TypeName || '',
        typeCode: a.TypeCode || '',
        tailNumber: a.Tailnumber || '',
        year: a.Year || null,
        seats: a.Seats || null,
        airportCode: a.AirportCode || '',
        city: a.City || '',
        state: (a.StateCode || '').trim(),
        isAmbulance: !!a.IsAmbulance,
        isCargo: !!a.IsCargo,
        bookRateMax: a.BookRateMax ? Number(a.BookRateMax) : null,
        bookRateMin: a.BookRateMin ? Number(a.BookRateMin) : null,
        bookAvgRate: a.BookAvgRate ? Number(a.BookAvgRate) : null,
        priceRange: a.priceRange || '',
        currencyCode: a.CurrencyCode || 'USD',
      }));

      const record = {
        source: 'aircharterguide',
        companyId: CompanyID,
        locationId: LocationID,
        name: BusName1 || '',
        name2: op.BusName2 || '',
        airportCode: op.AirportCode || '',
        city: op.City || '',
        state: (op.StateCode || '').trim(),
        country: op.CountryCode || 'US',
        metro: op.MetroName || '',
        argusRating: op.ArgusRating || detail?.argusRating?.ratingName || '',
        wyvern: op.Wyvern === '1' || op.Wyvern === true,
        wingman: op.Wingman === '1' || op.Wingman === true,
        fleetCount: detail?.fleetCount ?? op.AllAircraftCount ?? aircraft.length,
        dedicatedPilots: detail?.dedicatedPilots ?? null,
        established: detail?.established ?? null,
        shortDescription: op.ShortDesc || '',
        description: extractDescription(detail?.profileData),
        logoPath: detail?.logoPath || '',
        address: contact.address || '',
        phone: contact.phone || '',
        fax: contact.fax || '',
        email: contact.email || '',
        website: contact.website || '',
        aircraftCounts: {
          all: op.AllAircraftCount || 0,
          helicopter: op.HelicopterCount || 0,
          pistonSingle: op.PistonSingleCount || 0,
          pistonMulti: op.PistonMultiCount || 0,
          turboProp: op.TurboPropCount || 0,
          veryLightJet: op.VeryLightJetCount || 0,
          lightJet: op.LightJetCount || 0,
          midJet: op.MidJetCount || 0,
          heavyJet: op.HeavyJetCount || 0,
          turbopropAirliner: op.TurbopropAirlinerCount || 0,
          jetAirliner: op.JetAirlinerCount || 0,
          airlinerVIP: op.AirlinerVIPCount || 0,
          ambulance: op.AmbulanceCount || 0,
          cargo: op.CargoCount || 0,
        },
        aircraft,
      };

      records.push(record);
      succeeded++;
      if (aircraft.length > 0) withFleet++;

      if (succeeded <= 5 || succeeded % 25 === 0) {
        console.log(`[${i + 1}/${operators.length}] ${BusName1} (${City}, ${record.state}) — fleet:${record.fleetCount}, pilots:${record.dedicatedPilots ?? '?'}, aircraft in table:${aircraft.length}`);
      }

      // Save every 10 records
      if (succeeded % 10 === 0) {
        save(records);
        saveMeta(i, operators.length);
      }

    } catch (e) {
      failed++;
      console.warn(`  [!] Error on ${BusName1} (${CompanyID}/${LocationID}): ${e.message}`);
    }

    saveMeta(i, operators.length);
    await delay(DELAY_MS);
  }

  save(records);
  saveMeta(endIdx - 1, operators.length, endIdx === operators.length);

  console.log(`\n${'='.repeat(60)}`);
  console.log('AirCharterGuide Scrape Complete');
  console.log('='.repeat(60));
  console.log(`Total operators:          ${operators.length}`);
  console.log(`Processed this run:       ${endIdx - startIdx}`);
  console.log(`Succeeded:                ${succeeded}`);
  console.log(`Failed:                   ${failed}`);
  console.log(`With populated aircraft:  ${withFleet}`);
  console.log(`Total records in output:  ${records.length}`);
  console.log(`Output: ${OUTPUT_PATH}`);
})();
