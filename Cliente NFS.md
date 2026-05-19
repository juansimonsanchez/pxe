# **Manual de Uso: Script de Automatización de Cliente NFS en openSUSE**

Este manual detalla el funcionamiento del script diseñado para configurar de manera automatizada y segura un cliente NFS en sistemas **openSUSE** (tanto Leap como Tumbleweed).

## **1\. ¿Qué hace exactamente el script?**

El script automatiza los pasos manuales de configuración del protocolo de red NFS, estructurándose en cinco fases principales:

### **Fase 1: Control de Privilegios**

* Comprueba si el usuario tiene privilegios de superusuario (root). Como se realizan tareas de administración como instalar paquetes, crear directorios del sistema y modificar archivos de montaje, el script detiene la ejecución inmediatamente si no se inicia con sudo.

### **Fase 2: Instalación de Dependencias (zypper)**

* Llama al gestor de paquetes de openSUSE (zypper in \-y nfs-client) para instalar las herramientas necesarias del cliente NFS de forma no interactiva (gracias al parámetro \-y).

### **Fase 3: Creación del Punto de Montaje Local**

* Genera la carpeta local especificada mediante el comando mkdir \-p. El modificador \-p asegura que si la ruta contiene subcarpetas intermedias que no existen, estas se creen automáticamente sin lanzar errores.

### **Fase 4: Prueba de Conexión en Caliente**

* Intenta realizar un montaje temporal del recurso compartido usando: mount \-t nfs \-o timeo=50,retrans=2 "$SERVIDOR\_IP:$CARPETA\_REMOTA" "$PUNTO\_MONTAJE\_LOCAL"  
  * timeo=50: Establece un límite de tiempo de espera de 5 segundos (50 décimas de segundo) para evitar que el script se quede colgado indefinidamente si el servidor está apagado.  
  * retrans=2: Limita el número de reintentos de conexión a 2\.  
* **Control de Errores ($?):** Si el comando falla (código de salida diferente de 0), el script se detiene, informa al usuario del problema y evita escribir una configuración rota en el sistema.

### **Fase 5: Configuración Persistente y Segura en /etc/fstab**

* **Protección contra duplicados:** Antes de escribir en el archivo de configuración de discos del sistema (/etc/fstab), utiliza grep para verificar si ya existe una regla apuntando a esa misma carpeta. Si existe, omite la escritura para no corromper el archivo.  
* **Backup de seguridad:** Crea un respaldo en /etc/fstab.bak antes de modificar nada.  
* **Parámetros de montaje avanzados:**  
  * nofail: Evita que tu sistema se quede congelado en la pantalla de carga durante el arranque si el servidor NFS no está disponible en la red.  
  * x-systemd.automount: Crea una unidad de montaje dinámico. El recurso solo se conectará en el instante preciso en el que un usuario o aplicación intente acceder a la carpeta, optimizando el rendimiento de tu sistema.

### **Fase 6: Aplicación de cambios sin reiniciar**

* Ejecuta systemctl daemon-reload para que Systemd detecte la nueva regla y monta inmediatamente el recurso con mount \-a.

## **2\. Cómo utilizar el script paso a paso**

Sigue estos sencillos pasos para implementar la automatización en tu sistema:

### **Paso 1: Crear el archivo del script**

Abre tu terminal y crea un nuevo archivo con tu editor preferido (por ejemplo, nano):

nano nfs\_client.sh

Copia el código del script provisto anteriormente y pégalo dentro del archivo.

### **Paso 2: Personalizar las variables**

En la parte superior del archivo, busca el bloque de configuración y edita los valores para que coincidan con tu infraestructura:

\# \=====================================================================  
\# CONFIGURACIÓN DE PARÁMETROS (Modifica estos valores)  
\# \=====================================================================  
SERVIDOR\_IP="192.168.1.50"          \# \<-- Pon aquí la IP del servidor NFS  
CARPETA\_REMOTA="/srv/nfs/compartido" \# \<-- La ruta de la carpeta en el servidor  
PUNTO\_MONTAJE\_LOCAL="/mnt/servidor"  \# \<-- La ruta local donde quieres ver los datos  
\# \=====================================================================

Guarda los cambios pulsando Ctrl \+ O, luego pulsa Enter para confirmar y sal con Ctrl \+ X.

### **Paso 3: Asignar permisos de ejecución**

Para que el sistema permita ejecutar el script como si fuera una aplicación, debes darle permisos de ejecución ejecutando:

chmod \+x nfs\_client.sh

### **Paso 4: Ejecutar la automatización**

Finalmente, lanza el script haciendo uso de los privilegios sudo:

sudo ./nfs\_client.sh

## **3\. Verificación de que todo funciona correctamente**

Una vez finalizado el script sin errores, puedes verificar de dos formas que el recurso está correctamente conectado a tu openSUSE:

1. **Vía terminal:** Ejecuta el siguiente comando para ver los discos y recursos montados en el sistema:  
   df \-h | grep nfs

   Deberías ver una línea reflejando la IP del servidor, la carpeta remota y el espacio disponible.  
2. **Vía gestor de archivos:** Abre el explorador de archivos de tu entorno de escritorio (Dolphin en KDE, Nautilus en GNOME) y dirígete a la ruta local que configuraste (por ejemplo, /mnt/servidor). Deberías poder leer y escribir archivos con total normalidad.