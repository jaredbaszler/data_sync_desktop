// Reconnaissance script — loads GlobalAir FBO page with stealth to bypass Cloudflare
// Run: node scripts/inspect_globalair.js

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');

chromium.use(stealth);

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  console.log('Navigating to GlobalAir FBO directory (with stealth)...');
  await page.goto('https://www.globalair.com/directories/fbos-176.html', {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });

  // Wait for Cloudflare challenge to resolve — poll for up to 30s
  let title = await page.title();
  console.log('Initial title:', title);
  for (let i = 0; i < 30 && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  console.log('Final title:', title);
  console.log('Page URL:', page.url());

  // Dump full HTML
  const html = await page.content();
  fs.writeFileSync('scripts/globalair_page1.html', html);
  console.log(`Saved full HTML (${html.length} chars) to scripts/globalair_page1.html`);

  // Extract visible text
  const bodyText = await page.evaluate(() => {
    document.querySelectorAll('script, style, noscript').forEach(el => el.remove());
    return document.body?.innerText?.substring(0, 8000) || 'No body text';
  });
  console.log('\n--- First 8000 chars of page text ---');
  console.log(bodyText);

  // Look for pagination elements
  const paginationInfo = await page.evaluate(() => {
    const links = Array.from(document.querySelectorAll('a'));
    const pageLinks = links.filter(a =>
      a.href.includes('page') ||
      a.href.includes('fbos-') ||
      a.textContent.match(/^\d+$/) ||
      a.textContent.match(/next|prev|»|›/i)
    );
    return pageLinks.map(a => ({
      text: a.textContent.trim(),
      href: a.href,
      class: a.className,
    })).slice(0, 30);
  });
  console.log('\n--- Pagination-like links ---');
  console.log(JSON.stringify(paginationInfo, null, 2));

  // Look for table/list structures
  const structures = await page.evaluate(() => {
    const tables = Array.from(document.querySelectorAll('table'));
    const tableInfo = tables.map((t, i) => ({
      index: i,
      rows: t.rows.length,
      firstRowCells: Array.from(t.rows[0]?.cells || []).map(c => c.textContent.trim().substring(0, 50)),
      secondRowCells: t.rows.length > 1
        ? Array.from(t.rows[1]?.cells || []).map(c => c.textContent.trim().substring(0, 80))
        : [],
    }));

    const divClasses = {};
    document.querySelectorAll('div[class]').forEach(d => {
      const cls = d.className;
      divClasses[cls] = (divClasses[cls] || 0) + 1;
    });
    const repeatedDivs = Object.entries(divClasses)
      .filter(([_, count]) => count >= 5)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 15)
      .map(([cls, count]) => ({ className: cls, count }));

    return { tables: tableInfo, repeatedDivs };
  });
  console.log('\n--- Tables ---');
  console.log(JSON.stringify(structures.tables, null, 2));
  console.log('\n--- Repeated div classes ---');
  console.log(JSON.stringify(structures.repeatedDivs, null, 2));

  await browser.close();
  console.log('\nDone.');
})();
