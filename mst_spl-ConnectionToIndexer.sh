#!/usr/bin/env bash
set -u

# --------- Konfiguration ----------
PORTS=(9997 8089 8000)
CONNECT_TIMEOUT=3
# ----------------------------------

color() { # $1=color $2=text
  local c="$1"; shift
  case "$c" in
    green)  printf "\033[32m%s\033[0m" "$*";;
    red)    printf "\033[31m%s\033[0m" "$*";;
    yellow) printf "\033[33m%s\033[0m" "$*";;
    blue)   printf "\033[34m%s\033[0m" "$*";;
    *)      printf "%s" "$*";;
  esac
}

banner() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

# --- Distro-Erkennung ---
DISTRO="unknown"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*) DISTRO="debian/ubuntu" ;;
    *rhel*|*fedora*|*centos*) DISTRO="rhel/redhat" ;;
    *) DISTRO="${ID:-unknown}" ;;
  esac
fi

banner "Splunk Port-Connectivity Check"
echo "Erkannte Distribution: $(color blue "$DISTRO")"
echo "Zu prüfende Ports: ${PORTS[*]}"
echo

# --- Ziel-IP einlesen ---
read -rp "Bitte Ziel-IP oder Hostname eingeben: " TARGET
if [ -z "${TARGET// }" ]; then
  echo "$(color red "Fehler:") Keine Zieladresse angegeben."
  exit 1
fi

# --- Tool-Auswahl abhängig von Distro / Verfügbarkeit ---
# Priorität: nc (netcat) -> curl -> bash /dev/tcp
TOOL=""
if command -v nc >/dev/null 2>&1; then
  TOOL="nc"
elif command -v curl >/dev/null 2>&1; then
  TOOL="curl"
elif command -v timeout >/dev/null 2>&1 && [ -e /proc/sys/net/ipv4 ]; then
  TOOL="bash-tcp"
else
  echo "$(color red "Fehler:") Weder 'nc' noch 'curl' vorhanden, und 'timeout' oder Bash-/dev/tcp' nicht nutzbar."
  exit 2
fi

echo -n "Verwendetes Prüf-Tool: "
case "$TOOL" in
  nc)       echo "$(color blue "nc (netcat)")" ;;
  curl)     echo "$(color blue "curl")" ;;
  bash-tcp) echo "$(color blue "Bash /dev/tcp + timeout")" ;;
esac
echo

# --- Hilfsfunktionen für die Prüfungen ---
declare -A RESULTS
declare -A DETAILS

guess_scheme_for_curl() { # $1=port -> echo url
  local p="$1"
  case "$p" in
    8089) echo "https://$TARGET:$p" ;; # Splunk Mgmt (TLS)
    8000) echo "http://$TARGET:$p"  ;; # Splunk Web
    *)    echo "telnet://$TARGET:$p" ;; # generisch
  esac
}

check_with_nc() { # $1=port
  local p="$1"
  local cmd="nc -vz -w ${CONNECT_TIMEOUT} ${TARGET} ${p}"
  echo "⏳ Starte: $cmd"
  local out err rc
  out="$($cmd 2>&1)"; rc=$?
  echo "$out"
  if [ $rc -eq 0 ]; then
    RESULTS[$p]="OPEN"
    DETAILS[$p]="$out"
  else
    RESULTS[$p]="CLOSED"
    DETAILS[$p]="$out"
  fi
}

