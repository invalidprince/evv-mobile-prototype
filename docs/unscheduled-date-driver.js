#!/usr/bin/env node
// Host-side driver for EVVMobileUITests/UnscheduledDateShotTests.swift (build 62).
//
// Nick, #evv 2026-09-09: "There's no way to put a date on this like you can on
// desktop. Just fix this."
//
// Talks to prod RDS directly (DATABASE_URL from Secrets Manager evv-prod/app-env):
//   1. records the baseline and clears anything that would block the entry
//      (a demo S001 visit on the target day would 409 by the v0.4.334 overlap rule);
//   2. waits for /tmp/uvd_stage1_done (the app reported "Time recorded");
//   3. 🔑 asserts in RDS that the visit the PHONE created carries YESTERDAY's date —
//      the whole point of the card, proven from the database rather than the UI;
//   4. cleans up FK-ordered (exceptions → visit_events → visits → shift_staff →
//      shifts) and asserts the baseline is restored.
//
// \u{1F6A7} STATUS (build 62): pairs with EVVMobileUITests/UnscheduledDateShotTests.swift,
// which is currently blocked by iOS 26.3 simulator hit-testing (see that file's
// header). The evidence that shipped for this card is docs/manual-date-check
// (43/43 offline) + docs/manual-date-live (16/16 against live CloudFront). This
// driver is kept because the fixture setup + FK-ordered cleanup + baseline
// assertions are the reusable part.
//
// Run: node docs/unscheduled-date-driver.js   (start the UITest when it says so)
'use strict';
const { execSync } = require('child_process');
const fs = require('fs');

const PG = '/Users/nick/.openclaw/workspace-focus-nexus-codex/focus-nexus/evv-poc/node_modules/pg';
const { Pool } = require(PG);
const sec = JSON.parse(execSync(
  'aws secretsmanager get-secret-value --secret-id evv-prod/app-env --region us-east-2 --query SecretString --output text',
).toString());
const pool = new Pool({ connectionString: sec.DATABASE_URL.split('?')[0], ssl: { rejectUnauthorized: false } });

const STAFF = 'S001';
const CLIENT = 'C001';
const SERVICE = 'W8593'; // IDD Life Sharing — the non-EVV manual-time service

const todayET = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(new Date());
const shiftIso = (iso, days) => {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d, 12));
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const waitFile = async (p, ms) => {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (fs.existsSync(p)) return true; await sleep(1000); }
  return false;
};

let pass = 0; const fails = [];
const check = (name, cond, extra) => {
  if (cond) { pass += 1; console.log(`  \u2713 ${name}`); }
  else { fails.push(name); console.log(`  \u2717 ${name} ${extra === undefined ? '' : extra}`); }
};

