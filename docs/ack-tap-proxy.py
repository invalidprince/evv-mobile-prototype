#!/usr/bin/env python3
"""Build 95 reproduction proxy for the sign-off card tap (Todoist 6hXqxmCPjjhjCGHH).

Forwards every request to CloudFront unchanged, EXCEPT:
  * GET /api/me/visits*                → one fabricated INCOMPLETE past visit
                                          (V-ACKTEST) for the demo account
  * GET /api/visits/V-ACKTEST/documentation → a template whose
                                          pendingAcknowledgements carries the
                                          demo account's real pending doc

Nothing is ever written to production: POSTs are forwarded as-is and the
harness only ever taps the card row, never Submit. Run:
    python3 docs/ack-tap-proxy.py 8765
and launch the app with EVV_BASE_URL=http://127.0.0.1:8765/api.
"""
import http.server, json, sys, urllib.request, urllib.error, datetime

UPSTREAM = "https://d2hmfpgqkgeyu.cloudfront.net"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

yesterday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
FAKE_VISIT = {
    "id": "V-ACKTEST", "shiftId": None,
    "individual": {"id": "C140925", "name": "Ray E. Varner"},
    "service": "W7061", "serviceName": "In-Home & Community Support",
    "clockIn": "10:00 AM", "clockOut": "11:00 AM", "status": "completed",
    "date": yesterday, "duration": 60, "docStatus": "incomplete", "hasNote": False,
}
FAKE_DOC = {
    "visitId": "V-ACKTEST", "outcomes": [], "questions": [],
    "aiAssistEnabled": False, "noteRewriteEnabled": False,
    "pendingAcknowledgements": [{
        "docId": 18, "docName": "RV ISP 26-27", "docType": "ISP",
        "individualId": "C140925", "individualName": "Ray E. Varner",
        "signPath": "/my-day/acknowledgements",
    }],
}


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body, ctype="application/json"):
        data = json.dumps(body).encode() if not isinstance(body, bytes) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        payload = self.rfile.read(length) if length else None
        req = urllib.request.Request(UPSTREAM + self.path, data=payload, method=self.command)
        for k, v in self.headers.items():
            if k.lower() in ("host", "content-length", "accept-encoding"):
                continue
            req.add_header(k, v)
        req.add_header("Accept-Encoding", "identity")
        try:
            resp = urllib.request.urlopen(req, timeout=60)
            code, hdrs, data = resp.status, resp.headers, resp.read()
        except urllib.error.HTTPError as e:
            code, hdrs, data = e.code, e.headers, e.read()
        self.send_response(code)
        for k, v in hdrs.items():
            if k.lower() in ("transfer-encoding", "content-length", "connection", "content-encoding"):
                continue
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/api/me/visits":
            sys.stderr.write("[inject] /api/me/visits\n")
            return self._send(200, {"visits": [FAKE_VISIT]})
        if p == "/api/visits/V-ACKTEST/documentation":
            sys.stderr.write("[inject] documentation V-ACKTEST\n")
            return self._send(200, FAKE_DOC)
        if p.startswith("/api/visits/V-ACKTEST/"):
            return self._send(200, {})
        return self._proxy()

    def do_POST(self):
        if self.path.startswith("/api/visits/V-ACKTEST/"):
            sys.stderr.write("[refuse] POST to fake visit %s\n" % self.path)
            return self._send(400, {"error": "harness visit"})
        return self._proxy()

    do_PUT = do_PATCH = do_DELETE = do_POST

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))


if __name__ == "__main__":
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
