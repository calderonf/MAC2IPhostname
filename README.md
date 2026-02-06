# MAC2IPhostname

Asigna y mantiene actualizado un alias en `/etc/hosts` buscando un dispositivo por su direccion MAC.

Ideal cuando la IP cambia despues de reinicios del equipo o de la red.

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

Ejemplo:

```bash
TARGET_MAC="ec:71:db:34:c6:2f"
TARGET_ALIAS="camara-patio.local"
NETWORK_RANGE=""
LOG_FILE="/var/log/mac2ip_hostname.log"
```

Notas:
- `NETWORK_RANGE=""` usa deteccion automatica (`/24`) sobre la interfaz principal.
- Si necesitas fijar la red manualmente, usa por ejemplo `192.168.0.0/24`.

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
