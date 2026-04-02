// Scrape FBO listings from AirNav.com airport pages
// Run: node scripts/scrape_fbos_airnav.js
//
// Strategy:
//   1. Build airport list from existing GlobalAir FBO data (known FBO airports)
//   2. For each airport, load https://www.airnav.com/airport/{code}
//   3. Extract all FBOs from the "FBO, Fuel Providers" table section
//   4. Follow each FBO's detail URL for address, email, services
//   5. Save incrementally — resumes from last completed airport
//
// No Playwright needed — airnav.com serves plain HTML with no bot protection.
// Outputs: assets/airnav_fbos.json

const https = require('https');
const fs = require('fs');
const path = require('path');

const OUTPUT_PATH = path.join(__dirname, '..', 'assets', 'airnav_fbos.json');
const META_PATH = OUTPUT_PATH + '.meta';
const AIRPORT_DELAY_MS = 4000;  // between airport pages
const DETAIL_DELAY_MS = 2500;   // between FBO detail pages

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

async function fetchHtml(urlPath, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    const result = await new Promise((resolve, reject) => {
      const options = {
        hostname: 'www.airnav.com',
        path: urlPath,
        headers: { 'User-Agent': USER_AGENT },
      };
      https.get(options, res => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          const loc = res.headers.location || '';
          const newPath = loc.startsWith('http') ? new URL(loc).pathname : loc;
          return resolve(fetchHtml(newPath, retries));
        }
        if (res.statusCode === 503) return resolve('RATE_LIMITED');
        if (res.statusCode !== 200) return resolve(null);
        let html = '';
        res.on('data', d => html += d);
        res.on('end', () => resolve(html));
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
  return new Promise(r => setTimeout(r, ms + Math.random() * (ms * 0.3)));
}

// ─── Parsing ──────────────────────────────────────────────────────────────────

// Extract all FBO entries from an airport page.
// Returns array of { name, detailPath, phone, website }
function parseFbosFromAirportPage(html, airportCode) {
  const fbos = [];
  const fboSectionIdx = html.indexOf('FBO, Fuel Providers');
  if (fboSectionIdx === -1) return fbos;

  // Work only within the FBO section (up to the next major section or end)
  const sectionEnd = html.indexOf('<H3>', fboSectionIdx + 1);
  const section = html.substring(fboSectionIdx, sectionEnd !== -1 ? sectionEnd : html.length);

  // Each FBO row has a link: href="/airport/KXXX/SLUG"
  // Slugs to skip — these are airnav utility links, not FBO pages
  const SKIP_SLUGS = new Set(['reportlinks', 'services', 'fuel', 'photos', 'map']);

  const detailLinkRe = /href="(\/airport\/[A-Z0-9]+\/([A-Z0-9_]+))"/gi;
  const seen = new Set();
  let m;

  while ((m = detailLinkRe.exec(section)) !== null) {
    const detailPath = m[1];
    const slug = m[2];
    if (seen.has(detailPath)) continue;
    if (SKIP_SLUGS.has(slug.toLowerCase())) continue;
    seen.add(detailPath);

    // Grab the surrounding row context to extract phone + website
    const linkIdx = section.indexOf(m[0]);
    const rowContext = section.substring(Math.max(0, linkIdx - 200), linkIdx + 600);

    // Phone: first standalone phone-like number in the row
    const phoneMatch = rowContext.match(/(\(?\d{3}\)?[\s\-]\d{3}[\s\-]\d{4})/);
    const phone = phoneMatch ? phoneMatch[1].trim() : '';

    // Business name: from alt text of logo img or from "More info" link text
    const nameMatch = rowContext.match(/More info.*?of ([^<]+)<\/FONT>/i) ||
                      rowContext.match(/alt="([^"]+)"\s+border=0><\/A><\/A>/i);
    const name = nameMatch ? nameMatch[1].trim() : slug;

    // Website: from onMouseover or href in web site link
    const websiteMatch = rowContext.match(/window\.status='(https?:\/\/[^']+)'/i);
    const website = websiteMatch ? websiteMatch[1].trim() : '';

    fbos.push({ name, detailPath, phone, website });
  }

  return fbos;
}

