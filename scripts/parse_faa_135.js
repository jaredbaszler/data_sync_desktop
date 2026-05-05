// Parse FAA Part 135 certificate holder data from 3 Excel files.
// Joins operators, DBA names, and aircraft into unified records.
// Cross-references against assets/aircharterguide_operators.json to flag matches.
//
// Run: node scripts/parse_faa_135.js
// Output: assets/faa_135_operators.json

const XLSX = require('xlsx');
const fs   = require('fs');
const path = require('path');

const DIR        = path.join(__dirname, '..', 'assets', '135_Charter_Operators');
const ACG_PATH   = path.join(__dirname, '..', 'assets', 'aircharterguide_operators.json');
const OUTPUT     = path.join(__dirname, '..', 'assets', 'faa_135_operators.json');

// ─── Helpers ─────────────────────────────────────────────────────────────────

function readSheet(file) {
  const wb = XLSX.readFile(path.join(DIR, file));
  return XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: '' });
}

// Extract FSDO abbreviation from "EA23 - Rochester (ROC)" → "ROC"
// Some have "HNL FSDO" — strip " FSDO" before taking
function parseFsdo(raw) {
  const m = raw.match(/\(([A-Z][A-Z0-9 ]+)\)/);
  if (!m) return '';
  return m[1].replace(/\s+FSDO$/i, '').trim();
}

