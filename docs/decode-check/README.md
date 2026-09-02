# decode-check — offline proof that one bad row can't blank History (build 55)

Extracts the REAL `ServerIndividual` / `ServerHistoryVisit` / `HistoryVisitsResponse` /
`ServerException` / `RequestsResponse` / `FailableDecodable` declarations from
`EVVMobile/Services/APIClient.swift` (brace-matched, verbatim), compiles them with
`swiftc` against a stub `DiagnosticLogger`, and decodes:

1. the OLD `/api/me/requests` contract (`resolution` = JSONB object) — Nick's actual
   2026-09-02 payload shape → must decode, outcome `approved`;
2. the NEW contract (`resolution` = string, `resolutionDetail` object);
3. a mixed list with one garbage row → the good row survives;
4. the real `/api/me/visits` payload + one poisoned row → 11 of 12 kept.

Run (needs `/tmp/s013_requests.json` + `/tmp/s013_visits.json` captured with a token,
or edit the paths):

    python3 docs/decode-check/gen.py && swiftc -O /tmp/decode-check/main.swift -o /tmp/decode-check/dec && /tmp/decode-check/dec
