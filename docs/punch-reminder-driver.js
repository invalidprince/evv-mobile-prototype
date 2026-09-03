#!/usr/bin/env node
// Host-side driver for EVVMobileUITests/PunchReminderShotTests.swift (build 60/61,
// Todoist 6hQfcR8RVvmvqFcq). Talks to prod RDS directly (DATABASE_URL from Secrets
// Manager evv-prod/app-env) and hands the UITest a fixture through /tmp files:
//   1. creates ONE scheduled W7061 shift for demo S001 / C001 starting ~2 h from now
//      (parks any other S001 shift today so it is the only Up Next card);
//   2. waits for /tmp/prc_stage1_done (app logged in → reconcile ran),
//      /tmp/prc_stage2_done (clocked in), /tmp/prc_stage3_done (signed out);
//   3. reads the simulator log the caller captured into /tmp/prc_log.txt and asserts
//      the [punch-reminders] lines: 1 clock-in pending at start+15 → punchedIn cancelled
//      → 1 clock-out pending at end+60 → signOut cancelled;
//   4. cleans up everything it and the app wrote (FK order) and asserts the baseline.
// Run: node docs/punch-reminder-driver.js   (start the UITest when it says so)
'use strict';
const { execSync } = require('child_process');
const fs = require('fs');

const PG = '/Users/nick/.openclaw/workspace-focus-nexus-codex/focus-nexus/evv-poc/node_modules/pg';
const { Pool } = require(PG);
const sec = JSON.parse(execSync('aws secretsmanager get-secret-value --secret-id evv-prod/app-env --region us-east-2 --query SecretString --output text').toString());
const pool = new Pool({ connectionString: sec.DATABASE_URL.split('?')[0], ssl: { rejectUnauthorized: false } });
const STAFF = 'S001'; const CLIENT = 'C001'; const SERVICE = 'W7061';

const fmt = (d) => new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: '2-digit', hour12: true }).format(d).toUpperCase();
const hhmm = (d) => new Intl.DateTimeFormat('en-GB', { timeZone: 'America/New_York', hour: '2-digit', minute: '2-digit', hour12: false }).format(d);
const todayET = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(new Date());
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const waitFile = async (p, ms) => { const end = Date.now() + ms; while (Date.now() < end) { if (fs.existsSync(p)) return true; await sleep(1000); } return false; };
let pass = 0; const fails = [];
const check = (name, cond, extra) => { if (cond) { pass += 1; console.log(`  ✓ ${name}`); } else { fails.push(name); console.log(`  ✗ ${name} ${extra || ''}`); } };
const log = () => { try { return fs.readFileSync('/tmp/prc_log.txt', 'utf8'); } catch (_) { return ''; } };

