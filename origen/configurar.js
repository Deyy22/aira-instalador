// configurar.js — Asistente de alta del agente de Aira
//
// Lo llama el instalador con el código que ha tecleado el local:
//     node.exe configurar.js K7M2-9PXQ
//
// Hace tres cosas y escribe el resultado en resultado.json para que el
// instalador pueda enseñarlo:
//   1. Canjea el código por la llave de verdad (la llave nunca viaja por
//      WhatsApp: baja directa del servidor a este ordenador).
//   2. Busca la impresora en la red del local, por el puerto 9100.
//   3. Saca un papel de prueba para que confirmen que es la correcta.
//
// Sale con 0 si todo fue bien, con 1 si algo falló. El instalador mira eso.

const fs = require('fs')
const os = require('os')
const net = require('net')
const path = require('path')
const { execSync } = require('child_process')
const { createClient } = require('@supabase/supabase-js')

const SUPABASE_URL = 'https://dvigxxkmqjhobnzgwfgg.supabase.co'
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR2aWd4eGttcWpob2Juemd3ZmdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2NTk2MzcsImV4cCI6MjEwMDIzNTYzN30.GbULJh6DcOoN8p4iwZYuzQaGFWWNLBw1nP0WwJGst-c'

const PUERTO_IMPRESORA = 9100
const ESPERA_SONDEO_MS = 400      // por equipo de la red
const A_LA_VEZ = 40               // cuántos se prueban en paralelo

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
const aqui = (f) => path.join(__dirname, f)

function guardarResultado(obj) {
  try {
    // En latin1 a propósito, no en UTF-8: quien lee este archivo es el
    // instalador de Inno Setup, y su lenguaje no sabe convertir UTF-8.
    // Con latin1 los acentos de "Sidrería" o "Gijón" salen bien en el aviso
    // final. Es el único archivo que necesita esto; los demás van en UTF-8.
    fs.writeFileSync(aqui('resultado.json'), JSON.stringify(obj, null, 2), 'latin1')
  } catch {}
}

function paso(txt) {
  console.log(txt)
}

// ---------- 1. Canjear el código ----------
async function canjear(codigo) {
  const { data, error } = await supabase.rpc('agente_canjear', { p_codigo: codigo })
  if (error) throw new Error('No se pudo contactar con Aira: ' + error.message)
  if (!data || !data.ok) throw new Error(data?.motivo || 'Código no válido')
  return data
}

// ---------- 2. Buscar la impresora ----------
// Las redes de los locales son domésticas: una /24 con 254 equipos posibles.
// Probamos el puerto 9100 en todas, en tandas, con muy poca espera.
function redesLocales() {
  const redes = []
  for (const [, direcciones] of Object.entries(os.networkInterfaces())) {
    for (const d of direcciones || []) {
      if (d.family !== 'IPv4' || d.internal) continue
      const partes = d.address.split('.')
      if (partes.length !== 4) continue
      redes.push({ base: partes.slice(0, 3).join('.'), propia: d.address })
    }
  }
  return redes
}

function pruebaPuerto(ip) {
  return new Promise((resolve) => {
    const s = new net.Socket()
    let hecho = false
    const fin = (abierto) => {
      if (hecho) return
      hecho = true
      s.destroy()
      resolve(abierto ? ip : null)
    }
    s.setTimeout(ESPERA_SONDEO_MS)
    s.once('connect', () => fin(true))
    s.once('timeout', () => fin(false))
    s.once('error', () => fin(false))
    s.connect(PUERTO_IMPRESORA, ip)
  })
}

async function buscarImpresoras() {
  const encontradas = []
  for (const red of redesLocales()) {
    const candidatas = []
    for (let i = 1; i <= 254; i++) {
      const ip = `${red.base}.${i}`
      if (ip !== red.propia) candidatas.push(ip)
    }
    for (let i = 0; i < candidatas.length; i += A_LA_VEZ) {
      const tanda = candidatas.slice(i, i + A_LA_VEZ)
      const r = await Promise.all(tanda.map(pruebaPuerto))
      for (const ip of r) if (ip) encontradas.push(ip)
    }
  }
  return encontradas
}

