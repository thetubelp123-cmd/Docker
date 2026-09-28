#!/bin/bash
# Docker installieren / aktualisieren
# Baut die App (Release), signiert sie mit einem festen lokalen Zertifikat,
# legt sie in „Programme“, speichert ZIP und DMG im Ordner „Versionen“ und startet sie.
# Start: Doppelklick im Finder. Das erste Mal dauert es einige Minuten (Pakete laden).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/build"
exec > >(tee "$HERE/build/install.log") 2>&1

APP_NAME="Docker"
OLD_APP_NAME="DockerDoor"
BUNDLE_ID="de.leonardjaeger.DockerDoor"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION" 2>/dev/null || true)"
[ -n "$VERSION" ] || VERSION="0.1"
IFS=. read -r MAJOR MINOR PATCH _ <<< "$VERSION"
BUILD_NUMBER=$(( 10#${MAJOR:-0} * 100 + 10#${MINOR:-0} ))
PROJECT="$HERE/Docker.xcodeproj"
WORK="$HOME/Library/Caches/DockerDoor-Installer"

echo ""
echo "=== $APP_NAME $VERSION installieren ==="
echo ""

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "→ Baue die App (Release) …"
set +e
xcodebuild -project "$PROJECT" -scheme Docker -configuration Release \
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

DEST="/Applications"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi

# Nie eine fremde App gleichen Namens (z. B. Docker Desktop) überschreiben.
if [ -d "$DEST/$APP_NAME.app" ]; then
    EXISTING_ID="$(defaults read "$DEST/$APP_NAME.app/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "$BUNDLE_ID" ]; then
        echo "✗ In $DEST liegt bereits eine andere „$APP_NAME.app“ ($EXISTING_ID). Abbruch, damit sie nicht überschrieben wird."
        exit 1
    fi
fi

# Laufende Instanz finden – egal ob sie noch „DockerDoor“ oder schon „Docker“ heißt.
own_pids() {
    pgrep -f "/($APP_NAME|$OLD_APP_NAME)\.app/Contents/MacOS/($APP_NAME|$OLD_APP_NAME)\$" || true
}
if [ -n "$(own_pids)" ]; then
    echo "→ Beende die laufende App …"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
    for _ in 1 2 3 4 5 6 7 8; do [ -n "$(own_pids)" ] || break; sleep 1; done
    if [ -n "$(own_pids)" ]; then
        echo "  Die App hat nicht reagiert – wird per Signal beendet."
        kill -TERM $(own_pids) 2>/dev/null || true
        for _ in 1 2 3 4 5; do [ -n "$(own_pids)" ] || break; sleep 1; done
        [ -z "$(own_pids)" ] || kill -9 $(own_pids) 2>/dev/null || true
        sleep 1
    fi
fi
echo "→ Installiere nach $DEST/$APP_NAME.app …"
rm -rf "$DEST/$APP_NAME.app"
ditto "$APP" "$DEST/$APP_NAME.app"
touch "$DEST/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -f "$DEST/$APP_NAME.app" || true

# Alte Version unter dem früheren Namen entfernen.
if [ -d "$DEST/$OLD_APP_NAME.app" ]; then
    echo "→ Entferne die alte „$OLD_APP_NAME.app“ …"
    "$LSREGISTER" -u "$DEST/$OLD_APP_NAME.app" 2>/dev/null || true
    rm -rf "$DEST/$OLD_APP_NAME.app"
fi

# Kopien dieser Version für das Archiv: ZIP und DMG (mit Verknüpfung zu „Programme“)
VERSIONS="$HERE/Versionen"
mkdir -p "$VERSIONS"
ZIP="$VERSIONS/$APP_NAME-$VERSION.zip"
DMG="$VERSIONS/$APP_NAME-$VERSION.dmg"
echo "→ Lege ZIP und DMG in „Versionen“ ab …"
rm -f "$ZIP"
if ditto -c -k --sequesterRsrc --keepParent "$DEST/$APP_NAME.app" "$ZIP"; then
    echo "  ZIP: Versionen/$(basename "$ZIP")"
else
    echo "  Hinweis: ZIP konnte nicht erstellt werden."
fi
STAGE="$WORK/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$DEST/$APP_NAME.app" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Programme"
rm -f "$DMG"
if hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
    echo "  DMG: Versionen/$(basename "$DMG")"
else
    echo "  Hinweis: DMG konnte nicht erstellt werden."
fi
rm -rf "$STAGE"

echo ""
echo "✓ Fertig! $APP_NAME $VERSION liegt in $DEST und startet jetzt (Symbol in der Menüleiste)."
open "$DEST/$APP_NAME.app"
