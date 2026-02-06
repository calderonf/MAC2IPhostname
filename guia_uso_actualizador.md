# Guia de uso: MAC -> hostname local

Esta utilidad busca un equipo por MAC en la red local y actualiza su alias en `/etc/hosts`.

## Flujo recomendado

1. Descargar este repositorio.
2. Entrar al directorio del repo.
3. Dar permisos de ejecucion.
4. Ejecutar el instalador interactivo con `sudo`.

```bash
chmod +x actualizar_ip_camara.sh instalar_actualizador.sh test_manual.sh
sudo bash instalar_actualizador.sh
```

## Lo que pide el instalador

- MAC objetivo (ejemplo: `ec:71:db:34:c6:2f`)
- Alias/hostname (ejemplo: `camara-patio.local`)
- Ejecutar al reinicio con delay fijo: `Y` o `N`
- Hora diaria en formato militar de 4 digitos `HHMM` (ejemplo: `0300`, `1550`, `0010`)

## Que configura automaticamente

- Script instalado en `/usr/local/bin/actualizar_ip_camara.sh`
- Configuracion en `/etc/mac2ip_hostname.conf`
- Log en `/var/log/mac2ip_hostname.log`
- Bloque de `crontab` de root al final del archivo

## Regla importante de crontab

El instalador **no borra** otras tareas de `crontab`.

Comportamiento:
- Si no existe bloque gestionado, lo agrega al final.
- Si existe bloque igual, no cambia nada.
- Si existe bloque diferente o lineas antiguas para el mismo script, muestra alerta y no fuerza cambios.

## Ejecutar manualmente

```bash
sudo /usr/local/bin/actualizar_ip_camara.sh
```

## Verificacion rapida

```bash
sudo bash test_manual.sh
sudo crontab -l
tail -f /var/log/mac2ip_hostname.log
```

## Archivo de configuracion

Ruta: `/etc/mac2ip_hostname.conf`

Ejemplo:

```bash
TARGET_MAC="ec:71:db:34:c6:2f"
TARGET_ALIAS="camara-patio.local"
NETWORK_RANGE=""
LOG_FILE="/var/log/mac2ip_hostname.log"
```

Notas:
- `NETWORK_RANGE=""` usa deteccion automatica y escaneo `/24` de la interfaz principal.
- Si necesitas fijar una red manualmente, usa algo como `192.168.0.0/24`.

## Solucion de problemas

- No encuentra la MAC:
  - Verifica que el equipo este encendido y conectado.
  - Ejecuta manualmente el script para forzar escaneo.
- Error de permisos:
  - Ejecuta instalador y actualizador con `sudo`.
- Alerta de crontab:
  - Revisar `sudo crontab -e` y dejar solo la configuracion deseada del bloque `MAC2IP_HOSTNAME`.
