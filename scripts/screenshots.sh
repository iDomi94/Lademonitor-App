#!/bin/zsh
# Erzeugt die App-Store-Screenshots automatisch (UI-Test ScreenshotTests) und
# legt sie als PNG ab:
#
#   screenshots/<quelle>/<hell|dunkel>/<sprache>/<geraet>/01-Dashboard.png ...
#
# Quellen:
#   local   - Local-Only-Modus mit den Beispieldaten aus ScreenshotDemoData
#   server  - Server-Modus mit einem Testkonto. Nur wenn die Zugangsdaten
#             gesetzt sind, entweder als Umgebungsvariablen oder in
#             scripts/screenshots.env (nicht im Git):
#               SCREENSHOT_SERVER_URL=https://lademonitor.cloud
#               SCREENSHOT_USER=testkonto
#               SCREENSHOT_PASSWORD=...
#             Optional ein eigenes Konto fuer die englischen Screenshots:
#               SCREENSHOT_USER_EN=..., SCREENSHOT_PASSWORD_EN=...
#
# Aufruf:  scripts/screenshots.sh
# Anpassen per Umgebungsvariable, z.B.:
#   SOURCES="server" APPEARANCES="dark" DEVICES="iPhone 17 Pro Max" LANGUAGES="de" scripts/screenshots.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f scripts/screenshots.env ]]; then
    set -a
    source scripts/screenshots.env
    set +a
fi

has_server_account() {
    [[ -n "${SCREENSHOT_SERVER_URL:-}" && -n "${SCREENSHOT_USER:-}" && -n "${SCREENSHOT_PASSWORD:-}" ]]
}

# Je eine Displaygroesse in App Store Connect: 6,9" (iPhone 17 Pro Max),
# 6,3" (iPhone 18 Pro) und 13" (iPad Pro).
DEVICES=(${(f)${DEVICES:-"iPhone 17 Pro Max
iPhone 18 Pro
iPad Pro 13-inch (M5)"}})
LANGUAGES=(${=${LANGUAGES:-"de en"}})
APPEARANCES=(${=${APPEARANCES:-"light dark"}})
if has_server_account; then
    SOURCES=(${=${SOURCES:-"local server"}})
else
    SOURCES=(${=${SOURCES:-"local"}})
fi
if (( ${SOURCES[(Ie)server]} )) && ! has_server_account; then
    echo "Fuer SOURCES=server fehlen SCREENSHOT_SERVER_URL/SCREENSHOT_USER/SCREENSHOT_PASSWORD." >&2
    exit 1
fi

OUTPUT_DIR="screenshots"
WORK_DIR="$(mktemp -d)"
# KEEP_WORK=1 behaelt Ergebnis-Bundles und Elementbaeume zur Fehlersuche.
trap '[[ -n "${KEEP_WORK:-}" ]] || rm -rf "$WORK_DIR"' EXIT

# Einmal bauen, danach nur noch testen.
echo "==> Build"
xcodebuild build-for-testing \
    -project Lademonitor-App.xcodeproj \
    -scheme Lademonitor \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    -quiet

for device in "${DEVICES[@]}"; do
    udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == name:
            print(d['udid']); sys.exit()
" "$device")
    if [[ -z "$udid" ]]; then
        echo "Simulator '$device' nicht gefunden - uebersprungen." >&2
        continue
    fi

    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    # Aufgeraeumte Statusleiste wie in Apples Marketingbildern.
    xcrun simctl status_bar "$udid" override \
        --time "9:41" --dataNetwork wifi --wifiBars 3 --cellularBars 4 \
        --batteryState charged --batteryLevel 100

    for appearance in "${APPEARANCES[@]}"; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for source in "${SOURCES[@]}"; do
        for language in "${LANGUAGES[@]}"; do
            echo "==> $device / $source / $appearance / $language"
            run="${udid}-${source}-${appearance}-${language}"
            result="$WORK_DIR/${run}.xcresult"

            # Variablen mit TEST_RUNNER_-Praefix reicht xcodebuild an den
            # Test-Runner weiter, der sie der App mitgibt.
            test_env=(TEST_RUNNER_SCREENSHOT_LANG="$language")
            if [[ "$source" == "server" ]]; then
                # Englische Screenshots mit dem englischen Testkonto, falls gesetzt.
                user="$SCREENSHOT_USER"
                password="$SCREENSHOT_PASSWORD"
                if [[ "$language" == "en" && -n "${SCREENSHOT_USER_EN:-}" && -n "${SCREENSHOT_PASSWORD_EN:-}" ]]; then
                    user="$SCREENSHOT_USER_EN"
                    password="$SCREENSHOT_PASSWORD_EN"
                fi
                test_env+=(
                    TEST_RUNNER_SCREENSHOT_SERVER_URL="$SCREENSHOT_SERVER_URL"
                    TEST_RUNNER_SCREENSHOT_USER="$user"
                    TEST_RUNNER_SCREENSHOT_PASSWORD="$password"
                )
            fi

            env "${test_env[@]}" xcodebuild test-without-building \
                -project Lademonitor-App.xcodeproj \
                -scheme Lademonitor \
                -destination "id=$udid" \
                -derivedDataPath "$WORK_DIR/DerivedData" \
                -only-testing:LademonitorUITests/ScreenshotTests \
                -resultBundlePath "$result" \
                -quiet

            # Nur den Ordner dieses Durchgangs leeren - Bilder anderer
            # Geraete/Sprachen aus frueheren Laeufen bleiben liegen.
            target="$OUTPUT_DIR/$source/$appearance/$language/$device"
            rm -rf "$target"
            mkdir -p "$target"
            export_dir="$WORK_DIR/export-${run}"
            xcrun xcresulttool export attachments --path "$result" --output-path "$export_dir"
            # manifest.json ordnet die exportierten Dateien den Attachment-Namen zu.
            python3 - "$export_dir" "$target" <<'EOF'
import json, os, shutil, sys
source, target = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", attachment["exportedFileName"])
        # Xcode haengt "_0_<UUID>" an - fuer die Ablage nur den vergebenen Namen.
        name = name.split("_0_")[0]
        exported = attachment["exportedFileName"]
        if not exported.endswith(".png"):
            # Elementbaum aus dumpHierarchy: nur melden, nicht ablegen.
            print(f"Hinweis: {name} - Element nicht gefunden, siehe {os.path.join(source, exported)}")
            continue
        if not name.endswith(".png"):
            name += ".png"
        shutil.copy(os.path.join(source, exported), os.path.join(target, name))
EOF
        done
    done
    done

    xcrun simctl ui "$udid" appearance light
    xcrun simctl status_bar "$udid" clear
done

echo "Fertig: $OUTPUT_DIR/"
