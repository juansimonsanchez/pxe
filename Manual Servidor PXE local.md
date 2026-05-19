# **Manual de Uso: Servidor de Clonación PXE Clonezilla para Aulas (openSUSE)**

Este manual explica detalladamente el funcionamiento del script setup\_pxe.sh y cómo implementarlo en el **ordenador del profesor** para automatizar la clonación, copia de seguridad y restauración de los ordenadores de los alumnos a través de la red local (PXE).

## **1\. ¿Qué hace exactamente este script?**

El script convierte el ordenador del profesor en un **Servidor de Arranque por Red (PXE)** de alto rendimiento optimizado para aulas de informática. En lugar de instalar servicios complejos directamente en el sistema operativo del profesor, el script utiliza **Docker** para encapsular de forma limpia y aislada todo lo necesario.

A nivel técnico, el script realiza los siguientes procesos estructurados:

                   
             ORDENADOR DEL PROFESOR (SERVIDOR)          

                                                  │  
 │  │     SAMBA          │ │       NGINX           │ │  DNSMASQ   │  │  
 │  │  (Almacén de   │ │ (Servidor Web   │ │  (Proxy            │  │  
 │  │   Imágenes)      │ │ para SquashFS) │ │   DHCP)          │  │  
    │ (CIFS / Samba)      │ (HTTP)                    │ (PXE Boot)  
                             ▼                  ▼                ▼  
                   
             │                  RED LOCAL DEL AULA                    │  
                   
                                                │  
                                                ▼

                        │  PC ALUMNO (CLIENTE)    │

### **A. Detección Inteligente de Red**

* Obtiene automáticamente la dirección IP del profesor (SERVER\_IP) y la interfaz física de red por cable (SERVER\_IFACE).  
* Calcula el rango de subred (NETWORK\_PREFIX). Esto es vital para que los servicios de red respondan únicamente a la red de tu aula.

### **B. Apertura Segura del Cortafuegos (firewalld)**

* Detecta si el cortafuegos de openSUSE está activo.  
* Abre los puertos necesarios para la transferencia de archivos y el protocolo PXE de forma persistente:  
  * **Puerto 67 y 69 (UDP):** Para peticiones DHCP y descarga TFTP de cargadores de arranque.  
  * **Puerto 4011 (UDP):** Puerto reservado para el Proxy DHCP (crucial para no interferir en la red del centro).  
  * **Puerto 8090 (TCP):** Servidor HTTP para la transferencia a alta velocidad del sistema operativo Clonezilla.  
  * **Servicio Samba:** Permite el tráfico para leer/escribir las imágenes de disco guardadas.

### **C. Descarga de Cargadores de Red (Dual BIOS / UEFI)**

* Prepara el entorno para que sea compatible tanto con ordenadores antiguos como modernos:  
  * **Equipos BIOS tradicionales:** Descarga pxelinux.0 y sus librerías de soporte.  
  * **Equipos UEFI modernos:** Descarga ipxe.efi (compilado por el proyecto FOG), que permite configurar menús de red visuales y avanzados.

### **D. Descarga y Despiece de Clonezilla Live**

* Descarga el archivo comprimido oficial de Clonezilla.  
* Realiza un test de integridad para comprobar que no se haya corrompido durante la descarga.  
* Extrae únicamente los componentes esenciales para el arranque por red:  
  * vmlinuz (Kernel de Linux).  
  * initrd.img (Imagen de disco en memoria inicial).  
  * filesystem.squashfs (El sistema de archivos completo de Clonezilla).

### **E. Generación de Menús de Arranque Dinámicos**

Crea los archivos de menú tanto para terminales tradicionales como para los de interfaz gráfica (iPXE) con tres opciones preconfiguradas:

1. **Clonezilla Manual:** Inicia Clonezilla para que el usuario elija paso a paso qué hacer.  
2. **Restaurar Aula (Automático):** Se conecta por red al ordenador del profesor, monta el almacén de imágenes e intenta restaurar una imagen llamada **"aula"** de manera automatizada.  
3. **Guardar Aula (Automático):** Captura el estado actual del ordenador del alumno y lo sube al servidor del profesor guardándolo como la imagen **"aula"**.

### **F. Configuración del Servidor PXE (Dnsmasq en modo Proxy)**

* **¿Por qué modo Proxy?** Esta es la mejor decisión para un aula. En tu centro educativo ya existe un router o servidor DHCP general que asigna IPs a los ordenadores. Si pusieras otro servidor DHCP normal, causarías un conflicto masivo de IPs en el instituto.  
* El **Proxy DHCP** no asigna direcciones IP; simplemente "escucha" la red y, cuando detecta que un equipo arranca por red (PXE), le susurra al oído: *"Toma, yo tengo los archivos de arranque para que puedas iniciar el sistema"*.

### **G. Despliegue con Docker Compose**

Lanza tres contenedores ligeros:

