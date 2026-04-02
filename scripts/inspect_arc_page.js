// Inspect an ARC FBO detail page to see what data fields are available
const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
const fs = require('fs');

chromium.use(stealth);

// Pick a couple sample ARC FBO pages from our scraped data
const SAMPLE_URLS = [
  'https://www.globalair.com/airport/fbo-at-ixd-advanced-jet-center-2153.aspx',
  'https://www.globalair.com/airport/fbo-at-dab-atp-jet-center-361.aspx',
  'https://www.globalair.com/airport/fbo-at-grb-avflight-green-bay-1490.aspx',
];

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  });
  const page = await context.newPage();

  for (const url of SAMPLE_URLS) {
    console.log(`\n===== ${url} =====`);
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });

    let title = await page.title();
    for (let i = 0; i < 30 && title.includes('moment'); i++) {
      await page.waitForTimeout(1000);
      title = await page.title();
    }
    console.log('Title:', title);

    const bodyText = await page.evaluate(() => {
      document.querySelectorAll('script, style, noscript').forEach(el => el.remove());
      return document.body?.innerText?.substring(0, 5000) || 'empty';
    });
    console.log('\nBody text:\n', bodyText.substring(0, 3000));

    // Save HTML of first page for detailed inspection
    if (url === SAMPLE_URLS[0]) {
      const html = await page.content();
      fs.writeFileSync('scripts/arc_fbo_sample.html', html);
      console.log('\nSaved full HTML to scripts/arc_fbo_sample.html');
    }

    await page.waitForTimeout(2000);
  }

  await browser.close();
})();
