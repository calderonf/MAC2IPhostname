#!/bin/bash

# Script de instalación para el actualizador de IP de cámara
# Configura el script y lo añade a crontab automáticamente

echo "========================================="
echo "INSTALADOR - ACTUALIZADOR IP CÁMARA"
echo "========================================="
echo ""

# Verificar que se ejecuta como root o con sudo
if [ "$EUID" -ne 0 ]; then
    echo "❌ Este script necesita ejecutarse con sudo"
    echo "   Ejecuta: sudo bash instalar_actualizador.sh"
    exit 1
fi

# Configuración
SCRIPT_NAME="actualizar_ip_camara.sh"
INSTALL_DIR="/usr/local/bin"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
LOG_FILE="/var/log/camera_ip_update.log"

echo "[1] Copiando script a $INSTALL_DIR..."
if [ -f "./$SCRIPT_NAME" ]; then
    cp "./$SCRIPT_NAME" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "    ✓ Script instalado: $SCRIPT_PATH"
else
    echo "    ❌ ERROR: No se encontró $SCRIPT_NAME en el directorio actual"
    exit 1
fi

echo ""
echo "[2] Creando archivo de log..."
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo "    ✓ Log creado: $LOG_FILE"

echo ""
echo "[3] Configurando crontab del sistema..."

# Crear entrada de crontab temporal
CRON_TEMP=$(mktemp)

# Exportar crontab actual de root
crontab -l > "$CRON_TEMP" 2>/dev/null || true

# Verificar si ya existe la entrada
if grep -q "actualizar_ip_camara.sh" "$CRON_TEMP"; then
    echo "    ⚠ La entrada de crontab ya existe, eliminando duplicados..."
    sed -i '/actualizar_ip_camara.sh/d' "$CRON_TEMP"
fi

# Añadir nuevas entradas
cat >> "$CRON_TEMP" << EOF

# Actualizador de IP de cámara Reolink
# Al reiniciar (espera 2 minutos para que la red esté lista)
@reboot sleep 120 && $SCRIPT_PATH

# Diariamente a las 3:00 AM
0 3 * * * $SCRIPT_PATH

# Cada 6 horas (opcional, comenta si no lo necesitas)
# 0 */6 * * * $SCRIPT_PATH
EOF

# Instalar el nuevo crontab
crontab "$CRON_TEMP"
rm "$CRON_TEMP"

echo "    ✓ Crontab configurado"

echo ""
echo "[4] Ejecutando primera vez para verificar..."
$SCRIPT_PATH

echo ""
echo "========================================="
echo "✓ INSTALACIÓN COMPLETADA"
echo "========================================="
echo ""
echo "El script se ejecutará automáticamente:"
echo "  • Al reiniciar el sistema (después de 2 minutos)"
echo "  • Diariamente a las 3:00 AM"
echo ""
echo "Archivos instalados:"
echo "  • Script: $SCRIPT_PATH"
echo "  • Log: $LOG_FILE"
echo ""
echo "Comandos útiles:"
echo "  • Ver crontab: sudo crontab -l"
echo "  • Ver log: tail -f $LOG_FILE"
echo "  • Ejecutar manualmente: sudo $SCRIPT_PATH"
echo "  • Editar configuración: sudo nano $SCRIPT_PATH"
echo ""
echo "Para desinstalar:"
echo "  sudo crontab -e  # Elimina las líneas del actualizador"
echo "  sudo rm $SCRIPT_PATH"
echo "  sudo rm $LOG_FILE"
echo ""
