<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue'
import {
  MiuixArrowPreference,
  MiuixBottomSheet,
  MiuixButton,
  MiuixCard,
  MiuixDialog,
  MiuixDivider,
  MiuixIcon,
  MiuixIconButton,
  MiuixRadioButtonPreference,
  MiuixSmallTitle,
  MiuixSnackbarHost,
  MiuixSwitchPreference,
  dismissNewestSnackbar,
  setTheme,
  setThemeMode,
  showSnackbar,
  useTheme,
} from 'miuix-vue'
import {
  Copy,
  Delete,
  FavoritesFill,
  Folder,
  Info,
  Link,
  Lock,
  Music,
  Notes,
  Photos,
  Refresh,
  Tune,
  Unlock,
} from 'miuix-vue/icons'
import markUrl from './assets/mark.png'
import wechatQr from './assets/sponsor-wechat.png'
import alipayQr from './assets/sponsor-alipay.png'
import qqQr from './assets/sponsor-qq.png'
import {
  baseProfile,
  bridgeName,
  clearLog,
  exec,
  getState,
  isDemo,
  isMMRL,
  mmrlDark,
  needsGrant,
  readLog,
  readStatus,
  run as runCtl,
} from './bridge'

const THEME_KEY = 'autousb.theme'
const THEME_META_COLOR = { light: '#f7f7f7', dark: '#000000' }

const { theme } = useTheme()

try {
  const saved = localStorage.getItem(THEME_KEY)
  if (saved === 'light' || saved === 'dark') setTheme(saved)
  else if (mmrlDark !== null) setTheme(mmrlDark ? 'dark' : 'light')
  else setThemeMode('system')
} catch {
  setThemeMode('system')
}

watch(theme, (value) => {
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) meta.setAttribute('content', THEME_META_COLOR[value] ?? THEME_META_COLOR.light)
})

const state = reactive({
  enabled: '',
  lock: '',
  profile: '',
  onConnect: '',
  daemon: '',
  usb: '',
  functions: '',
  version: '',
  dir: '',
  disable: '',
  uid: '',
})

const loading = ref(true)
const refreshing = ref(false)
const busy = ref(false)
const fatal = ref('')
const nowTick = ref(Date.now())
const optimisticEnabled = ref(null)

function applyState(data) {
  state.enabled = data.enabled ?? ''
  state.lock = data.lock ?? ''
  state.profile = data.profile ?? ''
  state.onConnect = data.on_connect ?? ''
  state.daemon = data.daemon ?? ''
  state.usb = data.usb ?? ''
  state.functions = data.functions ?? ''
  state.version = data.version ?? ''
  state.dir = data.dir ?? ''
  state.disable = data.disable ?? ''
  state.uid = data.uid ?? ''
}

async function refresh({ silent = false } = {}) {
  if (refreshing.value) return
  if (needsGrant) {
    loading.value = false
    return
  }
  refreshing.value = true
  if (!silent && !state.version) loading.value = true
  try {
    const res = await getState()
    if (res.error) throw new Error(res.error)
    applyState(res.data)
    fatal.value = ''
  } catch (error) {
    fatal.value = String(error?.message || error)
  } finally {
    loading.value = false
    refreshing.value = false
    nowTick.value = Date.now()
  }
}

const moduleEnabled = computed(() => state.enabled === '1' && state.disable !== '1')
const daemonRunning = computed(() => Number(state.daemon) > 0)
const locked = computed(() => state.lock === '1')
const currentProfile = computed(() => baseProfile(locked.value ? state.profile : state.onConnect) || 'none')
const selectedMode = computed(() => currentProfile.value)
const canControl = computed(
  () =>
    !needsGrant &&
    state.dir !== '0' &&
    (!state.uid || state.uid === '0'),
)

