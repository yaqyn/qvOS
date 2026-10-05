#!/usr/bin/python3
"""Check the deployed Worker or a running cf dev instance without mutations."""
import hashlib
import json
import sys
import urllib.error
import urllib.request

base = sys.argv[1].rstrip("/")
release = json.load(urllib.request.urlopen(base + "/health", timeout=30))
response = urllib.request.urlopen(base + "/", timeout=30)
script = response.read().decode()
assert response.headers["Content-Type"].startswith("text/plain")
assert response.headers["Cache-Control"] == "no-store"
assert "@SOURCE_HASH@" not in script and release["sourceHash"] in script
assert release["sha256"] in script
payload = urllib.request.urlopen(base + "/downloads/" + release["archive"], timeout=120)
assert hashlib.sha256(payload.read()).hexdigest() == release["sha256"]
assert "immutable" in payload.headers["Cache-Control"]
for path, method, status in [("/not-found", "GET", 404), ("/", "POST", 405)]:
  try:
    urllib.request.urlopen(urllib.request.Request(base + path, method=method), timeout=30)
    raise AssertionError("unexpected success")
  except urllib.error.HTTPError as error:
    assert error.code == status
print("Worker routes, payload integrity, cache policy, and method guards passed.")
