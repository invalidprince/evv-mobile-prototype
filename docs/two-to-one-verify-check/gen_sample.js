#!/usr/bin/env node
// Generates sample.json from evv-poc's REAL two-to-one-verify.describe() so
// the decode test reads the server's own shape, not a hand-typed guess.
// Usage: node gen_sample.js <path-to-evv-poc> > sample.json
'use strict';
const path = require('path');
const root = process.argv[2] || path.join(__dirname, '../../../focus-nexus/evv-poc');
const tto = require(path.join(root, 'two-to-one-verify.js'));
const db = {
  staffById: (id) => ({ S013: { name: 'Nick Mudgett' }, S203: { name: 'Cassey Mudgett' }, S102: { name: 'Matthew Mudgett' } }[id] || null),
  clientById: (id) => (id === 'C673069' ? { name: 'Dustin Sackett' } : null),
  serviceName: (c) => (c === 'W7068' ? 'In-Home & Community Support (2:1)' : null),
};
const now = new Date('2026-09-22T18:33:10.000Z');
const ops = tto.createOps({ pool: { query: async () => ({ rows: [] }) }, loadSnapshot: async () => db, now: () => now, nowTimeET: () => '2:33 PM', todayET: () => '2026-09-22', loadWindowSec: async () => 120 });
const row = (o) => ({ id: 7, shift_id: 900, visit_id: 'V-2079', client_id: 'C673069', service: 'W7068', requested_by: 'S013', second_staff_id: 'S203', clock_in_label: '2:33 PM', requested_at: now, expires_at: new Date(now.getTime() + 120000), window_sec: 120, status: 'pending', resolved_at: null, confirmed_visit_id: null, ...o });
const payload = {
  shifts: [], openShifts: [],
  twoToOneVerify: {
    pending: [ops.describe(row({}), db)],
    mine: [ops.describe(row({ id: 8, visit_id: 'V-2081', status: 'expired' }), db), ops.describe(row({ id: 9, visit_id: 'V-2082', status: 'confirmed', confirmed_visit_id: 'V-3000' }), db)],
    windowSec: 120,
  },
};
process.stdout.write(JSON.stringify(payload, null, 2));
