// Local repro stub for the EVV mobile app — serves S013's REAL captured
// payloads (read-only capture from prod) so the simulator app can be driven
// through the open-shift pickup flow with ZERO prod writes.
const http = require('http');
const fs = require('fs');

const load = (f) => JSON.parse(fs.readFileSync('/tmp/' + f, 'utf8'));
const shifts = load('s013_shifts.json');
const visits = load('s013_visits.json');
const requests = load('s013_requests.json');
const individuals = load('s013_individuals.json');
const meds = load('s013_meds.json');
const missed = load('s013_missed.json');
const two = load('s013_221.json');
const docs = load('s013_docs.json');

let claimedIds = new Set();
let nextReq = 100;

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(body);
}

const server = http.createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', () => {
    const u = req.url;
    console.log(new Date().toISOString(), req.method, u, raw ? raw.slice(0, 200) : '');
    if (req.method === 'POST' && u === '/api/login') {
      return send(res, 200, {
        token: 'stub-token-1',
        staff: { id: 'S013', name: 'Nick Mudgett', email: 'nmudgett@fbhi.net', department: 'D001', departmentName: 'H/CBS' },
      });
    }
    if (u === '/api/token/refresh') return send(res, 200, { token: 'stub-token-2' });
    if (u === '/api/me/shifts') {
      // reflect claims: flip claimRequested on claimed open shifts
      const out = JSON.parse(JSON.stringify(shifts));
      for (const s of out.openShifts || []) if (claimedIds.has(s.id)) s.claimRequested = true;
      return send(res, 200, out);
    }
    const claimM = u.match(/^\/api\/shifts\/(\d+)\/claim$/);
    if (req.method === 'POST' && claimM) {
      const id = parseInt(claimM[1], 10);
      const open = (shifts.openShifts || []).find((s) => s.id === id);
      if (!open) return send(res, 404, { error: 'Shift not found' });
      if (claimedIds.has(id)) return send(res, 409, { error: 'You already requested this shift — a manager still has to approve it.', reason: 'already_requested', requestId: 2 });
      claimedIds.add(id);
      // exact prod shape: {...requestShiftClaim body, message, shift}
      return send(res, 200, {
        ok: true, pending: true, requestId: nextReq++, exceptionId: 'EX-900',
        message: 'Request sent — a manager must approve this pickup.',
        shift: open,
      });
    }
    if (u.startsWith('/api/me/visits')) return send(res, 200, visits);
    if (u === '/api/me/requests') return send(res, 200, requests);
    if (u === '/api/individuals') return send(res, 200, individuals);
    if (u === '/api/me/medications') return send(res, 200, meds);
    if (u === '/api/me/missed-shifts') return send(res, 200, missed);
    if (u === '/api/two-to-one/status') return send(res, 200, two);
    if (u === '/api/me/documents') return send(res, 200, docs);
    if (u === '/api/logs' && req.method === 'POST') return send(res, 200, { ok: true, received: 1 });
    if (u === '/api/me/todos') return send(res, 200, { todos: [] });
    if (u === '/api/me/nonbillable') return send(res, 200, { entries: [] });
    if (u === '/api/me/shift-requests') return send(res, 200, { requests: [] });
    console.log('  !! UNHANDLED', req.method, u);
    return send(res, 404, { error: 'not handled by stub: ' + u });
  });
});
server.listen(8099, '127.0.0.1', () => console.log('stub on http://127.0.0.1:8099'));
