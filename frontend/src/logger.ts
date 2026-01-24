type LogLevel = 'debug' | 'info' | 'warn' | 'error' | 'off'

const levelOrder: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
  off: 100,
}

type LogPayload = {
  level: LogLevel
  message: string
  meta?: Record<string, unknown>
  timestamp: string
  url?: string
  userAgent?: string
}

function normalizeLevel(value: string | null | undefined): LogLevel {
  const lower = (value || '').toLowerCase().trim()
  if (lower === 'debug' || lower === 'info' || lower === 'warn' || lower === 'warning' || lower === 'error' || lower === 'off') {
    return lower === 'warning' ? 'warn' : (lower as LogLevel)
  }
  return 'info'
}

function normalizeBool(value: string | null | undefined): boolean | null {
  if (value == null) return null
  const lower = value.toLowerCase().trim()
  if (lower === 'true' || lower === '1' || lower === 'yes' || lower === 'on') return true
  if (lower === 'false' || lower === '0' || lower === 'no' || lower === 'off') return false
  return null
}

function getDefaultOrigin(): string {
  if (typeof window === 'undefined') return ''
  const origin = window.location?.origin
  if (origin && origin !== 'null') return origin
  try {
    if (window.location?.href) {
      const parsed = new URL(window.location.href)
      if (parsed.origin && parsed.origin !== 'null') return parsed.origin
    }
  } catch {
    // ignore invalid window.location.href
  }
  return ''
}

function normalizeApiUrl(value: string): string {
  const trimmed = value.trim().replace(/^['"]|['"]$/g, '')
  const origin = getDefaultOrigin()
  if (!trimmed) return origin
  if (trimmed.startsWith('/')) {
    if (origin) {
      return `${origin}${trimmed}`
    }
    return trimmed
  }
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(trimmed)) return trimmed
  if (trimmed.startsWith('localhost') || trimmed.startsWith('127.0.0.1')) {
    return `http://${trimmed}`
  }
  return `https://${trimmed.replace(/^\/+/, '')}`
}

function resolveLogEndpoint(): string | null {
  const rawEndpoint = String(import.meta.env.VITE_LOG_ENDPOINT || '').trim()
  if (rawEndpoint) {
    if (rawEndpoint.startsWith('http://') || rawEndpoint.startsWith('https://')) {
      return rawEndpoint.replace(/\/+$/, '')
    }
    const origin = getDefaultOrigin()
    if (rawEndpoint.startsWith('/')) {
      return origin ? `${origin}${rawEndpoint}` : rawEndpoint
    }
  }
  const rawApi = String(import.meta.env.VITE_API_URL || '').trim()
  if (!rawApi) return null
  const apiBase = normalizeApiUrl(rawApi).replace(/\/+$/, '')
  return apiBase ? `${apiBase}/logs/client` : null
}

let logToken: string | null = null
export const setLogToken = (token: string | null) => {
  logToken = token
}

const envLevel = normalizeLevel(import.meta.env.VITE_LOG_LEVEL)
const storageRaw = typeof window !== 'undefined' ? window.localStorage.getItem('gigme:logLevel') : null
const storageLevel = storageRaw ? normalizeLevel(storageRaw) : null
const activeLevel: LogLevel = storageLevel ?? envLevel
const envToServer = normalizeBool(import.meta.env.VITE_LOG_TO_SERVER)
const storageToServerRaw = typeof window !== 'undefined' ? window.localStorage.getItem('gigme:logToServer') : null
const storageToServer = normalizeBool(storageToServerRaw)
const logToServer = storageToServer ?? envToServer ?? Boolean(import.meta.env.DEV)
const logEndpoint = resolveLogEndpoint()

function shouldLog(level: LogLevel) {
  return levelOrder[level] >= levelOrder[activeLevel]
}

function sendToServer(payload: LogPayload) {
  if (!logToServer || !logEndpoint) return
  if (typeof window === 'undefined') return
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }
  if (logToken) {
    headers['Authorization'] = `Bearer ${logToken}`
  }
  const body = JSON.stringify(payload)
  fetch(logEndpoint, {
    method: 'POST',
    headers,
    body,
    keepalive: true,
  }).catch(() => {
    // never throw from logging
  })
}

function emit(level: LogLevel, message: string, meta?: Record<string, unknown>) {
  if (!shouldLog(level)) return
  const payload = meta ? { ...meta } : undefined
  const ts = new Date().toISOString()
  const label = `[gigme:${level}]`
  const logArgs = payload ? [label, message, payload] : [label, message]
  switch (level) {
    case 'debug':
      console.debug(ts, ...logArgs)
      break
    case 'info':
      console.info(ts, ...logArgs)
      break
    case 'warn':
      console.warn(ts, ...logArgs)
      break
    case 'error':
      console.error(ts, ...logArgs)
      break
    default:
      break
  }

  sendToServer({
    level,
    message,
    meta: payload,
    timestamp: ts,
    url: typeof window !== 'undefined' ? window.location?.href : undefined,
    userAgent: typeof window !== 'undefined' ? navigator.userAgent : undefined,
  })
}

export const logDebug = (message: string, meta?: Record<string, unknown>) => emit('debug', message, meta)
export const logInfo = (message: string, meta?: Record<string, unknown>) => emit('info', message, meta)
export const logWarn = (message: string, meta?: Record<string, unknown>) => emit('warn', message, meta)
export const logError = (message: string, meta?: Record<string, unknown>) => emit('error', message, meta)

export const getActiveLogLevel = () => activeLevel
