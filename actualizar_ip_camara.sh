#!/bin/bash

# Script para actualizar automáticamente la IP de la cámara Reolink en /etc/hosts
# Busca por MAC address y actualiza si la IP cambió

# CONFIGURACIÓN
CAMERA_MAC="ec:71:db:34:c6:2f"
CAMERA_HOSTNAME="thecornercancha1.local"
NETWORK_RANGE="192.168.0.0/24"  # Ajusta según tu red
LOG_FILE="/var/log/camera_ip_update.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Buscar IP por MAC en la tabla ARP
find_ip_by_mac() {
    local mac="$1"
    # Normalizar MAC (convertir a minúsculas y formato con :)
    mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

    # Buscar en tabla ARP
    arp -an | grep -i "$mac" | awk '{print $2}' | tr -d '()'
}

# Escanear la red para llenar la tabla ARP
scan_network() {
    log "Escaneando red $NETWORK_RANGE para llenar tabla ARP..."

    # Método 1: ping rápido a toda la red (más rápido)
    for i in {1..254}; do
        ping -c 1 -W 1 "$(echo $NETWORK_RANGE | cut -d'/' -f1 | cut -d'.' -f1-3).$i" > /dev/null 2>&1 &
    done
    wait

    sleep 2  # Dar tiempo a que se llene la tabla ARP
}

# Actualizar /etc/hosts
update_hosts_file() {
    local ip="$1"
    local hostname="$2"

    # Verificar si ya existe la entrada con la IP correcta
    if grep -q "^$ip[[:space:]].*$hostname" /etc/hosts; then
        log "✓ /etc/hosts ya está actualizado: $ip -> $hostname"
        return 0
    fi

    # Crear backup
    cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

    # Eliminar entradas antiguas del hostname
    sed -i "/[[:space:]]$hostname$/d" /etc/hosts

    # Añadir nueva entrada
    echo "$ip    $hostname" >> /etc/hosts

    log "✓ /etc/hosts actualizado: $ip -> $hostname"
    return 0
}

# MAIN
log "========================================="
log "Iniciando actualización de IP de cámara"
log "MAC buscada: $CAMERA_MAC"
log "Hostname: $CAMERA_HOSTNAME"

# Paso 1: Buscar en tabla ARP actual
CURRENT_IP=$(find_ip_by_mac "$CAMERA_MAC")

if [ -z "$CURRENT_IP" ]; then
    log "⚠ MAC no encontrada en tabla ARP, escaneando red..."
    scan_network

    # Buscar de nuevo
    CURRENT_IP=$(find_ip_by_mac "$CAMERA_MAC")
fi

# Paso 2: Verificar si encontramos la IP
if [ -z "$CURRENT_IP" ]; then
    log "✗ ERROR: No se pudo encontrar la cámara con MAC $CAMERA_MAC"
    log "  Verifica que la cámara esté encendida y conectada a la red"
    exit 1
fi

log "✓ Cámara encontrada: $CURRENT_IP (MAC: $CAMERA_MAC)"

# Paso 3: Actualizar /etc/hosts si es necesario
update_hosts_file "$CURRENT_IP" "$CAMERA_HOSTNAME"

# Paso 4: Verificar conectividad
if ping -c 1 -W 2 "$CAMERA_HOSTNAME" > /dev/null 2>&1; then
    log "✓ Verificación exitosa: $CAMERA_HOSTNAME responde"
    log "✓ URL RTSP: rtsp://admin:Pi.1415926535@$CAMERA_HOSTNAME:554/h264Preview_01_main"
else
    log "⚠ ADVERTENCIA: $CAMERA_HOSTNAME no responde a ping (pero /etc/hosts fue actualizado)"
fi

log "Finalizado"
log "========================================="

exit 0
