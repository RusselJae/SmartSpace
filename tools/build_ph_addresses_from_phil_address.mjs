// tools/build_ph_addresses_from_psgc.mjs
import fs from 'node:fs';
import psgc from 'psgc';

const { provinces, municipalities, barangays } = psgc;

async function build() {
  const provList = provinces.all();
  const muniList = municipalities.all();
  const brgyList = barangays.all();

  // psgc uses NAMES for linking, not codes:
  // - municipalities have m.province (province name)
  // - barangays have b.citymun (municipality/city name)

  // Index municipalities by province NAME
  const munisByProvinceName = new Map();
  for (const m of muniList) {
    const provName = m.province?.trim();
    if (!provName) continue;
    if (!munisByProvinceName.has(provName)) {
      munisByProvinceName.set(provName, []);
    }
    munisByProvinceName.get(provName).push(m);
  }

  // Index barangays by municipality/city NAME
  const barangaysByMuniName = new Map();
  for (const b of brgyList) {
    const muniName = b.citymun?.trim();
    if (!muniName) continue;
    if (!barangaysByMuniName.has(muniName)) {
      barangaysByMuniName.set(muniName, []);
    }
    barangaysByMuniName.get(muniName).push(b);
  }

  // Build { "Province": { "City/Municipality": ["Barangay", ...] } }
  const out = {};

  for (const p of provList) {
    const provName = p.name?.trim();
    if (!provName) continue;

    const munis = munisByProvinceName.get(provName) ?? [];
    if (munis.length === 0) continue; // skip provinces with no municipalities

    if (!out[provName]) out[provName] = {};

    for (const m of munis) {
      const muniName = m.name?.trim();
      if (!muniName) continue;

      const brgys = (barangaysByMuniName.get(muniName) ?? [])
        .map((b) => b.name?.trim())
        .filter((name) => name && name.length > 0)
        .sort(); // alphabetize for easier browsing

      out[provName][muniName] = brgys;
    }
  }

  fs.writeFileSync(
    'app/assets/philippines_addresses_sample.json',
    JSON.stringify(out, null, 2),
    'utf8',
  );
  console.log('Wrote full PH dataset from psgc to app/assets/philippines_addresses_sample.json');
  console.log(`Generated ${Object.keys(out).length} provinces`);
}

build().catch((err) => {
  console.error('Failed to build PH dataset from psgc:', err);
  process.exit(1);
});