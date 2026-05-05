// Deeper probe — inspect rendered DOM for aircharterguide.com
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

  const page = await context.newPage();

  // Capture XHR / API calls — Angular likely hits a JSON API under the hood
  const apiCalls = [];
  page.on('response', async (res) => {
    const url = res.url();
    const ct = (res.headers()['content-type'] || '').toLowerCase();
    if (ct.includes('application/json') && (url.includes('aircharterguide') || url.includes('api'))) {
      try {
        const body = await res.text();
        apiCalls.push({ url, status: res.status(), ct, bodyPreview: body.slice(0, 500), bodyLen: body.length });
      } catch {}
    }
  });

  console.log('LISTING PAGE');
  console.log('='.repeat(60));
  await page.goto(LISTING_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(10000);

  // Dump visible body text
  const bodyText = await page.evaluate(() => document.body.innerText);
  fs.writeFileSync(path.join(__dirname, 'aircharterguide_listing_text.txt'), bodyText);
  console.log('Body text length:', bodyText.length);
  console.log('First 1500 chars of body text:');
  console.log(bodyText.slice(0, 1500));

  // Try common card/row selectors
  const selectors = ['mat-card', '.operator', '.listing', '[class*="operator"]', '[class*="listing"]', '[class*="card"]', 'article'];
  console.log('\nSelector counts on listing:');
  for (const sel of selectors) {
    const count = await page.$$eval(sel, els => els.length).catch(() => 0);
    console.log(`  ${sel}: ${count}`);
  }

  // All anchor hrefs matching operator_info
  const allLinks = await page.$$eval('a', as => as.map(a => a.href).filter(h => h && !h.startsWith('javascript')));
  const opLinks = allLinks.filter(h => h.includes('/operator_info/') || h.includes('operator'));
  console.log(`\nAll links: ${allLinks.length}, operator-related: ${opLinks.length}`);
  opLinks.slice(0, 10).forEach(h => console.log('   -', h));

  // Dump full rendered HTML
  const html = await page.content();
  fs.writeFileSync(path.join(__dirname, 'aircharterguide_listing_rendered.html'), html);
  console.log('Rendered HTML saved:', html.length, 'chars');

  console.log('\nAPI calls captured during listing:');
  apiCalls.forEach(a => console.log(`  [${a.status}] ${a.url} (${a.bodyLen} bytes)`));

  await page.close();

  // ───── Detail page ─────
  console.log('\nDETAIL PAGE');
  console.log('='.repeat(60));
  const page2 = await context.newPage();
  const apiCalls2 = [];
  page2.on('response', async (res) => {
    const url = res.url();
    const ct = (res.headers()['content-type'] || '').toLowerCase();
    if (ct.includes('application/json') && (url.includes('aircharterguide') || url.includes('api'))) {
      try {
        const body = await res.text();
        apiCalls2.push({ url, status: res.status(), bodyPreview: body.slice(0, 1500), bodyLen: body.length });
      } catch {}
    }
  });
  await page2.goto(DETAIL_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page2.waitForTimeout(10000);

  const detailText = await page2.evaluate(() => document.body.innerText);
  fs.writeFileSync(path.join(__dirname, 'aircharterguide_detail_text.txt'), detailText);
  console.log('Detail body text length:', detailText.length);
  console.log('First 3000 chars:');
  console.log(detailText.slice(0, 3000));

  const detailHtml = await page2.content();
  fs.writeFileSync(path.join(__dirname, 'aircharterguide_detail_rendered.html'), detailHtml);

  // Table content
  const tables = await page2.$$eval('table', ts => ts.map(t => t.outerHTML.slice(0, 2000)));
  console.log(`\nTables found: ${tables.length}`);
  tables.forEach((t, i) => { console.log(`\n--- Table ${i} (first 2000 chars) ---`); console.log(t); });

  console.log('\nAPI calls captured during detail:');
  apiCalls2.forEach(a => {
    console.log(`  [${a.status}] ${a.url}`);
    console.log(`    preview: ${a.bodyPreview}`);
  });

  await browser.close();
})();
