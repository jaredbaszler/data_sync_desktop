// Scrape FBO listings from AOPA's open AirportsAPI
// Run: node scripts/scrape_fbos_aopa.js
//
// Strategy:
//   1. Build airport list: all medium+large US airports + small airports already
//      known to have FBOs (from globalair/charterhub/airnav data) = ~1,720 airports
//   2. For each airport, call https://webapp.aopa.org/AirportsAPI/airports/{CODE}
//   3. Extract businesses where isFbo === true
//   4. Save incrementally — resumes from last completed airport
//
// No Playwright needed — AOPA's AirportsAPI is open JSON, no auth required.
// Outputs: assets/aopa_fbos.json

const https = require('https');
const fs = require('fs');
const path = require('path');

const OUTPUT_PATH = path.join(__dirname, '..', 'assets', 'aopa_fbos.json');
const META_PATH = OUTPUT_PATH + '.meta';
const DELAY_MS = 1500;  // between airport requests — respectful pace

// ─── HTTP helper ──────────────────────────────────────────────────────────────

async function fetchJson(airportCode, retries = 3) {
  const url = `https://webapp.aopa.org/AirportsAPI/airports/${airportCode}`;
  for (let attempt = 1; attempt <= retries; attempt++) {
    const result = await new Promise((resolve, reject) => {
      const options = {
        hostname: 'webapp.aopa.org',
        path: `/AirportsAPI/airports/${airportCode}`,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept': 'application/json',
          'Referer': `https://www.aopa.org/destinations/airports/${airportCode}/details`,
        },
      };
      https.get(options, res => {
        if (res.statusCode === 429 || res.statusCode === 503) {
          return resolve('RATE_LIMITED');
        }
        if (res.statusCode === 404 || res.statusCode === 400) {
          return resolve(null);
        }
        if (res.statusCode !== 200) {
          return resolve(null);
        }
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => {
          try { resolve(JSON.parse(body)); }
          catch { resolve(null); }
        });
        res.on('error', reject);
      }).on('error', reject);
    });

    if (result === 'RATE_LIMITED') {
      const waitSec = attempt * 30;
      console.warn(`  [rate limited] waiting ${waitSec}s before retry ${attempt}/${retries}...`);
      await delay(waitSec * 1000);
      continue;
    }
    return result;
  }
  return null;
}

function delay(ms) {
  return new Promise(r => setTimeout(r, ms + Math.random() * (ms * 0.2)));
}

// ─── Airport list ─────────────────────────────────────────────────────────────

function buildAirportList() {
  const codes = new Set();

  // Primary: all medium+large US airports from airport-codes.csv
  const csvPath = path.join(__dirname, '..', 'assets', 'airport-codes.csv');
  if (fs.existsSync(csvPath)) {
    const lines = fs.readFileSync(csvPath, 'utf-8').split('\n');
    const headers = lines[0].replace(/^\uFEFF/, '').split(',');
    const typeIdx = headers.indexOf('type');
    const countryIdx = headers.indexOf('iso_country');
    const identIdx = headers.indexOf('ident');
    for (let i = 1; i < lines.length; i++) {
      const cols = lines[i].split(',');
      if ((cols[countryIdx] || '').trim() !== 'US') continue;
      const t = (cols[typeIdx] || '').trim();
      if (t !== 'medium_airport' && t !== 'large_airport') continue;
      const icao = (cols[identIdx] || '').trim().toUpperCase();
      if (icao) codes.add(icao);
    }
    console.log(`  Medium+large US airports from CSV: ${codes.size}`);
  }

  // Also add any codes from our existing FBO data (catches small airports
  // already known to have FBOs from GlobalAir/ChartHub/AirNav scrapes)
  const fboFiles = [
    path.join(__dirname, '..', 'assets', 'globalair_fbos.json'),
    path.join(__dirname, '..', 'assets', 'charterhub_fbos.json'),
    path.join(__dirname, '..', 'assets', 'airnav_fbos.json'),
  ];
  for (const f of fboFiles) {
    if (!fs.existsSync(f)) continue;
    try {
      const data = JSON.parse(fs.readFileSync(f, 'utf-8'));
      data.forEach(e => {
        if (e.airportCode) codes.add(e.airportCode.toUpperCase().trim());
      });
    } catch {}
  }
  console.log(`  After adding known FBO airports: ${codes.size}`);

  return [...codes].sort();
}

// ─── Save helpers ─────────────────────────────────────────────────────────────

function save(fbos) {
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(fbos, null, 2));
}

function saveMeta(lastAirport, totalAirports, complete = false) {
  fs.writeFileSync(META_PATH, JSON.stringify({ lastAirport, totalAirports, complete }));
}