const MODES = [
  { id: 'none', title: '仅充电', summary: '仅开启ADB', icon: Unlock, tone: 'slate' },
  { id: 'mtp', title: 'MTP 文件传输', summary: '传照片和文件', icon: Folder, tone: 'blue' },
  { id: 'rndis', title: 'USB 网卡', summary: '把网络共享给电脑', icon: Link, tone: 'orange' },
  { id: 'ptp', title: 'PTP 相机', summary: '传输 导入图片', icon: Photos, tone: 'violet' },
  { id: 'midi', title: 'MIDI', summary: '连接乐器设备', icon: Music, tone: 'green' },
]

function formatFunctions(value) {
  const raw = String(value || '')
  if (!raw) return '—'
  if (raw === 'none') return '仅充电'
  const labels = {
    mtp: 'MTP',
    ptp: 'PTP',
    rndis: 'RNDIS',
    midi: 'MIDI',
    adb: 'ADB',
    ncm: 'NCM',
    hid: 'HID',
    uac1: 'UAC1',
    uac2: 'UAC2',
    mass_storage: '存储',
    accessory: '配件',
    audio_source: '音频',
  }
  return raw
    .split(',')
    .map((part) => labels[part.trim()] || part.trim())
    .filter(Boolean)
    .join(' + ')
}

function labelOf(value) {
  const base = baseProfile(value)
  const found = MODES.find((mode) => mode.id === base)
  if (found) return found.title.replace(' 文件传输', '').replace(' 相机', '')
  return base === 'none' ? '仅充电' : base
}

const headline = computed(() => {
  if (loading.value) return '正在读取'
  if (state.dir === '0') return '未安装'
  if (state.uid && state.uid !== '0') return '需要 Root'
  if (!moduleEnabled.value) return '已停用'
  if (!daemonRunning.value) return '未运行'
  return '已启用'
})

const subline = computed(() => {
  if (loading.value) return '正在读取 Auto USB 状态…'
  if (state.dir === '0') return '模块目录不存在，安装后需要重启一次'
  if (state.uid && state.uid !== '0') return '当前 WebUI 没有 root 权限，无法读取或修改模块状态'
  if (!moduleEnabled.value) return '模块已停用，插线不会自动切换 USB 模式'
  if (!daemonRunning.value) return '守护进程未运行，插线不会自动切换，请尝试重启守护进程'
  return `当前目标组合为 ${labelOf(currentProfile.value)}`
})

const posture = computed(() => {
  if (loading.value) return 'unknown'
  if (state.dir === '0' || (state.uid && state.uid !== '0')) return 'error'
  if (!moduleEnabled.value) return 'off'
  if (!daemonRunning.value) return 'stopped'
  if (locked.value) return 'locked'
  return 'ok'
})

const modeCode = computed(() => {
  if (posture.value === 'stopped') return 'STOP'
  if (posture.value === 'unknown') return '…'
  if (posture.value === 'off' || posture.value === 'error') return 'OFF'
  return String(currentProfile.value || 'none').toUpperCase()
})

const heroIcon = computed(() => {
  if (posture.value === 'locked') return Lock
  if (posture.value === 'ok') return Link
  return Info
})

const connectionText = computed(() => {
  const map = { configured: '已连接', powered: '仅供电', 'not attached': '未连接' }
  return map[state.usb] || state.usb || '未知'
})

const functionsText = computed(() => formatFunctions(state.functions))
const targetFunctionsText = computed(() => formatFunctions(currentProfile.value))

const daemonText = computed(() => (daemonRunning.value ? '运行中' : '已停止'))

const leds = computed(() => [
  {
    label: '连接',
    value: connectionText.value,
    state: state.usb === 'configured' ? 'ok' : state.usb === 'powered' ? 'unknown' : 'open',
  },
  {
    label: '目标组合',
    value: targetFunctionsText.value,
    state: targetFunctionsText.value === '—' ? 'unknown' : 'ok',
  },
  {
    label: '守护进程',
    value: daemonText.value,
    state: daemonRunning.value ? 'ok' : 'unknown',
  },
])

const enabledChecked = computed(() =>
  optimisticEnabled.value === null ? moduleEnabled.value : optimisticEnabled.value,
)

