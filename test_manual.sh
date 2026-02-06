#!/bin/bash

# Verificacion rapida de configuracion actual sin modificar crontab.

set -u

CONFIG_FILE="${CONFIG_FILE:-/etc/mac2ip_hostname.conf}"

normalize_mac() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:xdigit:]'
}

if [ ! -f "$CONFIG_FILE" ]; then
    echo "No existe $CONFIG_FILE"
    echo "Primero ejecuta: sudo bash instalar_actualizador.sh"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [ -z "${TARGET_MAC:-}" ] || [ -z "${TARGET_ALIAS:-}" ]; then
    echo "Configuracion incompleta en $CONFIG_FILE"
    exit 1
fi

echo "========================================="
echo "TEST MANUAL MAC -> HOSTNAME"
echo "========================================="
echo "MAC objetivo : $TARGET_MAC"
echo "Alias        : $TARGET_ALIAS"
echo "Config file  : $CONFIG_FILE"
echo ""

target_norm="$(normalize_mac "$TARGET_MAC")"
arp_line="$(arp -an | awk -v target="$target_norm" '
{
  mac = $4
  gsub(/[^0-9A-Fa-f]/, "", mac)
  if (tolower(mac) == target) {
    print
    exit
  }
}')"

if [ -n "$arp_line" ]; then
    detected_ip="$(echo "$arp_line" | awk '{print $2}' | tr -d '()')"
    echo "OK: MAC encontrada en ARP"
    echo "Linea ARP: $arp_line"
    echo "IP detectada: $detected_ip"
else
    echo "AVISO: MAC no encontrada en ARP actual"
    echo "Ejecuta el actualizador para forzar escaneo de red:"
    echo "  sudo /usr/local/bin/actualizar_ip_camara.sh"
    exit 1
fi

echo ""
if grep -Eq "^[0-9.]+[[:space:]]+.*\b${TARGET_ALIAS}\b" /etc/hosts; then
    hosts_line="$(grep -E "^[0-9.]+[[:space:]]+.*\b${TARGET_ALIAS}\b" /etc/hosts | head -n 1)"
    echo "Entrada actual en /etc/hosts: $hosts_line"
else
    echo "No existe entrada en /etc/hosts para $TARGET_ALIAS"
fi

echo ""
if ping -c 1 -W 2 "$TARGET_ALIAS" >/dev/null 2>&1; then
    echo "OK: El alias responde a ping"
else
    echo "AVISO: El alias no responde a ping"
fi

echo ""
echo "Test finalizado"
