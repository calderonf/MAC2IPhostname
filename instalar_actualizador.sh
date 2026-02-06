#!/bin/bash

set -u

SCRIPT_NAME="actualizar_ip_camara.sh"
INSTALL_DIR="/usr/local/bin"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
CONFIG_FILE="/etc/mac2ip_hostname.conf"
LOG_FILE="/var/log/mac2ip_hostname.log"
REBOOT_DELAY_SECONDS=120
CRON_BEGIN="# BEGIN MAC2IP_HOSTNAME"
CRON_END="# END MAC2IP_HOSTNAME"

normalize_mac() {
    local raw
    raw="$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:xdigit:]')"

    if [ "${#raw}" -ne 12 ]; then
        echo ""
        return
    fi

    echo "$raw" | sed 's/\(..\)/\1:/g; s/:$//'
}

prompt_mac() {
    local input normalized
    while true; do
        read -r -p "MAC objetivo (ej: ec:71:db:34:c6:2f): " input
        normalized="$(normalize_mac "$input")"

        if [ -n "$normalized" ]; then
            TARGET_MAC="$normalized"
            return
        fi

        echo "Formato invalido. Usa 12 hexadecimales (con o sin : o -)."
    done
}

prompt_alias() {
    local input
    while true; do
        read -r -p "Alias/hostname (ej: camara-patio.local): " input

        if [[ "$input" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
            TARGET_ALIAS="$input"
            return
        fi

        echo "Alias invalido. Usa solo letras, numeros, punto y guion."
    done
}

prompt_reboot_option() {
    local input
    while true; do
        read -r -p "Ejecutar tambien al reinicio con delay de ${REBOOT_DELAY_SECONDS}s? (Y/N): " input
        input="$(echo "$input" | tr '[:lower:]' '[:upper:]')"

        if [ "$input" = "Y" ] || [ "$input" = "N" ]; then
            RUN_AT_REBOOT="$input"
            return
        fi

        echo "Respuesta invalida. Escribe Y o N."
    done
}

prompt_daily_time() {
    local input hh mm
    while true; do
        read -r -p "Hora diaria en formato militar HHMM (ej: 0300, 1550, 0010): " input

        if [[ "$input" =~ ^[0-9]{4}$ ]]; then
            hh="${input:0:2}"
            mm="${input:2:2}"

            if [ $((10#$hh)) -le 23 ] && [ $((10#$mm)) -le 59 ]; then
                DAILY_HOUR="$hh"
                DAILY_MINUTE="$mm"
                return
            fi
        fi

        echo "Hora invalida. Debe estar entre 0000 y 2359."
    done
}

build_desired_cron_block() {
    local daily_line reboot_line
    daily_line="$((10#$DAILY_MINUTE)) $((10#$DAILY_HOUR)) * * * $SCRIPT_PATH"

    DESIRED_CRON_BLOCK="$CRON_BEGIN
# Gestionado por instalar_actualizador.sh
$daily_line"

    if [ "$RUN_AT_REBOOT" = "Y" ]; then
        reboot_line="@reboot sleep $REBOOT_DELAY_SECONDS && $SCRIPT_PATH"
        DESIRED_CRON_BLOCK="$DESIRED_CRON_BLOCK
$reboot_line"
    fi

    DESIRED_CRON_BLOCK="$DESIRED_CRON_BLOCK
$CRON_END"
}

get_current_crontab() {
    crontab -l 2>/dev/null || true
}

extract_managed_block() {
    printf '%s\n' "$1" | awk -v begin="$CRON_BEGIN" -v end="$CRON_END" '
    $0 == begin {capture = 1}
    capture {print}
    $0 == end {capture = 0}
    '
}

configure_crontab() {
    local current_cron existing_block new_cron

    current_cron="$(get_current_crontab)"
    existing_block="$(extract_managed_block "$current_cron")"

    if [ -n "$existing_block" ]; then
        if [ "$existing_block" != "$DESIRED_CRON_BLOCK" ]; then
            echo ""
            echo "ALERTA: Ya existe una configuracion previa de este servicio en crontab y no coincide con lo solicitado."
            echo "No se aplicaron cambios en crontab para evitar conflicto."
            echo ""
            echo "Bloque actual:"
            echo "$existing_block"
            echo ""
            echo "Bloque solicitado:"
            echo "$DESIRED_CRON_BLOCK"
            echo ""
            return 2
        fi

        echo "Crontab ya estaba configurado con los mismos valores."
        return 0
    fi

    if printf '%s\n' "$current_cron" | grep -Fq "$SCRIPT_PATH"; then
        echo ""
        echo "ALERTA: Se detectaron entradas antiguas para $SCRIPT_PATH fuera del bloque gestionado."
        echo "Revisa crontab manualmente para evitar duplicados: sudo crontab -e"
        echo "No se agrego un nuevo bloque automaticamente."
        echo ""
        return 2
    fi

    new_cron="$current_cron"

    if [ -n "$new_cron" ] && [ "${new_cron%$'\n'}" = "$new_cron" ]; then
        new_cron="$new_cron"$'\n'
    fi

    new_cron="$new_cron"$'\n'"$DESIRED_CRON_BLOCK"$'\n'
    printf '%s' "$new_cron" | crontab -

    echo "Crontab actualizado: bloque agregado al final."
    return 0
}

write_config_file() {
    cat > "$CONFIG_FILE" <<EOF_CONF
# Archivo de configuracion generado por instalar_actualizador.sh
TARGET_MAC="$TARGET_MAC"
TARGET_ALIAS="$TARGET_ALIAS"
# Deja vacio para deteccion automatica de /24 en la interfaz principal.
NETWORK_RANGE=""
LOG_FILE="$LOG_FILE"
EOF_CONF

    chmod 600 "$CONFIG_FILE"
}

install_script() {
    if [ ! -f "./$SCRIPT_NAME" ]; then
        echo "ERROR: No se encontro ./$SCRIPT_NAME en el directorio actual."
        exit 1
    fi

    cp "./$SCRIPT_NAME" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "Este script necesita ejecutarse con sudo/root."
        echo "Ejecuta: sudo bash instalar_actualizador.sh"
        exit 1
    fi

    echo "========================================="
    echo "CONFIGURACION MAC -> HOSTNAME"
    echo "========================================="

    prompt_mac
    prompt_alias
    prompt_reboot_option
    prompt_daily_time

    echo ""
    echo "Instalando en $SCRIPT_PATH ..."
    install_script

    echo "Generando configuracion en $CONFIG_FILE ..."
    write_config_file

    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    build_desired_cron_block

    echo "Configurando crontab..."
    configure_crontab
    cron_status=$?

    echo ""
    echo "Ejecutando una prueba inicial..."
    if "$SCRIPT_PATH"; then
        echo "Prueba inicial completada."
    else
        echo "AVISO: La prueba inicial fallo. Revisa el log: $LOG_FILE"
    fi

    echo ""
    echo "========================================="
    echo "INSTALACION COMPLETADA"
    echo "========================================="
    echo "Script: $SCRIPT_PATH"
    echo "Config: $CONFIG_FILE"
    echo "Log: $LOG_FILE"
    echo ""
    echo "Configuracion aplicada:"
    echo "  MAC: $TARGET_MAC"
    echo "  Alias: $TARGET_ALIAS"
    echo "  Diario: $DAILY_HOUR:$DAILY_MINUTE"
    echo "  En reinicio: $RUN_AT_REBOOT"
    echo ""
    echo "Comandos utiles:"
    echo "  sudo crontab -l"
    echo "  sudo $SCRIPT_PATH"
    echo "  tail -f $LOG_FILE"

    if [ "$cron_status" -eq 2 ]; then
        echo ""
        echo "IMPORTANTE: Hubo alerta de conflicto en crontab. Revisa y corrige manualmente si aplica."
    fi
}

main
