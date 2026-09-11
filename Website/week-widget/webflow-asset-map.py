#!/usr/bin/env python3
"""Map plate file names to the URLs Webflow gave them.

Webflow's asset manager keeps the original file name but serves every upload
from a hashed address, so the embed cannot derive a plate's URL from its name.
After uploading assets/*/gw-*.avif (and, if hosted there, Inter-Regular.woff2),
run this to write asset-map.json, then rebuild:

  python3 webflow-asset-map.py --site SITE_ID --token "$WEBFLOW_TOKEN" > asset-map.json
  python3 build-embed.py --asset-map asset-map.json --font-url <woff2 url or omit>

The token needs the assets:read scope and is never written anywhere. Only
files named gw-*.avif are listed, and every plate the manifests name must be
present — build-embed.py refuses a partial map, because a plate that is
missing from the map would be fetched from a path that does not exist and the
card would silently show its SDR twin there.

Standard library only; no third-party client.
"""

import argparse
import json
import sys
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--site", required=True, help="Webflow site id")
parser.add_argument("--token", required=True, help="Webflow API token (assets:read)")
args = parser.parse_args()

assets = {}
offset = 0
while True:
    url = f"https://api.webflow.com/v2/sites/{args.site}/assets?" + urllib.parse.urlencode(
        {"limit": 100, "offset": offset}
    )
    request = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {args.token}", "accept": "application/json"}
    )
    with urllib.request.urlopen(request) as response:
        page = json.load(response)
    for asset in page.get("assets", []):
        name = asset.get("originalFileName") or asset.get("displayName") or ""
        if name.startswith("gw-") and name.endswith(".avif") or name.endswith(".woff2"):
            assets[name] = asset["hostedUrl"]
    total = page.get("pagination", {}).get("total", 0)
    offset += 100
    if offset >= total:
        break

if not assets:
    print("no gw-*.avif assets found on that site", file=sys.stderr)
    sys.exit(1)
json.dump(assets, sys.stdout, indent=2, sort_keys=True)
print(file=sys.stdout)
print(f"{len(assets)} assets mapped", file=sys.stderr)
