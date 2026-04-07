// Enrich AOPA FBO records with detail data from the business endpoint.
// Run AFTER scrape_fbos_aopa.js has completed (or is complete enough to enrich).
// Run: node scripts/scrape_fbos_aopa_details.js
//
// For each FBO in assets/aopa_fbos.json that has an aopaBusinessId,
// calls: https://webapp.aopa.org/AirportsAPI/businesses/{id}
// Adds: address, email, website, contact name/title/email, hours, fax, GPS
//
// Saves incrementally — resumes from last processed businessId if interrupted.
// Overwrites assets/aopa_fbos.json in-place with enriched records.

const https = require('https');
const fs = require('fs');
const path = require('path');

const FBO_PATH = path.join(__dirname, '..', 'assets', 'aopa_fbos.json');
const META_PATH = FBO_PATH + '.details.meta';
const DELAY_MS = 800;  // lighter delay — same host, same API

// ─── HTTP helper ──────────────────────────────────────────────────────────────

async function fetchJson(businessId, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    const result = await new Promise((resolve) => {
      https.get({
        hostname: 'webapp.aopa.org',
        path: `/AirportsAPI/businesses/${businessId}`,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept': 'application/json',
          'Referer': 'https://www.aopa.org/',
        },
      }, res => {
        if (res.statusCode === 429 || res.statusCode === 503) return resolve('RATE_LIMITED');
        if (res.statusCode === 404 || res.statusCode === 400) return resolve(null);
        if (res.statusCode !== 200) return resolve(null);
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => {
          try { resolve(JSON.parse(body)); } catch { resolve(null); }
        });
        res.on('error', () => resolve(null));
      }).on('error', () => resolve(null));
    });

    if (result === 'RATE_LIMITED') {
      const waitSec = attempt * 30;
      console.warn(`  [rate limited] waiting ${waitSec}s...`);
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

// ─── Enrich one FBO record from detail API response ──────────────────────────

function enrichFbo(fbo, detail) {
  // Address: prefer 'business' type address
  const addresses = detail.addresses || [];
  const bizAddr = addresses.find(a => a.type === 'business') || addresses[0];
  if (bizAddr) {
    const parts = [bizAddr.addr1, bizAddr.addr2].filter(Boolean);
    fbo.address = parts.join(', ') || '';
    fbo.zip = bizAddr.zip || '';
    // city/state already set from airport-level data — only backfill if empty
    if (!fbo.city && bizAddr.city) fbo.city = bizAddr.city;
    if (!fbo.state && bizAddr.state) fbo.state = bizAddr.state;
  }

  // Contact info
  const rawEmail = (detail.emailAddress || '').trim();
  if (rawEmail) fbo.email = rawEmail;

  const rawWeb = (detail.webAddress || '').trim();
  if (rawWeb) {
    fbo.website = rawWeb.startsWith('http') ? rawWeb : 'https://' + rawWeb;
  }

  const rawFax = (detail.fax || '').replace(/\D/g, '');
  if (rawFax.length === 10) {
    fbo.fax = `(${rawFax.slice(0,3)}) ${rawFax.slice(3,6)}-${rawFax.slice(6)}`;
  }

  fbo.hours = detail.hours || '';
  fbo.description = detail.description || '';

  // GPS coordinates from business record (more precise than airport coords)
  if (detail.location?.latitude && detail.location?.longitude) {
    fbo.latitude = detail.location.latitude;
    fbo.longitude = detail.location.longitude;
  }

  // All contacts marked okToPublish — store as array so importer can insert each one
  const contacts = (detail.businessContacts || []).filter(c => c.okToPublish !== false);
  fbo.contacts = contacts.map(c => {
    const cp = (c.phone || '').replace(/\D/g, '');
    return {
      name: c.contactName || '',
      title: c.titleDept || '',
      email: c.email || '',
      phone: cp.length === 10 ? `(${cp.slice(0,3)}) ${cp.slice(3,6)}-${cp.slice(6)}` : '',
    };
  });

  // Tags — flatten to a list of tag names (e.g. "Line Services::Lavatory Service")
  const tags = (detail.businessTags || [])
    .filter(t => t.isActive)
    .map(t => t.tagName)
    .filter(Boolean);
  if (tags.length > 0) fbo.services = tags;

  fbo.detailFetched = true;
  return fbo;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

(async () => {
  if (!fs.existsSync(FBO_PATH)) {
    console.error('ERROR: assets/aopa_fbos.json not found. Run scrape_fbos_aopa.js first.');
    process.exit(1);
  }

  const fbos = JSON.parse(fs.readFileSync(FBO_PATH, 'utf-8'));
  console.log(`Loaded ${fbos.length} FBO records from aopa_fbos.json`);

  // Determine resume point
  let lastProcessedId = null;
  if (fs.existsSync(META_PATH)) {
    try {
      const meta = JSON.parse(fs.readFileSync(META_PATH, 'utf-8'));
      if (meta.complete) {
        console.log('Detail enrichment already complete.');
        process.exit(0);
      }
      lastProcessedId = meta.lastBusinessId || null;
    } catch {}
  }

  // Find start index
  let startIdx = 0;
  if (lastProcessedId !== null) {
    const idx = fbos.findIndex(f => f.aopaBusinessId === lastProcessedId);
    if (idx !== -1) {
      startIdx = idx + 1;
      const alreadyDone = fbos.filter(f => f.detailFetched).length;
      console.log(`Resuming from index ${startIdx}/${fbos.length} (after businessId ${lastProcessedId}), ${alreadyDone} already enriched.`);
    }
  }

  let enriched = 0;
  let failed = 0;

  for (let i = startIdx; i < fbos.length; i++) {
    const fbo = fbos[i];
    const bizId = fbo.aopaBusinessId;

    if (!bizId) {
      if ((i + 1) % 100 === 0) console.log(`  [${i+1}/${fbos.length}] skipped (no businessId)`);
      continue;
    }

    if (fbo.detailFetched) {
      // Already enriched from a previous run
      continue;
    }

    try {
      const detail = await fetchJson(bizId);
      if (detail) {
        enrichFbo(fbo, detail);
        enriched++;
        if (enriched % 50 === 0 || (i + 1) % 200 === 0) {
          console.log(`  [${i+1}/${fbos.length}] enriched: ${enriched}, failed: ${failed} — "${fbo.name}" (${fbo.airportCode})`);
        }
      } else {
        failed++;
        fbo.detailFetched = false;
      }
    } catch (e) {
      console.warn(`  [!] Error on businessId ${bizId}: ${e.message}`);
      failed++;
    }

    // Save every 50 records
    if ((i + 1) % 50 === 0) {
      fs.writeFileSync(FBO_PATH, JSON.stringify(fbos, null, 2));
      fs.writeFileSync(META_PATH, JSON.stringify({ lastBusinessId: bizId, complete: false }));
    }

    await delay(DELAY_MS);
  }

  // Final save
  fs.writeFileSync(FBO_PATH, JSON.stringify(fbos, null, 2));
  fs.writeFileSync(META_PATH, JSON.stringify({ lastBusinessId: fbos[fbos.length - 1]?.aopaBusinessId, complete: true }));

  console.log(`\n${'='.repeat(60)}`);
  console.log('AOPA FBO Detail Enrichment Complete');
  console.log('='.repeat(60));
  console.log(`Total FBOs:  ${fbos.length}`);
  console.log(`Enriched:    ${enriched}`);
  console.log(`Failed:      ${failed}`);
  console.log(`Output: ${FBO_PATH}`);
})();