(async () => {
  for (const f of ['/tmp/uvd_stage1_done']) { try { fs.unlinkSync(f); } catch (_) { /* ignore */ } }
  const TODAY = todayET();
  const TARGET = shiftIso(TODAY, -1); // yesterday — Nick's forgotten-visit case
  console.log(`today(ET)=${TODAY}  target day=${TARGET}`);

  const counts = async () => (await pool.query(
    `select (select count(*) from visits) v, (select count(*) from shifts) s,
            (select count(*) from exceptions) e, (select count(*) from visit_events) ev`,
  )).rows[0];
  const base = await counts();
  console.log('baseline', base);

  // Anything already on the target day for S001 would 409 (v0.4.334 staff
  // overlap) and the UITest would read as a feature failure. Park it.
  const { rows: blockers } = await pool.query(
    `select id, actual_in, actual_out from visits
      where staff_id = $1 and date = $2
        and approval_status is distinct from 'deleted'`, [STAFF, TARGET]);
  console.log(`blocking S001 visits on ${TARGET}:`, blockers.map((r) => r.id));
  const parked = [];
  for (const b of blockers) {
    await pool.query(`update visits set approval_status = 'deleted' where id = $1`, [b.id]);
    parked.push(b.id);
  }

  const before = new Set((await pool.query('select id from visits')).rows.map((r) => r.id));

  console.log('\n>>> START THE UITEST NOW (UnscheduledDateShotTests) <<<\n');
  const got = await waitFile('/tmp/uvd_stage1_done', 15 * 60 * 1000);
  check('the app reported "Time recorded"', got, '(timed out waiting for /tmp/uvd_stage1_done)');

  const mine = { visits: [], shifts: [] };
  if (got) {
    await sleep(3000);
    const { rows: fresh } = await pool.query(
      `select id, date, staff_id, client_id, service, actual_in, actual_out, units, shift_id
         from visits where staff_id = $1 order by id desc limit 10`, [STAFF]);
    const created = fresh.filter((r) => !before.has(r.id));
    check('the phone created exactly one visit', created.length === 1,
      JSON.stringify(created.map((r) => ({ id: r.id, date: r.date }))));
    if (created.length) {
      const v = created[0];
      mine.visits.push(v.id);
      if (v.shift_id) mine.shifts.push(v.shift_id);
      const iso = v.date instanceof Date
        ? new Intl.DateTimeFormat('en-CA', { timeZone: 'UTC' }).format(v.date)
        : String(v.date).slice(0, 10);
      console.log(`   created ${v.id}: date=${iso} ${v.actual_in}\u2013${v.actual_out} ${v.service} units=${v.units}`);
      check(`\u{1F511} the visit the PHONE created is dated ${TARGET}, NOT today`, iso === TARGET,
        `got ${iso}`);
      check('\u2026it is NOT filed under today', iso !== TODAY, `got ${iso}`);
      check('\u2026with the service the sheet selected', v.service === SERVICE, v.service);
      check('\u2026and the individual the sheet selected', v.client_id === CLIENT, v.client_id);
      check('\u202612:00 AM \u2192 12:00 AM survived as a full day (96 units), not 0',
        String(v.units) === '96', String(v.units));
    }
  }

  // ── cleanup, FK-ordered ────────────────────────────────────────────────
  // \u26a0\ufe0f exceptions FIRST: an unscheduled punch can raise an
  // "Unauthorized service" exception, and exceptions_visit_id_fkey blocks the
  // visit delete until that row is gone.
  for (const id of mine.visits) {
    await pool.query('delete from exceptions where visit_id = $1', [id]);
    await pool.query('delete from visit_events where visit_id = $1', [id]);
    await pool.query('delete from visits where id = $1', [id]);
  }
  for (const id of new Set(mine.shifts)) {
    const { rows } = await pool.query('select count(*) c from visits where shift_id = $1', [id]);
    if (Number(rows[0].c) === 0) {
      await pool.query('delete from shift_staff where shift_id = $1', [id]);
      await pool.query('delete from shifts where id = $1', [id]);
    }
  }
  for (const id of parked) {
    await pool.query(`update visits set approval_status = null where id = $1`, [id]);
  }
  const after = await counts();
  check('visits back to baseline', after.v === base.v, `${after.v} vs ${base.v}`);
  check('shifts back to baseline', after.s === base.s, `${after.s} vs ${base.s}`);
  check('exceptions back to baseline', after.e === base.e, `${after.e} vs ${base.e}`);
  check(`parked visits restored (${parked.length})`,
    (await pool.query(
      `select count(*) c from visits where id = any($1::text[]) and approval_status is null`,
      [parked.length ? parked : ['~none~']])).rows[0].c === String(parked.length));

  console.log(`\n${pass} passed, ${fails.length} failed`);
  fails.forEach((f) => console.log(`  FAILED: ${f}`));
  await pool.end();
  process.exit(fails.length ? 1 : 0);
})().catch(async (e) => { console.error(e); try { await pool.end(); } catch (_) {} process.exit(1); });
