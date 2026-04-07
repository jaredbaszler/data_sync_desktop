// Debug: Try the alternate URL and check page 7
const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();

chromium.use(stealth);

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  });
  const page = await context.newPage();

  // Try the alternate URL the user saw when browsing manually
  const ALT_URL = 'https://www.globalair.com/directories/airport-fbo-directory-13.html';

  console.log('=== Testing alternate URL ===');
  await page.goto(ALT_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  let title = await page.title();
  for (let i = 0; i < 30 && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  console.log('Title:', title);
  console.log('Listings:', await page.evaluate(() => document.querySelectorAll('ul.listings > li').length));
  console.log('Page count:', await page.evaluate(() => document.querySelector('.page-count')?.textContent?.trim() || 'not found'));

  // Now test what happens on page 7 of the ORIGINAL URL
  console.log('\n=== Testing original URL page 7 ===');
  await page.waitForTimeout(3000);
  const url7 = 'https://www.globalair.com/directories/fbos-176.html?sp=7';
  await page.goto(url7, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(3000);
  title = await page.title();
  for (let i = 0; i < 15 && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  console.log('Title:', title);
  console.log('Listings:', await page.evaluate(() => document.querySelectorAll('ul.listings > li').length));
  console.log('URL after load:', page.url());

  // Check if there's a login prompt or paywall
  const bodyPreview = await page.evaluate(() => {
    document.querySelectorAll('script, style').forEach(el => el.remove());
    return document.body?.innerText?.substring(0, 1000) || 'empty';
  });
  console.log('Body:', bodyPreview.substring(0, 600));

  // Now try the alternate URL page 7
  console.log('\n=== Testing alternate URL page 7 ===');
  await page.waitForTimeout(3000);
  const altUrl7 = `${ALT_URL}?sp=7`;
  await page.goto(altUrl7, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(3000);
  title = await page.title();
  for (let i = 0; i < 15 && title.includes('moment'); i++) {
    await page.waitForTimeout(1000);
    title = await page.title();
  }
  console.log('Title:', title);
  console.log('Listings:', await page.evaluate(() => document.querySelectorAll('ul.listings > li').length));

  if (await page.evaluate(() => document.querySelectorAll('ul.listings > li').length) > 0) {
    const first = await page.evaluate(() => {
      const li = document.querySelector('ul.listings > li');
      return li?.textContent?.substring(0, 200);
    });
    console.log('First FBO:', first?.substring(0, 150));
  }

  await browser.close();
})();
