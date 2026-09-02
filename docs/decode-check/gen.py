#!/usr/bin/env python3
"""Generate /tmp/decode-check/main.swift from the REAL APIClient.swift decoders. See README.md."""
import os, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
src = (root / 'EVVMobile/Services/APIClient.swift').read_text()
def grab(name):
    i = src.index(name); depth = 0; j = i
    while True:
        if src[j] == '{': depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0: return src[i:j+1]
        j += 1
parts = [grab('struct ServerIndividual: Decodable'), grab('struct ServerHistoryVisit: Decodable'),
         grab('struct HistoryVisitsResponse: Decodable'), grab('struct ServerException: Decodable'),
         grab('struct RequestsResponse: Decodable'), grab('struct FailableDecodable<T: Decodable>: Decodable')]
stub = 'import Foundation\nfinal class DiagnosticLogger { static let shared = DiagnosticLogger(); func logAPI(_ m: String){ print("LOG:", m) } }\n'
test = (root / 'docs/decode-check/test.swift.txt').read_text()
os.makedirs('/tmp/decode-check', exist_ok=True)
pathlib.Path('/tmp/decode-check/main.swift').write_text(stub + "\n".join(parts) + test)
print('wrote /tmp/decode-check/main.swift')
