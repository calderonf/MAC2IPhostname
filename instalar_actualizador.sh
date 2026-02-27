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

# Array de dispositivos a escribir en config
DEVICES_TO_WRITE=()

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
            NEW_MAC="$normalized"
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
            NEW_ALIAS="$input"
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
    {
        echo "# Archivo de configuracion generado por instalar_actualizador.sh"
        echo "# Formato: \"MAC ALIAS\" por dispositivo"
        echo "DEVICES=("
        for entry in "${DEVICES_TO_WRITE[@]}"; do
            echo "  \"$entry\""
        done
        echo ")"
        echo "# Deja vacio para deteccion automatica de /24 en la interfaz principal."
        echo "NETWORK_RANGE=\"\""
        echo "LOG_FILE=\"$LOG_FILE\""
    } > "$CONFIG_FILE"

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

load_existing_devices() {
    # Lee config existente y carga dispositivos en DEVICES_TO_WRITE
    DEVICES_TO_WRITE=()

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    if [ -n "${DEVICES+x}" ] && [ "${#DEVICES[@]}" -gt 0 ]; then
        DEVICES_TO_WRITE=("${DEVICES[@]}")
    elif [ -n "${TARGET_MAC:-}" ] && [ -n "${TARGET_ALIAS:-}" ]; then
        DEVICES_TO_WRITE=("$TARGET_MAC $TARGET_ALIAS")
    fi

    # Limpiar variables importadas para no interferir
    unset DEVICES TARGET_MAC TARGET_ALIAS NETWORK_RANGE 2>/dev/null || true
}

show_existing_devices() {
    echo ""
    echo "Dispositivos configurados actualmente:"
    local i=1
    for entry in "${DEVICES_TO_WRITE[@]}"; do
        local mac alias
        mac="$(echo "$entry" | awk '{print $1}')"
        alias="$(echo "$entry" | awk '{print $2}')"
        echo "  $i) $alias  (MAC: $mac)"
        i=$((i + 1))
    done
    echo ""
}

check_duplicate() {
    local new_mac="$1"
    local new_alias="$2"
    local norm_new
    norm_new="$(echo "$new_mac" | tr '[:upper:]' '[:lower:]' | tr -cd '[:xdigit:]')"

    for entry in "${DEVICES_TO_WRITE[@]}"; do
        local mac alias norm_existing
        mac="$(echo "$entry" | awk '{print $1}')"
        alias="$(echo "$entry" | awk '{print $2}')"
        norm_existing="$(echo "$mac" | tr '[:upper:]' '[:lower:]' | tr -cd '[:xdigit:]')"

        if [ "$norm_existing" = "$norm_new" ]; then
            echo "ERROR: La MAC $new_mac ya esta configurada como $alias."
            return 1
        fi
        if [ "$alias" = "$new_alias" ]; then
            echo "ERROR: El alias $new_alias ya esta en uso para MAC $mac."
            return 1
        fi
    done
    return 0
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

    local adding_to_existing=0

    if [ -f "$CONFIG_FILE" ]; then
        load_existing_devices

        if [ "${#DEVICES_TO_WRITE[@]}" -gt 0 ]; then
            show_existing_devices

            local input
            while true; do
                read -r -p "Deseas agregar un nuevo dispositivo? (Y/N): " input
                input="$(echo "$input" | tr '[:lower:]' '[:upper:]')"
                if [ "$input" = "Y" ] || [ "$input" = "N" ]; then
                    break
                fi
                echo "Respuesta invalida. Escribe Y o N."
            done

            if [ "$input" = "N" ]; then
                echo "No se realizaron cambios."
                exit 0
            fi

            adding_to_existing=1
        fi
    fi

    # Pedir MAC y alias del nuevo dispositivo
    prompt_mac
    prompt_alias

    # Validar que no sea duplicado
    if [ "${#DEVICES_TO_WRITE[@]}" -gt 0 ]; then
        if ! check_duplicate "$NEW_MAC" "$NEW_ALIAS"; then
            exit 1
        fi
    fi

    # Agregar nuevo dispositivo al array
    DEVICES_TO_WRITE+=("$NEW_MAC $NEW_ALIAS")

    # Solo pedir cron si es primera instalacion
    if [ "$adding_to_existing" -eq 0 ]; then
        prompt_reboot_option
        prompt_daily_time
    fi

    echo ""
    echo "Instalando en $SCRIPT_PATH ..."
    install_script

    echo "Generando configuracion en $CONFIG_FILE ..."
    write_config_file

    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    local cron_status=0
    if [ "$adding_to_existing" -eq 0 ]; then
        build_desired_cron_block
        echo "Configurando crontab..."
        configure_crontab
        cron_status=$?
    else
        echo "Crontab ya configurado, sin cambios."
    fi

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
    echo "Dispositivos configurados:"
    local i=1
    for entry in "${DEVICES_TO_WRITE[@]}"; do
        local mac alias
        mac="$(echo "$entry" | awk '{print $1}')"
        alias="$(echo "$entry" | awk '{print $2}')"
        echo "  $i) $alias  (MAC: $mac)"
        i=$((i + 1))
    done
    echo ""

    if [ "$adding_to_existing" -eq 0 ]; then
        echo "Programacion:"
        echo "  Diario: $DAILY_HOUR:$DAILY_MINUTE"
        echo "  En reinicio: $RUN_AT_REBOOT"
        echo ""
    fi

    echo "Comandos utiles:"
    echo "  sudo crontab -l"
    echo "  sudo $SCRIPT_PATH"
    echo "  tail -f $LOG_FILE"
    echo "  sudo bash instalar_actualizador.sh   (agregar mas dispositivos)"

    if [ "$cron_status" -eq 2 ]; then
        echo ""
        echo "IMPORTANTE: Hubo alerta de conflicto en crontab. Revisa y corrige manualmente si aplica."
    fi
}

main