check_with_curl() { # $1=port
  local p="$1"
  local url; url="$(guess_scheme_for_curl "$p")"
  local cmd
  if [[ "$url" == https://* ]]; then
    cmd="curl -sk --connect-timeout ${CONNECT_TIMEOUT} -o /dev/null -w '%{http_code}' '$url'"
  elif [[ "$url" == http://* ]]; then
    cmd="curl -s  --connect-timeout ${CONNECT_TIMEOUT} -o /dev/null -w '%{http_code}' '$url'"
  else
    cmd="curl -s --connect-timeout ${CONNECT_TIMEOUT} -o /dev/null -w '%{http_code}' '$url'"
  fi
  echo "⏳ Starte: $cmd"
  # Ausführen
  local code rc
  # shellcheck disable=SC2086
  code=$(eval $cmd); rc=$?
  echo "Antwort-/Exitcode: ${code} (rc=${rc})"
  if [ $rc -eq 0 ]; then
    # Für telnet:// gibt curl idR '000' zurück wenn Port offen aber kein Protokoll
    if [ "$code" = "000" ] || [[ "$code" =~ ^[0-9]{3}$ ]]; then
      RESULTS[$p]="OPEN"
      DETAILS[$p]="curl ok, code=$code"
    else
      RESULTS[$p]="CLOSED"
      DETAILS[$p]="curl unerwarteter Code=$code"
    fi
  else
    RESULTS[$p]="CLOSED"
    DETAILS[$p]="curl rc=$rc, code=$code"
  fi
}

check_with_bash_tcp() { # $1=port
  local p="$1"
  local cmd="timeout ${CONNECT_TIMEOUT} bash -c '</dev/tcp/${TARGET}/${p}'"
  echo "⏳ Starte: $cmd"
  local rc
  bash -c "timeout ${CONNECT_TIMEOUT} bash -c '</dev/tcp/${TARGET}/${p}'" </dev/null >/dev/null 2>&1
  rc=$?
  echo "Exitcode: ${rc}"
  if [ $rc -eq 0 ]; then
    RESULTS[$p]="OPEN"
    DETAILS[$p]="/dev/tcp Verbindung erfolgreich"
  else
    RESULTS[$p]="CLOSED"
    DETAILS[$p]="/dev/tcp rc=$rc"
  fi
}

check_port() { # $1=port
  local p="$1"
  echo
  echo "---- Prüfe Port ${p} ----"
  case "$TOOL" in
    nc)       check_with_nc "$p" ;;
    curl)     check_with_curl "$p" ;;
    bash-tcp) check_with_bash_tcp "$p" ;;
  esac
}

# --- Hauptlauf ---
echo "Hinweis: Timeout pro Port: ${CONNECT_TIMEOUT}s"
for port in "${PORTS[@]}"; do
  check_port "$port"
done

# --- Zusammenfassung ---
banner "Zusammenfassung"
open_cnt=0
for p in "${PORTS[@]}"; do
  if [ "${RESULTS[$p]}" = "OPEN" ]; then ((open_cnt++)); fi
done

for p in "${PORTS[@]}"; do
  label=""
  case "$p" in
    9997) label="(Forwarder → Indexer Daten)" ;;
    8089) label="(Management-Port)" ;;
    8000) label="(Splunk Web UI)" ;;
  esac

  if [ "${RESULTS[$p]}" = "OPEN" ]; then
    printf "Port %-5s %s %s\n" "$p" "$(color green "[OFFEN]")" "$label"
  else
    printf "Port %-5s %s %s\n" "$p" "$(color red   "[GESCHLOSSEN]")" "$label"
  fi
done

echo
if [ $open_cnt -eq ${#PORTS[@]} ]; then
  echo "$(color green "Ergebnis: Alle Splunk-Ports sind erreichbar von $TARGET.")"
else
  echo "$(color yellow "Ergebnis: $open_cnt/${#PORTS[@]} Ports erreichbar. Details:")"
  for p in "${PORTS[@]}"; do
    printf "  - %s: %s\n" "$p" "${DETAILS[$p]}"
  done
fi

echo
echo "Tipp:"
echo "  - Falls 'nc' fehlt, installiere es auf $(color blue "$DISTRO"):"
echo "    • Debian/Ubuntu : sudo apt-get update && sudo apt-get install -y netcat-openbsd"
echo "    • RHEL/CentOS   : sudo dnf install -y nmap-ncat   # oder: sudo yum install -y nmap-ncat"
echo "  - Firewalls/Security-Groups prüfen, wenn Ports als geschlossen gemeldet werden."
