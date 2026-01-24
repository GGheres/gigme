import { logDebug, logError, logWarn } from './logger'

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

function validateApiUrl(value: string): string | null {
  if (!value || value === 'null') {
    return 'API URL is missing. Set VITE_API_URL (frontend/.env) to https://your-api-host'
  }
  try {
    const parsed = new URL(value)
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return 'API URL must start with http:// or https://'
    }
  } catch {
    return `API URL "${value}" is invalid. Set VITE_API_URL to a full https:// URL`
  }
  return null
}

const rawApiUrl = import.meta.env.VITE_API_URL || ''
export const API_URL = normalizeApiUrl(rawApiUrl).replace(/\/+$/, '')
export const API_URL_ERROR = validateApiUrl(API_URL)

const NGROK_SKIP_HEADER = 'ngrok-skip-browser-warning'
const NGROK_HOST_RE = /ngrok-free\.app|ngrok\.io/i
const shouldSkipNgrokWarning = () => NGROK_HOST_RE.test(API_URL)

function buildApiUrl(path: string): string {
  if (API_URL_ERROR) {
    throw new Error(API_URL_ERROR)
  }
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  return `${API_URL}${normalizedPath}`
}

export type User = {
  id: number
  telegramId: number
  username?: string
  firstName: string
  lastName?: string
  photoUrl?: string
}

export type EventMarker = {
  id: number
  title: string
  startsAt: string
  lat: number
  lng: number
  isPromoted: boolean
  filters?: string[]
}

export type EventCard = {
  id: number
  title: string
  description: string
  startsAt: string
  endsAt?: string
  lat: number
  lng: number
  capacity?: number
  promotedUntil?: string
  creatorName?: string
  thumbnailUrl?: string
  participantsCount: number
  filters?: string[]
}

export type EventDetail = {
  event: EventCard & {
    creatorUserId: number
    addressLabel?: string
    isHidden: boolean
    createdAt: string
    updatedAt: string
  }
  participants: { userId: number; name: string; joinedAt: string }[]
  media: string[]
  isJoined: boolean
}

async function apiFetch<T>(path: string, options: RequestInit = {}, token?: string) {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...((options.headers as Record<string, string> | undefined) || {}),
  }
  if (token) headers['Authorization'] = `Bearer ${token}`
  if (shouldSkipNgrokWarning() && !headers[NGROK_SKIP_HEADER]) {
    headers[NGROK_SKIP_HEADER] = 'true'
  }

  const url = buildApiUrl(path)
  const start = performance.now()
  logDebug('api_request', {
    path,
    method: options.method || 'GET',
    hasToken: Boolean(token),
  })
  try {
    const res = await fetch(url, { ...options, headers })
    if (!res.ok) {
      const text = await res.text()
      let message = text || res.statusText
      if (text) {
        try {
          const parsed = JSON.parse(text)
          if (parsed && typeof parsed.error === 'string') {
            message = parsed.error
          }
        } catch {
          // ignore JSON parse errors for non-JSON responses
        }
      }
      const durationMs = Math.round(performance.now() - start)
      logWarn('api_response_error', {
        path,
        method: options.method || 'GET',
        status: res.status,
        durationMs,
      })
      throw new Error(message)
    }
    const durationMs = Math.round(performance.now() - start)
    logDebug('api_response', {
      path,
      method: options.method || 'GET',
      status: res.status,
      durationMs,
    })
    return (await res.json()) as T
  } catch (err: any) {
    if (err instanceof Error) {
      if (err.name === 'TypeError') {
        const hint = /localhost|127\.0\.0\.1/.test(url)
          ? 'Check VITE_API_URL: localhost is not reachable from this device.'
          : 'Check network or VITE_API_URL.'
        logError('api_network_error', {
          path,
          method: options.method || 'GET',
          message: err.message,
        })
        throw new Error(`Request failed (${url}): ${err.message}. ${hint}`)
      }
      logError('api_error', {
        path,
        method: options.method || 'GET',
        message: err.message,
      })
      throw err
    }
    logError('api_unknown_error', { path, method: options.method || 'GET' })
    throw new Error(`Request failed (${url})`)
  }
}

