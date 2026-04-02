// Enrich FBO JSON with detail data from ARC FBO pages (address, phone, manager, hours)
// Run: node scripts/enrich_fbos_arc.js
//
// Reads assets/globalair_fbos.json, visits each arcFboUrl, adds detail fields.
// Resumable: skips entries that already have 'address' populated.
// Saves progress every 10 entries.

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');
const path = require('path');

chromium.use(stealth);

const JSON_PATH = path.join(__dirname, '..', 'assets', 'globalair_fbos.json');
const DELAY_MIN_MS = 2000;
const DELAY_MAX_MS = 4000;
const SAVE_EVERY = 10;

function randomDelay() {
  return DELAY_MIN_MS + Math.random() * (DELAY_MAX_MS - DELAY_MIN_MS);
}

function save(fbos) {
  fs.writeFileSync(JSON_PATH, JSON.stringify(fbos, null, 2));
}

async function extractDetails(page) {
  return await page.evaluate(() => {
    // Street address — in a DimGray box with a <p class="mt-2"> inside
    let streetAddress = '';
    let cityStateZip = '';
    const addressBox = document.querySelector('[style*="DimGray"] p.mt-2, [style*="dimgray"] p.mt-2');
    if (addressBox) {
      const parts = addressBox.innerHTML.split(/<br\s*\/?>/i).map(s =>
        s.replace(/<[^>]+>/g, '').trim()
      ).filter(Boolean);
      if (parts.length >= 1) streetAddress = parts[0];
      if (parts.length >= 2) cityStateZip = parts.slice(1).join(', ').replace(/\s+USA\s*$/, '').trim();
    }

    // Phone — from the contact modal table (tel: link)
    let phone = '';
    const telLink = document.querySelector('table a[href^="tel:"]');
    if (telLink) {
      phone = telLink.textContent.trim();
    }

    // Manager name — from the modal table
    let manager = '';
    const rows = document.querySelectorAll('table tr');
    for (const row of rows) {
      const th = row.querySelector('th');
      const td = row.querySelector('td');
      if (th && td && th.textContent.toLowerCase().includes('manager')) {
        manager = td.textContent.trim();
        break;
      }
    }

    // Hours of operation
    let hours = '';
    const hoursSpan = document.querySelector('span.ms-3');
    if (hoursSpan) {
      const allSpans = document.querySelectorAll('span.ms-3');
      for (const span of allSpans) {
        if (span.textContent.toLowerCase().includes('hours of operation')) {
          const bold = span.querySelector('b');
          if (bold) hours = bold.textContent.trim();
          break;
        }
      }
    }

    // Ramp fee
    let rampFee = '';
    const allSpans2 = document.querySelectorAll('span.ms-3');
    for (const span of allSpans2) {
      if (span.textContent.toLowerCase().includes('ramp fee')) {
        const bold = span.querySelector('b');
        if (bold) rampFee = bold.textContent.trim();
        break;
      }
    }

    return { streetAddress, cityStateZip, phone, manager, hours, rampFee };
  });
}

async function waitForClearance(page, maxWait = 20) {
  let title = await page.title();
  for (let i = 0; i < maxWait && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  return !title.includes('moment');
}

(async () => {
  if (!fs.existsSync(JSON_PATH)) {
    console.error('ERROR: assets/globalair_fbos.json not found. Run scrape_fbos_globalair.js first.');
    process.exit(1);
  }

  const fbos = JSON.parse(fs.readFileSync(JSON_PATH, 'utf-8'));
  const toEnrich = fbos.filter(f => f.arcFboUrl && !f.address);
  const alreadyDone = fbos.filter(f => f.address).length;

  console.log(`Total FBOs: ${fbos.length}`);
  console.log(`Already enriched: ${alreadyDone}`);
  console.log(`To enrich: ${toEnrich.length}`);

  if (toEnrich.length === 0) {
    console.log('All entries already enriched!');
    process.exit(0);
  }

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    locale: 'en-US',
  });
  const page = await context.newPage();

  let enriched = 0;
  let failed = 0;

  // Load a base page first to establish session / pass Cloudflare
  console.log('\nEstablishing session...');
  await page.goto('https://www.globalair.com/directories/airport-fbo-directory-13.html', {
    waitUntil: 'domcontentloaded', timeout: 60000,
  });
  if (!await waitForClearance(page)) {
    console.error('Could not pass Cloudflare. Try again.');
    await browser.close();
    process.exit(1);
  }
  console.log('Session established.\n');

  for (let i = 0; i < fbos.length; i++) {
    const fbo = fbos[i];
    if (!fbo.arcFboUrl || fbo.address) continue; // skip already done or no URL

    process.stdout.write(`[${enriched + failed + 1}/${toEnrich.length}] ${fbo.name}... `);

    try {
      await page.waitForTimeout(randomDelay());
      await page.goto(fbo.arcFboUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

      // Handle potential re-challenge
      if (!await waitForClearance(page, 10)) {
        // One retry
        await page.waitForTimeout(5000);
        await page.goto(fbo.arcFboUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
        if (!await waitForClearance(page, 10)) {
          console.log('BLOCKED — skipping');
          failed++;
          continue;
        }
      }

      const details = await extractDetails(page);
      fbo.address = details.streetAddress || null;
      fbo.cityStateZip = details.cityStateZip || null;
      fbo.phone = details.phone || null;
      fbo.manager = details.manager || null;
      fbo.hours = details.hours || null;
      fbo.rampFee = details.rampFee || null;

      console.log(`OK — ${details.streetAddress || 'no address'} | ${details.phone || 'no phone'}`);
      enriched++;

      // Save periodically
      if (enriched % SAVE_EVERY === 0) {
        save(fbos);
        console.log(`  [saved ${enriched} enriched so far]`);
      }

    } catch (err) {
      console.log(`ERROR: ${err.message.substring(0, 80)}`);
      failed++;
    }
  }

  save(fbos);
  await browser.close();

  console.log(`\n${'='.repeat(60)}`);
  console.log('ARC FBO Enrichment Complete');
  console.log('='.repeat(60));
  console.log(`Enriched:  ${enriched}`);
  console.log(`Failed:    ${failed}`);
  console.log(`Skipped (no URL): ${fbos.filter(f => !f.arcFboUrl).length}`);
  console.log(`Output: ${JSON_PATH}`);
})();
