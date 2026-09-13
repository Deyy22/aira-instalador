# Instalador del agente de Aira

El programa que se envía a un local nuevo para que empiece a imprimir tickets.
Lo descargan desde **airareservas.es/descargar**, lo abren, teclean un código
de alta y ya está.

El `.exe` no vive en este repositorio: está en las
[Releases](../../releases). Aquí solo está el código con el que se construye.

## Qué hace al instalarse

1. Copia su propio Node, el agente y las librerías a `%LOCALAPPDATA%\Aira`
2. Pide el **código de alta** (8 caracteres, caduca a los 15 minutos)
3. Lo canjea por la llave del local — la llave nunca viaja por mensajes
4. Busca la impresora en la red por el puerto 9100 y saca un papel de prueba
5. Deja un acceso directo en la carpeta de Inicio para que arranque solo

No pide permisos de administrador y no abre ninguna ventana al funcionar.

## Por qué está montado así

**Se instala en AppData, no en Archivos de programa.** El agente se actualiza
solo reescribiendo su propio `agente.js`. En Archivos de programa Windows no
le dejaría escribir sin permisos de administrador y la autoactualización
moriría en todos los locales.

**El arranque es un acceso directo en Inicio, no una tarea programada.**
`schtasks` obliga a anidar comillas dentro del parámetro `/TR` y eso se rompe
en cuanto la ruta del usuario lleva un espacio. El acceso directo no tiene ese
problema y además se ve en la pestaña "Inicio" del Administrador de tareas.

**`arrancar.vbs` no solo lanza: vigila.** Si el agente se cierra, lo vuelve a
levantar. No es un extra: el agente se cierra *a propósito* cada vez que se
actualiza, esperando que alguien lo reinicie. Sin ese bucle, cada
actualización dejaría al local sin imprimir hasta reiniciar el ordenador.

**`resultado.json` se escribe en latin1 y no en UTF-8.** Lo lee el instalador
de Inno Setup, cuyo lenguaje no sabe convertir UTF-8, y si no los acentos de
"Sidrería" salen rotos en el mensaje final.

## Construirlo

Hace falta [Inno Setup 6](https://jrsoftware.org/isinfo.php) y Node.

```bash
# 1. Traer el motor de Node y las librerías (no están en git)
copy "C:\Program Files\nodejs\node.exe" origen\node.exe
cd origen && npm install && cd ..

# 2. Traer la versión del agente que se quiere empaquetar
copy ..\reservas-gijon\public\agente\2.1.2.js origen\agente.js

# 3. Compilar
"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" AiraAgente.iss
```

Sale en `salida\AiraAgente-Setup.exe`, unos 27 MB.

## Publicar una versión

```bash
gh release create v1.0.1 --repo Deyy22/aira-instalador \
  --title "Instalador v1.0.1" --notes "qué cambia" \
  "salida\AiraAgente-Setup.exe"
```

El archivo **tiene que llamarse `AiraAgente-Setup.exe`**: la redirección de
`airareservas.es/descargar/agente` apunta a ese nombre exacto dentro de la
última Release. Si cambia el nombre, el enlace de descarga deja de funcionar.

## Probarlo sin tocar pantallas

```bash
AiraAgente-Setup.exe /SILENT /CODIGO=K7M29PXQ /LOG="%TEMP%\aira.log"
```

Genera el código antes desde Aira Admin. Ojo: **el canje crea un agente de
verdad en la base**, así que después hay que borrarlo.