export function authTelegram(initData: string) {
  return apiFetch<{ accessToken: string; user: User }>('/auth/telegram', {
    method: 'POST',
    body: JSON.stringify({ initData }),
  })
}

export function updateLocation(token: string, lat: number, lng: number) {
  return apiFetch<{ ok: boolean }>(
    '/me/location',
    { method: 'POST', body: JSON.stringify({ lat, lng }) },
    token
  )
}

export function getNearby(token: string, lat: number, lng: number, radiusM = 0, filters: string[] = []) {
  const params = new URLSearchParams({
    lat: String(lat),
    lng: String(lng),
  })
  if (radiusM > 0) {
    params.set('radiusM', String(radiusM))
  }
  if (filters.length > 0) {
    params.set('filters', filters.join(','))
  }
  return apiFetch<EventMarker[]>(`/events/nearby?${params.toString()}`, {}, token)
}

export function getFeed(token: string, lat: number, lng: number, radiusM = 0, filters: string[] = []) {
  const params = new URLSearchParams({
    lat: String(lat),
    lng: String(lng),
    limit: '50',
    offset: '0',
  })
  if (radiusM > 0) {
    params.set('radiusM', String(radiusM))
  }
  if (filters.length > 0) {
    params.set('filters', filters.join(','))
  }
  return apiFetch<EventCard[]>(`/events/feed?${params.toString()}`, {}, token)
}

export function getEvent(token: string, id: number) {
  return apiFetch<EventDetail>(`/events/${id}`, {}, token)
}

export function createEvent(token: string, payload: {
  title: string
  description: string
  startsAt: string
  endsAt?: string
  lat: number
  lng: number
  capacity?: number
  media: string[]
  addressLabel?: string
  filters?: string[]
}) {
  return apiFetch<{ eventId: number }>(
    '/events',
    { method: 'POST', body: JSON.stringify(payload) },
    token
  )
}

export function joinEvent(token: string, id: number) {
  return apiFetch<{ ok: boolean }>(`/events/${id}/join`, { method: 'POST' }, token)
}

export function leaveEvent(token: string, id: number) {
  return apiFetch<{ ok: boolean }>(`/events/${id}/leave`, { method: 'POST' }, token)
}

export function presignMedia(token: string, payload: {
  fileName: string
  contentType: string
  sizeBytes: number
}) {
  return apiFetch<{ uploadUrl: string; fileUrl: string }>(
    '/media/presign',
    { method: 'POST', body: JSON.stringify(payload) },
    token
  )
}

export async function uploadMedia(token: string, file: File) {
  const form = new FormData()
  form.append('file', file)
  const url = buildApiUrl('/media/upload')
  const start = performance.now()
  logDebug('upload_request', { fileName: file.name, sizeBytes: file.size, contentType: file.type })
  try {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${token}`,
    }
    if (shouldSkipNgrokWarning()) {
      headers[NGROK_SKIP_HEADER] = 'true'
    }
    const res = await fetch(url, {
      method: 'POST',
      headers,
      body: form,
    })
    if (!res.ok) {
      const text = await res.text()
      logWarn('upload_response_error', {
        status: res.status,
        durationMs: Math.round(performance.now() - start),
      })
      throw new Error(text || res.statusText)
    }
    logDebug('upload_response', { status: res.status, durationMs: Math.round(performance.now() - start) })
    return (await res.json()) as { fileUrl: string }
  } catch (err: any) {
    if (err instanceof Error) {
      if (err.name === 'TypeError') {
        const hint = /localhost|127\.0\.0\.1/.test(url)
          ? 'Check VITE_API_URL: localhost is not reachable from this device.'
          : 'Check network or VITE_API_URL.'
        logError('upload_network_error', { message: err.message })
        throw new Error(`Upload failed (${url}): ${err.message}. ${hint}`)
      }
      logError('upload_error', { message: err.message })
      throw err
    }
    logError('upload_unknown_error')
    throw new Error(`Upload failed (${url})`)
  }
}
