#!/bin/bash

# Actualiza /etc/hosts buscando dispositivos por su MAC.
# Soporta multiples dispositivos (array DEVICES) y formato legacy (TARGET_MAC/TARGET_ALIAS).
# Detecta cloud-init y actualiza su template para persistir entre reinicios.
# Configuracion esperada en /etc/mac2ip_hostname.conf

set -u

CONFIG_FILE="${CONFIG_FILE:-/etc/mac2ip_hostname.conf}"
DEFAULT_LOG_FILE="/var/log/mac2ip_hostname.log"
CLOUD_INIT_TEMPLATE="/etc/cloud/templates/hosts.debian.tmpl"
CLOUD_INIT_BEGIN="# BEGIN MAC2IP_HOSTNAME"
CLOUD_INIT_END="# END MAC2IP_HOSTNAME"

DEVICE_LIST=()

# Almacena "alias ip" de cada dispositivo resuelto para actualizar template cloud-init
RESOLVED_ENTRIES=()

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

    if [ -n "${DEVICES+x}" ] && [ "${#DEVICES[@]}" -gt 0 ]; then
        DEVICE_LIST=("${DEVICES[@]}")
    elif [ -n "${TARGET_MAC:-}" ] && [ -n "${TARGET_ALIAS:-}" ]; then
        DEVICE_LIST=("$TARGET_MAC $TARGET_ALIAS")
    else
        echo "ERROR: Se requiere array DEVICES o TARGET_MAC/TARGET_ALIAS en $CONFIG_FILE"
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
    local max_rounds="${2:-2}"
    local base batch_size=50

    base="$(echo "$range" | cut -d'/' -f1 | cut -d'.' -f1-3)"

    local round=1
    while [ "$round" -le "$max_rounds" ]; do
        log "Escaneando red $range (ronda $round/$max_rounds, orden aleatorio)..."

        # Generar lista aleatorizada de IPs
        local ip_list
        if command -v shuf >/dev/null 2>&1; then
            ip_list="$(shuf -i 1-254)"
        else
            ip_list="$(seq 1 254)"
            log "AVISO: shuf no disponible, escaneo secuencial"
        fi

        # Enviar pings en lotes para no saturar la red
        local count=0
        for i in $ip_list; do
            ping -c 1 -W 1 "$base.$i" >/dev/null 2>&1 &
            count=$((count + 1))
            if [ $((count % batch_size)) -eq 0 ]; then
                wait
                sleep 1
            fi
        done
        wait
        sleep 2

        # Verificar si todos los dispositivos ya fueron encontrados
        local all_found=1
        for entry in "${DEVICE_LIST[@]}"; do
            local mac
            mac="$(echo "$entry" | awk '{print $1}')"
            if [ -z "$(find_ip_by_mac "$mac")" ]; then
                all_found=0
                break
            fi
        done

        if [ "$all_found" -eq 1 ]; then
            log "Todos los dispositivos encontrados en ronda $round"
            return 0
        fi

        round=$((round + 1))

        if [ "$round" -le "$max_rounds" ]; then
            log "Dispositivos pendientes, reintentando..."
            sleep 3
        fi
    done
}

remove_alias_from_file() {
    local alias="$1"
    local target_file="$2"
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
    }' "$target_file" > "$tmp_file"

    cat "$tmp_file" > "$target_file"
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

    remove_alias_from_file "$alias" /etc/hosts
    echo "$ip    $alias" >> /etc/hosts

    log "OK: /etc/hosts actualizado: $ip -> $alias"
}

# --- cloud-init ---

