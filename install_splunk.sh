#!/bin/bash

# 1. Anlegen des Download-Ordners im Home-Verzeichnis
DOWNLOAD_DIR="$HOME/Downloads"
mkdir -p "$DOWNLOAD_DIR"
echo "[INFO] Download-Ordner erstellt: $DOWNLOAD_DIR"

# 2. Abfrage des Splunk-Download-Links
read -p "Bitte den vollständigen wget-Link für Splunk eingeben: " SPLUNK_WGET

# 3. Download der Datei in den Download-Ordner
FILENAME=$(echo "$SPLUNK_WGET" | sed -n 's/.*-O\s\+\([^ ]\+\).*/\1/p')
if [ -z "$FILENAME" ]; then
  echo "[FEHLER] Konnte Dateinamen nicht aus wget-Link extrahieren."
  exit 1
fi
cd "$DOWNLOAD_DIR"
echo "[INFO] Lade Splunk herunter..."
eval "$SPLUNK_WGET"
if [ $? -ne 0 ]; then
  echo "[FEHLER] Fehler beim Herunterladen von Splunk."
  exit 1
fi

# 4. Entpacken nach /opt
echo "[INFO] Entpacke $FILENAME nach /opt ..."
sudo tar -xzvC /opt -f "$FILENAME"

# 5. Bestimmen ob Forwarder oder Indexer
if [[ "$FILENAME" == splunkforwarder-* ]]; then
  SPLUNK_DIR="/opt/splunkforwarder"
else
  SPLUNK_DIR="/opt/splunk"
fi

# 6. Aktuellen Benutzer ermitteln und Rechte setzen
CURRENT_USER=$(whoami)
echo "[INFO] Setze Besitzerrechte auf $CURRENT_USER"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$SPLUNK_DIR"

# 7. Starte Splunk (inkl. Lizenzannahme)
echo "[INFO] Starte Splunk mit Lizenzannahme..."
"$SPLUNK_DIR/bin/splunk" start --accept-license --answer-yes 
#--no-prompt

# 8. Servernamen abfragen
read -p "Bitte den gewünschten Servernamen eingeben: " SERVERNAME

# 9. Servernamen und Default-Hostname setzen
echo "[INFO] Setze Servernamen und Default-Hostname..."
"$SPLUNK_DIR/bin/splunk" set servername "$SERVERNAME"
"$SPLUNK_DIR/bin/splunk" set default-hostname "$SERVERNAME"

# 10. IP des Deploymentservers erfragen
read -p "Bitte die IP des Deploymentservers eingeben (nur IP, ohne Port): " DEPLOY_IP

# Port 8089 anhängen
DEPLOY_TARGET="${DEPLOY_IP}:8089"

# 11. Deployment-Server setzen
echo "[INFO] Setze Deployment-Server auf $DEPLOY_TARGET"
"$SPLUNK_DIR/bin/splunk" set deploy-poll "$DEPLOY_TARGET"

# 12. Splunk bei Systemstart aktivieren
echo "[INFO] Aktiviere Splunk beim Systemstart..."
sudo "$SPLUNK_DIR/bin/splunk" enable boot-start -user "$CURRENT_USER"

echo "[FERTIG] Splunk wurde erfolgreich installiert, gestartet und konfiguriert."