// Extract detailed info from an FBO detail page
function parseFboDetail(html, airportCode) {
  // Strip tags for clean text extraction
  const text = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\s+/g, ' ')
    .trim();

  // Airport address block appears right after the airport name line
  // Pattern: "StreetAddress\n City, ST XXXXX"
  // Address: street number + name ending in a road suffix, followed by City, ST ZIP
  // Address: try explicit "Address:" label first (Signature-style pages),
  // then fall back to anchor before "United States" (independent FBO pages)
  let address = '';
  const labelMatch = text.match(/\bAddress:\s*(\d[\w\s,]+,\s*[A-Z]{2}\s+\d{5})/i);
  if (labelMatch) {
    address = labelMatch[1].trim();
  } else {
    // Address is always the last chunk before "United States" in the text.
    // Grab only the last 150 chars before that anchor to avoid matching junk earlier in the page.
    const usIdx = text.indexOf('United States');
    if (usIdx !== -1) {
      const window = text.substring(Math.max(0, usIdx - 150), usIdx).trim();
      // Require uppercase first letter after street number — filters out "4888 users online..."
      const anchorMatch = window.match(/(\d{2,5}\s+(?:[NSEW]{1,2}\s+)?[A-Z][a-z].+,\s*[A-Z]{2}\s+\d{5})\s*$/);
      if (anchorMatch) address = anchorMatch[1].trim();
    }
  }

  // Email
  const emailMatch = html.match(/href="mailto:([^?"]+)/i);
  const email = emailMatch ? emailMatch[1].trim() : '';

  // Website: look for www. or http in plain text after stripping tags
  const websiteMatch = text.match(/\b(www\.[a-z0-9][-a-z0-9.]+\.[a-z]{2,}(?:\/\S*)?)\b/i);
  const website = websiteMatch ? ('https://' + websiteMatch[1].replace(/^https?:\/\//i, '')) : '';

  // Hours
  const hoursMatch = text.match(/(?:FBO Hours|Hours)[:\s]+([^.]+?(?:am|pm)[^.]*)/i);
  const hours = hoursMatch ? hoursMatch[1].trim() : '';

  // Services — everything between "Services, Facilities" and "Aviation fuel services"
  const servicesStart = text.indexOf('Services, Facilities');
  const servicesEnd = text.indexOf('Aviation fuel services', servicesStart);
  let services = '';
  if (servicesStart !== -1 && servicesEnd !== -1) {
    services = text.substring(servicesStart + 'Services, Facilities and Amenities'.length, servicesEnd).trim();
  }

  return { address, email, website, hours, services };
}

// ─── Airport list ─────────────────────────────────────────────────────────────

// Build a FAA local_code → ICAO ident lookup from airport-codes.csv
function buildFaaToIcaoMap() {
  const csvPath = path.join(__dirname, '..', 'assets', 'airport-codes.csv');
  if (!fs.existsSync(csvPath)) return {};
  const lines = fs.readFileSync(csvPath, 'utf-8').split('\n');
  // Header: ident,type,name,...,gps_code,iata_code,local_code,...
  const headers = lines[0].replace(/^\uFEFF/, '').split(',');
  const identIdx = headers.indexOf('ident');
  const localIdx = headers.indexOf('local_code');
  const countryIdx = headers.indexOf('iso_country');
  const map = {};
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(',');
    if (cols.length < 3) continue;
    const country = (cols[countryIdx] || '').trim();
    if (country !== 'US') continue;
    const icao = (cols[identIdx] || '').trim().toUpperCase();
    const faa = (cols[localIdx] || '').trim().toUpperCase();
    if (icao && faa) map[faa] = icao;
  }
  return map;
}

