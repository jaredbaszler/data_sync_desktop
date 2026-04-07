// Scrape FBO listings from ChartHub.com FBO directory
// Run: node scripts/scrape_fbos_charterhub.js
//
// Data is server-rendered as a JSON blob inside the HTML — no API calls needed.
// Filters to US-only entries. Saves incrementally.
// Outputs: assets/charterhub_fbos.json

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');
const path = require('path');

chromium.use(stealth);

const BASE_URL = 'https://www.charterhub.com/fbo/directory/find-charter-flight-companies/?Page=';
const OUTPUT_PATH = path.join(__dirname, '..', 'assets', 'charterhub_fbos.json');
const DELAY_MIN_MS = 8000;
const DELAY_MAX_MS = 14000;
const ROTATE_CONTEXT_EVERY = 3; // fresh browser context every N pages to reset session

const US_STATES = new Set([
  'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN','IA',
  'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ',
  'NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VT',
  'VA','WA','WV','WI','WY','DC',
]);

function randomDelay() {
  return DELAY_MIN_MS + Math.random() * (DELAY_MAX_MS - DELAY_MIN_MS);
}

// Simulate a human scrolling down the page in several steps
async function simulateScroll(page) {
  const scrollHeight = await page.evaluate(() => document.body.scrollHeight);
  const steps = 4 + Math.floor(Math.random() * 4); // 4-7 scroll steps
  for (let i = 1; i <= steps; i++) {
    const y = Math.floor((scrollHeight / steps) * i);
    await page.evaluate((scrollY) => window.scrollTo({ top: scrollY, behavior: 'smooth' }), y);
    await page.waitForTimeout(300 + Math.random() * 500);
  }
  // Scroll back up slightly, like a human re-checking something
  await page.evaluate(() => window.scrollTo({ top: Math.random() * 300, behavior: 'smooth' }));
  await page.waitForTimeout(200 + Math.random() * 300);
}

// Move the mouse around randomly to signal human presence
async function simulateMouseMovement(page) {
  for (let i = 0; i < 3; i++) {
    const x = 200 + Math.random() * 1200;
    const y = 100 + Math.random() * 700;
    await page.mouse.move(x, y, { steps: 10 });
    await page.waitForTimeout(100 + Math.random() * 200);
  }
}

function save(fbos) {
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(fbos, null, 2));
}

function extractFromHtml(html) {
  // The Dealers array lives in the raw HTML as server-rendered JSON
  // Find it directly in the source string
  const idx = html.indexOf('"Dealers"');
  if (idx === -1) return [];

  // Extract the array — find '[' after "Dealers":
  const arrStart = html.indexOf('[', idx);
  if (arrStart === -1) return [];

  // Walk forward to find the matching closing bracket
  let depth = 0;
  let i = arrStart;
  while (i < html.length) {
    if (html[i] === '[' || html[i] === '{') depth++;
    else if (html[i] === ']' || html[i] === '}') {
      depth--;
      if (depth === 0) break;
    }
    i++;
  }

  const arrJson = html.substring(arrStart, i + 1);
  try {
    return JSON.parse(arrJson);
  } catch (e) {
    console.warn('  JSON parse error:', e.message.substring(0, 80));
    return [];
  }
}

function extractTotalCount(html) {
  const m = html.match(/Number of Matches\s*:\s*([\d,]+)/);
  if (m) return parseInt(m[1].replace(/,/g, ''), 10);
  // Also try from JSON blob
  const m2 = html.match(/"TotalCount"\s*:\s*(\d+)/);
  if (m2) return parseInt(m2[1], 10);
  return 0;
}

