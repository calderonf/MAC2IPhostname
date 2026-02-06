#!/bin/bash

# Actualiza /etc/hosts buscando un dispositivo por su MAC.
# Configuracion esperada en /etc/mac2ip_hostname.conf

set -u

CONFIG_FILE="${CONFIG_FILE:-/etc/mac2ip_hostname.conf}"
DEFAULT_LOG_FILE="/var/log/mac2ip_hostname.log"

log() {
    local msg="$1"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    if [ -n "${LOG_FILE:-}" ]; then
        echo "[$ts] $msg" | tee -a "$LOG_FILE"
    else
        echo "[$ts] $msg"
    fi
}

normalize_mac() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:xdigit:]'
}

validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "ERROR: No se encontro archivo de configuracion: $CONFIG_FILE"
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    if [ -z "${TARGET_MAC:-}" ] || [ -z "${TARGET_ALIAS:-}" ]; then
        echo "ERROR: TARGET_MAC y TARGET_ALIAS son obligatorios en $CONFIG_FILE"
        exit 1
    fi

    if [ -z "${LOG_FILE:-}" ]; then
        LOG_FILE="$DEFAULT_LOG_FILE"
    fi

    if [ -z "${NETWORK_RANGE:-}" ]; then
        NETWORK_RANGE="$(detect_network_range)"
    fi
}

detect_network_range() {
    local local_ip
    local_ip="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 | head -n 1)"

    if [ -z "$local_ip" ]; then
        # Fallback: red comun
        echo "192.168.1.0/24"
        return
    fi

    echo "${local_ip%.*}.0/24"
}

find_ip_by_mac() {
    local target_mac
    target_mac="$(normalize_mac "$1")"

    arp -an | awk -v target="$target_mac" '
    {
        ip = $2
        gsub(/[()]/, "", ip)

        mac = $4
        gsub(/[^0-9A-Fa-f]/, "", mac)

        if (tolower(mac) == target) {
            print ip
        }
    }' | head -n 1
}

scan_network() {
    local range="$1"
    local base

    base="$(echo "$range" | cut -d'/' -f1 | cut -d'.' -f1-3)"

    log "Escaneando red $range para poblar ARP..."

    for i in {1..254}; do
        ping -c 1 -W 1 "$base.$i" >/dev/null 2>&1 &
    done
    wait

    sleep 2
}

remove_alias_from_hosts() {
    local alias="$1"
    local tmp_file

    tmp_file="$(mktemp)"

    awk -v target_alias="$alias" '
    {
        if ($0 ~ /^[[:space:]]*#/) {
            print
            next
        }

        keep = 1
        for (i = 2; i <= NF; i++) {
            if ($i == target_alias) {
                keep = 0
                break
            }
        }

        if (keep) {
            print
        }
    }' /etc/hosts > "$tmp_file"

    cat "$tmp_file" > /etc/hosts
    rm -f "$tmp_file"
}

update_hosts_file() {
    local ip="$1"
    local alias="$2"

    if grep -Eq "^${ip}[[:space:]]+.*\b${alias}\b" /etc/hosts; then
        log "OK: /etc/hosts ya contiene $ip -> $alias"
        return 0
    fi

    cp /etc/hosts "/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"

    remove_alias_from_hosts "$alias"
    echo "$ip    $alias" >> /etc/hosts

    log "OK: /etc/hosts actualizado: $ip -> $alias"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Este script requiere permisos de root."
        echo "Ejecuta: sudo $0"
        exit 1
    fi

    validate_config

    log "========================================="
    log "Inicio de actualizacion MAC -> hostname"
    log "MAC objetivo: $TARGET_MAC"
    log "Alias objetivo: $TARGET_ALIAS"
    log "Rango de escaneo: $NETWORK_RANGE"

    local current_ip
    current_ip="$(find_ip_by_mac "$TARGET_MAC")"

    if [ -z "$current_ip" ]; then
        log "MAC no encontrada en ARP actual, iniciando escaneo"
        scan_network "$NETWORK_RANGE"
        current_ip="$(find_ip_by_mac "$TARGET_MAC")"
    fi

    if [ -z "$current_ip" ]; then
        log "ERROR: No se encontro dispositivo con MAC $TARGET_MAC"
        log "Verifica que el equipo este encendido y conectado"
        log "Fin con error"
        log "========================================="
        exit 1
    fi

    log "OK: Dispositivo encontrado en IP $current_ip"
    update_hosts_file "$current_ip" "$TARGET_ALIAS"

    if ping -c 1 -W 2 "$TARGET_ALIAS" >/dev/null 2>&1; then
        log "OK: Verificacion por hostname exitosa ($TARGET_ALIAS)"
    else
        log "AVISO: $TARGET_ALIAS no respondio a ping (hosts ya fue actualizado)"
    fi

    log "Fin"
    log "========================================="
}

main
