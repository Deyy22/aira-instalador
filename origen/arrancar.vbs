' arrancar.vbs — Lanza el agente y lo vigila.
'
' Hace dos cosas:
'
'   1. Lo arranca SIN ventana negra. Si se llamara a node.exe directamente,
'      al encender el PC se abriría una consola en medio de la pantalla y el
'      personal la cerraría pensando que sobra.
'
'   2. Lo vuelve a levantar si se cierra. Esto NO es un extra: el agente se
'      actualiza solo, y para hacerlo se cierra a propósito esperando que
'      alguien lo reinicie. Sin este bucle, cada actualización dejaría al
'      local sin imprimir hasta que reiniciaran el ordenador a mano.
'
' Se lanza desde el acceso directo que el instalador deja en la carpeta de
' Inicio de Windows, así que arranca solo al encender.

Option Explicit

Dim sh, fso, carpeta, comando, esperaSeg

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

carpeta = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = carpeta

comando = """" & carpeta & "\node.exe"" """ & carpeta & "\agente.js"""

Do
  ' El 0 lo mantiene invisible. El True hace que esperemos a que termine:
  ' así sabemos cuándo se ha cerrado y podemos volver a levantarlo.
  sh.Run comando, 0, True

  ' Una pausa antes de reintentar. Si el agente estuviera roto y saliera al
  ' instante, sin esto tendríamos un bucle a toda velocidad comiéndose el PC.
  WScript.Sleep 5000
Loop
