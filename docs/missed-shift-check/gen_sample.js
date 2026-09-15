#!/usr/bin/env node
// Build 71 — emit a GET /api/me/missed-shifts payload EXACTLY as api.js shapes
// it, using the REAL server builders (todo-core.missedShiftsForStaff →
// missed-shifts.js) over the fixture from evv-poc/docs/test-missed-shift-
// resolution.js. The Swift decoder test consumes the output, so the app is
// proven against the server's real row shape, not a hand-typed guess.
// Falls back to sample.json when the evv-poc checkout is not beside this repo.
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://offline:offline@127.0.0.1:1/offline';
const path = require('path');
const fs = require('fs');
const root = path.resolve(__dirname, '../../../focus-nexus/evv-poc');
let out;
try {
  const todoCore = require(path.join(root, 'todo-core'));
  const ms = require(path.join(root, 'missed-shifts'));
  const { NOT_WORKED_REASONS } = require(path.join(root, 'db'));
  const TODAY = '2026-09-18';
  const NOW = new Date('2026-09-18T15:00:00Z');
  const svc = [
    { code: 'W1726', description: 'IHCS', requiresClockIn: true },
    { code: 'W8593', description: 'Lifesharing', requiresClockIn: false },
  ];
  const shifts = [
    { id: 1, date: '2026-09-16', start: '9:00 AM', end: '1:00 PM', client: 'C1', staff: 'S1', service: 'W1726', status: 'scheduled' },
    { id: 5, date: '2026-09-15', start: '1:00 PM', end: '5:00 PM', client: 'C1', staff: 'S1', service: 'W1726', status: 'scheduled' },
    { id: 6, date: '2026-09-17', start: '8:00 AM', end: '4:00 PM', client: null, clientList: [{ clientId: 'C1' }], staff: null, staffList: [{ staffId: 'S1' }, { staffId: 'S2' }], service: 'W1726', status: 'scheduled' },
  ];
  const staff = [{ id: 'S1', name: 'Dee Esp', departments: ['D1'], status: 'Active', app_role: 'DSP' }, { id: 'S2', name: 'Two', departments: ['D1'], status: 'Active', app_role: 'DSP' }];
  const clients = [{ id: 'C1', name: 'Ray V', departments: ['D1'] }];
  const db = {
    TODAY, serviceCodes: svc, shifts, visits: [], pendingVisits: [], staff, clients, departments: [],
    missedShiftResolutions: [], missedShiftResolutionByKey: new Map(),
    visitById: () => null, staffById: (id) => staff.find((s) => s.id === id) || null,
    clientById: (id) => clients.find((c) => c.id === id) || null,
    serviceByCode: (c) => svc.find((s) => s.code === c) || null,
    deptById: () => null, deptSupervisorStaffId: () => null, descendantIds: (id) => [id],
    shiftById: (id) => shifts.find((s) => s.id === Number(id)) || null,
  };
  const minDate = '2026-09-11';
  const rows = todoCore.missedShiftsForStaff(db, 'S1', { now: NOW }).map((m) => Object.assign({}, m, {
    canRequest: m.date >= minDate, requestMinDate: minDate,
  }));
  out = { missedShifts: rows, reasons: NOT_WORKED_REASONS, requiredFrom: ms.REASON_REQUIRED_FROM, shiftRequestMaxDays: 7 };
  fs.writeFileSync(path.join(__dirname, 'sample.json'), JSON.stringify(out, null, 2) + '\n');
  process.stderr.write(`gen_sample: ${rows.length} rows from the REAL server builders\n`);
} catch (e) {
  process.stderr.write(`gen_sample: evv-poc not available (${e.message}); using checked-in sample.json\n`);
  out = JSON.parse(fs.readFileSync(path.join(__dirname, 'sample.json'), 'utf8'));
}
process.stdout.write(JSON.stringify(out));
