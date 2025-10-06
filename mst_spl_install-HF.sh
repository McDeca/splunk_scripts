### M.Steinmetz @ 07/2025 ###

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

# 5. Bestimmen ob Forwarder oder Indexer
if [[ "$FILENAME" == splunkforwarder-* ]]; then
  SPLUNK_DIR="/opt/splunkforwarder"
else
  SPLUNK_DIR="/opt/splunk"
fi

# 4. Entpacken nach /opt
echo "[INFO] Entpacke $FILENAME nach /opt ..."
sudo tar -xzvC /opt -f "$FILENAME"

# 6. Benutzer für Berechtigung abfragen
read -p "Welchen Service-User sollen auf $SPLUNK_DIR berechtigt werden? " SPLUNK_USER

# 7. Berechtigungen setzen
echo "[INFO] Setze Besitzerrechte auf $SPLUNK_USER"
sudo chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_DIR"

# 8. Splunk starten (inkl. Lizenzannahme)
echo "[INFO] Starte Splunk (interaktive Lizenzannahme)..."
sudo -u "$SPLUNK_USER" "$SPLUNK_DIR/bin/splunk" start --accept-license

# Prüfen ob Start erfolgreich war
if [ $? -ne 0 ]; then
  echo "[FEHLER] Splunk konnte nicht erfolgreich gestartet werden. Vorgang abgebrochen."
  exit 1
fi

#  Berechtigungen erneut setzen
echo "[INFO] Setze Besitzerrechte auf $SPLUNK_USER"
sudo chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_DIR"

# 9. Servernamen abfragen
read -p "Bitte den gewünschten Servernamen eingeben: " SERVERNAME

# 10. Servernamen und Default-Hostname setzen
echo "[INFO] Setze Servernamen und Default-Hostname..."
"$SPLUNK_DIR/bin/splunk" set servername "$SERVERNAME"
"$SPLUNK_DIR/bin/splunk" set default-hostname "$SERVERNAME"

# 13. Splunk für Autostart konfigurieren
echo "[INFO] Aktiviere Splunk beim Systemstart für Benutzer '$SPLUNK_USER' ..."
sudo "$SPLUNK_DIR/bin/splunk" enable boot-start -user "$SPLUNK_USER"

# 11. IP des Deploymentservers abfragen
read -p "Bitte die IP des Deploymentservers eingeben (nur IP, ohne Port): " DEPLOY_IP
DEPLOY_TARGET="${DEPLOY_IP}:8089"

# 12. Deployment-Server konfigurieren
echo "[INFO] Setze Deployment-Server auf $DEPLOY_TARGET"
"$SPLUNK_DIR/bin/splunk" set deploy-poll "$DEPLOY_TARGET"

echo "[FERTIG] Splunk wurde erfolgreich installiert & gestartet."

echo "[RESTART] Splunk wird neugestartet."
# Restart Splunkd
"$SPLUNK_DIR/bin/splunk" restart

# 6. splunkforwarder aktivieren
echo "[INFO] SplunkForwarder wird aktiviert!"
read -p "Splunk Admin User: " SPLUNK_ADMIN
read -p "Splunk Admin User Password: " SPLUNK_ADMIN_PW
"$SPLUNK_DIR/bin/splunk" enable app SplunkForwarder -auth $SPLUNK_ADMIN:$SPLUNK_ADMIN_PW
echo "[FERTIG] SplunkForwarder ist aktiviert!"

#
echo "[INFO] Zu welchem Server soll weitergeleitet werden?"
read -p "Add forward-server to indexers ip? IP: " INDEXER_IP
"$SPLUNK_DIR/bin/splunk" add forward-server INDEXER_IP:8089 -auth $SPLUNK_ADMIN:$SPLUNK_ADMIN_PW

echo "[INFO] SplunkForwarder sendet von Daten an INDEXER_IP:8089 ist aktiviert!"