// Normalize name for matching: lowercase, strip legal suffixes, collapse spaces
function normalizeName(s) {
  return (s || '')
    .toLowerCase()
    .replace(/\bllc\b|\bl\.l\.c\.\b|\binc\b|\binc\.\b|\bcorp\b|\bcorp\.\b|\bltd\b|\bltd\.\b|\bco\b|\bco\.\b|\blp\b|\bpllc\b|\bplc\b/gi, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function formatPhone(raw) {
  if (!raw) return '';
  const digits = String(raw).replace(/\D/g, '');
  if (digits.length === 10) return `(${digits.slice(0,3)}) ${digits.slice(3,6)}-${digits.slice(6)}`;
  if (digits.length === 11 && digits[0] === '1') return `(${digits.slice(1,4)}) ${digits.slice(4,7)}-${digits.slice(7)}`;
  return String(raw).trim();
}

// ─── Parse operators file ────────────────────────────────────────────────────

console.log('Reading 135 - Air Operators (FAA).xlsx...');
const opRows = readSheet('135 - Air Operators (FAA).xlsx');
const opHeaders = opRows[0];
console.log(`  ${opRows.length - 1} operators`);

const opMap = {};   // DSGN_CODE → operator record
for (let i = 1; i < opRows.length; i++) {
  const r = opRows[i];
  const code = r[2] || '';
  if (!code) continue;

  const addr = [r[6], r[7], r[8]].map(s => String(s).trim()).filter(Boolean).join(', ');

  opMap[code] = {
    source:      'faa_135',
    dsgnCode:    code,
    certNumber:  r[3] || '',
    certDate:    r[4] || '',
    name:        String(r[0] || '').trim(),
    ceo:         String(r[5] || '').trim(),
    address:     addr,
    city:        String(r[9]  || '').trim(),
    state:       String(r[10] || '').trim(),
    country:     String(r[11] || '').trim(),
    zip:         String(r[12] || '').trim(),
    phone:       formatPhone(r[13]),
    dirOps:      String(r[16] || '').trim(),
    dirMaint:    String(r[17] || '').trim(),
    chiefPilot:  String(r[18] || '').trim(),
    employees: {
      picCaptains:       Number(r[19]) || 0,
      inspectors:        Number(r[20]) || 0,
      designatedInspectors: Number(r[21]) || 0,
      nonCertMechanics:  Number(r[22]) || 0,
      certMechanics:     Number(r[23]) || 0,
      repairmen:         Number(r[24]) || 0,
      total:             Number(r[25]) || 0,
    },
    dbaNames: [],
    fsdoCode: '',
    fsdoDistrict: '',
    aircraft: [],
    acgMatch: null,
  };
}

// ─── Parse DBA file ──────────────────────────────────────────────────────────

console.log('Reading 135 - Air Operators DBA (FAA).xlsx...');
const dbaRows = readSheet('135 - Air Operators DBA (FAA).xlsx');
console.log(`  ${dbaRows.length - 1} DBA rows`);

// Merged cells: columns A-E are merged across multi-DBA rows, so DSGN_CODE
// is blank on rows 2+ for the same operator. Carry forward last non-blank code.
let currentDbaCode = '';
for (let i = 1; i < dbaRows.length; i++) {
  const r    = dbaRows[i];
  const code = r[2] || '';
  if (code) currentDbaCode = code;
  const dba  = String(r[6] || '').trim();   // last column — DBA name
  if (!currentDbaCode || !dba) continue;
  if (opMap[currentDbaCode]) {
    if (!opMap[currentDbaCode].dbaNames.includes(dba)) opMap[currentDbaCode].dbaNames.push(dba);
  }
}

// ─── Parse aircraft file ─────────────────────────────────────────────────────

console.log('Reading 135aircraft.xlsx...');
const acRows = readSheet('135aircraft.xlsx');
console.log(`  ${acRows.length - 1} aircraft rows`);

for (let i = 1; i < acRows.length; i++) {
  const r    = acRows[i];
  const code = r[1] || '';       // Certificate Designator
  if (!code) continue;

  const fsdo = String(r[2] || '').trim();

  if (opMap[code]) {
    // Set FSDO from first aircraft row
    if (!opMap[code].fsdoCode) {
      opMap[code].fsdoCode     = parseFsdo(fsdo);
      opMap[code].fsdoDistrict = fsdo;
    }

    opMap[code].aircraft.push({
      regNumber:        String(r[3] || '').trim(),
      serialNumber:     String(r[4] || '').trim(),
      makeModelSeries:  String(r[5] || '').trim(),
      classOfOperation: String(r[6] || '').trim(),
      section119:       String(r[7] || '').trim(),
    });
  }
}

// ─── Cross-reference aircharterguide ────────────────────────────────────────

let acgRecords = [];
if (fs.existsSync(ACG_PATH)) {
  acgRecords = JSON.parse(fs.readFileSync(ACG_PATH, 'utf-8'));
  console.log(`\nLoaded ${acgRecords.length} AirCharterGuide operators for matching.`);
}

// Build lookup: normalizedName → acg record
const acgByName = new Map();
for (const acg of acgRecords) {
  const key = normalizeName(acg.name);
  if (key) acgByName.set(key, acg);
  // also index name2 (alternate name)
  if (acg.name2) {
    const k2 = normalizeName(acg.name2);
    if (k2 && !acgByName.has(k2)) acgByName.set(k2, acg);
  }
}

let matchCount = 0;
for (const op of Object.values(opMap)) {
  // Try operator legal name
  const norm = normalizeName(op.name);
  let match = acgByName.get(norm);

  // Try each DBA
  if (!match) {
    for (const dba of op.dbaNames) {
      match = acgByName.get(normalizeName(dba));
      if (match) break;
    }
  }

  if (match) {
    matchCount++;
    op.acgMatch = {
      companyId:      match.companyId,
      locationId:     match.locationId,
      argusRating:    match.argusRating,
      wyvern:         match.wyvern,
      wingman:        match.wingman,
      fleetCount:     match.fleetCount,
      website:        match.website,
      email:          match.email,
    };
  }
}

console.log(`Matched ${matchCount} FAA operators to AirCharterGuide records.`);
console.log(`Unmatched (FAA-only): ${Object.keys(opMap).length - matchCount}`);

// ─── Output ──────────────────────────────────────────────────────────────────

const operators = Object.values(opMap);
operators.sort((a, b) => a.name.localeCompare(b.name));

fs.writeFileSync(OUTPUT, JSON.stringify(operators, null, 2));

// ─── Summary ─────────────────────────────────────────────────────────────────

const withAircraft  = operators.filter(o => o.aircraft.length > 0);
const withDba       = operators.filter(o => o.dbaNames.length > 0);
const withPhone     = operators.filter(o => o.phone);
const withFsdo      = operators.filter(o => o.fsdoCode);
const withAcgMatch  = operators.filter(o => o.acgMatch);
const totalAc       = operators.reduce((s,o) => s + o.aircraft.length, 0);
const fileSize      = fs.statSync(OUTPUT).size;

console.log(`\n${'='.repeat(60)}`);
console.log('FAA 135 Parse Complete');
console.log('='.repeat(60));
console.log(`Total operators:          ${operators.length}`);
console.log(`With aircraft records:    ${withAircraft.length}  (${totalAc} total aircraft)`);
console.log(`With DBA names:           ${withDba.length}`);
console.log(`With phone:               ${withPhone.length}`);
console.log(`With FSDO code:           ${withFsdo.length}`);
console.log(`Matched to AirCharterGuide: ${withAcgMatch.length}`);
console.log(`FAA-only (no ACG match):    ${operators.length - withAcgMatch.length}`);
console.log(`Output: ${OUTPUT} (${(fileSize/1024/1024).toFixed(2)} MB)`);