(async () => {
  for (const f of ['/tmp/prc_stage1_done', '/tmp/prc_stage2_done', '/tmp/prc_stage3_done']) { try { fs.unlinkSync(f); } catch (_) {} }
  const today = todayET();
  const counts = async () => (await pool.query(`select (select count(*) from visits) v, (select count(*) from shifts) s,
    (select count(*) from exceptions) e, (select count(*) from visit_events) ev`)).rows[0];
  const base = await counts();
  const before = (await pool.query('select id from shifts where staff_id=$1 and date=$2', [STAFF, today])).rows.map((r) => r.id);
  const { rows: [pol] } = await pool.query('select clock_in_staff_after_min ci, clock_out_staff_after_min co, app_reminders_enabled ae from punch_alert_settings where id=1');
  console.log('baseline', base, 'S001 today shifts before:', before, 'policy', pol);
  const mine = { shifts: [], visits: [] };
  try {
    await pool.query(`update shifts set status='cancelled' where staff_id=$1 and date=$2 and status<>'cancelled'`, [STAFF, today]);
    const start = new Date(Date.now() + 2 * 3600000); const end = new Date(start.getTime() + 3600000);
    if (todayET() !== new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(end)) throw new Error('too close to midnight for a same-day fixture');
    const { rows: [sh] } = await pool.query(
      `insert into shifts (date, client_id, staff_id, service, start_time, end_time, status) values ($1,$2,$3,$4,$5,$6,'scheduled') returning id`,
      [today, CLIENT, STAFF, SERVICE, fmt(start), fmt(end)]);
    mine.shifts.push(sh.id);
    const expectIn = hhmm(new Date(start.getTime() + pol.ci * 60000));
    const expectOut = hhmm(new Date(end.getTime() + pol.co * 60000));
    console.log(`fixture: scheduled shift ${sh.id} ${fmt(start)}–${fmt(end)} → expect clock-in reminder @${expectIn}, clock-out reminder @${expectOut}`);
    console.log('→ start the UITest now');

    if (!(await waitFile('/tmp/prc_stage1_done', 15 * 60000))) throw new Error('test never reached stage 1');
    await sleep(3000);
    let L = log();
    const rec1 = (L.match(/reconciled: [^\n]*/g) || []);
    console.log('  stage 1 log lines:', rec1.length);
    check('stage 1: a reconcile ran after login', rec1.length >= 1, L.slice(-400));
    const last1 = rec1[rec1.length - 1] || '';
    check('stage 1: exactly 1 pending — 1 clock-in, 0 clock-out', /reconciled: 1 pending \(1 clock-in, 0 clock-out\)/.test(last1), last1);
    check(`stage 1: keyed on THE server shift id, firing at start+${pol.ci} (${expectIn})`, last1.includes(`punch-in-shift-${sh.id}@${expectIn}`), last1);
    check('stage 1: policy echoed from the server (enabled, minutes)', last1.includes(`enabled=true clockIn=${pol.ci} clockOut=${pol.co}`), last1);

    if (!(await waitFile('/tmp/prc_stage2_done', 5 * 60000))) throw new Error('test never reached stage 2');
    await sleep(3000);
    L = log();
    const { rows: live } = await pool.query(`select id, shift_id from visits where staff_id=$1 and date=$2 and active=true`, [STAFF, today]);
    for (const v of live) mine.visits.push(v.id);
    check('stage 2: the app clocked in on THE fixture shift (one running visit)', live.length === 1 && live[0].shift_id === sh.id, JSON.stringify(live));
    check(`stage 2: punchedIn cancelled punch-in-shift-${sh.id}`, L.includes(`punchedIn: cancelled punch-in-shift-${sh.id}`), L.slice(-600));
    const rec2 = (L.match(/reconciled: [^\n]*/g) || []);
    const last2 = rec2[rec2.length - 1] || '';
    check('stage 2: reconcile after the punch → 0 clock-in, 1 clock-out', /reconciled: 1 pending \(0 clock-in, 1 clock-out\)/.test(last2), last2);
    if (live.length === 1) check(`stage 2: clock-out reminder keyed on the server visit id, firing at end+${pol.co} (${expectOut})`, last2.includes(`punch-out-visit-${live[0].id}@${expectOut}`), last2);
    check('stage 2: no clock-in reminder survives the punch', !/punch-in-shift-/.test(last2), last2);

    if (!(await waitFile('/tmp/prc_stage3_done', 3 * 60000))) throw new Error('test never reached stage 3');
    await sleep(2000);
    L = log();
    check('stage 3: sign-out cancelled the pending punch reminder(s)', /signOut: cancelled [1-9]/.test(L), L.slice(-300));
    check('no note reminder id ever appears in a punch-reminders line', !/note-eod-|note-late-/.test(L));
  } catch (e) {
    console.error('driver error:', e.message); fails.push(e.message);
  } finally {
    for (const vid of mine.visits) {
      await pool.query('delete from nudges where exception_id in (select id from exceptions where visit_id=$1)', [vid]);
      await pool.query('delete from exceptions where visit_id=$1', [vid]);
      await pool.query('delete from visit_events where visit_id=$1', [vid]);
      await pool.query('delete from visits where id=$1', [vid]);
      await pool.query(`delete from audit_log where entity_type='visit' and $1 = any(string_to_array(entity_id, ','))`, [vid]);
    }
    const { rows: stray } = await pool.query('select id from visits where shift_id = any($1::int[])', [mine.shifts.length ? mine.shifts : [0]]);
    for (const v of stray) {
      await pool.query('delete from exceptions where visit_id=$1', [v.id]);
      await pool.query('delete from visit_events where visit_id=$1', [v.id]);
      await pool.query('delete from visits where id=$1', [v.id]);
    }
    for (const sid of mine.shifts) {
      await pool.query('delete from shift_staff where shift_id=$1', [sid]);
      await pool.query('delete from shift_individuals where shift_id=$1', [sid]);
      await pool.query('delete from shifts where id=$1', [sid]);
      await pool.query(`delete from audit_log where entity_type='shift' and entity_id=$1`, [String(sid)]);
    }
    const { rows: lazy } = await pool.query(`select id from shifts where staff_id=$1 and date=$2 and id <> all($3::int[]) and not exists (select 1 from visits where shift_id=shifts.id)`, [STAFF, today, before.length ? before : [0]]);
    for (const s of lazy) { await pool.query('delete from shift_staff where shift_id=$1', [s.id]); await pool.query('delete from shifts where id=$1', [s.id]); }
    if (before.length) await pool.query(`update shifts set status='scheduled' where id = any($1::int[]) and status='cancelled'`, [before]);
    await pool.query(`delete from audit_log where actor in ('mgonzalez@fbhi.net','demo@focus.com') and ts > now() - interval '30 minutes' and action in ('clock-in','clock-out','mobile-login')`);
    const after = await counts();
    const same = ['v', 's', 'e', 'ev'].every((k) => String(after[k]) === String(base[k]));
    check(`cleanup: counts back to baseline ${JSON.stringify(base)}`, same, JSON.stringify(after));
    await pool.end();
    console.log(`\n${pass} passed, ${fails.length} failed`);
    process.exit(fails.length ? 1 : 0);
  }
})();
