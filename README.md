# MAC2IPhostname

Asigna y mantiene actualizado uno o mas alias en `/etc/hosts` buscando dispositivos por su direccion MAC.

Ideal cuando la IP cambia despues de reinicios del equipo o de la red. Soporta multiples camaras/dispositivos en una sola instalacion.

## Requisitos

- Linux con `bash`
- `sudo`
- comandos de red basicos: `arp`, `ping`, `crontab`

## Instalacion desde consola (paso a paso)

1. Clonar el repositorio:

```bash
git clone https://github.com/calderonf/MAC2IPhostname.git
```

2. Entrar al directorio:

```bash
cd MAC2IPhostname
```

3. Dar permisos de ejecucion:

```bash
chmod +x actualizar_ip_camara.sh instalar_actualizador.sh test_manual.sh
```

4. Ejecutar instalador interactivo:

```bash
sudo bash instalar_actualizador.sh
```

## Lo que te pedira el instalador

- MAC objetivo
  - Ejemplo: `ec:71:db:34:c6:2f`
- Alias/hostname local
  - Ejemplo: `camara-patio.local`
- Ejecutar al reinicio con delay
  - Respuesta: `Y` o `N`
- Hora diaria en formato militar de 4 digitos (`HHMM`)
  - Ejemplos: `0300`, `1550`, `0010`

## Agregar mas dispositivos

Para agregar una segunda camara (o tercera, etc.), ejecuta el instalador de nuevo:

```bash
sudo bash instalar_actualizador.sh
```

El instalador detecta la configuracion existente, muestra los dispositivos ya configurados y te permite agregar uno nuevo. Solo te pedira MAC y alias; la programacion de crontab se mantiene sin cambios.

## Que deja configurado

- Script principal: `/usr/local/bin/actualizar_ip_camara.sh`
- Configuracion: `/etc/mac2ip_hostname.conf`
- Log: `/var/log/mac2ip_hostname.log`
- Tareas en `crontab` de root (bloque gestionado)

## Comandos utiles despues de instalar

Ejecutar una corrida manual:

```bash
sudo /usr/local/bin/actualizar_ip_camara.sh
```

Ver tareas programadas:

```bash
sudo crontab -l
```

Ver log en tiempo real:

```bash
tail -f /var/log/mac2ip_hostname.log
```

Prueba rapida:

```bash
sudo bash test_manual.sh
```

## Regla de seguridad de crontab

El instalador no borra tareas existentes.

- Si no existe bloque gestionado, lo agrega al final.
- Si el bloque ya existe y coincide, no cambia nada.
- Si detecta una configuracion previa distinta o entradas antiguas fuera del bloque, muestra alerta y no fuerza cambios.

## Archivo de configuracion

Ruta:

```bash
/etc/mac2ip_hostname.conf
```

Ejemplo con multiples dispositivos:

```bash
DEVICES=(
  "ec:71:db:34:c6:2f camara-patio.local"
  "11:22:33:44:55:66 camara-entrada.local"
)
NETWORK_RANGE=""
LOG_FILE="/var/log/mac2ip_hostname.log"
```

Formato legacy (un solo dispositivo, sigue siendo compatible):

```bash
TARGET_MAC="ec:71:db:34:c6:2f"
TARGET_ALIAS="camara-patio.local"
NETWORK_RANGE=""
LOG_FILE="/var/log/mac2ip_hostname.log"
```

Notas:
- `NETWORK_RANGE=""` usa deteccion automatica (`/24`) sobre la interfaz principal.
- Si necesitas fijar la red manualmente, usa por ejemplo `192.168.0.0/24`.
- El formato legacy se migra automaticamente al agregar un segundo dispositivo con el instalador.

## Sistemas con cloud-init (Raspberry Pi OS, Ubuntu cloud, etc.)

En sistemas donde `cloud-init` gestiona `/etc/hosts` (comun en Raspberry Pi OS y Ubuntu Server), el archivo `/etc/hosts` se regenera en cada reinicio, borrando las entradas agregadas por este script.

El script detecta esta situacion automaticamente:

1. Verifica si `manage_etc_hosts: True` esta activo en `/etc/cloud/cloud.cfg`
2. Si es asi, ademas de actualizar `/etc/hosts`, actualiza el template de cloud-init en `/etc/cloud/templates/hosts.debian.tmpl`
3. Al siguiente reinicio, cloud-init regenera `/etc/hosts` incluyendo las entradas del template
4. Cuando el script se ejecuta con `@reboot` (120s despues), actualiza las IPs si cambiaron

No necesitas hacer nada especial: el script se encarga de todo.

Si prefieres desactivar cloud-init manualmente:

```bash
sudo nano /etc/cloud/cloud.cfg
# Cambiar manage_etc_hosts: True  ->  manage_etc_hosts: False
```

## Escaneo de red

El script escanea la red local con ping para poblar la tabla ARP y encontrar los dispositivos.

Caracteristicas del escaneo:
- **Orden aleatorio**: las IPs se escanean en orden aleatorio (requiere `shuf`, incluido en coreutils) para evitar que dispositivos con proteccion anti-escaneo ignoren barridos secuenciales.
- **Lotes**: los pings se envian en lotes de 50 con pausas entre ellos para no saturar la red.
- **Reintentos**: se realizan hasta 2 rondas de escaneo. Si todos los dispositivos se encuentran en la primera ronda, la segunda se omite.

## Solucion de problemas rapida

No encuentra la MAC:

```bash
sudo /usr/local/bin/actualizar_ip_camara.sh
tail -n 50 /var/log/mac2ip_hostname.log
```

Problema de permisos:

```bash
sudo bash instalar_actualizador.sh
```

Conflicto de crontab:

```bash
sudo crontab -e
```

Deja solo el bloque `MAC2IP_HOSTNAME` que quieras usar.

cloud-init borra entradas al reiniciar:

Normalmente el script lo maneja automaticamente. Si no funciona, verifica:

```bash
cat /etc/cloud/templates/hosts.debian.tmpl | grep MAC2IP
```

Debe mostrar el bloque `BEGIN MAC2IP_HOSTNAME` con tus entradas.
