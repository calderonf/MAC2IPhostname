#!/bin/bash

# Script de prueba manual rápido
# Úsalo para verificar que todo funcione antes de instalarlo en crontab

echo "========================================="
echo "TEST RÁPIDO - ACTUALIZADOR DE IP"
echo "========================================="
echo ""

CAMERA_MAC="ec:71:db:34:c6:2f"
CAMERA_HOSTNAME="thecornercancha1.local"

echo "Configuración:"
echo "  MAC: $CAMERA_MAC"
echo "  Hostname: $CAMERA_HOSTNAME"
echo ""

# Test 1: ¿Está la cámara en la tabla ARP?
echo "[Test 1] Buscando en tabla ARP..."
ARP_RESULT=$(arp -an | grep -i "$CAMERA_MAC")
if [ -n "$ARP_RESULT" ]; then
    echo "✓ Encontrada en ARP:"
    echo "  $ARP_RESULT"
    CAMERA_IP=$(echo "$ARP_RESULT" | awk '{print $2}' | tr -d '()')
    echo "  IP detectada: $CAMERA_IP"
else
    echo "✗ No encontrada en ARP"
    echo "  Esto es normal si no has hecho ping recientemente"
    CAMERA_IP=""
fi
echo ""

# Test 2: Escanear la red
if [ -z "$CAMERA_IP" ]; then
    echo "[Test 2] Escaneando red 192.168.0.0/24..."
    echo "  (Esto puede tardar 10-15 segundos)"

    for i in {1..254}; do
        ping -c 1 -W 1 192.168.0.$i > /dev/null 2>&1 &
    done
    wait

    sleep 2

    ARP_RESULT=$(arp -an | grep -i "$CAMERA_MAC")
    if [ -n "$ARP_RESULT" ]; then
        echo "✓ Cámara encontrada después del escaneo:"
        echo "  $ARP_RESULT"
        CAMERA_IP=$(echo "$ARP_RESULT" | awk '{print $2}' | tr -d '()')
        echo "  IP detectada: $CAMERA_IP"
    else
        echo "✗ No se pudo encontrar la cámara"
        echo ""
        echo "Posibles causas:"
        echo "  1. La cámara está apagada o desconectada"
        echo "  2. La MAC es incorrecta"
        echo "  3. La cámara está en otra red (verifica el rango)"
        echo ""
        exit 1
    fi
    echo ""
fi

# Test 3: ¿Puede hacer ping?
echo "[Test 3] Probando ping a $CAMERA_IP..."
if ping -c 3 -W 2 "$CAMERA_IP" > /dev/null 2>&1; then
    echo "✓ Ping exitoso"
else
    echo "⚠ Ping falló (pero la cámara existe en la red)"
fi
echo ""

# Test 4: ¿Qué hay en /etc/hosts actualmente?
echo "[Test 4] Contenido actual de /etc/hosts..."
if grep -q "$CAMERA_HOSTNAME" /etc/hosts; then
    CURRENT_HOSTS=$(grep "$CAMERA_HOSTNAME" /etc/hosts)
    echo "✓ Ya existe entrada:"
    echo "  $CURRENT_HOSTS"

    HOSTS_IP=$(echo "$CURRENT_HOSTS" | awk '{print $1}')
    if [ "$HOSTS_IP" = "$CAMERA_IP" ]; then
        echo "  ✓ La IP es correcta ($HOSTS_IP)"
    else
        echo "  ⚠ La IP es diferente: en hosts=$HOSTS_IP, detectada=$CAMERA_IP"
        echo "    El script la actualizará"
    fi
else
    echo "⚠ No existe entrada para $CAMERA_HOSTNAME"
    echo "  El script la creará"
fi
echo ""

# Test 5: ¿Tiene permisos para modificar /etc/hosts?
echo "[Test 5] Verificando permisos..."
if [ -w "/etc/hosts" ]; then
    echo "✓ Tienes permisos de escritura en /etc/hosts"
elif [ "$EUID" -eq 0 ]; then
    echo "✓ Ejecutando como root, puedes modificar /etc/hosts"
else
    echo "✗ No tienes permisos para modificar /etc/hosts"
    echo "  Ejecuta este script con sudo: sudo bash $0"
    echo ""
    exit 1
fi
echo ""

# Test 6: Simular actualización
echo "[Test 6] Simulando actualización..."
echo "  Se añadiría/actualizaría esta línea en /etc/hosts:"
echo "  $CAMERA_IP    $CAMERA_HOSTNAME"
echo ""

# Test 7: ¿Queremos hacer la actualización real?
read -p "¿Quieres actualizar /etc/hosts ahora? (s/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[SsYy]$ ]]; then
    echo "  Haciendo backup de /etc/hosts..."
    cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

    echo "  Eliminando entradas antiguas..."
    sed -i "/[[:space:]]$CAMERA_HOSTNAME$/d" /etc/hosts

    echo "  Añadiendo nueva entrada..."
    echo "$CAMERA_IP    $CAMERA_HOSTNAME" >> /etc/hosts

    echo "  ✓ /etc/hosts actualizado"
    echo ""

    # Test final
    echo "[Test Final] Verificando hostname..."
    if ping -c 2 -W 2 "$CAMERA_HOSTNAME" > /dev/null 2>&1; then
        echo "✓ ¡Éxito! $CAMERA_HOSTNAME responde"
        echo ""
        echo "URL RTSP lista para usar:"
        echo "  rtsp://admin:Pi.1415926535@$CAMERA_HOSTNAME:554/h264Preview_01_main"
    else
        echo "⚠ $CAMERA_HOSTNAME no responde a ping"
        echo "  Esto puede ser normal si la cámara tiene ping deshabilitado"
        echo "  Prueba la URL RTSP de todas formas"
    fi
else
    echo "  ✗ Actualización cancelada"
fi

echo ""
echo "========================================="
echo "Test completado"
echo "========================================="
