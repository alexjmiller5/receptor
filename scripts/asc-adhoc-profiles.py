#!/usr/bin/env python3
# /// script
# dependencies = ["httpx", "pyjwt[crypto]"]
# ///
"""Create (or refresh) the three iOS Ad Hoc provisioning profiles through the
App Store Connect API and print them base64-encoded, one JSON object.

The bundle IDs and the App Group must already exist (Xcode's automatic signing
registers them on the first `-allowProvisioningUpdates` device build). This
script only mints distribution profiles, which Xcode never does for Ad Hoc.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (PEM), ASC_TEAM_DEVICE_UDIDS (comma
separated; defaults to every enabled iPhone/iPad on the team).
"""

import base64
import json
import os
import sys
import time

import httpx
import jwt

API = "https://api.appstoreconnect.apple.com/v1"
PROFILES = {
    "app": ("com.alexmiller.receptor", "Receptor Ad Hoc"),
    "share": ("com.alexmiller.receptor.share", "Receptor Share Ad Hoc"),
    "widgets": ("com.alexmiller.receptor.widgets", "Receptor Widgets Ad Hoc"),
}


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def main() -> int:
    client = httpx.Client(base_url=API, headers={"Authorization": f"Bearer {token()}"}, timeout=60)

    def get(path, **params):
        r = client.get(path, params=params)
        r.raise_for_status()
        return r.json()["data"]

    certs = [c for c in get("/certificates", **{"filter[certificateType]": "DISTRIBUTION"})]
    if not certs:
        print("no Apple Distribution certificate on the team", file=sys.stderr)
        return 1
    devices = get("/devices", **{"filter[platform]": "IOS", "filter[status]": "ENABLED"})
    wanted = {u.strip() for u in os.environ.get("ASC_TEAM_DEVICE_UDIDS", "").split(",") if u.strip()}
    if wanted:
        devices = [d for d in devices if d["attributes"]["udid"] in wanted]
    if not devices:
        print("no enabled iOS devices matched", file=sys.stderr)
        return 1

    out = {}
    for key, (bundle_id, name) in PROFILES.items():
        bids = get("/bundleIds", **{"filter[identifier]": bundle_id, "filter[platform]": "IOS"})
        bids = [b for b in bids if b["attributes"]["identifier"] == bundle_id]
        if not bids:
            print(f"bundle id {bundle_id} not registered - run `just build` once first", file=sys.stderr)
            return 1
        # Profiles are immutable: delete the old one of this name, mint a new one.
        for old in get("/profiles", **{"filter[name]": name}):
            client.delete(f"/profiles/{old['id']}").raise_for_status()
        body = {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_ADHOC"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bids[0]["id"]}},
                    "certificates": {"data": [{"type": "certificates", "id": c["id"]} for c in certs]},
                    "devices": {"data": [{"type": "devices", "id": d["id"]} for d in devices]},
                },
            }
        }
        r = client.post("/profiles", json=body)
        if r.status_code >= 400:
            print(r.text, file=sys.stderr)
            return 1
        attrs = r.json()["data"]["attributes"]
        out[f"{key}_mobileprovision_base64"] = attrs["profileContent"]
        out[f"{key}_expires"] = attrs["expirationDate"]
        print(f"minted {name} (uuid {attrs['uuid']}, expires {attrs['expirationDate']})", file=sys.stderr)
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
