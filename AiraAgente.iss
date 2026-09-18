; ============================================================================
;  AIRA · Instalador del agente de impresion
;
;  Compilar con:
;    "C:\Users\Deyvi\AppData\Local\Programs\Inno Setup 6\ISCC.exe" AiraAgente.iss
;  Sale en  salida\AiraAgente-Setup.exe
;
;  POR QUE SE INSTALA EN AppData Y NO EN "Archivos de programa":
;    El agente se actualiza solo reescribiendo su propio agente.js. En
;    Archivos de programa Windows no le deja escribir sin permisos de
;    administrador, asi que la autoactualizacion moriria en todos los locales.
;    En AppData escribe sin problemas, y ademas el instalador NO pide permisos
;    de administrador: el duenio del bar hace doble clic y ya.
;
;  QUE INSTALA:
;    node.exe        el motor, para no depender de que el PC tenga Node
;    agente.js       el agente (se actualiza solo despues)
;    configurar.js   el asistente de alta: canjea el codigo y busca la impresora
;    arrancar.vbs    lo lanza sin ventana negra
;    node_modules\   las tres librerias que necesita
; ============================================================================

#define Nombre      "Aira · Agente de impresion"
#define Version     "1.1.0"
#define Publicador  "Aira"
#define Web         "https://airareservas.es"
#define Tarea       "Aira agente de impresion"

