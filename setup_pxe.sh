#!/bin/bash

set -e

########################################
# CONFIGURACIÓN
########################################

CLONEZILLA_VERSION="3.1.2-22"
CLONEZILLA_ZIP="clonezilla.zip"
HTTP_PORT="8090"

# Credenciales para el almacén de imágenes (Samba)
SAMBA_USER="profesor"
SAMBA_PASS="aula123"

########################################
# DETECCIÓN DE RED (Optimizado con awk)
########################################

echo "======================================"
echo " Clonezilla iPXE Proxy - openSUSE Ed."
echo "======================================"

echo "--> Detectando configuración de red por cable..."

SERVER_IP=$(ip route get 1 | awk '{print $7; exit}')
SERVER_IFACE=$(ip route get 1 | awk '{print $5; exit}')

if [ -z "$SERVER_IP" ] || [ -z "$SERVER_IFACE" ]; then
    echo "[-] ERROR: No se pudo detectar la interfaz o la IP local. ¿Está el cable conectado?"
    exit 1
fi

# Formato limpio para el prefijo de red utilizando la IP real del servidor
NETWORK_PREFIX=$(echo "$SERVER_IP" | awk -F. '{print $1"."$2"."$3}')

echo "[+] IP Servidor : $SERVER_IP"
echo "[+] Interfaz    : $SERVER_IFACE"
echo "[+] Red Base    : ${NETWORK_PREFIX}.0/24"
echo "[+] Puerto HTTP : $HTTP_PORT"

########################################
# CONFIGURACIÓN DEL CORTAFUEGOS (openSUSE)
########################################

echo ""
echo "--> Configurando el cortafuegos (firewalld)..."
if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
    echo "[+] firewalld detectado activo. Abriendo puertos para el Aula..."
    
    sudo firewall-cmd --zone=public --add-port=67/udp --permanent
    sudo firewall-cmd --zone=public --add-port=69/udp --permanent
    sudo firewall-cmd --zone=public --add-port=4011/udp --permanent
    sudo firewall-cmd --zone=public --add-service=samba --permanent
    sudo firewall-cmd --zone=public --add-port=${HTTP_PORT}/tcp --permanent
    
    echo "--> Aplicando cambios en firewalld..."
    sudo firewall-cmd --reload
    echo "[+] Cortafuegos actualizado correctamente con soporte Proxy DHCP (Puerto 4011)."
else
    echo "[!] AVISO: firewalld no está activo. Asegúrate de liberar los puertos manualmente si usas otro cortafuegos."
fi

########################################
# CREACIÓN DE ESTRUCTURA
########################################

echo ""
echo "--> Creando la estructura de directorios..."
mkdir -p tftp
mkdir -p www
mkdir -p images
mkdir -p config
mkdir -p tmp_extract

echo "--> Otorgando permisos a ./images y ./www..."
chmod 777 images
sudo chmod -R 755 www/
echo "[+] Estructura local lista."

########################################
# CARGADORES iPXE (Descarga Segura y Estable)
########################################

echo ""
echo "--> Descargando cargadores de arranque (PXELinux y FOG iPXE)..."

echo "    [1/2] Descargando pxelinux.0 (Equipos BIOS) para evitar fallos STP..."
wget --quiet --show-progress -O tftp/pxelinux.0 http://archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/pxelinux.0
wget --quiet --show-progress -O tftp/ldlinux.c32 http://archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/ldlinux.c32

echo "    [2/2] Descargando ipxe.efi (Equipos UEFI x86_64)..."
wget --quiet --show-progress -O tftp/ipxe.efi https://github.com/FOGProject/fogproject/raw/master/packages/tftp/ipxe.efi || echo "[!] Falló la descarga de ipxe.efi"

if [ ! -s "tftp/pxelinux.0" ] || [ ! -s "tftp/ldlinux.c32" ]; then
    echo "[-] ERROR CRÍTICO: No se pudo obtener PXELinux de Ubuntu Archive."
    exit 1
fi

echo "[+] Cargadores de red PXE preparados en ./tftp/"

########################################
# DESCARGAR Y EXTRAER CLONEZILLA (Anti-corrupción)
########################################

URL="https://downloads.sourceforge.net/project/clonezilla/clonezilla_live_stable/$CLONEZILLA_VERSION/clonezilla-live-$CLONEZILLA_VERSION-amd64.zip"

