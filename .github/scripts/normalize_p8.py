"""Gibt den App-Store-Connect-Key aus ASC_KEY_P8 als sauberes PEM aus.

Akzeptiert die komplette .p8, nur den Base64-Block dazwischen, Base64 der
ganzen Datei, Windows-Zeilenenden und woertliche "\\n". Bricht mit einer
lesbaren Meldung ab, statt xcodebuild einen kaputten Key zu geben.
"""

import base64
import os
import re
import sys

raw = os.environ.get("ASC_KEY_P8", "").replace("\\n", "\n").replace("\r", "").strip()
if not raw:
    sys.exit("Secret ASC_KEY_P8 ist leer oder nicht gesetzt.")

if "-----BEGIN" not in raw:
    # Vielleicht die ganze Datei Base64-kodiert?
    try:
        decoded = base64.b64decode(raw, validate=False).decode("utf-8")
        if "-----BEGIN" in decoded:
            raw = decoded
    except Exception:
        pass

body = re.sub(r"-----(BEGIN|END)[^-]*-----", "", raw)
body = re.sub(r"\s+", "", body)
if not body:
    sys.exit("ASC_KEY_P8 enthaelt keinen Schluessel.")
try:
    der = base64.b64decode(body, validate=True)
except Exception:
    sys.exit("ASC_KEY_P8 ist kein gueltiges Base64 - bitte den Inhalt der .p8 unveraendert einfuegen.")
if len(der) < 100:
    sys.exit(f"ASC_KEY_P8 ist zu kurz ({len(der)} Byte) - vermutlich unvollstaendig kopiert.")

lines = [body[i:i + 64] for i in range(0, len(body), 64)]
print("-----BEGIN PRIVATE KEY-----")
print("\n".join(lines))
print("-----END PRIVATE KEY-----")