[Setup]
AppId={{8E1B2C44-7A3D-4F59-9C21-AIRA00000001}
AppName={#Nombre}
AppVersion={#Version}
AppPublisher={#Publicador}
AppPublisherURL={#Web}
AppSupportURL={#Web}/descargar
DefaultDirName={localappdata}\Aira
DefaultGroupName=Aira
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=salida
OutputBaseFilename=AiraAgente-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#Nombre}
UninstallDisplayIcon={app}\node.exe
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
es.WelcomeLabel1=Instalar Aira en este ordenador
es.WelcomeLabel2=Este programa imprime los tickets de reserva en cuanto entran.%n%nAntes de empezar, ten a mano el código que te ha dado Aira y asegúrate de que la impresora está encendida y conectada a la misma red que este ordenador.
es.FinishedHeadingLabel=Aira ya está funcionando

[Files]
Source: "origen\node.exe";      DestDir: "{app}"; Flags: ignoreversion
Source: "origen\agente.js";     DestDir: "{app}"; Flags: ignoreversion
Source: "origen\configurar.js"; DestDir: "{app}"; Flags: ignoreversion
Source: "origen\arrancar.vbs";  DestDir: "{app}"; Flags: ignoreversion
Source: "origen\package.json";  DestDir: "{app}"; Flags: ignoreversion
Source: "origen\node_modules\*"; DestDir: "{app}\node_modules"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Sin acceso a ninguna pantalla de estado: desde la 2.1.2 el agente trabaja en
; silencio y lo que hay que vigilar se mira en Aira Admin. Aqui solo queda la
; desinstalacion, para que el local pueda quitarlo sin buscar por el Panel de
; control.
Name: "{group}\Desinstalar Aira"; Filename: "{uninstallexe}"

; El arranque automatico. Se hace con un acceso directo en la carpeta de Inicio
; y no con una tarea programada: schtasks exige anidar comillas dentro del
; parametro /TR y eso se rompe en cuanto la ruta del usuario lleva un espacio.
; Esto no tiene ese problema y se ve en "Inicio" del Administrador de tareas,
; donde cualquiera puede comprobar que esta puesto.
Name: "{userstartup}\Aira agente"; Filename: "{sys}\wscript.exe"; \
  Parameters: """{app}\arrancar.vbs"""; WorkingDir: "{app}"; \
  Comment: "Arranca el agente de impresion de Aira"

[Run]
; Arrancarlo ya, sin esperar a reiniciar el ordenador
Filename: "{sys}\wscript.exe"; Parameters: """{app}\arrancar.vbs"""; \
  WorkingDir: "{app}"; Flags: runhidden nowait postinstall; \
  Description: "Arrancar Aira ahora"

[UninstallRun]
; Primero el vigilante y luego el agente: al reves, el vigilante lo levantaria
; otra vez antes de que nos diera tiempo a nada.
Filename: "taskkill.exe"; Parameters: "/F /IM wscript.exe"; Flags: runhidden; RunOnceId: "PararVigilante"
Filename: "taskkill.exe"; Parameters: "/F /IM node.exe";    Flags: runhidden; RunOnceId: "PararAgente"

[UninstallDelete]
; Lo que crea el agente mientras funciona y que Inno no conoce
Type: files; Name: "{app}\aira-config.json"
Type: files; Name: "{app}\estado.json"
Type: files; Name: "{app}\estado.html"
Type: files; Name: "{app}\resultado.json"
Type: files; Name: "{app}\aira-log.txt"
Type: files; Name: "{app}\aira-log-anterior.txt"
Type: filesandordirs; Name: "{app}\node_modules"

[Code]
var
  PaginaCodigo: TInputQueryWizardPage;

// Permite pasar el codigo sin teclearlo:  AiraAgente-Setup.exe /CODIGO=K7M29PXQ
// Sirve para instalar en varios locales de golpe y para las pruebas
// automaticas. Si no se pasa, se pide en pantalla como siempre.
function CodigoDeLaLinea: String;
var
  i: Integer;
  s: String;
begin
  Result := '';
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if Pos('/CODIGO=', Uppercase(s)) = 1 then
      Result := Copy(s, 9, Length(s));
  end;
end;

procedure InitializeWizard;
begin
  PaginaCodigo := CreateInputQueryPage(wpWelcome,
    'Código de alta',
    'Escribe el código que te ha dado Aira',
    'Son 8 letras y números, por ejemplo K7M2-9PXQ. Caduca a los 15 minutos:' + #13#10 +
    'si se te ha pasado el tiempo, pide otro y vuelve a empezar.');
  PaginaCodigo.Add('Código:', False);
  // Si vino por la línea de comandos, ya queda escrito
  PaginaCodigo.Values[0] := CodigoDeLaLinea;
end;

// Deja solo letras y numeros, en mayusculas. Asi da igual que lo escriban
// con guion, con espacios o en minusculas.
function LimpiarCodigo(S: String): String;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  S := Uppercase(S);
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if ((c >= 'A') and (c <= 'Z')) or ((c >= '0') and (c <= '9')) then
      Result := Result + c;
  end;
end;

function NextButtonClick(PageId: Integer): Boolean;
begin
  Result := True;
  if PageId = PaginaCodigo.ID then
  begin
    if Length(LimpiarCodigo(PaginaCodigo.Values[0])) <> 8 then
    begin
      MsgBox('El código son 8 letras y números.' + #13#10 +
             'Míralo otra vez: los guiones y los espacios no importan.',
             mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// Lee resultado.json sin pretender entender JSON: solo busca el texto que
// necesita. Es fragil de mas para un caso general, pero aqui el archivo lo
// escribimos nosotros mismos dos lineas antes.
function SacarValor(const Json, Clave: String): String;
var
  p, q: Integer;
  resto: String;
begin
  Result := '';
  p := Pos('"' + Clave + '"', Json);
  if p = 0 then Exit;
  resto := Copy(Json, p + Length(Clave) + 2, Length(Json));
  p := Pos(':', resto);
  if p = 0 then Exit;
  resto := Copy(resto, p + 1, Length(resto));
  p := Pos('"', resto);
  if p = 0 then Exit;
  resto := Copy(resto, p + 1, Length(resto));
  q := Pos('"', resto);
  if q = 0 then Exit;
  Result := Copy(resto, 1, q - 1);
end;

// Si ya habia un agente corriendo, hay que pararlo antes de copiar: Windows
// no deja sobrescribir un node.exe que esta en uso, y la reinstalacion
// fallaria a medias.
procedure PararLoQueHaya;
var
  Salida: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM wscript.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Salida);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM node.exe', '',
       SW_HIDE, ewWaitUntilTerminated, Salida);
  Sleep(700);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Codigo, Json, Negocio, Impresora, Aviso, Motivo: String;
  // LoadStringFromFile devuelve AnsiString aunque el resto sea Unicode
  JsonBruto: AnsiString;
  Salida: Integer;
begin
  if CurStep = ssInstall then
  begin
    PararLoQueHaya;
    Exit;
  end;

  if CurStep <> ssPostInstall then Exit;

  Codigo := LimpiarCodigo(PaginaCodigo.Values[0]);

  WizardForm.StatusLabel.Caption := 'Dando de alta y buscando la impresora...';
  WizardForm.Refresh;

  if not Exec(ExpandConstant('{app}\node.exe'),
              ExpandConstant('"{app}\configurar.js" ') + Codigo,
              ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Salida) then
  begin
    MsgBox('No he podido ejecutar el asistente de alta.' + #13#10 +
           'El programa queda instalado; avisa a Aira.', mbError, MB_OK);
    Exit;
  end;

  if not LoadStringFromFile(ExpandConstant('{app}\resultado.json'), JsonBruto) then
  begin
    MsgBox('El alta terminó pero no encuentro el resultado.' + #13#10 +
           'Avisa a Aira.', mbError, MB_OK);
    Exit;
  end;

  // El asistente escribe este archivo en latin1 justamente para que esta
  // conversion directa funcione y los acentos salgan bien
  Json := String(JsonBruto);

  Negocio   := SacarValor(Json, 'negocio');
  Impresora := SacarValor(Json, 'impresora');
  Aviso     := SacarValor(Json, 'aviso');
  Motivo    := SacarValor(Json, 'motivo');

  if Salida <> 0 then
  begin
    MsgBox('No se pudo dar de alta:' + #13#10#13#10 + Motivo + #13#10#13#10 +
           'El programa queda instalado. Cuando tengas un código nuevo, vuelve' + #13#10 +
           'a ejecutar este instalador.', mbError, MB_OK);
    Exit;
  end;

  if Impresora <> '' then
    MsgBox('Listo, ' + Negocio + '.' + #13#10#13#10 +
           'Impresora encontrada en ' + Impresora + '.' + #13#10 +
           'Debería haber salido un papel de prueba: si ha salido, ya está todo.' + #13#10#13#10 +
           'A partir de ahora los tickets saldrán solos.', mbInformation, MB_OK)
  else
    MsgBox('Alta correcta, ' + Negocio + '.' + #13#10#13#10 + Aviso, mbInformation, MB_OK);
end;