echo ""
echo "--> Comprobando archivo de Clonezilla..."
# Verificamos si existe el archivo y si pasa el test de integridad ZIP completo
if [ -f "$CLONEZILLA_ZIP" ] && unzip -t "$CLONEZILLA_ZIP" >/dev/null 2>&1; then
    echo "[+] Clonezilla ya se encuentra descargado e íntegro ($CLONEZILLA_ZIP). Saltando descarga."
else
    if [ -f "$CLONEZILLA_ZIP" ]; then
        echo "[!] El archivo Clonezilla local está incompleto o corrupto. Eliminando para redescargar..."
        rm -f "$CLONEZILLA_ZIP"
    fi
    echo "[!] Descargando ZIP oficial de Clonezilla (~400MB)..."
    wget --quiet --show-progress -O "$CLONEZILLA_ZIP" -L "$URL"
    echo "[+] Descarga de Clonezilla finalizada."
fi

echo ""
echo "--> Extrayendo archivos del sistema Clonezilla..."
unzip -q -o "$CLONEZILLA_ZIP" -d tmp_extract

echo "--> Trasladando el Kernel y Sistema de Archivos a sus destinos..."
cp -f tmp_extract/live/vmlinuz tftp/
cp -f tmp_extract/live/initrd.img tftp/

cp -f tmp_extract/live/vmlinuz www/
cp -f tmp_extract/live/initrd.img www/

cp -f tmp_extract/live/filesystem.squashfs www/

echo "--> Limpiando el directorio temporal..."
rm -rf tmp_extract
echo "[+] Archivos de Clonezilla listos."

echo ""
echo "--> Generando menú dinámico PXELinux (tftp/pxelinux.cfg/default) y FOG UEFI..."

mkdir -p tftp/pxelinux.cfg

cat <<EOF > tftp/boot.txt
======================================
 Clonezilla PXE Boot - Aula PRO
======================================

Opciones disponibles:
  - clonezilla    (Modo manual, por defecto)
  - restore_auto  (Restaurar imagen auto)
  - save_auto     (Crear imagen auto)

Escribe una opcion y presiona Enter, o espera 10s.
boot: 
EOF

cat <<EOF > tftp/pxelinux.cfg/default
DEFAULT clonezilla
TIMEOUT 100
PROMPT 1
DISPLAY boot.txt

LABEL clonezilla
    KERNEL vmlinuz
    APPEND initrd=initrd.img boot=live components config union=overlay net.ifnames=0 biosdevname=0 fetch=http://$SERVER_IP:$HTTP_PORT/filesystem.squashfs
    IPAPPEND 1

LABEL restore_auto
    KERNEL vmlinuz
    APPEND initrd=initrd.img boot=live components config union=overlay net.ifnames=0 biosdevname=0 fetch=http://$SERVER_IP:$HTTP_PORT/filesystem.squashfs ocs_prerun="mount -t cifs -o username=$SAMBA_USER,password=$SAMBA_PASS,vers=3.0,sec=ntlmssp //$SERVER_IP/images /home/partimag" ocs_live_run="ocs-sr -e1 auto -e2 -r -j2 -p poweroff restoredisk aula ask_user"
    IPAPPEND 1

LABEL save_auto
    KERNEL vmlinuz
    APPEND initrd=initrd.img boot=live components config union=overlay net.ifnames=0 biosdevname=0 fetch=http://$SERVER_IP:$HTTP_PORT/filesystem.squashfs ocs_prerun="mount -t cifs -o username=$SAMBA_USER,password=$SAMBA_PASS,vers=3.0,sec=ntlmssp //$SERVER_IP/images /home/partimag" ocs_live_run="ocs-sr -q2 -j2 -z1p -i 2000 savedisk aula ask_user"
    IPAPPEND 1
EOF

# Y para los equipos UEFI que sigan usando el binario FOG:
cat <<EOF > tftp/default.ipxe
#!ipxe
chain http://$SERVER_IP:$HTTP_PORT/boot.ipxe
EOF

cat <<EOF > www/boot.ipxe
#!ipxe

cpair --foreground 7 --background 4 0
cpair --foreground 2 1

:start
menu Servidor de Clonacion - Aula PRO
item --key c clonezilla      [C] Iniciar Clonezilla Live (Manual)
item --key r restore_auto    [R] Restaurar Imagen de Aula (Preguntar Disco)
item --key s save_auto       [S] Crear/Guardar Imagen de Aula (Preguntar Disco)
choose --default clonezilla --timeout 10000 target && goto \${target}

:clonezilla
kernel http://$SERVER_IP:$HTTP_PORT/vmlinuz boot=live components config union=overlay net.ifnames=0 biosdevname=0 nomodeset vga=normal debug=1 fetch=http://$SERVER_IP:$HTTP_PORT/filesystem.squashfs
initrd http://$SERVER_IP:$HTTP_PORT/initrd.img
boot

