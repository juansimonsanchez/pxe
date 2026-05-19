#!/bin/bash

# =====================================================================
# CONFIGURACIÓN DE PARÁMETROS (Modifica estos valores)
# =====================================================================
SERVIDOR_IP="192.168.5.1"
CARPETA_REMOTA="/home/partimag"
PUNTO_MONTAJE_LOCAL="/mnt/servidor"
# =====================================================================

# Asegurar que el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usando sudo)."
  exit 1
fi

echo "[+] 1. Instalando el cliente NFS en openSUSE..."
zypper in -y nfs-client

echo "[+] 2. Creando el punto de montaje local en $PUNTO_MONTAJE_LOCAL..."
mkdir -p "$PUNTO_MONTAJE_LOCAL"

echo "[+] 3. Probando conexión temporal con el servidor..."
mount -t nfs -o timeo=50,retrans=2 "$SERVIDOR_IP:$CARPETA_REMOTA" "$PUNTO_MONTAJE_LOCAL"

if [ $? -eq 0 ]; then
    echo "[+] ¡Conexión temporal exitosa! El servidor responde correctamente."
    # Desmontamos para hacer la configuración limpia en fstab
    umount "$PUNTO_MONTAJE_LOCAL"
else
    echo "[-] Error: No se pudo conectar al servidor NFS."
    echo "    Verifica la IP, que el servidor esté encendido y que el firewall permita el tráfico."
    exit 1
fi

echo "[+] 4. Configurando montaje permanente en /etc/fstab..."
LINEA_FSTAB="$SERVIDOR_IP:$CARPETA_REMOTA  $PUNTO_MONTAJE_LOCAL  nfs  defaults,nofail,x-systemd.automount  0  0"

# Comprobar si ya existe una regla para este punto de montaje en fstab
if grep -q "$PUNTO_MONTAJE_LOCAL" /etc/fstab; then
    echo "[!] Advertencia: Ya existe una regla en /etc/fstab para $PUNTO_MONTAJE_LOCAL."
    echo "    No se ha modificado el archivo para evitar duplicados."
else
    # Hacer una copia de seguridad de fstab por si acaso
    cp /etc/fstab /etc/fstab.bak
    echo "$LINEA_FSTAB" >> /etc/fstab
    echo "[+] Configuración añadida a /etc/fstab exitosamente (Copia de seguridad guardada en /etc/fstab.bak)."
fi

echo "[+] 5. Aplicando los cambios..."
systemctl daemon-reload
mount -a

echo "[+] ¡Proceso completado! La carpeta NFS ya está lista en: $PUNTO_MONTAJE_LOCAL"