1. **pxe-dnsmasq:** Gestiona el Proxy DHCP y sirve los primeros archivos de arranque ligeros por TFTP.  
2. **pxe-http (Nginx):** Sirve el archivo pesado de Clonezilla (filesystem.squashfs) por protocolo web HTTP (hasta 10 veces más rápido que TFTP).  
3. **pxe-samba:** Crea una carpeta compartida segura en la red del aula (//IP\_PROFESOR/images) para guardar y leer los backups de los sistemas operativos.

## **2\. Preparación previa en el ordenador del Profesor**

Antes de ejecutar el script en el equipo con **openSUSE**, asegúrate de cumplir con los siguientes requisitos:

1. **Instalar Docker y Docker Compose:**  
   Abre una terminal en openSUSE e instala los servicios necesarios:  
   sudo zypper in docker docker-compose

   Habilita y arranca el motor de Docker:  
   sudo systemctl enable \--now docker

   *(Opcional)* Añade tu usuario al grupo de Docker para no requerir sudo en comandos comunes de contenedores (aunque el script de instalación requiere sudo igualmente por los cambios de red):  
   sudo usermod \-aG docker $USER

2. **Conexión por Cable:** El ordenador del profesor **debe estar conectado por cable ethernet** a la misma red (o switch) que los equipos de los alumnos. El protocolo PXE no funciona a través de redes Wi-Fi.

## **3\. Guía de Ejecución y Puesta en Marcha**

Sigue estos pasos para arrancar el servidor de clonación:

### **Paso 1: Crear el script en el ordenador del profesor**

Crea una carpeta de trabajo ordenada y crea el archivo:

mkdir \-p \~/ServidorClonacion  
cd \~/ServidorClonacion  
nano setup\_pxe.sh

Pega dentro el contenido del script setup\_pxe.sh y guárdalo (Ctrl \+ O, Enter, Ctrl \+ X).

### **Paso 2: Ejecutar el script instalador**

Otorga permisos de ejecución al script y lánzalo como superusuario:

chmod \+x setup\_pxe.sh  
sudo ./setup\_pxe.sh

El script empezará a trabajar. Verás en pantalla cómo detecta tu IP de profesor, configura tu cortafuegos, descarga Clonezilla, crea las estructuras de datos y genera los archivos de Docker Compose.

### **Paso 3: Levantar el servidor**

Una vez finalizado el script con éxito, levanta los contenedores ejecutando en esa misma carpeta:

sudo docker-compose up \-d

Puedes comprobar que los tres contenedores están corriendo de manera estable con:

sudo docker ps

## **4\. Estructura de Carpetas Generada**

El script habrá creado la siguiente estructura en el directorio donde lo ejecutaste:

* **tftp/:** Contiene los cargadores de arranque básicos (pxelinux.0, ipxe.efi) y el Kernel de Linux (vmlinuz, initrd.img).  
* **www/:** Almacena los archivos que se descargarán vía web por HTTP, principalmente el sistema de archivos completo de Clonezilla (filesystem.squashfs) y el menú dinámico iPXE.  
* **images/:** **¡Esta es la carpeta más importante\!** Aquí es donde se guardarán las imágenes de tus aulas.  
  * *Nota:* Cuando hagas la copia de seguridad de un aula, Clonezilla creará aquí una carpeta llamada aula/.  
* **config/:** Archivo de configuración interno de dnsmasq.

## **5\. Cómo utilizar el sistema para clonar tus aulas**

Una vez que el servidor está encendido en el ordenador del profesor, puedes empezar a trabajar con los ordenadores de los alumnos:

### **Procedimiento A: Crear la imagen patrón (Copia de Seguridad)**

Para guardar el estado del ordenador de un alumno (que ya tiene todos los programas, configuraciones y actualizaciones listas) y usarlo como plantilla:

1. Enciende el ordenador del alumno "modelo".  
2. Entra en el menú de arranque de la placa (suele ser F12, F11 o F8 dependiendo del fabricante) o accede a la BIOS y activa la opción **Network Boot / PXE Boot**.  
3. El PC del alumno detectará el servidor del profesor y verás aparecer en pantalla el menú azul de **Servidor de Clonación \- Aula PRO**.  
4. Selecciona la opción **\[S\] Crear/Guardar Imagen de Aula**.  
5. El proceso se ejecutará de forma automática. Te preguntará en qué disco local se encuentra el sistema operativo del alumno y, tras confirmar, transmitirá todos los datos al ordenador del profesor. La copia se guardará en la carpeta ./images/aula/ del profesor.

### **Procedimiento B: Restauración masiva de los alumnos (Despliegue)**

Cuando quieras restaurar toda la clase (por ejemplo, al principio de un trimestre o si algún alumno ha desconfigurado su ordenador):

1. Enciende los equipos de los alumnos y hazlos arrancar por red (PXE).  
2. En el menú de red que aparece en cada pantalla, selecciona la opción **\[R\] Restaurar Imagen de Aula**.  
3. El sistema se conectará silenciosamente al ordenador del profesor, montará de forma invisible la carpeta compartida por Samba, leerá la imagen del sistema y la grabará en los discos locales de los alumnos.  
4. Al terminar el proceso, el script de Clonezilla está configurado para apagar automáticamente el equipo del alumno (-p poweroff), lo que te confirmará visualmente que la restauración ha concluido con éxito.

## **6\. Consejos y Mantenimiento del Servidor**

* **Detener el servidor temporalmente:** Si no vas a clonar y quieres liberar recursos en el PC del profesor, puedes apagar los servicios de red con:  
  sudo docker-compose down

* **Ver logs en tiempo real:** Si algún equipo de un alumno tiene problemas para conectar, puedes ver qué está ocurriendo en el servidor con:  
  sudo docker logs \-f pxe-dnsmasq

* **Permisos de imágenes:** Si decides copiar manualmente imágenes de Clonezilla que ya tuvieras guardadas de años anteriores a la carpeta ./images/, asegúrate de que tengan permisos de lectura y escritura para que el contenedor Samba pueda leerlas sin problemas:  
  sudo chmod \-R 777 \~/ServidorClonacion/images  
