# Guía de Uso - Actualizador Automático de IP para Cámara Reolink

## 📋 Descripción

Este sistema mantiene actualizado automáticamente el hostname de tu cámara Reolink en `/etc/hosts`, incluso si la IP cambia. Busca la cámara por su dirección MAC y actualiza la entrada DNS local.

**Perfecto para:**
- Routers que no permiten DHCP reservation
- Redes donde la cámara puede cambiar de IP
- Sistemas que necesitan conectarse siempre por hostname

## 🚀 Instalación Rápida

### Opción A: Instalación Automática (Recomendada)

```bash
# 1. Haz los scripts ejecutables
chmod +x actualizar_ip_camara.sh
chmod +x instalar_actualizador.sh

# 2. Ejecuta el instalador con sudo
sudo bash instalar_actualizador.sh
```

¡Listo! El sistema ya está funcionando.

### Opción B: Instalación Manual

```bash
# 1. Copiar el script al sistema
sudo cp actualizar_ip_camara.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/actualizar_ip_camara.sh

# 2. Crear archivo de log
sudo touch /var/log/camera_ip_update.log
sudo chmod 644 /var/log/camera_ip_update.log

# 3. Editar crontab de root
sudo crontab -e

# 4. Añadir estas líneas:
@reboot sleep 120 && /usr/local/bin/actualizar_ip_camara.sh
0 3 * * * /usr/local/bin/actualizar_ip_camara.sh
```

## ⚙️ Configuración

Edita el script para ajustarlo a tu red:

```bash
sudo nano /usr/local/bin/actualizar_ip_camara.sh
```

### Variables a configurar:

```bash
# MAC de tu cámara
CAMERA_MAC="ec:71:db:34:c6:2f"

# Hostname que quieres usar
CAMERA_HOSTNAME="thecornercancha1.local"

# Rango de tu red (ajusta según tu router)
NETWORK_RANGE="192.168.0.0/24"
# Para red 192.168.1.x usa: "192.168.1.0/24"
# Para red 10.0.0.x usa: "10.0.0.0/24"
```

### Cómo encontrar tu MAC (si no la tienes):

```bash
# Método 1: Si conoces la IP actual
ping 192.168.0.231
arp -n | grep 192.168.0.231

# Método 2: Escanear toda la red
sudo arp-scan --localnet | grep -i reolink

# Método 3: Desde la interfaz web
# Accede a http://[IP_CAMARA] → Settings → Network → MAC Address
```

## 📅 Programación (Crontab)

El script se ejecuta automáticamente:

### Configuración por defecto:

```bash
# Al reiniciar (espera 2 minutos)
@reboot sleep 120 && /usr/local/bin/actualizar_ip_camara.sh

# Diariamente a las 3:00 AM
0 3 * * * /usr/local/bin/actualizar_ip_camara.sh
```

### Otras opciones útiles:

```bash
# Cada 6 horas
0 */6 * * * /usr/local/bin/actualizar_ip_camara.sh

# Cada hora (útil para IPs muy dinámicas)
0 * * * * /usr/local/bin/actualizar_ip_camara.sh

# Cada 30 minutos
*/30 * * * * /usr/local/bin/actualizar_ip_camara.sh

# Al inicio y cada 12 horas
@reboot sleep 120 && /usr/local/bin/actualizar_ip_camara.sh
0 */12 * * * /usr/local/bin/actualizar_ip_camara.sh
```

### Editar programación:

```bash
sudo crontab -e
```

## 🔍 Monitoreo y Verificación

### Ver el log en tiempo real:

```bash
tail -f /var/log/camera_ip_update.log
```

### Ver últimas 20 líneas del log:

```bash
tail -20 /var/log/camera_ip_update.log
```

### Verificar contenido de /etc/hosts:

```bash
grep thecornercancha1 /etc/hosts
```

### Ver crontab activo:

```bash
sudo crontab -l
```

### Ejecutar manualmente (para probar):

```bash
sudo /usr/local/bin/actualizar_ip_camara.sh
```

## 🧪 Pruebas

### Después de instalar, prueba que funciona:

```bash
# 1. Ejecutar el script manualmente
sudo /usr/local/bin/actualizar_ip_camara.sh

# 2. Verificar que se añadió al /etc/hosts
cat /etc/hosts | grep thecornercancha1

# 3. Probar conectividad por hostname
ping thecornercancha1.local

# 4. Probar RTSP con hostname
ffprobe -rtsp_transport tcp "rtsp://admin:Pi.1415926535@thecornercancha1.local:554/h264Preview_01_main"

# O con VLC
vlc "rtsp://admin:Pi.1415926535@thecornercancha1.local:554/h264Preview_01_main"
```

## 🔧 Solución de Problemas

### Problema: Script no encuentra la cámara

**Síntomas en el log:**
```
ERROR: No se pudo encontrar la cámara con MAC ec:71:db:34:c6:2f
```

**Soluciones:**

1. Verifica que la cámara esté encendida y conectada:
   ```bash
   ping 192.168.0.231  # Usa la IP que creas que tiene
   ```

2. Verifica que la MAC sea correcta:
   ```bash
   sudo arp-scan --localnet
   # O
   arp -a
   ```

