#!/bin/bash

# Verificacion rapida de configuracion actual sin modificar crontab.
# Soporta multiples dispositivos (array DEVICES) y formato legacy (TARGET_MAC/TARGET_ALIAS).

set -u

CONFIG_FILE="${CONFIG_FILE:-/etc/mac2ip_hostname.conf}"

DEVICE_LIST=()

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

if [ -n "${DEVICES+x}" ] && [ "${#DEVICES[@]}" -gt 0 ]; then
    DEVICE_LIST=("${DEVICES[@]}")
elif [ -n "${TARGET_MAC:-}" ] && [ -n "${TARGET_ALIAS:-}" ]; then
    DEVICE_LIST=("$TARGET_MAC $TARGET_ALIAS")
else
    echo "Configuracion incompleta en $CONFIG_FILE"
    exit 1
fi

echo "========================================="
echo "TEST MANUAL MAC -> HOSTNAME"
echo "========================================="
echo "Config file  : $CONFIG_FILE"
echo "Dispositivos : ${#DEVICE_LIST[@]}"
echo ""

errors=0

for entry in "${DEVICE_LIST[@]}"; do
    mac="$(echo "$entry" | awk '{print $1}')"
    alias="$(echo "$entry" | awk '{print $2}')"

    echo "-----------------------------------------"
    echo "Dispositivo: $alias"
    echo "MAC objetivo: $mac"
    echo ""

    target_norm="$(normalize_mac "$mac")"
    arp_line="$(arp -an | awk -v target="$target_norm" '
    {
      m = $4
      gsub(/[^0-9A-Fa-f]/, "", m)
      if (tolower(m) == target) {
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
        errors=$((errors + 1))
        echo ""
        continue
    fi

    echo ""
    if grep -Eq "^[0-9.]+[[:space:]]+.*\b${alias}\b" /etc/hosts; then
        hosts_line="$(grep -E "^[0-9.]+[[:space:]]+.*\b${alias}\b" /etc/hosts | head -n 1)"
        echo "Entrada actual en /etc/hosts: $hosts_line"
    else
        echo "No existe entrada en /etc/hosts para $alias"
    fi

    echo ""
    if ping -c 1 -W 2 "$alias" >/dev/null 2>&1; then
        echo "OK: El alias responde a ping"
    else
        echo "AVISO: El alias no responde a ping"
    fi

    echo ""
done

echo "========================================="
echo "Test finalizado: ${#DEVICE_LIST[@]} dispositivo(s) verificado(s)"
if [ "$errors" -gt 0 ]; then
    echo "$errors dispositivo(s) no encontrado(s) en ARP"
fi