is_cloud_init_managing_hosts() {
    # Detectar si cloud-init gestiona /etc/hosts
    if [ -f "$CLOUD_INIT_TEMPLATE" ]; then
        # Verificar en cloud.cfg si manage_etc_hosts esta activo
        if [ -f /etc/cloud/cloud.cfg ]; then
            if grep -Eq '^\s*manage_etc_hosts\s*:\s*(True|true)' /etc/cloud/cloud.cfg; then
                return 0
            fi
        fi
        # Tambien verificar por el comentario en /etc/hosts
        if grep -q "manage_etc_hosts.*True" /etc/hosts 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

update_cloud_init_template() {
    # Actualiza el template de cloud-init con un bloque gestionado
    # que contiene todas las entradas resueltas.
    # Asi al reiniciar, cloud-init regenera /etc/hosts incluyendo nuestras entradas.

    if [ "${#RESOLVED_ENTRIES[@]}" -eq 0 ]; then
        return
    fi

    local tmp_file
    tmp_file="$(mktemp)"

    # Copiar template sin nuestro bloque gestionado previo
    awk -v begin="$CLOUD_INIT_BEGIN" -v end="$CLOUD_INIT_END" '
    $0 == begin {skip = 1; next}
    $0 == end {skip = 0; next}
    !skip {print}
    ' "$CLOUD_INIT_TEMPLATE" > "$tmp_file"

    # Agregar bloque gestionado al final
    {
        echo ""
        echo "$CLOUD_INIT_BEGIN"
        for line in "${RESOLVED_ENTRIES[@]}"; do
            echo "$line"
        done
        echo "$CLOUD_INIT_END"
    } >> "$tmp_file"

    cp "$CLOUD_INIT_TEMPLATE" "${CLOUD_INIT_TEMPLATE}.backup.$(date +%Y%m%d_%H%M%S)"
    cat "$tmp_file" > "$CLOUD_INIT_TEMPLATE"
    rm -f "$tmp_file"

    log "OK: Template cloud-init actualizado ($CLOUD_INIT_TEMPLATE)"
}

# --- procesamiento ---

process_device() {
    local mac="$1"
    local alias="$2"

    log "-----------------------------------------"
    log "Procesando dispositivo: $alias (MAC: $mac)"

    local current_ip
    current_ip="$(find_ip_by_mac "$mac")"

    if [ -z "$current_ip" ]; then
        log "ERROR: No se encontro dispositivo con MAC $mac ($alias)"
        log "Verifica que el equipo este encendido y conectado"
        return 1
    fi

    log "OK: Dispositivo encontrado en IP $current_ip"
    update_hosts_file "$current_ip" "$alias"

    # Guardar entrada resuelta para cloud-init
    RESOLVED_ENTRIES+=("$current_ip    $alias")

    if ping -c 1 -W 2 "$alias" >/dev/null 2>&1; then
        log "OK: Verificacion por hostname exitosa ($alias)"
    else
        log "AVISO: $alias no respondio a ping (hosts ya fue actualizado)"
    fi

    return 0
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
    log "Dispositivos configurados: ${#DEVICE_LIST[@]}"
    log "Rango de escaneo: $NETWORK_RANGE"

    # Detectar cloud-init
    local cloud_init_active=0
    if is_cloud_init_managing_hosts; then
        cloud_init_active=1
        log "AVISO: cloud-init gestiona /etc/hosts (manage_etc_hosts=True)"
        log "Se actualizara tambien el template: $CLOUD_INIT_TEMPLATE"
    fi

    # Primer intento: buscar todas las MACs en ARP actual
    local need_scan=0
    for entry in "${DEVICE_LIST[@]}"; do
        local mac
        mac="$(echo "$entry" | awk '{print $1}')"
        local ip
        ip="$(find_ip_by_mac "$mac")"
        if [ -z "$ip" ]; then
            need_scan=1
            break
        fi
    done

    # Escanear red (con reintentos) si al menos un dispositivo no se encontro
    if [ "$need_scan" -eq 1 ]; then
        log "Al menos un dispositivo no encontrado en ARP, iniciando escaneo"
        scan_network "$NETWORK_RANGE" 2
    fi

    # Procesar cada dispositivo
    local errors=0
    for entry in "${DEVICE_LIST[@]}"; do
        local mac alias
        mac="$(echo "$entry" | awk '{print $1}')"
        alias="$(echo "$entry" | awk '{print $2}')"
        if ! process_device "$mac" "$alias"; then
            errors=$((errors + 1))
        fi
    done

    # Actualizar template cloud-init si aplica
    if [ "$cloud_init_active" -eq 1 ]; then
        update_cloud_init_template
    fi

    log "========================================="
    if [ "$errors" -gt 0 ]; then
        log "Fin con $errors error(es) de ${#DEVICE_LIST[@]} dispositivo(s)"
        exit 1
    else
        log "Fin: ${#DEVICE_LIST[@]} dispositivo(s) procesado(s) correctamente"
    fi
    log "========================================="
}

main
