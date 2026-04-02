// Inspect ChartHub FBO directory structure
const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');

chromium.use(stealth);

const BASE_URL = 'https://www.charterhub.com/fbo/directory/find-charter-flight-companies/?Page=1';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  });
  const page = await context.newPage();

  console.log('Loading ChartHub FBO directory...');
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });

  let title = await page.title();
  for (let i = 0; i < 30 && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  console.log('Title:', title);
  console.log('URL:', page.url());

  // Save full HTML
  const html = await page.content();
  fs.writeFileSync('scripts/charterhub_page1.html', html);
  console.log(`Saved HTML (${html.length} chars)`);

  // Page text overview
  const bodyText = await page.evaluate(() => {
    document.querySelectorAll('script, style, noscript').forEach(el => el.remove());
    return document.body?.innerText?.substring(0, 5000) || 'empty';
  });
  console.log('\n--- Page text ---\n', bodyText.substring(0, 3000));

  // Look for listing containers and pagination
  const info = await page.evaluate(() => {
    // Count listing cards/rows
    const cards = document.querySelectorAll('[class*="listing"], [class*="result"], [class*="card"], [class*="fbo"], [class*="company"]');
    const detailLinks = Array.from(document.querySelectorAll('a')).filter(a =>
      a.textContent.toLowerCase().includes('detail') ||
      a.textContent.toLowerCase().includes('view') ||
      a.href.includes('detail') || a.href.includes('profile')
    ).slice(0, 10).map(a => ({ text: a.textContent.trim(), href: a.href }));

    const pageLinks = Array.from(document.querySelectorAll('a')).filter(a =>
      a.href.includes('Page=') || a.textContent.match(/^\d+$/) ||
      a.textContent.match(/next|prev/i)
    ).slice(0, 15).map(a => ({ text: a.textContent.trim(), href: a.href }));

    // Repeated div patterns
    const divClasses = {};
    document.querySelectorAll('div[class]').forEach(d => {
      divClasses[d.className] = (divClasses[d.className] || 0) + 1;
    });
    const repeated = Object.entries(divClasses)
      .filter(([_, c]) => c >= 3).sort((a, b) => b[1] - a[1]).slice(0, 15)
      .map(([cls, count]) => ({ cls, count }));

    return { cardCount: cards.length, detailLinks, pageLinks, repeated };
  });

  console.log('\n--- Detail-like links ---');
  console.log(JSON.stringify(info.detailLinks, null, 2));
  console.log('\n--- Pagination links ---');
  console.log(JSON.stringify(info.pageLinks, null, 2));
  console.log('\n--- Repeated div classes ---');
  console.log(JSON.stringify(info.repeated, null, 2));

  // Now click the first "View FBO Details" link and inspect that page
  const firstDetailLink = await page.$('a[href*="detail"], a[href*="profile"], a:has-text("View"), a:has-text("Detail")');
  if (firstDetailLink) {
    const href = await firstDetailLink.getAttribute('href');
    console.log('\n--- Navigating to first detail page:', href);
    await page.waitForTimeout(2000);
    await page.goto(href.startsWith('http') ? href : `https://www.charterhub.com${href}`, {
      waitUntil: 'domcontentloaded', timeout: 30000,
    });
    const detailText = await page.evaluate(() => {
      document.querySelectorAll('script, style, noscript').forEach(el => el.remove());
      return document.body?.innerText?.substring(0, 3000) || 'empty';
    });
    console.log('Detail page text:\n', detailText.substring(0, 2000));
    const detailHtml = await page.content();
    fs.writeFileSync('scripts/charterhub_detail.html', detailHtml);
    console.log('Saved detail HTML to scripts/charterhub_detail.html');
  }

  await browser.close();
})();