function parseDealers(dealers) {
  const fbos = [];
  for (const d of dealers) {
    const cityStatePostal = d.DealerCityStatePostal || '';

    // Extract state
    const stateMatch = cityStatePostal.match(/,\s*([A-Z]{2})\s+\d/);
    const state = stateMatch ? stateMatch[1] : null;
    if (!state || !US_STATES.has(state)) continue;

    // Extract city
    const cityMatch = cityStatePostal.match(/^([^,]+),/);
    const city = cityMatch ? cityMatch[1].trim() : '';

    // Extract zip
    const zipMatch = cityStatePostal.match(/\b(\d{5}(?:-\d{4})?)\b/);
    const zipCode = zipMatch ? zipMatch[1] : '';

    const detailPath = d.InventoryUrls?.[0]?.Url || '';

    fbos.push({
      source: 'charterhub',
      locationId: d.LocationID,
      name: d.DealerName || '',
      address: d.DealerAddress || '',
      city,
      state,
      zipCode,
      phone: d.FormattedDealerPhoneNumber || '',
      premierFbo: d.PremierFBO || false,
      detailUrl: detailPath ? `https://www.charterhub.com${detailPath}` : '',
      fuelPrices: (d.FuelPrices || []).map(f => ({
        type: f.Type,
        brand: f.Brand,
        price: f.Price,
        updated: f.Updated,
        comments: f.Comments,
      })),
    });
  }
  return fbos;
}

function isBotPage(title, html) {
  if (title.includes('moment') || title.includes('Pardon Our Interruption')) return true;
  if (html && html.length < 20000) return true; // any short page is a challenge/block page
  return false;
}

async function waitForClearance(page, maxWait = 20) {
  let title = await page.title();
  let html = await page.content();
  for (let i = 0; i < maxWait && isBotPage(title, html); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
    html = await page.content();
  }
  return !isBotPage(title, html);
}

