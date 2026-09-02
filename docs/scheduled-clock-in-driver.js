#!/usr/bin/env node
// Host-side driver for EVVMobileUITests/ScheduledClockInRejectionShotTests.swift
// (build 57). Talks to prod RDS directly (DATABASE_URL from Secrets Manager
// evv-prod/app-env) as the DEMO account S001 / C001 and cleans up everything it
// writes. Handshake with the UITest via files (simulator shares the host FS):
//   /tmp/sci_stage1_done  ← test saw the inline refusal
//   /tmp/sci_go           → driver deleted the blocker
//   /tmp/sci_stage2_done  ← test saw "Clocked in" + Today active card
//
// Fixture:
//   1. ONE scheduled W7061 shift for S001 today (the only Up Next card).
//   2. A completed visit on a throwaway unscheduled shift whose span covers
//      "now" (±60 min) → the server's staff-overlap rule (v0.4.334) REFUSES the
//      live clock-in with 409 staff_overlap. This is a server refusal the app
//      used to paint as success.
// Run: node docs/scheduled-clock-in-driver.js
'use strict';
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PG = '/Users/nick/.openclaw/workspace-focus-nexus-codex/focus-nexus/evv-poc/node_modules/pg';
const { Pool } = require(PG);
const sec = JSON.parse(execSync('aws secretsmanager get-secret-value --secret-id evv-prod/app-env --region us-east-2 --query SecretString --output text').toString());
const pool = new Pool({ connectionString: sec.DATABASE_URL.split('?')[0], ssl: { rejectUnauthorized: false } });
const STAFF = 'S001'; const CLIENT = 'C001'; const SERVICE = 'W7061';

const fmt = (d) => new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: '2-digit', hour12: true }).format(d).toUpperCase();
const todayET = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(new Date());
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const waitFile = async (p, ms) => { const end = Date.now() + ms; while (Date.now() < end) { if (fs.existsSync(p)) return true; await sleep(1000); } return false; };