const diagnostics = computed(() => [
  ['运行环境', isDemo ? '浏览器预览' : isMMRL ? 'MMRL' : 'KernelSU API'],
  ['WebUI 桥接', bridgeName],
  ['UID', state.uid || '—'],
  ['模块目录', '/data/adb/modules/autousb'],
  ['模块版本', state.version || '1.1.0'],
  ['模块状态', moduleEnabled.value ? '已启用' : '已停用'],
  ['守护进程', daemonRunning.value ? `运行中 (${state.daemon})` : '已停止'],
  ['USB 连接', connectionText.value],
  ['当前组合', functionsText.value],
  ['目标组合', targetFunctionsText.value],
  ['运行模式', `已启用 · ${labelOf(currentProfile.value)}`],
  ['插线模式', state.onConnect || '—'],
  ['上次刷新', lastUpdatedText.value],
])

const lastUpdatedText = computed(() => {
  if (!nowTick.value) return '—'
  const date = new Date(nowTick.value)
  const pad = (n) => String(n).padStart(2, '0')
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
})

const logSheet = ref(false)
const diagSheet = ref(false)
const sponsorOpen = ref(false)
const sponsorMethod = ref('wechat')
const heartPopping = ref(false)
const logText = ref('')
const logLoading = ref(false)
const statusText = ref('')
const statusLoading = ref(false)
let heartTimer = null

const sponsorMethods = [
  { id: 'wechat', label: '微信', hint: '打开微信扫一扫', image: wechatQr },
  { id: 'alipay', label: '支付宝', hint: '打开支付宝扫一扫', image: alipayQr },
  { id: 'qq', label: 'QQ', hint: '用 QQ 扫一扫', image: qqQr },
]

const currentSponsor = computed(
  () => sponsorMethods.find((method) => method.id === sponsorMethod.value) ?? sponsorMethods[0],
)

const confirmState = reactive({
  open: false,
  title: '',
  summary: '',
  confirmText: '确认',
  danger: false,
  action: null,
})

function askConfirm(options) {
  dismissNewestSnackbar()
  Object.assign(confirmState, {
    open: true,
    title: '',
    summary: '',
    confirmText: '确认',
    danger: false,
    action: null,
    ...options,
  })
}

async function runConfirm() {
  const action = confirmState.action
  confirmState.open = false
  if (action) await action()
}

function output(result) {
  return String(result?.out ?? '').trim()
}

function firstLine(text) {
  return String(text ?? '').split('\n').map((line) => line.trim()).find(Boolean) ?? ''
}

