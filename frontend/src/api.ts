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
  rating?: number
  ratingCount?: number
  balanceTokens?: number
}

export type UserEvent = {
  id: number
  title: string
  startsAt: string
  participantsCount: number
  thumbnailUrl?: string
}

export type UserEventsResponse = {
  items: UserEvent[]
  total: number
}

export type ReferralCodeResponse = {
  code: string
}

export type ReferralClaimResponse = {
  awarded: boolean
  bonus?: number
  inviterBalanceTokens?: number
  inviteeBalanceTokens?: number
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
  contactTelegram?: string
  contactWhatsapp?: string
  contactWechat?: string
  contactFbMessenger?: string
  contactSnapchat?: string
  capacity?: number
  promotedUntil?: string
  creatorName?: string
  thumbnailUrl?: string
  participantsCount: number
  likesCount: number
  commentsCount: number
  filters?: string[]
  isJoined?: boolean
  isLiked?: boolean
  isPrivate?: boolean
  accessKey?: string
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

export type EventComment = {
  id: number
  eventId: number
  userId: number
  userName: string
  body: string
  createdAt: string
}

export type AdminUser = {
  id: number
  telegramId: number
  username?: string
  firstName: string
  lastName?: string
  photoUrl?: string
  rating?: number
  ratingCount?: number
  balanceTokens?: number
  isBlocked: boolean
  blockedReason?: string
  blockedAt?: string
  lastSeenAt?: string
  createdAt: string
  updatedAt: string
}

export type AdminUsersResponse = {
  items: AdminUser[]
  total: number
}

export type AdminUserDetailResponse = {
  user: AdminUser
  createdEvents: UserEvent[]
}

export type BroadcastButton = {
  text: string
  url: string
}

export type BroadcastPayload = {
  message: string
  buttons?: BroadcastButton[]
}

export type AdminBroadcast = {
  id: number
  adminUserId: number
  audience: string
  payload: BroadcastPayload
  status: string
  createdAt: string
  updatedAt: string
  targeted: number
  sent: number
  failed: number
}

export type AdminBroadcastsResponse = {
  items: AdminBroadcast[]
  total: number
}

export type AdminEventUpdate = {
  title?: string
  description?: string
  startsAt?: string
  endsAt?: string
  lat?: number
  lng?: number
  capacity?: number
  media?: string[]
  addressLabel?: string
  filters?: string[]
  contactTelegram?: string
  contactWhatsapp?: string
  contactWechat?: string
  contactFbMessenger?: string
  contactSnapchat?: string
}

export type PromoteRequest = {
  promotedUntil?: string
  durationMinutes?: number
  clear?: boolean
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
      const error = new Error(message) as Error & { status?: number }
      error.status = res.status
      throw error
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

export function getMe(token: string) {
  return apiFetch<User>('/me', {}, token)
}

export function getMyEvents(token: string, limit = 20, offset = 0) {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
  return apiFetch<UserEventsResponse>(`/events/mine?${params.toString()}`, {}, token)
}

export function topupToken(token: string, amount: number) {
  return apiFetch<{ balanceTokens: number }>(
    '/wallet/topup/token',
    { method: 'POST', body: JSON.stringify({ amount }) },
    token
  )
}

export function topupCard(token: string) {
  return apiFetch<{ paymentUrl?: string; invoiceId?: string }>(
    '/wallet/topup/card',
    { method: 'POST', body: JSON.stringify({}) },
    token
  )
}

export function getReferralCode(token: string) {
  return apiFetch<ReferralCodeResponse>('/referrals/my-code', {}, token)
}

export function claimReferral(token: string, payload: { eventId: number; refCode: string }) {
  return apiFetch<ReferralClaimResponse>(
    '/referrals/claim',
    { method: 'POST', body: JSON.stringify(payload) },
    token
  )
}

export function getNearby(
  token: string,
  lat: number,
  lng: number,
  radiusM = 0,
  filters: string[] = [],
  accessKeys: string[] = []
) {
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
  if (accessKeys.length > 0) {
    params.set('eventKeys', accessKeys.join(','))
  }
  return apiFetch<EventMarker[]>(`/events/nearby?${params.toString()}`, {}, token)
}

export function getFeed(
  token: string,
  lat: number,
  lng: number,
  radiusM = 0,
  filters: string[] = [],
  accessKeys: string[] = []
) {
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
  if (accessKeys.length > 0) {
    params.set('eventKeys', accessKeys.join(','))
  }
  return apiFetch<EventCard[]>(`/events/feed?${params.toString()}`, {}, token)
}

export function getEvent(token: string, id: number, accessKey?: string) {
  const params = new URLSearchParams()
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  const suffix = params.toString() ? `?${params.toString()}` : ''
  return apiFetch<EventDetail>(`/events/${id}${suffix}`, {}, token)
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
  isPrivate?: boolean
  contactTelegram?: string
  contactWhatsapp?: string
  contactWechat?: string
  contactFbMessenger?: string
  contactSnapchat?: string
}) {
  return apiFetch<{ eventId: number; accessKey?: string }>(
    '/events',
    { method: 'POST', body: JSON.stringify(payload) },
    token
  )
}

export function joinEvent(token: string, id: number, accessKey?: string) {
  const params = new URLSearchParams()
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  const suffix = params.toString() ? `?${params.toString()}` : ''
  return apiFetch<{ ok: boolean }>(`/events/${id}/join${suffix}`, { method: 'POST' }, token)
}

export function leaveEvent(token: string, id: number, accessKey?: string) {
  const params = new URLSearchParams()
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  const suffix = params.toString() ? `?${params.toString()}` : ''
  return apiFetch<{ ok: boolean }>(`/events/${id}/leave${suffix}`, { method: 'POST' }, token)
}

export function promoteEvent(token: string, id: number, payload: PromoteRequest) {
  return apiFetch<{ ok: boolean }>(`/events/${id}/promote`, { method: 'POST', body: JSON.stringify(payload) }, token)
}

export function updateEventAdmin(token: string, id: number, payload: AdminEventUpdate) {
  return apiFetch<{ ok: boolean }>(`/admin/events/${id}`, { method: 'PATCH', body: JSON.stringify(payload) }, token)
}

export function deleteEventAdmin(token: string, id: number) {
  return apiFetch<{ ok: boolean }>(`/admin/events/${id}`, { method: 'DELETE' }, token)
}

export function adminListUsers(
  token: string,
  params: { search?: string; blocked?: 'true' | 'false'; limit?: number; offset?: number } = {}
) {
  const qs = new URLSearchParams()
  if (params.search) qs.set('search', params.search)
  if (params.blocked) qs.set('blocked', params.blocked)
  if (typeof params.limit === 'number') qs.set('limit', String(params.limit))
  if (typeof params.offset === 'number') qs.set('offset', String(params.offset))
  const suffix = qs.toString() ? `?${qs.toString()}` : ''
  return apiFetch<AdminUsersResponse>(`/admin/users${suffix}`, {}, token)
}

export function adminGetUser(token: string, id: number) {
  return apiFetch<AdminUserDetailResponse>(`/admin/users/${id}`, {}, token)
}

export function adminBlockUser(token: string, id: number, reason: string) {
  return apiFetch<{ ok: boolean }>(
    `/admin/users/${id}/block`,
    { method: 'POST', body: JSON.stringify({ reason }) },
    token
  )
}

export function adminUnblockUser(token: string, id: number) {
  return apiFetch<{ ok: boolean }>(`/admin/users/${id}/unblock`, { method: 'POST' }, token)
}

export function adminCreateBroadcast(
  token: string,
  payload: {
    audience: 'all' | 'selected' | 'filter'
    userIds?: number[]
    filters?: { blocked?: boolean; minBalance?: number; lastSeenAfter?: string }
    message: string
    buttons?: BroadcastButton[]
  }
) {
  return apiFetch<{ broadcastId: number; targets: number }>(
    '/admin/broadcasts',
    { method: 'POST', body: JSON.stringify(payload) },
    token
  )
}

export function adminStartBroadcast(token: string, id: number) {
  return apiFetch<{ ok: boolean }>(`/admin/broadcasts/${id}/start`, { method: 'POST' }, token)
}

export function adminListBroadcasts(token: string, limit = 50, offset = 0) {
  const qs = new URLSearchParams({ limit: String(limit), offset: String(offset) })
  return apiFetch<AdminBroadcastsResponse>(`/admin/broadcasts?${qs.toString()}`, {}, token)
}

export function adminGetBroadcast(token: string, id: number) {
  return apiFetch<AdminBroadcast>(`/admin/broadcasts/${id}`, {}, token)
}

export function likeEvent(token: string, id: number, accessKey?: string) {
  const params = new URLSearchParams()
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  const suffix = params.toString() ? `?${params.toString()}` : ''
  return apiFetch<{ ok: boolean; likesCount: number; isLiked: boolean }>(
    `/events/${id}/like${suffix}`,
    { method: 'POST' },
    token
  )
}

export function unlikeEvent(token: string, id: number, accessKey?: string) {
  const params = new URLSearchParams()
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  const suffix = params.toString() ? `?${params.toString()}` : ''
  return apiFetch<{ ok: boolean; likesCount: number; isLiked: boolean }>(
    `/events/${id}/like${suffix}`,
    { method: 'DELETE' },
    token
  )
}

export function getEventComments(token: string, id: number, limit = 50, offset = 0, accessKey?: string) {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  return apiFetch<EventComment[]>(`/events/${id}/comments?${params.toString()}`, {}, token)
}

export function addEventComment(token: string, id: number, body: string, accessKey?: string) {
  const params = new URLSearchParams()
  if (accessKey) {
    params.set('eventKey', accessKey)
  }
  const suffix = params.toString() ? `?${params.toString()}` : ''
  return apiFetch<{ comment: EventComment; commentsCount: number }>(
    `/events/${id}/comments${suffix}`,
    { method: 'POST', body: JSON.stringify({ body }) },
    token
  )
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