:restore_auto
kernel http://$SERVER_IP:$HTTP_PORT/vmlinuz boot=live components config union=overlay net.ifnames=0 biosdevname=0 fetch=http://$SERVER_IP:$HTTP_PORT/filesystem.squashfs ocs_prerun="mount -t cifs -o username=$SAMBA_USER,password=$SAMBA_PASS,vers=3.0,sec=ntlmssp //$SERVER_IP/images /home/partimag" ocs_live_run="ocs-sr -e1 auto -e2 -r -j2 -p poweroff restoredisk aula ask_user"
initrd http://$SERVER_IP:$HTTP_PORT/initrd.img
boot

:save_auto
kernel http://$SERVER_IP:$HTTP_PORT/vmlinuz boot=live components config union=overlay net.ifnames=0 biosdevname=0 fetch=http://$SERVER_IP:$HTTP_PORT/filesystem.squashfs ocs_prerun="mount -t cifs -o username=$SAMBA_USER,password=$SAMBA_PASS,vers=3.0,sec=ntlmssp //$SERVER_IP/images /home/partimag" ocs_live_run="ocs-sr -q2 -j2 -z1p -i 2000 savedisk aula ask_user"
initrd http://$SERVER_IP:$HTTP_PORT/initrd.img
boot
EOF

echo "[+] Menús de PXELinux e iPXE generados correctamente."

########################################
# CONFIGURACIÓN DNSMASQ (PROXY DHCP TOTAL)
########################################

echo ""
echo "--> Escribiendo configuración para Proxy DHCP (config/dnsmasq.conf)..."

cat <<EOF > config/dnsmasq.conf
user=root
port=0
log-dhcp
interface=$SERVER_IFACE

# Modo PROXY global: Responde a peticiones PXE inyectando las opciones necesarias
dhcp-range=${NETWORK_PREFIX}.0,proxy,255.255.255.0

# Servicios PXE para clientes de hardware (descarga TFTP)
# FOG iPXE binarios ignorarán las opciones DHCP secundarias y cargarán default.ipxe
pxe-service=x86PC, "BIOS PXE Boot", pxelinux.0
pxe-service=X86-64_EFI, "UEFI PXE Boot", ipxe.efi
pxe-service=BC_EFI, "UEFI PXE Boot", ipxe.efi

enable-tftp
tftp-root=/tftp
EOF
echo "[+] Configuración de dnsmasq guardada."

########################################
# ARCHIVO DOCKER COMPOSE (CON PRIVILEGIOS)
########################################

echo ""
echo "--> Generando manifiesto docker-compose.yml..."

cat <<EOF > docker-compose.yml
services:
  pxe-proxy:
    image: jpillora/dnsmasq
    container_name: pxe-dnsmasq
    entrypoint: ["dnsmasq", "--no-daemon"]
    network_mode: host
    privileged: true
    cap_add:
      - NET_ADMIN
    volumes:
      - ./config/dnsmasq.conf:/etc/dnsmasq.conf
      - ./tftp:/tftp
    restart: unless-stopped

  web-server:
    image: nginx:alpine
    container_name: pxe-http
    ports:
      - "$HTTP_PORT:80"
    volumes:
      - ./www:/usr/share/nginx/html
    restart: unless-stopped

  samba-share:
    image: dperson/samba
    container_name: pxe-samba
    environment:
      - USERID=0
      - GROUPID=0
    ports:
      - "139:139"
      - "445:445"
    volumes:
      - ./images:/mnt/images
    command: -u "$SAMBA_USER;$SAMBA_PASS" -s "images;/mnt/images;yes;no;no;$SAMBA_USER"
    restart: unless-stopped
EOF
echo "[+] Manifiesto docker-compose.yml creado."

########################################
# COMPLETADO
########################################

echo ""
echo "=========================================================="
echo "     ¡SERVIDOR PROXY iPXE INSTALADO Y OPTIMIZADO!         "
echo "=========================================================="
echo "[*] IP del Servidor : $SERVER_IP"
echo "[*] Interfaz Usada  : $SERVER_IFACE"
echo "[*] Almacén Samba   : //$SERVER_IP/images"
echo "[*] Credenciales    : Usuario: $SAMBA_USER | Clave: $SAMBA_PASS"
echo "----------------------------------------------------------"
echo "--> Para levantar la infraestructura limpia ahora mismo:"
echo "    docker compose down && docker compose up -d"
echo "=========================================================="