// ─── Main ─────────────────────────────────────────────────────────────────────

(async () => {
  console.log('Building airport list...');
  const airports = buildAirportList();
  console.log(`Total airports to check: ${airports.length}`);

  // Resume support
  let allFbos = [];
  let startIdx = 0;

  if (fs.existsSync(OUTPUT_PATH)) {
    try {
      const existing = JSON.parse(fs.readFileSync(OUTPUT_PATH, 'utf-8'));
      if (Array.isArray(existing) && existing.length > 0) {
        allFbos = existing;
      }
    } catch { allFbos = []; }
  }

  if (fs.existsSync(META_PATH)) {
    try {
      const meta = JSON.parse(fs.readFileSync(META_PATH, 'utf-8'));
      if (meta.complete) {
        console.log(`Scrape already complete. ${allFbos.length} FBOs saved.`);
        process.exit(0);
      }
      if (meta.lastAirport) {
        const idx = airports.indexOf(meta.lastAirport);
        if (idx !== -1) {
          startIdx = idx + 1;
          console.log(`Resuming from airport ${startIdx + 1}/${airports.length} (after ${meta.lastAirport}), ${allFbos.length} FBOs already saved.`);
        }
      }
    } catch {}
  }

  let airportsWithFbos = 0;
  let airportsEmpty = 0;
  let airportsNotFound = 0;

  for (let i = startIdx; i < airports.length; i++) {
    const airportCode = airports[i];

    try {
      const data = await fetchJson(airportCode);

      if (!data) {
        airportsNotFound++;
        if ((i + 1) % 100 === 0) {
          console.log(`  [${i + 1}/${airports.length}] ${airportCode}: not found (${airportsWithFbos} airports with FBOs, ${allFbos.length} total FBOs)`);
        }
        saveMeta(airportCode, airports.length);
        await delay(DELAY_MS);
        continue;
      }

      // Filter to FBO businesses only
      const fboBusinesses = (data.businesses || []).filter(b => b.isFbo === true && !b.hideBusiness);

      if (fboBusinesses.length === 0) {
        airportsEmpty++;
        if ((i + 1) % 100 === 0) {
          console.log(`  [${i + 1}/${airports.length}] ${airportCode}: no FBOs (${airportsWithFbos} airports with FBOs, ${allFbos.length} total FBOs)`);
        }
        saveMeta(airportCode, airports.length);
        await delay(DELAY_MS);
        continue;
      }

      airportsWithFbos++;
      console.log(`\n[${i + 1}/${airports.length}] ${airportCode}: ${fboBusinesses.length} FBO(s)`);

      for (const biz of fboBusinesses) {
        // Format phone from raw digits to (XXX) XXX-XXXX
        const rawPhone = (biz.phone1 || '').replace(/\D/g, '');
        const phone = rawPhone.length === 10
          ? `(${rawPhone.slice(0,3)}) ${rawPhone.slice(3,6)}-${rawPhone.slice(6)}`
          : rawPhone;

        const fbo = {
          source: 'aopa',
          airportCode,
          name: biz.name || '',
          city: biz.city || '',
          state: biz.state || '',
          phone,
          locationOnField: biz.locationOnField || '',
          maintenance: biz.maintenance || false,
          flightTraining: biz.flightTraining || false,
          rental: biz.rental || {},
          fuelTypes: (biz.businessFuels || []).map(f => f.fuelType).filter((v, i, a) => a.indexOf(v) === i),
          feeTypes: biz.feeTypes || [],
          aopaBusinessId: biz.businessId,
        };

        allFbos.push(fbo);
        console.log(`  + ${fbo.name} (${airportCode})`);
      }

      save(allFbos);
      saveMeta(airportCode, airports.length);

    } catch (e) {
      console.warn(`  [!] Error on ${airportCode}: ${e.message}`);
      saveMeta(airportCode, airports.length);
    }

    await delay(DELAY_MS);
  }

  save(allFbos);
  saveMeta(airports[airports.length - 1], airports.length, true);

  console.log(`\n${'='.repeat(60)}`);
  console.log('AOPA FBO Scrape Complete');
  console.log('='.repeat(60));
  console.log(`Airports checked:      ${airports.length}`);
  console.log(`Airports with FBOs:    ${airportsWithFbos}`);
  console.log(`Airports with no FBOs: ${airportsEmpty}`);
  console.log(`Airports not found:    ${airportsNotFound}`);
  console.log(`Total FBOs scraped:    ${allFbos.length}`);
  console.log(`Output: ${OUTPUT_PATH}`);
})();
