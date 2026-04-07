// Wrapper that auto-retries scrape_fbos_charterhub.js until complete.
// Run: node scripts/run_charterhub_scraper.js
//
// Each run of the scraper gets ~4 pages before Imperva blocks us.
// This wrapper waits between runs and resumes from where it left off.
// No API calls — purely local Node.js. Safe to leave running overnight.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const META_PATH = path.join(__dirname, '..', 'assets', 'charterhub_fbos.json.meta');
const WAIT_BETWEEN_RUNS_MS = 35 * 60 * 1000; // 35 minutes between attempts
const MAX_ATTEMPTS = 50; // safety ceiling — 111 pages / ~4 per run = ~28 needed

function getMeta() {
  try {
    return JSON.parse(fs.readFileSync(META_PATH, 'utf-8'));
  } catch {
    return {};
  }
}

function formatWait(ms) {
  const mins = Math.floor(ms / 60000);
  const secs = Math.floor((ms % 60000) / 1000);
  return `${mins}m ${secs}s`;
}

(async () => {
  console.log('ChartHub auto-retry runner started.');
  console.log(`Will wait ${formatWait(WAIT_BETWEEN_RUNS_MS)} between blocked runs.`);
  console.log('Press Ctrl+C at any time to stop.\n');

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const meta = getMeta();
    if (meta.complete) {
      console.log('\nScrape already marked complete. Nothing to do.');
      break;
    }

    const resumePage = (meta.lastPage || 0) + 1;
    console.log(`\n${'─'.repeat(60)}`);
    console.log(`Attempt ${attempt}/${MAX_ATTEMPTS} — starting from page ${resumePage}`);
    console.log(new Date().toLocaleTimeString());
    console.log('─'.repeat(60));

    try {
      execSync('node scripts/scrape_fbos_charterhub.js', {
        cwd: path.join(__dirname, '..'),
        stdio: 'inherit',
      });
    } catch {
      // scraper exits with code 1 on bot block — that's expected, not a fatal error
    }

    // Check if we're done
    const metaAfter = getMeta();
    if (metaAfter.complete) {
      console.log('\n' + '='.repeat(60));
      console.log('ALL PAGES SCRAPED — scrape complete!');
      console.log('='.repeat(60));
      break;
    }

    const pagesAfter = metaAfter.lastPage || 0;
    if (pagesAfter >= 111) {
      console.log('\nReached page 111 — done.');
      break;
    }

    console.log(`\nBlocked after page ${pagesAfter}. Waiting ${formatWait(WAIT_BETWEEN_RUNS_MS)} before retry...`);
    console.log(`Next attempt at: ${new Date(Date.now() + WAIT_BETWEEN_RUNS_MS).toLocaleTimeString()}`);

    await new Promise(resolve => setTimeout(resolve, WAIT_BETWEEN_RUNS_MS));
  }
})();