function shortError(error) {
  const message = firstLine(error?.message ?? error) || '未知错误'
  return message.length > 90 ? `${message.slice(0, 90)}…` : message
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function runAction(args, okMessage) {
  if (busy.value || !canControl.value) return
  busy.value = true
  try {
    const result = await runCtl(args)
    const text = output(result)
    if (result.code !== 0 || /^(ERROR|usage|unknown|invalid|sh:)/i.test(text)) {
      throw new Error(text || `退出码 ${result.code}`)
    }
    if (okMessage) showSnackbar({ message: okMessage, duration: 'short' })
  } catch (error) {
    showSnackbar({ message: `操作失败：${shortError(error)}`, duration: 'long' })
  } finally {
    busy.value = false
    await delay(450)
    await refresh({ silent: true })
  }
}

function onToggleEnabled(value) {
  if (busy.value || !canControl.value) return
  if (value) {
    optimisticEnabled.value = true
    runAction('on', '已启用 Auto USB').finally(() => {
      optimisticEnabled.value = null
    })
    return
  }
  askConfirm({
    title: '停用 Auto USB？',
    summary: '守护进程会停止，插线不再自动切换 USB 模式；配置会保留。',
    confirmText: '仍然停用',
    danger: true,
    action: async () => {
      optimisticEnabled.value = false
      await runAction('off', '已停用 Auto USB')
      optimisticEnabled.value = null
    },
  })
}

function onSelectMode(mode) {
  if (busy.value || !canControl.value || selectedMode.value === mode.id) return
  runAction(`lock on ${mode.id}`, `已启用 ${mode.title}`)
}

function reloadDaemon() {
  runAction('reload', '守护进程已重启')
}

function openLog() {
  dismissNewestSnackbar()
  logSheet.value = true
  refreshLog()
}

async function refreshLog() {
  logLoading.value = true
  try {
    const result = await readLog()
    logText.value = output(result) || '暂无运行日志'
  } catch (error) {
    logText.value = `读取日志失败：${shortError(error)}`
  } finally {
    logLoading.value = false
  }
}

function askClearLog() {
  askConfirm({
    title: '清空运行日志？',
    summary: '将删除 /data/adb/autousb/autousb.log 中的全部记录。',
    confirmText: '清空',
    danger: true,
    action: async () => {
      const result = await clearLog()
      if (result.code !== 0) {
        showSnackbar({ message: `清空失败：${firstLine(result.err) || result.code}`, duration: 'long' })
        return
      }
      await refreshLog()
      showSnackbar({ message: '运行日志已清空', duration: 'short' })
    },
  })
}

async function copyLog() {
  const ok = await copyText(logText.value)
  showSnackbar({ message: ok ? '日志已复制' : '复制失败，请手动选择文本', duration: 'short' })
}

function openDiag() {
  dismissNewestSnackbar()
  diagSheet.value = true
  refreshStatus()
}

async function refreshStatus() {
  statusLoading.value = true
  try {
    const result = await readStatus()
    statusText.value = output(result) || '暂无诊断输出'
  } catch (error) {
    statusText.value = `读取诊断失败：${shortError(error)}`
  } finally {
    statusLoading.value = false
  }
}

async function copyDiag() {
  const text = [
    ...diagnostics.value.map(([key, value]) => `${key}: ${value}`),
    '',
    statusText.value,
  ].join('\n')
  const ok = await copyText(text)
  showSnackbar({ message: ok ? '诊断信息已复制' : '复制失败，请手动选择文本', duration: 'short' })
}

function pulseHeart() {
  heartPopping.value = false
  requestAnimationFrame(() => {
    heartPopping.value = true
    clearTimeout(heartTimer)
    heartTimer = setTimeout(() => {
      heartPopping.value = false
    }, 520)
  })
  try {
    navigator.vibrate?.(10)
  } catch {}
}

async function copyText(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text)
      return true
    }
  } catch {}
  try {
    const area = document.createElement('textarea')
    area.value = text
    area.setAttribute('readonly', '')
    area.style.position = 'fixed'
    area.style.opacity = '0'
    document.body.appendChild(area)
    area.select()
    const ok = document.execCommand('copy')
    area.remove()
    return ok
  } catch {
    return false
  }
}

let themeTransitioning = false

async function applyTheme(next) {
  document.documentElement.classList.remove('m-theme-light')
  setTheme(next)
  try {
    localStorage.setItem(THEME_KEY, next)
  } catch {}
  await nextTick()
}

function themeOrigin(event) {
  const rect = event?.currentTarget?.getBoundingClientRect?.()
  const x = rect ? rect.left + rect.width / 2 : window.innerWidth - 44
  const y = rect ? rect.top + rect.height / 2 : 44
  const radius = Math.hypot(
    Math.max(x, window.innerWidth - x),
    Math.max(y, window.innerHeight - y),
  )
  return { x, y, radius }
}

function toggleTheme(event) {
  if (themeTransitioning) return
  const next = theme.value === 'dark' ? 'light' : 'dark'
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (reduceMotion) {
    applyTheme(next)
    return
  }
  const { x, y, radius } = themeOrigin(event)
  themeTransitioning = true

  if (typeof document.startViewTransition === 'function') {
    try {
      const transition = document.startViewTransition(() => applyTheme(next))
      transition.ready
        .then(() => {
          document.documentElement.animate(
            {
              clipPath: [
                `circle(0px at ${x}px ${y}px)`,
                `circle(${radius}px at ${x}px ${y}px)`,
              ],
            },
            {
              duration: 520,
              easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
              pseudoElement: '::view-transition-new(root)',
            },
          )
        })
        .catch(() => {})
      transition.finished.finally(() => {
        themeTransitioning = false
      })
      return
    } catch {
      themeTransitioning = false
    }
  }

  animateThemeCircle(next, x, y, radius)
}

