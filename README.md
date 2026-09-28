# Docker

**Deutsch** · [English](README.en.md)

**Docker ersetzt das macOS-Dock durch ein eigenes, frei gestaltbares Dock.** Es zeigt Apps, Ordner, Widgets und minimierte Fenster, kann unten, links oder rechts am Bildschirmrand sitzen und passt sich per Profil an das an, woran du gerade arbeitest. Dazu kommen Fenstervorschauen beim Überfahren und ein schneller Fensterumschalter.

Docker ist eine private macOS-App (macOS 13 oder neuer) und läuft unauffällig über ein Symbol in der Menüleiste.

## Basis: DockDoor

Docker baut auf dem Open-Source-Projekt **[DockDoor](https://github.com/ejbills/DockDoor)** von Ethan Bills (ejbills) und den DockDoor-Mitwirkenden auf. Von DockDoor stammen unter anderem:

- **Fenstervorschauen** beim Überfahren eines App-Symbols, mit Aktionen wie Schließen, Minimieren oder Vollbild
- **Fensterumschalter** per Alt+Tab mit Vorschaubildern aller Fenster
- **Erweiterung für Cmd+Tab** mit Fensterauswahl
- Filter, Gesten, Tastenkürzel und viele Darstellungsoptionen

Wie DockDoor steht auch Docker unter der **GNU GPL v3** (siehe [LICENSE](LICENSE)). Docker ist kein offizielles DockDoor-Produkt und hat nichts mit „DockDoor Pro“ oder mit Docker, Inc. zu tun.

## Neu in Docker

### Eigenes Dock
- Ersetzt das macOS-Dock vollständig. Das Original-Dock wird ausgeblendet und beim Beenden mit deinen alten Einstellungen wiederhergestellt.
- Übernimmt beim ersten Start deine Apps und Ordner aus dem macOS-Dock.
- **Position unten, links oder rechts**, als schwebendes Dock oder als randlose Leiste über die ganze Breite.
- Vergrößerung beim Überfahren, frei wählbare Symbolgröße, automatisches Ausblenden.
- Materialien: Liquid Glass, Milchglas, einfarbig oder klar, mit Tönung, Rahmen und hellem oder dunklem Erscheinungsbild.
- Anzeige laufender Apps per Punkt oder Karte, Namen beim Überfahren, Startanimation.

### Inhalte
- Apps, Ordner und Dateien per Drag-and-drop anheften, verschieben und entfernen. Dateien lassen sich auf Apps oder in den Papierkorb ziehen.
- **Ordner als Stapel** in Fächer-, Gitter- oder Listenansicht, mit Sortierung nach Name, Datum oder Art.
- **App-Gruppen**: mehrere Apps in einem Symbol bündeln, gemeinsam öffnen oder starten.
- **Minimierte Fenster** erscheinen als eigene Symbole vor dem Papierkorb. Ein Klick holt sie zurück.
- **Zuletzt benutzte Apps**: Bis zu drei zuletzt beendete Apps stehen hinter den laufenden Apps.
- **Abstände und Trennstriche** zum Gliedern des Docks.
- Rechtsklick-Menüs für Apps, Ordner, Gruppen und den Papierkorb, zum Beispiel mit allen Fenstern einer App, Minimieren, Exposé und Beenden.

### Widgets
- **Uhr** (digital oder analog), **Wetter** (Ort suchen oder Standort), **Kalender**, **Batterie** und **Now Playing**.
- Now Playing mit Songtexten (über LRCLIB) und Lautstärke per Scrollen.
- **Widget-Stapel**, die sich automatisch durchblättern und bei Musik zu Now Playing wechseln können.
- Jedes Widget öffnet per Klick ein ausführliches Fenster.

### Profile und Bildschirme
- **Profile** mit eigenem Inhalt und eigenem Aussehen, umschaltbar über ein Kontrollzentrum im Dock.
- **AppSense**: wechselt das Profil automatisch passend zur aktiven App.
- **Mehrere Bildschirme**: Dock nur auf dem Hauptbildschirm, auf allen Bildschirmen oder dem Mauszeiger folgend.

### Komfort
- **Benachrichtigungs-Badges** (zum Beispiel ungelesene Nachrichten) an den App-Symbolen.
- **Buchstaben-Navigation**: Per Tastenkürzel (Standard ⌥⌘D) steuerst du Dock-Einträge mit dem Anfangsbuchstaben an.
- **Sichern und Wiederherstellen** aller Dock-Einstellungen und Profile, mit täglicher automatischer Sicherung.
- **Einstellungssuche**, die auch alle Dock-Optionen findet.
- Sparsam im Leerlauf, mit Protokoll und Hänger-Überwachung.

## Installation

1. Xcode installieren (für den Build).
2. Im Projektordner doppelt auf **„Docker installieren.command“** klicken.
   Das Skript baut die App, installiert sie nach „Programme“, startet sie und legt eine ZIP und eine DMG der Version im Ordner „Versionen“ ab.
3. Beim ersten Start die Freigaben **Bedienungshilfen** und **Bildschirmaufnahme** erteilen (Systemeinstellungen → Datenschutz & Sicherheit).

## Lizenz

GNU General Public License v3.0. Siehe [LICENSE](LICENSE).
Ursprünglicher Code © Ethan Bills und die DockDoor-Mitwirkenden. Erweiterungen © Leonard Jäger.