function buildAirportList() {
  const faaToIcao = buildFaaToIcaoMap();
  console.log(`  FAA→ICAO map loaded: ${Object.keys(faaToIcao).length} US airports`);

  function toIcao(code) {
    const c = code.toUpperCase().trim();
    return faaToIcao[c] || c;
  }

  const codes = new Set();

  // Primary: all medium + large US airports from airport-codes.csv
  // These are the airports most likely to have FBOs — much broader than just
  // what GlobalAir already knows about.
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

  // Also add any codes from GlobalAir/ChartHub not already covered
  // (catches small airports that happen to have FBOs)
  const globalAirPath = path.join(__dirname, '..', 'assets', 'globalair_fbos.json');
  if (fs.existsSync(globalAirPath)) {
    const data = JSON.parse(fs.readFileSync(globalAirPath, 'utf-8'));
    data.forEach(f => { if (f.airportCode) codes.add(toIcao(f.airportCode)); });
    console.log(`  After GlobalAir additions: ${codes.size}`);
  }

  const charterHubPath = path.join(__dirname, '..', 'assets', 'charterhub_fbos.json');
  if (fs.existsSync(charterHubPath)) {
    const data = JSON.parse(fs.readFileSync(charterHubPath, 'utf-8'));
    data.forEach(f => { if (f.airportCode) codes.add(toIcao(f.airportCode)); });
    console.log(`  After ChartHub additions: ${codes.size}`);
  }

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
        console.log('Scrape already complete.');
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

  for (let i = startIdx; i < airports.length; i++) {
    const airportCode = airports[i];

    try {
      const html = await fetchHtml(`/airport/${airportCode}`);
      if (!html) {
        console.log(`  [${i + 1}/${airports.length}] ${airportCode}: not found`);
        saveMeta(airportCode, airports.length);
        continue;
      }

      const fboEntries = parseFbosFromAirportPage(html, airportCode);

      if (fboEntries.length === 0) {
        airportsEmpty++;
        if ((i + 1) % 50 === 0) {
          console.log(`  [${i + 1}/${airports.length}] ${airportCode}: no FBOs (${airportsWithFbos} airports with FBOs so far, ${allFbos.length} total FBOs)`);
        }
        saveMeta(airportCode, airports.length);
        await delay(AIRPORT_DELAY_MS);
        continue;
      }

      airportsWithFbos++;
      console.log(`\n[${i + 1}/${airports.length}] ${airportCode}: ${fboEntries.length} FBO(s)`);

      for (const entry of fboEntries) {
        await delay(DETAIL_DELAY_MS);

        let detail = { address: '', email: '', website: '', hours: '', services: '' };
        try {
          const detailHtml = await fetchHtml(entry.detailPath);
          if (detailHtml) {
            detail = parseFboDetail(detailHtml, airportCode);
          }
        } catch (e) {
          console.warn(`  [!] Detail fetch failed for ${entry.detailPath}: ${e.message}`);
        }

        const fbo = {
          source: 'airnav',
          airportCode,
          name: entry.name,
          address: detail.address || '',
          phone: entry.phone || '',
          email: detail.email || '',
          website: detail.website || entry.website || '',
          hours: detail.hours || '',
          services: detail.services || '',
          detailUrl: `https://www.airnav.com${entry.detailPath}`,
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

    await delay(AIRPORT_DELAY_MS);
  }

  save(allFbos);
  saveMeta(airports[airports.length - 1], airports.length, true);

  console.log(`\n${'='.repeat(60)}`);
  console.log('AirNav FBO Scrape Complete');
  console.log('='.repeat(60));
  console.log(`Airports checked: ${airports.length}`);
  console.log(`Airports with FBOs: ${airportsWithFbos}`);
  console.log(`Total FBOs scraped: ${allFbos.length}`);
  console.log(`Output: ${OUTPUT_PATH}`);
})();
