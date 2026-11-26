// WebUI bridge for Auto USB.
// KernelSU / APatch / MMRL all expose a `ksu`-style WebView bridge; MMRL also
// offers `mmrl`, and older hosts use other names. Each host returns results in
// a slightly different shape, so every call is normalised to { code, out, err }.
// With no host at all (plain browser) the UI runs on simulated data.

const win = typeof window === 'undefined' ? {} : window

export const CTL = '/system/bin/sh /data/adb/modules/autousb/bin/autousbctl'

const HOSTS = ['ksu', 'APatch', 'mmrl', '$webui', 'webuix', 'webui', 'kernelsu', 'magisk']
const METHODS = ['exec', 'execCommand', 'shell']

function findBridge() {
  for (const name of HOSTS) {
    let host
    try {
      host = win[name]
    } catch {
      host = null
    }
    if (!host) continue
    for (const method of METHODS) {
      let fn
      try {
        fn = host[method]
      } catch {
        fn = null
      }
      if (typeof fn === 'function') return { host, fn, name: `${name}.${method}` }
    }
  }
  return null
}

const host = findBridge()

export const isMMRL = Boolean(win.mmrl)
export const isDemo = !host && !isMMRL
export const needsGrant = isMMRL && !host
export const bridgeName = host ? host.name.split('.')[0] : '浏览器预览'

export const mmrlDark = (() => {
  try {
    const api = win.$autousb
    return api && typeof api.isDarkMode === 'function' ? api.isDarkMode() : null
  } catch {
    return null
  }
})()

function normalise(raw) {
  if (raw === null || raw === undefined) return null
  if (typeof raw === 'string') {
    const text = raw.replace(/^\s+/, '')
    if (text.startsWith('{')) {
      try {
        const parsed = JSON.parse(text)
        if (parsed && typeof parsed === 'object') {
          if ('stdout' in parsed || 'errno' in parsed || 'code' in parsed || 'stderr' in parsed) {
            return normalise(parsed)
          }
        }
      } catch {}
    }
    return { code: 0, out: raw, err: '' }
  }
  if (typeof raw === 'number') return { code: raw, out: '', err: '' }
  if (typeof raw === 'object') {
    const out =
      typeof raw.stdout === 'string'
        ? raw.stdout
        : typeof raw.result === 'string'
          ? raw.result
          : typeof raw.output === 'string'
            ? raw.output
            : typeof raw.out === 'string'
              ? raw.out
              : ''
    const code =
      typeof raw.errno === 'number'
        ? raw.errno
        : typeof raw.code === 'number'
          ? raw.code
          : typeof raw.returnCode === 'number'
            ? raw.returnCode
            : 0
    const err = typeof raw.stderr === 'string' ? raw.stderr : typeof raw.error === 'string' ? raw.error : ''
    return { code, out, err }
  }
  return null
}

export function exec(command) {
  if (isDemo) return demoRun(command === `${CTL} state` ? 'state' : command.replace(`${CTL} `, ''))
  if (!host) {
    return Promise.resolve({
      code: -1,
      out: '',
      err: '当前 WebUI 没有 root shell 权限，请在 MMRL 中允许「高级 KernelSU API」',
    })
  }

  return new Promise((resolve) => {
    let done = false
    let callbackSeq = (exec.seq = (exec.seq || 0) + 1)
    const callbackName = `__autousb_cb_${Date.now()}_${callbackSeq}`
    const timer = setTimeout(() => finish({ code: -1, out: '', err: 'shell timeout' }), 12000)

    function finish(raw) {
      if (done) return
      done = true
      clearTimeout(timer)
      try {
        delete win[callbackName]
      } catch {}
      resolve(normalise(raw) ?? { code: -1, out: '', err: 'unexpected host reply' })
    }

    function callback(a, b, c) {
      if (typeof a === 'string') {
        const text = a.trim()
        if (text.startsWith('{') || text.startsWith('[')) {
          try {
            return finish(JSON.parse(text))
          } catch {}
        }
        return finish({ code: 0, out: a, err: typeof b === 'string' ? b : '' })
      }
      if (a && typeof a === 'object') return finish(a)
      finish({ code: a, out: b, err: c })
    }

    // 1. Promise / synchronous one-argument host
    let first
    try {
      first = host.fn.call(host.host, command)
    } catch {}
    if (first && typeof first.then === 'function') {
      first.then(finish, () => attemptTwo())
      return
    }
    if (first !== undefined && first !== null) return finish(first)

    attemptTwo()

    // 2. callback-function style
    function attemptTwo() {
      if (done) return
      let second
      try {
        second = host.fn.call(host.host, command, callback)
      } catch {
        return attemptThree()
      }
      if (second && typeof second.then === 'function') {
        second.then(finish, () => attemptThree())
        return
      }
      if (second !== undefined && second !== null) return finish(second)
      setTimeout(() => {
        if (!done) attemptThree()
      }, 1200)
    }

    // 3. options-object style
    function attemptThree() {
      if (done) return
      let third
      try {
        third = host.fn.call(host.host, command, {
          cwd: '/',
          env: { PATH: '/system/bin:/system/xbin:/sbin' },
        })
      } catch {
        return attemptFour()
      }
      if (third && typeof third.then === 'function') {
        third.then(finish, () => attemptFour())
        return
      }
      if (third !== undefined && third !== null) return finish(third)
      attemptFour()
    }

    // 4. global callback-name style (KernelSU / APatch)
    function attemptFour() {
      if (done) return
      try {
        win[callbackName] = callback
        const fourth = host.fn.call(host.host, command, '{}', callbackName)
        if (fourth && typeof fourth.then === 'function') {
          fourth.then(finish, () => {})
          return
        }
        if (fourth !== undefined && fourth !== null) finish(fourth)
      } catch {}
    }
  })
}

