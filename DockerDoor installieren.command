#!/bin/bash
# DockerDoor installieren / aktualisieren
# Baut die App (Release), signiert sie mit einem festen lokalen Zertifikat,
# legt sie in „Programme“ und startet sie.
# Start: Doppelklick im Finder. Das erste Mal dauert es einige Minuten (Pakete laden).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/build"
exec > >(tee "$HERE/build/install.log") 2>&1

APP_NAME="DockerDoor"
BUNDLE_ID="de.leonardjaeger.DockerDoor"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION" 2>/dev/null || true)"
[ -n "$VERSION" ] || VERSION="0.1"
IFS=. read -r MAJOR MINOR PATCH _ <<< "$VERSION"
BUILD_NUMBER=$(( 10#${MAJOR:-0} * 100 + 10#${MINOR:-0} ))
PROJECT="$HERE/DockDoor.xcodeproj"
WORK="$HOME/Library/Caches/DockerDoor-Installer"

echo ""
echo "=== $APP_NAME $VERSION installieren ==="
echo ""

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "→ Baue die App (Release) …"
set +e
xcodebuild -project "$PROJECT" -scheme DockDoor -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$WORK/DerivedData" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    build > "$HERE/build/xcodebuild.log" 2>&1
STATUS=$?
set -e
if [ $STATUS -ne 0 ]; then
    echo "✗ Bauen fehlgeschlagen. Fehler:"
    grep -E "error:|\*\* BUILD FAILED" "$HERE/build/xcodebuild.log" | sort -u | head -60
    echo ""
    echo "Vollständiges Protokoll: build/xcodebuild.log"
    exit 1
fi

APP="$WORK/DerivedData/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "Fehler: Die App wurde nicht gebaut."; exit 1; }

# Feste Signatur: macOS merkt sich Freigaben (Bedienungshilfen, Bildschirmaufnahme) je Signatur.
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SIGN_NAME=""
for CANDIDATE in "Dropper Signatur (lokal)" "DockerDoor Signatur (lokal)"; do
    if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CANDIDATE"; then
        SIGN_NAME="$CANDIDATE"; break
    fi
done
if [ -z "$SIGN_NAME" ]; then
    SIGN_NAME="DockerDoor Signatur (lokal)"
    echo "→ Lege einmalig ein eigenes Signatur-Zertifikat an („${SIGN_NAME}“) …"
    CERT_DIR="$(mktemp -d)"
    cat > "${CERT_DIR}/cert.conf" <<CONF
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = ${SIGN_NAME}
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF
    LEGACY=""
    if openssl version 2>/dev/null | grep -q "^OpenSSL 3"; then LEGACY="-legacy"; fi
    if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "${CERT_DIR}/cert.conf" -extensions ext \
           -keyout "${CERT_DIR}/key.pem" -out "${CERT_DIR}/cert.pem" >/dev/null 2>&1 \
       && openssl pkcs12 -export $LEGACY -inkey "${CERT_DIR}/key.pem" -in "${CERT_DIR}/cert.pem" \
           -name "${SIGN_NAME}" -out "${CERT_DIR}/cert.p12" -passout pass:dockerdoor >/dev/null 2>&1 \
       && security import "${CERT_DIR}/cert.p12" -k "${KEYCHAIN}" -P dockerdoor -T /usr/bin/codesign >/dev/null; then
        echo "  Zertifikat liegt im Schlüsselbund „Anmeldung“."
    else
        echo "  Hinweis: Zertifikat konnte nicht angelegt werden – die App bleibt ad hoc signiert."
        SIGN_NAME=""
    fi
    rm -rf "${CERT_DIR}"
fi
if [ -n "$SIGN_NAME" ]; then
    echo "→ Signiere mit „${SIGN_NAME}“ (falls macOS nach dem Schlüsselbund fragt: „Immer erlauben“) …"
    codesign --force --deep --sign "${SIGN_NAME}" --keychain "${KEYCHAIN}" --timestamp=none \
        --preserve-metadata=entitlements "$APP" \
        || echo "  Hinweis: Signieren fehlgeschlagen – Freigaben gelten dann nur bis zur nächsten Installation."
fi

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "→ Beende die laufende $APP_NAME-App …"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
    for _ in 1 2 3 4 5 6 7 8; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 1; done
fi

DEST="/Applications"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
echo "→ Installiere nach $DEST/$APP_NAME.app …"
rm -rf "$DEST/$APP_NAME.app"
ditto "$APP" "$DEST/$APP_NAME.app"
touch "$DEST/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -f "$DEST/$APP_NAME.app" || true

echo ""
echo "✓ Fertig! $APP_NAME $VERSION liegt in $DEST und startet jetzt (Symbol in der Menüleiste)."
open "$DEST/$APP_NAME.app"