// ---------- 3. Papel de prueba ----------
// ESC/POS mínimo. Si sale el papel, es la impresora correcta: es la única
// comprobación que no depende de que el programa acierte.
function papelDePrueba(negocio) {
  const ESC = 0x1b, GS = 0x1d
  const t = (n) => Buffer.from([GS, 0x21, n])
  const linea = (s) => Buffer.from(s + '\n', 'latin1')
  return Buffer.concat([
    Buffer.from([ESC, 0x40]),            // reiniciar
    Buffer.from([ESC, 0x61, 0x01]),      // centrar
    t(0x11), linea('AIRA'), t(0x00),
    linea(''),
    linea('Impresora configurada'),
    linea(negocio || ''),
    linea(''),
    linea(new Date().toLocaleString('es-ES')),
    linea(''),
    linea('Ya puedes cerrar el instalador.'),
    Buffer.from('\n\n\n\n'),
    Buffer.from([GS, 0x56, 0x00]),       // cortar
  ])
}

function imprimir(ip, datos) {
  return new Promise((resolve, reject) => {
    const s = new net.Socket()
    s.setTimeout(6000)
    s.connect(PUERTO_IMPRESORA, ip, () => s.write(datos, () => s.end()))
    s.on('close', resolve)
    s.on('timeout', () => { s.destroy(); reject(new Error('La impresora no responde')) })
    s.on('error', reject)
  })
}

// ---------- Todo junto ----------
;(async () => {
  const codigo = (process.argv[2] || '').trim()
  if (!codigo) {
    guardarResultado({ ok: false, motivo: 'No me han dado ningún código' })
    paso('ERROR: falta el código')
    process.exit(1)
  }

  try {
    paso('Comprobando el código...')
    const alta = await canjear(codigo)
    paso('Correcto: ' + alta.negocio)

    // La llave, a su archivo. Es lo único propio de este local.
    fs.writeFileSync(aqui('aira-config.json'),
      JSON.stringify({ token: alta.token }, null, 2), 'utf8')

    paso('Buscando la impresora en la red...')
    const impresoras = await buscarImpresoras()

    if (impresoras.length === 0) {
      // El agente ya está dado de alta: la impresora se puede poner luego
      // desde Aira Admin sin volver a tocar este ordenador.
      guardarResultado({
        ok: true, negocio: alta.negocio, impresora: null,
        aviso: 'No he encontrado ninguna impresora en la red. El agente queda instalado; avisa a Aira para configurarla.',
      })
      paso('AVISO: no encontré impresora. El agente queda instalado igual.')
      process.exit(0)
    }

    if (impresoras.length > 1) {
      // No adivinamos: mandar tickets con datos de clientes a la impresora
      // equivocada sería peor que pedir ayuda.
      guardarResultado({
        ok: true, negocio: alta.negocio, impresora: null,
        candidatas: impresoras,
        aviso: 'He encontrado varias impresoras (' + impresoras.join(', ') +
               '). Avisa a Aira para elegir la correcta.',
      })
      paso('AVISO: varias impresoras encontradas. No elijo por mi cuenta.')
      process.exit(0)
    }

    const ip = impresoras[0]
    paso('Impresora encontrada en ' + ip + '. Imprimiendo una prueba...')
    await imprimir(ip, papelDePrueba(alta.negocio))

    // Que quede anotada en Aira: así se puede cambiar en remoto sin venir aquí.
    //
    // Se guarda también la MAC. La IP la reparte el router y puede cambiar con
    // un corte de luz; la MAC es del hardware y no cambia nunca. Con ella
    // apuntada, si el día de mañana la impresora aparece en otra dirección, el
    // agente la reconoce y se reconfigura solo. La leemos justo después de la
    // prueba, que es cuando la tabla ARP del sistema acaba de refrescarse.
    let mac = null
    try {
      const salida = execSync('arp -a ' + ip, { encoding: 'latin1', timeout: 4000 })
      const re = /(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F]{2}(?:[-:][0-9a-fA-F]{2}){5})/g
      let m
      while ((m = re.exec(salida)) !== null) {
        if (m[1] === ip) { mac = m[2].toLowerCase().replace(/:/g, '-'); break }
      }
    } catch {
      // sin MAC el agente funciona igual: la aprenderá él solo al primer ticket
    }
    try {
      await supabase.rpc('agente_set_impresora', { p_token: alta.token, p_ip: ip, p_mac: mac })
    } catch {
      // si no se puede anotar, el agente funciona igual con lo que tiene
    }

    guardarResultado({ ok: true, negocio: alta.negocio, impresora: ip })
    paso('Listo. Debería haber salido un papel de la impresora.')
    process.exit(0)

  } catch (e) {
    guardarResultado({ ok: false, motivo: e.message })
    paso('ERROR: ' + e.message)
    process.exit(1)
  }
})()