function animateThemeCircle(next, x, y, radius) {
  const overlay = document.createElement('div')
  overlay.className = 'theme-wipe'
  overlay.style.background = next === 'dark' ? '#000' : '#f7f7f7'
  overlay.style.clipPath = `circle(0px at ${x}px ${y}px)`
  document.body.appendChild(overlay)

  const animation = overlay.animate(
    [
      { clipPath: `circle(0px at ${x}px ${y}px)` },
      { clipPath: `circle(${radius}px at ${x}px ${y}px)` },
    ],
    { duration: 520, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', fill: 'forwards' },
  )

  animation.finished
    .then(async () => {
      await applyTheme(next)
      overlay.classList.add('is-fading')
      window.setTimeout(() => {
        overlay.remove()
        themeTransitioning = false
      }, 240)
    })
    .catch(() => {
      overlay.remove()
      themeTransitioning = false
    })
}

let timer = null
function onVisibility() {
  if (document.visibilityState === 'visible' && !busy.value) refresh({ silent: true })
}

onMounted(() => {
  refresh()
  timer = setInterval(() => {
    if (document.visibilityState === 'visible' && !busy.value) refresh({ silent: true })
  }, 8000)
  document.addEventListener('visibilitychange', onVisibility)
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
  if (heartTimer) clearTimeout(heartTimer)
  document.removeEventListener('visibilitychange', onVisibility)
})
</script>

<template>
  <div class="app">
    <div class="shell">
      <header class="app-header reveal">
        <div class="brand-mark">
          <img :src="markUrl" alt="" />
        </div>
        <div class="brand-text">
          <h1 class="brand-title">Auto USB</h1>
          <p class="brand-sub">插线自动切换 · USB 模式</p>
        </div>
        <div class="header-actions">
          <MiuixIconButton
            aria-label="刷新状态"
            :class="{ 'is-spinning': refreshing }"
            @click="refresh()"
          >
            <MiuixIcon :icon="Refresh" :size="20" />
          </MiuixIconButton>
          <MiuixIconButton
            :aria-label="theme === 'dark' ? '切换到浅色模式' : '切换到深色模式'"
            @click="toggleTheme"
          >
            <span class="theme-toggle-icon">
              <svg
                class="theme-sun"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.7"
                stroke-linecap="round"
                aria-hidden="true"
              >
                <circle cx="12" cy="12" r="4.1" />
                <path
                  d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.4 5.4l1.6 1.6M17 17l1.6 1.6M18.6 5.4 17 7M7 17l-1.6 1.6"
                />
              </svg>
              <svg
                class="theme-moon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.7"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M20.5 14.2A8.6 8.6 0 0 1 9.8 3.5a8.6 8.6 0 1 0 10.7 10.7Z" />
              </svg>
            </span>
          </MiuixIconButton>
        </div>
      </header>

      <MiuixCard v-if="isDemo" class="notice reveal">
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>浏览器预览</b>
            <span>未检测到模块管理器，当前显示模拟数据。</span>
          </div>
        </div>
      </MiuixCard>

      <MiuixCard v-if="needsGrant" class="notice notice--error reveal">
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>MMRL 授权未开启</b>
            <span>请在 MMRL 的模块设置中允许本模块使用「高级 KernelSU API」，然后重新打开 WebUI。</span>
          </div>
        </div>
      </MiuixCard>

      <MiuixCard v-if="fatal" class="notice notice--error reveal">
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>读取失败</b>
            <span>{{ fatal }}</span>
          </div>
        </div>
      </MiuixCard>

      <template v-if="!needsGrant">
        <MiuixCard class="hero reveal" :data-state="posture">
          <div class="hero__body">
            <div class="hero__badge">
              <MiuixIcon :icon="heroIcon" :size="28" />
            </div>
            <div class="hero__copy">
              <span class="hero__eyebrow">
                <i class="live-dot"></i>
                {{ loading ? '正在读取' : 'USB SWITCH' }}
              </span>
              <h2 class="hero__title">{{ headline }}</h2>
              <p class="hero__sub">{{ subline }}</p>
            </div>
            <div class="hero__mode">
              <span>MODE</span>
              <b>{{ modeCode }}</b>
            </div>
          </div>

        <div class="hero__leds">
          <div
            v-for="led in leds"
            :key="led.label"
            class="led"
            :class="'is-' + led.state"
          >
            <span class="led__dot"></span>
            <span class="led__label">{{ led.label }}</span>
            <span class="led__value">{{ led.value }}</span>
          </div>
        </div>
      </MiuixCard>

        <MiuixSmallTitle class="section-title">模块</MiuixSmallTitle>
        <MiuixCard class="list-card reveal">
          <MiuixSwitchPreference
            :model-value="enabledChecked"
            title="启用 Auto USB"
            summary="开机自动运行，插线时自动切换 USB 模式"
            :disabled="busy || !canControl"
            @update:model-value="onToggleEnabled"
          >
            <template #start>
              <span class="row-icon tone-blue"><MiuixIcon :icon="Link" :size="18" /></span>
            </template>
            <template #end>
              <span v-if="busy" class="row-pending">处理中</span>
            </template>
          </MiuixSwitchPreference>
        </MiuixCard>

        <MiuixSmallTitle class="section-title">USB 模式</MiuixSmallTitle>
        <MiuixCard class="list-card reveal">
          <template v-for="(mode, index) in MODES" :key="mode.id">
            <MiuixDivider v-if="index" class="row-divider" />
            <MiuixRadioButtonPreference
              :model-value="selectedMode === mode.id"
              :title="mode.title"
              :summary="mode.summary"
              :disabled="busy || !canControl"
              location="end"
              @select="onSelectMode(mode)"
            >
              <template #start>
                <span class="row-icon" :class="'tone-' + mode.tone">
                  <MiuixIcon :icon="mode.icon" :size="18" />
                </span>
              </template>
            </MiuixRadioButtonPreference>
          </template>
        </MiuixCard>

        <MiuixSmallTitle class="section-title">操作</MiuixSmallTitle>
        <div class="button-stack reveal">
          <MiuixButton
            class="btn-xl btn-blue-xl"
            :disabled="busy || !canControl"
            @click="reloadDaemon"
          >
            <span class="btn-inner">
              <MiuixIcon :icon="Refresh" :size="19" />
              <span>重启守护进程</span>
            </span>
          </MiuixButton>
        </div>

        <MiuixSmallTitle class="section-title">工具</MiuixSmallTitle>
        <MiuixCard class="list-card reveal">
          <MiuixArrowPreference title="运行日志" summary="最近 200 行运行记录" @click="openLog">
            <template #start>
              <span class="row-icon tone-slate"><MiuixIcon :icon="Notes" :size="18" /></span>
            </template>
          </MiuixArrowPreference>
          <MiuixDivider class="row-divider" />
          <MiuixArrowPreference title="诊断信息" summary="运行信息" @click="openDiag">
            <template #start>
              <span class="row-icon tone-slate"><MiuixIcon :icon="Tune" :size="18" /></span>
            </template>
          </MiuixArrowPreference>
        </MiuixCard>

        <footer class="footnote">
          <button class="sponsor-entry" type="button" @click="sponsorOpen = true">
            <MiuixIcon :icon="FavoritesFill" :size="16" />
            <span>赞助开发</span>
          </button>
          <p class="footnote__meta">Auto USB · GPL-3.0</p>
        </footer>
      </template>
    </div>

    <MiuixBottomSheet v-model="logSheet" title="运行日志">
      <template #end-action>
        <MiuixIconButton aria-label="刷新日志" @click="refreshLog">
          <MiuixIcon :icon="Refresh" :size="19" />
        </MiuixIconButton>
      </template>
      <div class="sheet-body">
        <p class="sheet-hint">最近 200 行 · 由 autousb.log 追加</p>
        <pre class="log-view">{{ logText }}</pre>
        <div class="sheet-actions">
          <MiuixButton class="sheet-btn" @click="copyLog">
            <span class="btn-inner"><MiuixIcon :icon="Copy" :size="17" /><span>复制</span></span>
          </MiuixButton>
          <MiuixButton class="sheet-btn sheet-btn--danger" @click="askClearLog">
            <span class="btn-inner"><MiuixIcon :icon="Delete" :size="17" /><span>清空</span></span>
          </MiuixButton>
        </div>
      </div>
    </MiuixBottomSheet>

    <MiuixBottomSheet v-model="diagSheet" title="诊断信息">
      <template #end-action>
        <MiuixIconButton aria-label="复制诊断信息" @click="copyDiag">
          <MiuixIcon :icon="Copy" :size="19" />
        </MiuixIconButton>
      </template>
      <div class="sheet-body">
        <dl class="diag">
          <div v-for="row in diagnostics" :key="row[0]" class="diag__row">
            <dt>{{ row[0] }}</dt>
            <dd>{{ row[1] || '—' }}</dd>
          </div>
        </dl>
        <p class="sheet-hint sheet-hint--top">autousbctl status</p>
        <pre class="log-view log-view--short">{{ statusText || '读取中…' }}</pre>
      </div>
    </MiuixBottomSheet>

    <MiuixDialog v-model="sponsorOpen" title="赞助支持">
      <div class="sponsor-card">
        <div class="sponsor-head">
          <button
            class="sponsor-heart"
            :class="{ 'is-popping': heartPopping }"
            type="button"
            aria-label="感谢支持"
            @click="pulseHeart"
          >
            <svg class="heart-ring heart-ring--1" viewBox="0 0 24 24" aria-hidden="true">
              <path
                d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"
              />
            </svg>
            <svg class="heart-ring heart-ring--2" viewBox="0 0 24 24" aria-hidden="true">
              <path
                d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"
              />
            </svg>
            <MiuixIcon :icon="FavoritesFill" :size="24" />
          </button>
          <p class="sponsor-lead">
            如果Auto USB有幸帮助了您<br />
            可否邀请开发者饮一杯热茶<br />
            若能与您共饮<br />
            荣幸之至
          </p>
        </div>
        <div class="sponsor-methods">
          <button
            v-for="method in sponsorMethods"
            :key="method.id"
            class="sponsor-tab"
            :class="{ 'is-active': sponsorMethod === method.id }"
            type="button"
            @click="sponsorMethod = method.id"
          >
            {{ method.label }}
          </button>
        </div>
        <div class="sponsor-qr">
          <img :src="currentSponsor.image" :alt="`${currentSponsor.label}赞赏码`" />
        </div>
        <p class="sponsor-hint">{{ currentSponsor.hint }}</p>
        <MiuixButton class="sponsor-close" @click="sponsorOpen = false">关闭</MiuixButton>
      </div>
    </MiuixDialog>

    <MiuixDialog
      v-model="confirmState.open"
      :title="confirmState.title"
      :summary="confirmState.summary"
    >
      <div class="dialog-actions">
        <MiuixButton class="dialog-btn" @click="confirmState.open = false">取消</MiuixButton>
        <MiuixButton
          class="dialog-btn"
          :class="{ 'danger-fill': confirmState.danger }"
          type="primary"
          @click="runConfirm"
        >
          {{ confirmState.confirmText }}
        </MiuixButton>
      </div>
    </MiuixDialog>

    <MiuixSnackbarHost />
  </div>
</template>