(async () => {
  // Resume support
  let allFbos = [];
  let startPage = 1;
  if (fs.existsSync(OUTPUT_PATH)) {
    try {
      const existing = JSON.parse(fs.readFileSync(OUTPUT_PATH, 'utf-8'));
      if (Array.isArray(existing) && existing.length > 0) {
        allFbos = existing;
        // Use locationId of last entry to find resume page — rough: 25 entries/page
        // Better: track via a metadata file
        const metaPath = OUTPUT_PATH + '.meta';
        if (fs.existsSync(metaPath)) {
          const meta = JSON.parse(fs.readFileSync(metaPath, 'utf-8'));
          startPage = (meta.lastPage || 0) + 1;
          console.log(`Resuming from page ${startPage}, ${allFbos.length} US FBOs already saved.`);
        }
      }
    } catch { allFbos = []; }
  }

  const browser = await chromium.launch({ headless: true });

  // Creates a fresh browser context + page — resets cookies, fingerprint, session state
  async function freshPage() {
    const ctx = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      locale: 'en-US',
    });
    return ctx.newPage();
  }

  let page = await freshPage();
  let pagesOnCurrentContext = 0;
  let totalPages = 111; // default estimate (2764 / 25)

  async function rotatePage() {
    try { await page.context().close(); } catch (_) {}
    page = await freshPage();
    pagesOnCurrentContext = 0;
    console.log('  [context rotated]');
    // Brief pause after creating new context so it looks like a fresh visitor
    await page.waitForTimeout(3000 + Math.random() * 3000);
  }

  async function loadPage(url) {
    // Rotate context every ROTATE_CONTEXT_EVERY pages
    if (pagesOnCurrentContext > 0 && pagesOnCurrentContext % ROTATE_CONTEXT_EVERY === 0) {
      await rotatePage();
    }
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    } catch {
      console.warn(`  Timeout loading ${url}, retrying after 5s...`);
      await page.waitForTimeout(5000);
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }
    pagesOnCurrentContext++;
  }

  try {
    console.log(`Loading page ${startPage}...`);
    await loadPage(`${BASE_URL}${startPage}`);

    if (!await waitForClearance(page)) {
      console.error('Could not bypass bot protection. Try again.');
      await browser.close();
      process.exit(1);
    }

    await simulateMouseMovement(page);
    await simulateScroll(page);

    const html = await page.content();
    const totalCount = extractTotalCount(html);
    if (totalCount > 0) {
      totalPages = Math.ceil(totalCount / 25);
      console.log(`Total FBOs on site: ${totalCount}, pages: ${totalPages}`);
    }

    const dealers = extractFromHtml(html);
    if (startPage === 1 && dealers.length === 0) {
      console.error('Could not extract dealers from page 1. Check page structure.');
      await browser.close();
      process.exit(1);
    }

    const fbos = parseDealers(dealers);
    allFbos.push(...fbos);
    console.log(`  Page ${startPage}/${totalPages}: ${dealers.length} total, ${fbos.length} US (running total: ${allFbos.length})`);
    save(allFbos);
    fs.writeFileSync(OUTPUT_PATH + '.meta', JSON.stringify({ lastPage: startPage }));

    for (let p = startPage + 1; p <= totalPages; p++) {
      await page.waitForTimeout(randomDelay());
      await loadPage(`${BASE_URL}${p}`);

      if (!await waitForClearance(page, 15)) {
        console.warn(`  Page ${p}: bot challenge hit. Saving and stopping.`);
        console.warn(`  Re-run to resume from page ${p}.`);
        save(allFbos);
        fs.writeFileSync(OUTPUT_PATH + '.meta', JSON.stringify({ lastPage: p - 1 }));
        await browser.close();
        process.exit(1);
      }

      await simulateMouseMovement(page);
      await simulateScroll(page);

      const pageHtml = await page.content();
      const pageTitle = await page.title();
      if (isBotPage(pageTitle, pageHtml)) {
        console.warn(`  Page ${p}: bot protection detected ("${pageTitle}"). Saving and stopping.`);
        console.warn(`  Re-run to resume from page ${p}.`);
        save(allFbos);
        fs.writeFileSync(OUTPUT_PATH + '.meta', JSON.stringify({ lastPage: p - 1 }));
        await browser.close();
        process.exit(1);
      }

      const pageDealers = extractFromHtml(pageHtml);

      if (pageDealers.length === 0) {
        if (pageHtml.includes('0 Matches') || pageHtml.includes('No results')) {
          console.log(`  Page ${p}: no more results. Done.`);
          break;
        }
        if (pageHtml.length < 50000) {
          console.warn(`  Page ${p}: 0 dealers on short page (${pageHtml.length} chars) — likely bot challenge. Saving and stopping.`);
          console.warn(`  Re-run to resume from page ${p}.`);
          save(allFbos);
          fs.writeFileSync(OUTPUT_PATH + '.meta', JSON.stringify({ lastPage: p - 1 }));
          await browser.close();
          process.exit(1);
        }
        console.warn(`  Page ${p}: 0 dealers — skipping.`);
        continue;
      }

      const pageFbos = parseDealers(pageDealers);
      allFbos.push(...pageFbos);
      console.log(`  Page ${p}/${totalPages}: ${pageDealers.length} total, ${pageFbos.length} US (running total: ${allFbos.length})`);
      save(allFbos);
      fs.writeFileSync(OUTPUT_PATH + '.meta', JSON.stringify({ lastPage: p }));
    }

    save(allFbos);
    fs.writeFileSync(OUTPUT_PATH + '.meta', JSON.stringify({ lastPage: totalPages, complete: true }));

    console.log(`\n${'='.repeat(60)}`);
    console.log('ChartHub FBO Scrape Complete');
    console.log('='.repeat(60));
    console.log(`US FBOs scraped: ${allFbos.length}`);
    console.log(`Output: ${OUTPUT_PATH}`);

  } catch (err) {
    console.error('Error:', err.message);
    if (allFbos.length > 0) {
      save(allFbos);
      console.log(`Saved ${allFbos.length} partial results.`);
    }
  } finally {
    await browser.close();
  }
})();