(async () => {
  for (const f of ['/tmp/sci_stage1_done', '/tmp/sci_go', '/tmp/sci_stage2_done']) { try { fs.unlinkSync(f); } catch (_) {} }
  const today = todayET();
  const counts = async () => (await pool.query(`select (select count(*) from visits) v, (select count(*) from shifts) s,
    (select count(*) from exceptions) e, (select count(*) from visit_events) ev`)).rows[0];
  const base = await counts();
  const before = (await pool.query('select id from shifts where staff_id=$1 and date=$2', [STAFF, today])).rows.map((r) => r.id);
  console.log('baseline', base, 'S001 today shifts before:', before);
  const mine = { shifts: [], visits: [] };
  try {
    // Park any pre-existing S001 shifts today (demo lazy shift) so ours is the only card.
    await pool.query(`update shifts set status='cancelled' where staff_id=$1 and date=$2 and status<>'cancelled'`, [STAFF, today]);

    const { rows: [sh] } = await pool.query(
      `insert into shifts (date, client_id, staff_id, service, start_time, end_time, status) values ($1,$2,$3,$4,'11:00 PM','11:45 PM','scheduled') returning id`,
      [today, CLIENT, STAFF, SERVICE]);
    mine.shifts.push(sh.id);

    // Blocker: completed visit spanning now-60m → now+60m on a throwaway unscheduled shift
    const now = Date.now();
    const a = fmt(new Date(now - 60 * 60000)); const b = fmt(new Date(now + 60 * 60000));
    const { rows: [bsh] } = await pool.query(
      `insert into shifts (date, client_id, staff_id, service, start_time, end_time, status, origin) values ($1,$2,$3,$4,$5,$6,'completed','unscheduled') returning id`,
      [today, CLIENT, STAFF, SERVICE, a, b]);
    mine.shifts.push(bsh.id);
    const { rows: [mx] } = await pool.query(`select coalesce(max(cast(substring(id from 3) as int)),2000) m from visits where id like 'V-%'`);
    const bvid = `V-${Number(mx.m) + 1}`;
    await pool.query(
      `insert into visits (id, date, client_id, staff_id, service, sched_start, sched_end, actual_in, actual_out, units, verification, evv, billing, doc, active, location_status, sync, note_status, shift_id, pickup, corrections)
       values ($1,$2,$3,$4,$5,$6,$7,$6,$7,'2','verified','pending','unbilled','incomplete',false,'n/a','synced','incomplete',$8,false,'[]')`,
      [bvid, today, CLIENT, STAFF, SERVICE, a, b, bsh.id]);
    mine.visits.push(bvid);
    console.log(`fixture: scheduled shift ${sh.id} (11:00–11:45 PM), blocker ${bvid} ${a}–${b} on shift ${bsh.id}`);
    console.log('→ start the UITest now (copy the test body over MyDocumentsShotTests.swift and run it)');

    if (!(await waitFile('/tmp/sci_stage1_done', 15 * 60000))) throw new Error('test never reached stage 1');
    const midCounts = await counts();
    // baseline + our ONE blocker visit = nothing else was written by the refused punch
    const wroteNothing = Number(midCounts.v) === Number(base.v) + 1;
    console.log('stage 1 reached (inline refusal). counts now', midCounts, '— refused punch wrote nothing?', wroteNothing ? 'YES (visits = baseline + the 1 fixture blocker)' : 'NO');
    fs.writeFileSync('/tmp/sci_refusal_wrote_nothing', wroteNothing ? 'yes' : 'no');

    // Remove the blocker (mirror the delete-approval semantics: soft delete + release the shift)
    await pool.query(`update visits set approval_status='deleted', active=false where id=$1`, [bvid]);
    await pool.query(`update shifts set status='cancelled' where id=$1`, [bsh.id]);
    fs.writeFileSync('/tmp/sci_go', 'go');
    console.log('blocker soft-deleted → /tmp/sci_go');

    if (!(await waitFile('/tmp/sci_stage2_done', 5 * 60000))) throw new Error('test never reached stage 2');
    const { rows: live } = await pool.query(`select id, client_id, shift_id, actual_in, active from visits where staff_id=$1 and date=$2 and active=true`, [STAFF, today]);
    console.log('stage 2 reached. running visit(s):', live);
    for (const v of live) mine.visits.push(v.id);
    const okRow = live.length === 1 && live[0].shift_id === sh.id && live[0].client_id === CLIENT;
    console.log(okRow ? '✓ the accepted punch is on THE scheduled shift / THE right individual' : '✗ unexpected running visit shape');
    fs.writeFileSync('/tmp/sci_result', okRow ? 'ok' : 'bad');
    await sleep(3000);
  } catch (e) {
    console.error('driver error:', e.message);
  } finally {
    // Cleanup — FK order
    for (const vid of mine.visits) {
      await pool.query('delete from nudges where exception_id in (select id from exceptions where visit_id=$1)', [vid]);
      await pool.query('delete from exceptions where visit_id=$1', [vid]);
      await pool.query('delete from visit_events where visit_id=$1', [vid]);
      await pool.query('delete from visits where id=$1', [vid]);
      await pool.query(`delete from audit_log where entity_type='visit' and $1 = any(string_to_array(entity_id, ','))`, [vid]);
    }
    // any visit the app created on our shifts that we did not see
    const { rows: stray } = await pool.query('select id from visits where shift_id = any($1::int[])', [mine.shifts]);
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
    // any lazily created demo shift provoked by the run
    const { rows: lazy } = await pool.query(`select id from shifts where staff_id=$1 and date=$2 and id <> all($3::int[]) and not exists (select 1 from visits where shift_id=shifts.id)`, [STAFF, today, before.length ? before : [0]]);
    for (const s of lazy) { await pool.query('delete from shift_staff where shift_id=$1', [s.id]); await pool.query('delete from shifts where id=$1', [s.id]); }
    // un-park the pre-existing S001 shifts
    if (before.length) await pool.query(`update shifts set status='scheduled' where id = any($1::int[]) and status='cancelled'`, [before]);
    await pool.query(`delete from audit_log where actor in ('mgonzalez@fbhi.net','demo@focus.com') and ts > now() - interval '30 minutes' and action in ('clock-in','clock-out','mobile-login')`);
    const after = await counts();
    console.log('cleanup done. baseline', base, 'after', after,
      (after.v === base.v && after.s === base.s && after.e === base.e && after.ev === base.ev) ? '✓ baseline restored' : '✗ BASELINE DIFFERS');
    await pool.end();
  }
})();
