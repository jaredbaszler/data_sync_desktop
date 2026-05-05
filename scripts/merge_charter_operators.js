// Merge assets/aircharterguide_operators.json + assets/faa_135_operators.json
// into a single assets/charter_operators.json
//
// Strategy:
//   - FAA records that matched ACG (have acgMatch.companyId): merge FAA cert/personnel/
//     N-number data INTO the ACG record (ACG is primary — richer contact/fleet/safety data)
//   - ACG records with no FAA match: keep as-is
//   - FAA-only records (no acgMatch): add as standalone records from FAA data
//
// Run: node scripts/merge_charter_operators.js

const fs   = require('fs');
const path = require('path');

const ACG_PATH = path.join(__dirname, '..', 'assets', 'aircharterguide_operators.json');
const FAA_PATH = path.join(__dirname, '..', 'assets', 'faa_135_operators.json');
const OUT_PATH = path.join(__dirname, '..', 'assets', 'charter_operators.json');

function normalizeName(s) {
  return (s || '')
    .toLowerCase()
    .replace(/\bllc\b|\bl\.l\.c\.\b|\binc\b|\binc\.\b|\bcorp\b|\bcorp\.\b|\bltd\b|\bltd\.\b|\bco\b|\bco\.\b|\blp\b|\bpllc\b/gi, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const acg = JSON.parse(fs.readFileSync(ACG_PATH, 'utf-8'));
const faa = JSON.parse(fs.readFileSync(FAA_PATH, 'utf-8'));

console.log(`ACG: ${acg.length} operators`);
console.log(`FAA: ${faa.length} operators`);

// Build ACG lookup: companyId → record index
const acgByCompanyId = new Map();
acg.forEach((r, i) => acgByCompanyId.set(r.companyId, i));

// Separate FAA into matched vs. unmatched
const faaMatched   = faa.filter(r => r.acgMatch?.companyId);
const faaUnmatched = faa.filter(r => !r.acgMatch);

console.log(`FAA matched to ACG: ${faaMatched.length}`);
console.log(`FAA-only (no ACG):  ${faaUnmatched.length}`);

// Step 1: enrich ACG records with FAA data where matched
let enriched = 0;
for (const faaRec of faaMatched) {
  const idx = acgByCompanyId.get(faaRec.acgMatch.companyId);
  if (idx === undefined) continue;

  const acgRec = acg[idx];
  acgRec.source = 'both';

  // FAA cert / regulatory info
  acgRec.dsgnCode    = faaRec.dsgnCode   || acgRec.dsgnCode   || '';
  acgRec.certNumber  = faaRec.certNumber || acgRec.certNumber || '';
  acgRec.certDate    = faaRec.certDate   || acgRec.certDate   || '';

  // DBA names — merge ACG name2 + FAA dbaNames, deduplicate
  const allDba = new Set();
  if (acgRec.name2) allDba.add(acgRec.name2.trim().toUpperCase());
  (faaRec.dbaNames || []).forEach(d => allDba.add(d.trim().toUpperCase()));
  acgRec.dbaNames = [...allDba].filter(Boolean);
  delete acgRec.name2; // folded into dbaNames

  // Personnel (FAA-only fields)
  acgRec.ceo        = faaRec.ceo        || '';
  acgRec.dirOps     = faaRec.dirOps     || '';
  acgRec.dirMaint   = faaRec.dirMaint   || '';
  acgRec.chiefPilot = faaRec.chiefPilot || '';
  acgRec.employees  = faaRec.employees  || null;

  // FSDO district info
  acgRec.fsdoCode     = faaRec.fsdoCode     || '';
  acgRec.fsdoDistrict = faaRec.fsdoDistrict || '';

  // Contact backfill: phone/address from FAA if ACG is empty
  if (!acgRec.phone && faaRec.phone) acgRec.phone = faaRec.phone;
  if (!acgRec.address && faaRec.address) acgRec.address = faaRec.address;
  if (!acgRec.zip && faaRec.zip) acgRec.zip = faaRec.zip;

  // FAA aircraft with tail numbers (keep ACG aircraft table too — different data)
  acgRec.faaAircraft = faaRec.aircraft || [];

  enriched++;
}

// Step 2: clean up ACG records that had no FAA match — ensure consistent shape
for (const r of acg) {
  if (r.source !== 'both') {
    r.source = 'aircharterguide';
    // Fold name2 into dbaNames
    const allDba = new Set();
    if (r.name2) allDba.add(r.name2.trim().toUpperCase());
    if (!r.dbaNames) r.dbaNames = [];
    r.dbaNames.forEach(d => allDba.add(d.trim().toUpperCase()));
    r.dbaNames = [...allDba].filter(Boolean);
    delete r.name2;

    r.dsgnCode    = '';
    r.certNumber  = '';
    r.certDate    = '';
    r.ceo         = '';
    r.dirOps      = '';
    r.dirMaint    = '';
    r.chiefPilot  = '';
    r.employees   = null;
    r.fsdoCode    = '';
    r.fsdoDistrict = '';
    r.faaAircraft = [];
  }
}

// Step 3: convert FAA-only records to unified shape
const faaOnlyRecords = faaUnmatched.map(r => {
  const dbaNames = new Set((r.dbaNames || []).map(d => d.trim().toUpperCase()));

  return {
    source:       'faa_135',
    // No ACG IDs for FAA-only
    companyId:    null,
    locationId:   null,
    // Identity
    name:         r.name,
    dbaNames:     [...dbaNames].filter(Boolean),
    airportCode:  '',       // will be geocoded/assigned at import time
    city:         r.city,
    state:        r.state.trim(),
    country:      r.country || 'US',
    metro:        '',
    // Safety ratings
    argusRating:  '',
    wyvern:       false,
    wingman:      false,
    // Fleet summary
    fleetCount:   r.aircraft?.length || 0,
    dedicatedPilots: null,
    established:  null,
    // Descriptions
    shortDescription: '',
    description:  '',
    logoPath:     '',
    // Contact
    address:      r.address,
    phone:        r.phone,
    fax:          '',
    email:        '',
    website:      '',
    zip:          r.zip,
    // ACG aircraft table — not available for FAA-only
    aircraftCounts: null,
    aircraft:     [],
    // FAA cert / regulatory
    dsgnCode:     r.dsgnCode,
    certNumber:   r.certNumber,
    certDate:     r.certDate,
    // FAA personnel
    ceo:          r.ceo,
    dirOps:       r.dirOps,
    dirMaint:     r.dirMaint,
    chiefPilot:   r.chiefPilot,
    employees:    r.employees,
    // FSDO
    fsdoCode:     r.fsdoCode,
    fsdoDistrict: r.fsdoDistrict,
    // FAA aircraft with tail numbers
    faaAircraft:  r.aircraft || [],
  };
});

// Combine: enriched ACG (907) + FAA-only (~1085)
const merged = [...acg, ...faaOnlyRecords];

// Sort: state then name
merged.sort((a, b) => {
  const s = (a.state || '').localeCompare(b.state || '');
  return s !== 0 ? s : (a.name || '').localeCompare(b.name || '');
});

fs.writeFileSync(OUT_PATH, JSON.stringify(merged, null, 2));

const fileSize = fs.statSync(OUT_PATH).size;
const withEmail    = merged.filter(r => r.email).length;
const withPhone    = merged.filter(r => r.phone).length;
const withWebsite  = merged.filter(r => r.website).length;
const withAddress  = merged.filter(r => r.address).length;
const withCert     = merged.filter(r => r.certNumber).length;
const withFaaAc    = merged.filter(r => r.faaAircraft?.length > 0).length;
const withAcgAc    = merged.filter(r => r.aircraft?.length > 0).length;
const totalFaaAc   = merged.reduce((s, r) => s + (r.faaAircraft?.length || 0), 0);
const totalAcgAc   = merged.reduce((s, r) => s + (r.aircraft?.length || 0), 0);

console.log(`\n${'='.repeat(60)}`);
console.log('Charter Operator Merge Complete');
console.log('='.repeat(60));
console.log(`ACG records:             ${acg.length}`);
console.log(`  Enriched with FAA:     ${enriched}`);
console.log(`  ACG-only (no FAA):     ${acg.length - enriched}`);
console.log(`FAA-only new records:    ${faaOnlyRecords.length}`);
console.log(`Total merged:            ${merged.length}`);
console.log('');
console.log('Field coverage:');
console.log(`  Email:       ${withEmail} (${Math.round(100*withEmail/merged.length)}%)`);
console.log(`  Phone:       ${withPhone} (${Math.round(100*withPhone/merged.length)}%)`);
console.log(`  Website:     ${withWebsite} (${Math.round(100*withWebsite/merged.length)}%)`);
console.log(`  Address:     ${withAddress} (${Math.round(100*withAddress/merged.length)}%)`);
console.log(`  FAA cert #:  ${withCert} (${Math.round(100*withCert/merged.length)}%)`);
console.log(`  ACG fleet:   ${withAcgAc} operators, ${totalAcgAc} aircraft`);
console.log(`  FAA N#s:     ${withFaaAc} operators, ${totalFaaAc} aircraft`);
console.log(`Output: ${OUT_PATH} (${(fileSize/1024/1024).toFixed(2)} MB)`);
