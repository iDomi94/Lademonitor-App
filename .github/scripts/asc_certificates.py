"""Merkt sich die Zertifikate des Teams vor dem Build und widerruft danach
genau die, die dieser Lauf angelegt hat.

Aufruf:
  asc_certificates.py snapshot <datei>   IDs sichern, Anzahl je Typ ausgeben
  asc_certificates.py revoke-new <datei> alles widerrufen, was nicht in <datei> steht

Umgebung: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (sauberes PEM, siehe
normalize_p8.py).

Warum: der Runner ist bei jedem Lauf frisch, die automatische Signierung legt
deshalb jedes Mal ein neues Zertifikat an. Apple begrenzt die Anzahl je Team -
nach ein paar Laeufen bricht das Archivieren mit "maximum number of
certificates" ab (so geschehen bei v1.3.0). Ein widerrufenes Zertifikat macht
den bereits hochgeladenen Build nicht ungueltig: Apple signiert ihn fuer
TestFlight/App Store selbst neu.
"""

import collections
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def request(method: str, url: str, **kwargs) -> requests.Response:
    resp = requests.request(method, url, timeout=60,
                            headers={"Authorization": f"Bearer {token()}"}, **kwargs)
    if resp.status_code >= 400:
        sys.exit(f"{method} {url} -> {resp.status_code}: {resp.text}")
    return resp


def certificates() -> list[dict]:
    result, url, params = [], API + "/certificates", {"limit": 200}
    while url:
        body = request("GET", url, params=params).json()
        result.extend(body["data"])
        url, params = body.get("links", {}).get("next"), None
    return result


def describe(cert: dict) -> str:
    attrs = cert["attributes"]
    return (f"{cert['id']} {attrs.get('certificateType')} "
            f"\"{attrs.get('displayName') or attrs.get('name')}\" "
            f"bis {attrs.get('expirationDate', '?')[:10]}")


def snapshot(path: str) -> None:
    certs = certificates()
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(c["id"] for c in certs))
    counts = collections.Counter(c["attributes"].get("certificateType") for c in certs)
    print(f"API-Key funktioniert. Zertifikate im Team: {len(certs)}")
    for kind, n in sorted(counts.items()):
        print(f"  {kind}: {n}")
    dev = sum(n for kind, n in counts.items() if kind in DEVELOPMENT_TYPES)
    print(f"Entwicklerzertifikate: {dev}")
    for cert in certs:
        print(f"  {describe(cert)}")


def revoke_new(path: str) -> None:
    try:
        with open(path, encoding="utf-8") as f:
            known = set(f.read().split())
    except FileNotFoundError:
        # Ohne Stand von vorher ist nicht zu unterscheiden, was dieser Lauf
        # angelegt hat - dann lieber nichts widerrufen.
        print("Kein Stand von vorher, es wird nichts widerrufen.")
        return
    new = [c for c in certificates() if c["id"] not in known]
    if not new:
        print("Dieser Lauf hat kein Zertifikat angelegt.")
        return
    for cert in new:
        request("DELETE", f"{API}/certificates/{cert['id']}")
        print(f"Widerrufen: {describe(cert)}")


def main() -> None:
    command, path = sys.argv[1:3]
    if command == "snapshot":
        snapshot(path)
    elif command == "revoke-new":
        revoke_new(path)
    else:
        sys.exit(f"Unbekannter Befehl: {command}")


if __name__ == "__main__":
    main()
