// tools/inspect_psgc.mjs
import psgc from 'psgc';

const { regions, provinces, municipalities, barangays } = psgc;

console.log('Sample region:', regions.all()[0]);
console.log('Sample province:', provinces.all()[0]);
console.log('Sample municipality:', municipalities.all()[0]);
console.log('Sample barangay:', barangays.all()[0]);