3. Ajusta el rango de red en el script:
   ```bash
   sudo nano /usr/local/bin/actualizar_ip_camara.sh
   # Cambia NETWORK_RANGE según tu red
   ```

### Problema: Script no se ejecuta automáticamente

**Verificar:**

1. Que crontab esté instalado:
   ```bash
   sudo crontab -l
   ```

2. Que el servicio cron esté corriendo:
   ```bash
   sudo systemctl status cron
   # O en sistemas más antiguos:
   sudo service cron status
   ```

3. Ver logs de cron:
   ```bash
   grep CRON /var/log/syslog
   ```

### Problema: Permiso denegado

**Solución:**
El script necesita ejecutarse como root para modificar `/etc/hosts`.

```bash
# Asegúrate de que el crontab sea del usuario root
sudo crontab -l

# Si lo pusiste en el crontab de usuario normal, muévelo:
crontab -l  # Copiar las líneas del actualizador
crontab -e  # Eliminar las líneas del actualizador
sudo crontab -e  # Pegar las líneas aquí
```

### Problema: /etc/hosts no se actualiza

**Verificar permisos:**
```bash
ls -la /etc/hosts
# Debe mostrar: -rw-r--r-- root root

# Si no:
sudo chmod 644 /etc/hosts
sudo chown root:root /etc/hosts
```

## 🔐 Seguridad

### Rotación de logs (opcional)

Si el log crece mucho, configura rotación:

```bash
sudo nano /etc/logrotate.d/camera-update
```

Contenido:
```
/var/log/camera_ip_update.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

## 🗑️ Desinstalación

```bash
# 1. Eliminar de crontab
sudo crontab -e
# Elimina las líneas del actualizador

# 2. Eliminar el script
sudo rm /usr/local/bin/actualizar_ip_camara.sh

# 3. Eliminar el log
sudo rm /var/log/camera_ip_update.log

# 4. Limpiar /etc/hosts (opcional)
sudo nano /etc/hosts
# Elimina la línea de thecornercancha1.local
```

## 📊 Ejemplo de Log Exitoso

```
[2026-02-06 08:00:01] =========================================
[2026-02-06 08:00:01] Iniciando actualización de IP de cámara
[2026-02-06 08:00:01] MAC buscada: ec:71:db:34:c6:2f
[2026-02-06 08:00:01] Hostname: thecornercancha1.local
[2026-02-06 08:00:01] ✓ Cámara encontrada: 192.168.0.231 (MAC: ec:71:db:34:c6:2f)
[2026-02-06 08:00:01] ✓ /etc/hosts ya está actualizado: 192.168.0.231 -> thecornercancha1.local
[2026-02-06 08:00:02] ✓ Verificación exitosa: thecornercancha1.local responde
[2026-02-06 08:00:02] ✓ URL RTSP: rtsp://admin:Pi.1415926535@thecornercancha1.local:554/h264Preview_01_main
[2026-02-06 08:00:02] Finalizado
[2026-02-06 08:00:02] =========================================
```

## 💡 Consejos Avanzados

### Múltiples cámaras

Para gestionar varias cámaras, crea múltiples copias del script:

```bash
sudo cp /usr/local/bin/actualizar_ip_camara.sh /usr/local/bin/actualizar_ip_camara2.sh
sudo nano /usr/local/bin/actualizar_ip_camara2.sh
# Cambia MAC y hostname

# Añade a crontab
sudo crontab -e
# Añadir líneas para el segundo script
```

### Notificaciones por email (opcional)

Modifica el script para enviar email si hay cambios:

```bash
# Al final del script, antes de exit 0:
if [ "$IP_CHANGED" = "true" ]; then
    echo "La IP de la cámara cambió a $CURRENT_IP" | mail -s "Cambio IP Cámara" tu@email.com
fi
```

### Integración con Home Assistant / Domoticz

El hostname se puede usar directamente en la configuración:

```yaml
# Home Assistant configuration.yaml
camera:
  - platform: generic
    name: Corner Cancha
    still_image_url: http://thecornercancha1.local/cgi-bin/api.cgi?cmd=Snap&channel=0
    stream_source: rtsp://admin:Pi.1415926535@thecornercancha1.local:554/h264Preview_01_main
```

## 📞 Soporte

Si tienes problemas:

1. **Revisa el log:** `tail -f /var/log/camera_ip_update.log`
2. **Ejecuta manualmente:** `sudo /usr/local/bin/actualizar_ip_camara.sh`
3. **Verifica crontab:** `sudo crontab -l`
4. **Comprueba la MAC:** `arp -a | grep -i ec:71:db:34:c6:2f`

## ✅ Checklist Post-Instalación

- [ ] Script instalado en `/usr/local/bin/`
- [ ] Permisos de ejecución configurados (chmod +x)
- [ ] MAC y hostname configurados correctamente en el script
- [ ] Crontab configurado (verificar con `sudo crontab -l`)
- [ ] Script ejecutado manualmente con éxito
- [ ] Entrada en `/etc/hosts` verificada
- [ ] Ping a hostname funciona
- [ ] RTSP con hostname funciona
- [ ] Log file creado y escribible

¡Tu sistema ahora es robusto contra cambios de IP! 🎉
