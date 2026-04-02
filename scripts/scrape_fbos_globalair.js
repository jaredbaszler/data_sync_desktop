// Scrape FBO listings from GlobalAir.com
// Run: node scripts/scrape_fbos_globalair.js
//
// Uses playwright-extra + stealth plugin to bypass Cloudflare bot protection.
// Resumes from partial results if assets/globalair_fbos.json already exists.
// Outputs: assets/globalair_fbos.json

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');
const path = require('path');

chromium.use(stealth);

// The alternate directory URL (what users see when browsing manually)
const BASE_URL = 'https://www.globalair.com/directories/airport-fbo-directory-13.html';
const OUTPUT_PATH = path.join(__dirname, '..', 'assets', 'globalair_fbos.json');
const DELAY_MIN_MS = 4000;
const DELAY_MAX_MS = 7000;

function scrapeFn() {
  // Runs in browser context
  const items = document.querySelectorAll('ul.listings > li');
  const fbos = [];

  for (const li of items) {
    // Name link may wrap a <strong> tag or contain the text directly
    const nameAnchor = li.querySelector('a[target="_blank"]');
    const name = nameAnchor?.textContent?.trim() || '';
    const websiteURL = nameAnchor?.href || '';

    const fullText = li.textContent || '';
    const afterName = fullText.substring(fullText.indexOf(name) + name.length);
    const match = afterName.match(/^\s*-\s*([^,]+),\s*([A-Z]{2})\s*\(([^)]+)\)\s*-\s*([\s\S]*)/);

    let city = '', state = '', airportCode = '', description = '';
    if (match) {
      city = match[1].trim();
      state = match[2].trim();
      airportCode = match[3].trim();
      description = match[4].trim()
        .replace(/\s+/g, ' ')
        .replace(/Airport\s*(ARC FBO Page)?$/, '')
        .replace(/Closest airport$/, '')
        .trim();
    }

    const arcLink = li.querySelector('a[href*="fbo-at-"]');
    const arcFboUrl = arcLink ? `https://www.globalair.com${arcLink.getAttribute('href')}` : '';

    if (name) {
      fbos.push({ name, city, state, airportCode, websiteURL, description, arcFboUrl });
    }
  }
  return fbos;
}

async function waitForClearance(page, maxWait = 30) {
  let title = await page.title();
  for (let i = 0; i < maxWait && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  return !title.includes('moment');
}

async function getPageCount(page) {
  const countText = await page.$eval('.page-count', el => el.textContent.trim());
  const match = countText.match(/of\s+(\d+)/);
  return match ? parseInt(match[1], 10) : 1;
}

function save(fbos) {
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(fbos, null, 2));
}

(async () => {
  // Load existing partial results to resume from
  let allFbos = [];
  let startPage = 1;
  if (fs.existsSync(OUTPUT_PATH)) {
    try {
      allFbos = JSON.parse(fs.readFileSync(OUTPUT_PATH, 'utf-8'));
      // Calculate which page to resume from (20 per page)
      startPage = Math.floor(allFbos.length / 20) + 1;
      if (allFbos.length > 0 && allFbos.length % 20 === 0) {
        startPage++; // last full page was complete, start next
      }
      console.log(`Resuming: ${allFbos.length} FBOs loaded, starting from page ${startPage}`);
    } catch {
      allFbos = [];
    }
  }

  const browser = await chromium.launch({
    headless: true,
    args: ['--disable-blink-features=AutomationControlled'],
  });

  // Use a persistent context-like approach: create context with realistic viewport
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    locale: 'en-US',
  });
  const page = await context.newPage();

  try {
    // Load the first page to establish session cookies & pass Cloudflare
    console.log('Establishing session...');
    await page.goto(BASE_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });

    if (!await waitForClearance(page)) {
      console.error('ERROR: Could not bypass Cloudflare challenge.');
      await browser.close();
      process.exit(1);
    }

    await page.waitForSelector('ul.listings', { timeout: 10000 });
    const totalPages = await getPageCount(page);
    console.log(`Total pages: ${totalPages}`);

    // Scrape page 1 if needed
    if (startPage <= 1) {
      const fbos = await page.evaluate(scrapeFn);
      allFbos.push(...fbos);
      console.log(`  Page 1: ${fbos.length} FBOs (total: ${allFbos.length})`);
      save(allFbos);
      startPage = 2;
    }

    // Scrape remaining pages using the same tab (cookies carry over)
    for (let sp = startPage; sp <= totalPages; sp++) {
      const delay = DELAY_MIN_MS + Math.random() * (DELAY_MAX_MS - DELAY_MIN_MS);
      await page.waitForTimeout(delay);

      const url = `${BASE_URL}?sp=${sp}`;
      console.log(`Loading page ${sp}/${totalPages}...`);

      try {
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      } catch (err) {
        console.warn(`  Page ${sp}: Navigation timeout, retrying after 5s...`);
        await page.waitForTimeout(5000);
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      }

      if (!await waitForClearance(page, 15)) {
        console.warn(`  Page ${sp}: Cloudflare re-challenge. Waiting 10s and retrying...`);
        await page.waitForTimeout(10000);
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
        if (!await waitForClearance(page, 15)) {
          console.error(`  Page ${sp}: Still blocked. Saving partial results and exiting.`);
          console.error(`  Re-run the script to resume from page ${sp}.`);
          save(allFbos);
          await browser.close();
          process.exit(1);
        }
      }

      try {
        await page.waitForSelector('ul.listings', { timeout: 10000 });
      } catch {
        console.warn(`  Page ${sp}: No listings selector found, skipping.`);
        continue;
      }

      const fbos = await page.evaluate(scrapeFn);
      if (fbos.length === 0) {
        // Diagnose: what does the page actually look like?
        const pageTitle = await page.title();
        const listingsHtml = await page.evaluate(() => {
          const ul = document.querySelector('ul.listings');
          return ul ? `ul.listings found with ${ul.children.length} children` : 'ul.listings NOT FOUND';
        });
        // Dump the first 3 raw li elements to see their structure
        const rawLis = await page.evaluate(() => {
          return Array.from(document.querySelectorAll('ul.listings > li'))
            .slice(0, 3)
            .map(li => li.innerHTML.substring(0, 400));
        });
        console.warn(`  Page ${sp}: 0 FBOs — title="${pageTitle}", ${listingsHtml}`);
        rawLis.forEach((html, i) => console.warn(`  li[${i}]: ${html}`));
        console.warn(`  Saving ${allFbos.length} results. Re-run to resume from page ${sp}.`);
        save(allFbos);
        await browser.close();
        process.exit(1);
      }

      allFbos.push(...fbos);
      console.log(`  Page ${sp}: ${fbos.length} FBOs (total: ${allFbos.length})`);
      save(allFbos); // save after every page for resilience
    }

    console.log(`\nDone! Scraped ${allFbos.length} FBOs across ${totalPages} pages.`);
    console.log(`Output: ${OUTPUT_PATH}`);

  } catch (err) {
    console.error('Scraping error:', err.message);
    if (allFbos.length > 0) {
      save(allFbos);
      console.log(`Saved ${allFbos.length} partial results.`);
    }
  } finally {
    await browser.close();
  }
})();
