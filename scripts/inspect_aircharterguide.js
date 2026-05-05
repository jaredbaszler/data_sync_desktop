// Probe aircharterguide.com listing + detail page with Playwright stealth
// Run: node scripts/inspect_aircharterguide.js

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');
const path = require('path');

chromium.use(stealth);

const LISTING_URL = 'https://www.aircharterguide.com/listingsearch?dt=8&region=north%20america&country=us';
const DETAIL_URL  = 'https://www.aircharterguide.com/operator_info/air%2Bnew%2Bengland%2Bllc/98244/portsmouth/67862';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1440, height: 900 },
    locale: 'en-US',
  });

  // Listing page
  console.log('Fetching listing...');
  const page1 = await context.newPage();
  try {
    await page1.goto(LISTING_URL, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page1.waitForTimeout(5000);
    const listingHtml = await page1.content();
    fs.writeFileSync(path.join(__dirname, 'aircharterguide_listing.html'), listingHtml);
    console.log(`  Listing saved (${listingHtml.length} chars). Title: "${await page1.title()}"`);

    // Count anchor tags to /operator_info/
    const opLinks = await page1.$$eval('a[href*="/operator_info/"]', as => as.map(a => a.getAttribute('href')));
    console.log(`  /operator_info/ links on page: ${opLinks.length}`);
    console.log('  Sample links:');
    opLinks.slice(0, 5).forEach(h => console.log('   -', h));

    // Pagination hints
    const paginationText = await page1.$$eval('a', as => as.map(a => a.textContent?.trim()).filter(t => t && (t.match(/page|next|>|\d+$/i))).slice(0, 30));
    console.log('  Pagination-ish links:', paginationText);
  } catch (e) {
    console.error('  Listing error:', e.message);
  }
  await page1.close();

  // Detail page
  console.log('\nFetching detail...');
  const page2 = await context.newPage();
  try {
    await page2.goto(DETAIL_URL, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page2.waitForTimeout(5000);
    const detailHtml = await page2.content();
    fs.writeFileSync(path.join(__dirname, 'aircharterguide_detail.html'), detailHtml);
    console.log(`  Detail saved (${detailHtml.length} chars). Title: "${await page2.title()}"`);

    // Show H1/H2 to understand section structure
    const headings = await page2.$$eval('h1, h2, h3', hs => hs.map(h => `${h.tagName}: ${h.textContent?.trim()}`).slice(0, 30));
    console.log('  Headings:');
    headings.forEach(h => console.log('   -', h));

    // Count tables
    const tables = await page2.$$('table');
    console.log(`  Tables on page: ${tables.length}`);
  } catch (e) {
    console.error('  Detail error:', e.message);
  }
  await page2.close();

  await browser.close();
  console.log('\nDone. Saved aircharterguide_listing.html and aircharterguide_detail.html in scripts/');
})();
