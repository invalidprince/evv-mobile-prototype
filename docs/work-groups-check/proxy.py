#!/usr/bin/env python3
"""Build 126 — READ-ONLY staging proxy for the Work-tab group screenshots.

    EVV_MOBILE_TOKEN=<mv1 token for a staging manager> python3 docs/work-groups-check/proxy.py 8766

* POST /api/login        → answered locally with EVV_MOBILE_TOKEN (minted from the
                            STAGING SESSION_SECRET for a manager, e.g. S013) — the
                            password never matters, nothing is sent upstream.
* every GET              → forwarded to STAGING (d2vx4uq6k3g4bo) unchanged, so the
                            Work tab renders the REAL grouped /api/me/todos.
* every other method     → 403 locally. Nothing is ever written, not even to staging.
"""
import http.server, json, os, sys, time, urllib.request, urllib.error

UPSTREAM = "https://d2vx4uq6k3g4bo.cloudfront.net"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
TOKEN = os.environ["EVV_MOBILE_TOKEN"]
STAFF = {"id": os.environ.get("EVV_STAFF_ID", "S013"), "name": os.environ.get("EVV_STAFF_NAME", "Staging Manager"),
         "email": "staging-manager@example.invalid", "department": os.environ.get("EVV_STAFF_DEPT", ""), "departmentName": ""}


class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        req = urllib.request.Request(UPSTREAM + self.path, headers={
            k: v for k, v in self.headers.items() if k.lower() in ("authorization", "accept", "user-agent")})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                self._send(r.status, r.read(), r.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as e:
            self._send(e.code, e.read(), e.headers.get("Content-Type", "application/json"))
        sys.stderr.write(f"GET {self.path}\n")

    def _refuse(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n: self.rfile.read(n)
        if self.path.rstrip("/") == "/api/login":
            body = {"token": TOKEN, "tokenExpiresAt": int(time.time() * 1000) + 3600_000, "staff": STAFF}
            return self._send(200, json.dumps(body).encode())
        sys.stderr.write(f"REFUSED {self.command} {self.path}\n")
        self._send(403, json.dumps({"error": "read-only proxy"}).encode())

    do_POST = do_PUT = do_PATCH = do_DELETE = _refuse

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