export function parseState(text) {
  const data = {}
  String(text ?? '')
    .split(/[\r\n;]+/)
    .forEach((line) => {
      const at = line.indexOf('=')
      if (at > 0) data[line.slice(0, at).trim()] = line.slice(at + 1).trim()
    })
  return data
}

export function baseProfile(value) {
  const parts = String(value || '').split(',')
  for (const part of parts) {
    if (part && part !== 'adb') return part
  }
  return 'none'
}

export async function getState() {
  if (isDemo) return { data: demoSnapshot() }
  const result = await exec(`${CTL} state`)
  const data = parseState(result.out)
  if (!result.out || data.enabled === undefined || data.daemon === undefined) {
    return { error: result.err || result.out || '模块未响应', result }
  }
  return { data, result }
}

export function run(args) {
  if (isDemo) return demoRun(args)
  return exec(`${CTL} ${args}`)
}

export async function readLog() {
  if (isDemo) return { code: 0, out: demo.logs.join('\n'), err: '' }
  return exec(`${CTL} log 200`)
}

export async function clearLog() {
  if (isDemo) {
    demo.logs = []
    return { code: 0, out: 'log cleared', err: '' }
  }
  return exec(`${CTL} clearlog`)
}

export async function readStatus() {
  if (isDemo) return { code: 0, out: demoStatusText(), err: '' }
  return exec(`${CTL} status`)
}

/* ------------------------------------------------------------------ */
/* Simulated device                                                    */
/* ------------------------------------------------------------------ */

const now = () => Math.floor(Date.now() / 1000)

function stamp(epoch) {
  const d = new Date(epoch * 1000)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

const seeded = now() - 6 * 60

const demo = {
  enabled: 1,
  lock: 0,
  profile: 'none',
  on_connect: 'none',
  daemon: '4210',
  usb: 'configured',
  functions: 'none',
  version: '1.1.0',
  dir: 1,
  disable: 0,
  uid: '0',
  logs: [
    `${stamp(seeded)} boot: configured none + adb`,
    `${stamp(seeded)} daemon started pid=4210`,
    `${stamp(seeded)} connected: none`,
  ],
}

function demoSnapshot() {
  return {
    enabled: String(demo.enabled),
    lock: String(demo.lock),
    profile: demo.profile,
    on_connect: demo.on_connect,
    daemon: demo.daemon,
    usb: demo.usb,
    functions: demo.functions,
    version: demo.version,
    dir: String(demo.dir),
    disable: String(demo.disable),
    uid: demo.uid,
  }
}

function demoStatusText() {
  return [
    `module       : /data/adb/modules/autousb`,
    `enabled      : ${demo.enabled ? 'yes' : 'no'}`,
    `usb state    : ${demo.usb}`,
    `functions    : ${demo.functions}`,
    `daemon       : running (${demo.daemon})`,
    `mode         : ${demo.lock ? 'LOCK -> ' + demo.profile : 'AUTO -> ' + demo.on_connect}`,
    `ON_DISCONNECT: keep`,
    `INSECURE_ADB : 0 (ro.adb.secure=1)`,
  ].join('\n')
}

function demoLog(line) {
  demo.logs.push(`${stamp(now())} ${line}`)
  if (demo.logs.length > 200) demo.logs = demo.logs.slice(-200)
}

function demoRun(args) {
  const text = String(args || '')
  if (text === 'state') return Promise.resolve({ code: 0, out: JSON.stringify(demoSnapshot()), err: '' })
  if (text === 'status') return Promise.resolve({ code: 0, out: demoStatusText(), err: '' })
  if (text === 'log 200') return Promise.resolve({ code: 0, out: demo.logs.join('\n'), err: '' })
  if (text === 'clearlog') {
    demo.logs = []
    return Promise.resolve({ code: 0, out: 'log cleared', err: '' })
  }
  if (text === 'off') {
    demo.enabled = 0
    demo.daemon = '0'
    demoLog('disabled')
  } else if (text === 'on') {
    demo.enabled = 1
    demo.daemon = '4210'
    demoLog('enabled')
  } else if (text === 'auto') {
    demo.lock = 0
    demo.functions = demo.on_connect
    demoLog('auto mode')
  } else if (text.startsWith('lock on ')) {
    demo.lock = 1
    demo.profile = baseProfile(text.slice(8)) || 'none'
    demo.functions = demo.profile
    demoLog(`locked -> ${demo.profile}`)
  } else if (text === 'apply') {
    demo.functions = demo.lock ? demo.profile : demo.on_connect
    demoLog(`applied -> ${demo.functions || 'none'}`)
  } else if (text === 'reload') {
    demo.daemon = '4210'
    demoLog('daemon reloaded')
  }
  return Promise.resolve({ code: 0, out: text, err: '' })
}
