function normalizeApiUrl(value: string): string {
  const trimmed = value.trim().replace(/^['"]|['"]$/g, '')
  if (!trimmed) return window.location.origin
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(trimmed)) return trimmed
  if (trimmed.startsWith('localhost') || trimmed.startsWith('127.0.0.1')) {
    return `http://${trimmed}`
  }
  return `https://${trimmed.replace(/^\/+/, '')}`
}

const rawApiUrl = import.meta.env.VITE_API_URL || ''
const API_URL = normalizeApiUrl(rawApiUrl).replace(/\/+$/, '')

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
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(`${API_URL}${path}`, { ...options, headers })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
  return (await res.json()) as T
}

export function authTelegram(initData: string) {
  return apiFetch<{ accessToken: string; user: User }>('/auth/telegram', {
    method: 'POST',
    body: JSON.stringify({ initData }),
  })
}

export function getNearby(token: string, lat: number, lng: number, radiusM = 5000) {
  return apiFetch<EventMarker[]>(`/events/nearby?lat=${lat}&lng=${lng}&radiusM=${radiusM}`, {}, token)
}

export function getFeed(token: string, lat: number, lng: number, radiusM = 5000) {
  return apiFetch<EventCard[]>(`/events/feed?lat=${lat}&lng=${lng}&radiusM=${radiusM}&limit=50&offset=0`, {}, token)
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
