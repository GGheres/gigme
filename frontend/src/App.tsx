import React, { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import {
  API_URL,
  API_URL_ERROR,
  addEventComment,
  adminBlockUser,
  adminCreateBroadcast,
  adminCreateParserSource,
  adminGeocodeLocation,
  adminGetBroadcast,
  adminGetUser,
  adminImportParsedEvent,
  adminLogin,
  adminListBroadcasts,
  adminListParsedEvents,
  adminListParserSources,
  adminListUsers,
  adminParseInput,
  adminParseSource,
  adminRejectParsedEvent,
  adminStartBroadcast,
  adminUnblockUser,
  adminUpdateParserSource,
  authTelegram,
  AdminBroadcast,
  AdminParsedEvent,
  AdminParserSource,
  AdminUser,
  BroadcastButton,
  createEvent,
  deleteEventAdmin,
  EventCard,
  EventComment,
  EventDetail,
  EventMarker,
  getEventComments,
  getEvent,
  getFeed,
  getMe,
  getMyEvents,
  getNearby,
  getReferralCode,
  joinEvent,
  likeEvent,
  leaveEvent,
  promoteEvent,
  claimReferral,
  topupCard,
  topupToken,
  presignMedia,
  unlikeEvent,
  updateEventAdmin,
  uploadMedia,
  UserEvent,
  User,
  updateLocation,
} from './api'
import { getActiveLogLevel, logDebug, logError, logInfo, logWarn, setLogToken } from './logger'

type LatLng = { lat: number; lng: number }
type UploadedMedia = { fileUrl: string; previewUrl: string }
type EventFilter = 'dating' | 'party' | 'travel' | 'fun' | 'bar' | 'feedme' | 'sport' | 'study' | 'business'
type FormDefaults = {
  title: string
  startsAt: string
  endsAt: string
  capacity: string
  contactTelegram: string
  contactWhatsapp: string
  contactWechat: string
  contactFbMessenger: string
  contactSnapchat: string
  isPrivate: boolean
}
type AppPage = 'home' | 'profile' | 'admin'
type AdminSection = 'users' | 'user' | 'broadcasts' | 'parser'
type ParserImportDraft = {
  startsAt: string
  lat: string
  lng: string
  addressLabel: string
}

const EMPTY_FORM_DEFAULTS: FormDefaults = {
  title: '',
  startsAt: '',
  endsAt: '',
  capacity: '',
  contactTelegram: '',
  contactWhatsapp: '',
  contactWechat: '',
  contactFbMessenger: '',
  contactSnapchat: '',
  isPrivate: false,
}

const parseAdminIds = (value: string) => {
  const set = new Set<number>()
  value
    .split(',')
    .map((item) => item.trim())
    .forEach((item) => {
      if (!item) return
      const parsed = Number(item)
      if (Number.isFinite(parsed) && parsed > 0) {
        set.add(parsed)
      }
    })
  return set
}

const ADMIN_TELEGRAM_IDS = parseAdminIds(String(import.meta.env.VITE_ADMIN_TELEGRAM_IDS || ''))
const TELEGRAM_BOT_USERNAME = String(import.meta.env.VITE_TELEGRAM_BOT_USERNAME || '').trim()
const CARD_TOPUP_ENABLED = String(import.meta.env.VITE_CARD_TOPUP_ENABLED || '')
  .toLowerCase()
  .trim() === 'true'
const PROFILE_PATH = '/profile'
const MAX_TOPUP_TOKENS = 1_000_000
const PENDING_REFERRAL_STORAGE = 'gigme:pendingReferral'
const MAX_REF_CODE_LENGTH = 32

const formatDateTimeLocal = (value?: string | null) => {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const pad = (num: number) => String(num).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours()
  )}:${pad(date.getMinutes())}`
}

const formatTimestamp = (value?: string | null) => {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return date.toLocaleString()
}

const sortFeedItems = (items: EventCard[]) => {
  const now = Date.now()
  return [...items].sort((a, b) => {
    const aPromoted = a.promotedUntil ? new Date(a.promotedUntil).getTime() > now : false
    const bPromoted = b.promotedUntil ? new Date(b.promotedUntil).getTime() > now : false
    if (aPromoted !== bPromoted) return aPromoted ? -1 : 1
    return new Date(a.startsAt).getTime() - new Date(b.startsAt).getTime()
  })
}

const buildEventCardFromDetail = (detail: EventDetail, accessKey?: string): EventCard => ({
  id: detail.event.id,
  title: detail.event.title,
  description: detail.event.description,
  startsAt: detail.event.startsAt,
  endsAt: detail.event.endsAt,
  lat: detail.event.lat,
  lng: detail.event.lng,
  capacity: detail.event.capacity,
  promotedUntil: detail.event.promotedUntil,
  creatorName: detail.event.creatorName,
  thumbnailUrl: detail.media[0],
  participantsCount: detail.event.participantsCount,
  likesCount: detail.event.likesCount,
  commentsCount: detail.event.commentsCount,
  filters: detail.event.filters || [],
  contactTelegram: detail.event.contactTelegram,
  contactWhatsapp: detail.event.contactWhatsapp,
  contactWechat: detail.event.contactWechat,
  contactFbMessenger: detail.event.contactFbMessenger,
  contactSnapchat: detail.event.contactSnapchat,
  isJoined: detail.isJoined,
  isLiked: detail.event.isLiked,
  isPrivate: detail.event.isPrivate,
  accessKey,
})

const mergeFeedWithShared = (feedItems: EventCard[], sharedEvents: Record<number, EventCard>) => {
  if (!sharedEvents || Object.keys(sharedEvents).length === 0) return feedItems
  const map = new Map(feedItems.map((item) => [item.id, item]))
  Object.values(sharedEvents).forEach((item) => {
    map.set(item.id, item)
  })
  return sortFeedItems(Array.from(map.values()))
}

const mergeMarkersWithShared = (markers: EventMarker[], sharedEvents: Record<number, EventCard>) => {
  if (!sharedEvents || Object.keys(sharedEvents).length === 0) return markers
  const map = new Map(markers.map((item) => [item.id, item]))
  Object.values(sharedEvents).forEach((event) => {
    map.set(event.id, {
      id: event.id,
      title: event.title,
      startsAt: event.startsAt,
      lat: event.lat,
      lng: event.lng,
      isPromoted: Boolean(event.promotedUntil),
      filters: event.filters || [],
    })
  })
  return Array.from(map.values())
}

const DEFAULT_CENTER: LatLng = { lat: 52.37, lng: 4.9 }
const COORDS_LABEL = 'Coordinates:'
const MAX_DESCRIPTION = 1000
const MAX_CONTACT_LENGTH = 120
const MAX_COMMENT_LENGTH = 400
const LOCATION_POLL_MS = 60000
const VIEW_STORAGE_KEY = 'gigme:lastCenter'
const MAX_EVENT_FILTERS = 3
const NEARBY_RADIUS_M = 100_000
const FOCUS_ZOOM = 16
const EVENT_KEY_STORAGE = 'gigme:eventKeys'
const MAX_EVENT_KEY_LENGTH = 64
const MAX_UPLOAD_IMAGE_DIMENSION = 1920
const MAX_UPLOAD_IMAGE_BYTES = 2_000_000
const UPLOAD_IMAGE_QUALITY = 0.82
const MIN_COMPRESS_GAIN_RATIO = 0.93

const EVENT_FILTERS: { id: EventFilter; label: string; icon: string }[] = [
  { id: 'dating', label: 'Dating', icon: '💘' },
  { id: 'party', label: 'Party', icon: '🎉' },
  { id: 'travel', label: 'Travel', icon: '✈️' },
  { id: 'fun', label: 'Fun', icon: '🎈' },
  { id: 'bar', label: 'Bar', icon: '🍸' },
  { id: 'feedme', label: 'Feedme', icon: '🍕' },
  { id: 'sport', label: 'Sport', icon: '🏀' },
  { id: 'study', label: 'Study', icon: '📚' },
  { id: 'business', label: 'Business', icon: '💼' },
]

const formatCoords = (lat: number, lng: number) => `${lat.toFixed(5)}, ${lng.toFixed(5)}`
const buildCoordsUrl = (lat: number, lng: number) =>
  `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=16/${lat}/${lng}`
const buildShareUrl = (eventId: number, accessKey?: string, refCode?: string) => {
  if (typeof window === 'undefined') return ''
  const botUsername = TELEGRAM_BOT_USERNAME.replace(/^@+/, '').trim()
  let payload = `e_${eventId}`
  if (accessKey) {
    payload = `${payload}_${accessKey}`
  }
  if (refCode) {
    payload = `${payload}__r_${refCode}`
  }
  if (botUsername) {
    try {
      const tgUrl = new URL(`https://t.me/${botUsername}`)
      tgUrl.searchParams.set('startapp', payload)
      tgUrl.searchParams.set('start', payload)
      return tgUrl.toString()
    } catch {
      // fall through to web share URL
    }
  }
  try {
    const url = new URL(window.location.origin)
    url.pathname = window.location.pathname
    url.searchParams.set('eventId', String(eventId))
    if (accessKey) {
      url.searchParams.set('eventKey', accessKey)
    } else {
      url.searchParams.delete('eventKey')
    }
    if (refCode) {
      url.searchParams.set('refCode', refCode)
    } else {
      url.searchParams.delete('refCode')
    }
    return url.toString()
  } catch {
    return ''
  }
}

const toRadians = (value: number) => (value * Math.PI) / 180
const getDistanceKm = (from: LatLng, to: LatLng) => {
  const dLat = toRadians(to.lat - from.lat)
  const dLng = toRadians(to.lng - from.lng)
  const lat1 = toRadians(from.lat)
  const lat2 = toRadians(to.lat)
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return 6371 * c
}

const formatDistanceLabel = (km: number) => {
  if (!Number.isFinite(km)) return ''
  if (km < 1) return `${Math.max(1, Math.round(km * 1000))} m`
  if (km < 10) return `${km.toFixed(1)} km`
  return `${Math.round(km)} km`
}
const COORDS_REGEX = /Coordinates:\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)/i
const buildMediaProxyUrl = (eventId: number, index: number, accessKey?: string) => {
  if (API_URL_ERROR) return ''
  const base = `${API_URL}/media/events/${eventId}/${index}`
  if (!accessKey) return base
  const separator = base.includes('?') ? '&' : '?'
  return `${base}${separator}eventKey=${encodeURIComponent(accessKey)}`
}
const resolveMediaSrc = (eventId: number, index: number, fallback?: string, accessKey?: string) => {
  const proxy = buildMediaProxyUrl(eventId, index, accessKey)
  return proxy || fallback || ''
}
const NGROK_HOST_RE = /ngrok-free\.app|ngrok\.io/i

const isNgrokUrl = (value?: string) => {
  if (!value) return false
  return NGROK_HOST_RE.test(value)
}

const isAndroidDevice = () => {
  if (typeof navigator === 'undefined') return false
  return /Android/i.test(navigator.userAgent || '')
}

type DecodedImage = {
  source: CanvasImageSource
  width: number
  height: number
  release: () => void
}

const buildOptimizedFileName = (name: string, mimeType: string) => {
  const ext = mimeType === 'image/webp' ? 'webp' : mimeType === 'image/png' ? 'png' : 'jpg'
  const dotIndex = name.lastIndexOf('.')
  const baseName = dotIndex > 0 ? name.slice(0, dotIndex) : name
  return `${baseName || 'photo'}.${ext}`
}

const decodeImageForCanvas = async (file: File): Promise<DecodedImage | null> => {
  if (typeof window === 'undefined') return null
  if (typeof createImageBitmap === 'function') {
    try {
      const bitmap = await createImageBitmap(file)
      return {
        source: bitmap,
        width: bitmap.width,
        height: bitmap.height,
        release: () => bitmap.close(),
      }
    } catch {
      // fall back to Image() decode
    }
  }
  return new Promise((resolve) => {
    const blobUrl = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(blobUrl)
      resolve({
        source: img,
        width: img.naturalWidth || img.width,
        height: img.naturalHeight || img.height,
        release: () => {
          img.src = ''
        },
      })
    }
    img.onerror = () => {
      URL.revokeObjectURL(blobUrl)
      resolve(null)
    }
    img.src = blobUrl
  })
}

const optimizeImageForUpload = async (file: File): Promise<File> => {
  if (!file.type.startsWith('image/')) return file
  if (file.type === 'image/gif' || file.type === 'image/svg+xml') return file
  const decoded = await decodeImageForCanvas(file)
  if (!decoded || !decoded.width || !decoded.height) return file
  try {
    const longestSide = Math.max(decoded.width, decoded.height)
    const scale = longestSide > MAX_UPLOAD_IMAGE_DIMENSION ? MAX_UPLOAD_IMAGE_DIMENSION / longestSide : 1
    const targetWidth = Math.max(1, Math.round(decoded.width * scale))
    const targetHeight = Math.max(1, Math.round(decoded.height * scale))
    const needsResize = scale < 1
    const needsCompression = file.size > MAX_UPLOAD_IMAGE_BYTES || file.type === 'image/png'
    if (!needsResize && !needsCompression) return file

    const canvas = document.createElement('canvas')
    canvas.width = targetWidth
    canvas.height = targetHeight
    const ctx = canvas.getContext('2d')
    if (!ctx) return file
    ctx.imageSmoothingQuality = 'high'
    ctx.drawImage(decoded.source, 0, 0, targetWidth, targetHeight)

    const preferredType = file.type === 'image/webp' || file.type === 'image/png' ? 'image/webp' : 'image/jpeg'
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, preferredType, UPLOAD_IMAGE_QUALITY)
    )
    if (!blob || !blob.size) return file
    if (!needsResize && file.size > 0 && blob.size / file.size >= MIN_COMPRESS_GAIN_RATIO) return file

    const nextType = blob.type || preferredType
    return new File([blob], buildOptimizedFileName(file.name, nextType), {
      type: nextType,
      lastModified: file.lastModified,
    })
  } finally {
    decoded.release()
  }
}

const parseCoordsFromLine = (line: string): LatLng | null => {
  const match = line.match(COORDS_REGEX)
  if (!match) return null
  const lat = Number(match[1])
  const lng = Number(match[2])
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null
  return { lat, lng }
}

type ContactKind = 'telegram' | 'whatsapp' | 'wechat' | 'fbmessenger' | 'snapchat'
type ContactSource = {
  contactTelegram?: string
  contactWhatsapp?: string
  contactWechat?: string
  contactFbMessenger?: string
  contactSnapchat?: string
}

type CreateErrors = {
  title?: string
  description?: string
  startsAt?: string
  contacts?: string
  location?: string
}

const CONTACT_CONFIG: { id: ContactKind; label: string; shortLabel: string; field: keyof ContactSource }[] = [
  { id: 'telegram', label: 'Telegram', shortLabel: 'TG', field: 'contactTelegram' },
  { id: 'whatsapp', label: 'WhatsApp', shortLabel: 'WA', field: 'contactWhatsapp' },
  { id: 'wechat', label: 'WeChat', shortLabel: 'WC', field: 'contactWechat' },
  { id: 'fbmessenger', label: 'Messenger', shortLabel: 'FB', field: 'contactFbMessenger' },
  { id: 'snapchat', label: 'Snapchat', shortLabel: 'SC', field: 'contactSnapchat' },
]

const CONTACT_ICON_SRC: Record<ContactKind, string> = {
  telegram: '/contacts/telegram.png',
  whatsapp: '/contacts/whatsapp.png',
  wechat: '/contacts/wechat.ico',
  fbmessenger: '/contacts/messenger.png',
  snapchat: '/contacts/snapchat.ico',
}

const isLikelyUrl = (value: string) => /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(value)
const ensureHttps = (value: string) => (value.startsWith('http://') || value.startsWith('https://') ? value : `https://${value}`)

const normalizeHandle = (value: string, hosts: string[]) => {
  let out = value.trim().replace(/^@+/, '')
  const lower = out.toLowerCase()
  for (const host of hosts) {
    const idx = lower.indexOf(host)
    if (idx >= 0) {
      out = out.slice(idx + host.length)
      out = out.replace(/^\/+/, '')
      break
    }
  }
  return out
}

const isPresignEnabled = () => {
  const raw = String(import.meta.env.VITE_PRESIGN_ENABLED || '').trim().toLowerCase()
  if (!raw) return true
  if (['false', '0', 'no', 'off'].includes(raw)) return false
  if (['true', '1', 'yes', 'on'].includes(raw)) return true
  return true
}

const buildContactHref = (kind: ContactKind, value: string) => {
  const trimmed = value.trim()
  if (!trimmed) return ''
  if (isLikelyUrl(trimmed)) return trimmed
  switch (kind) {
    case 'telegram': {
      if (/t\.me\/|telegram\.me\//i.test(trimmed)) {
        return ensureHttps(trimmed)
      }
      return `https://t.me/${normalizeHandle(trimmed, ['t.me/', 'telegram.me/'])}`
    }
    case 'whatsapp': {
      if (/wa\.me\/|api\.whatsapp\.com\//i.test(trimmed)) {
        return ensureHttps(trimmed)
      }
      const digits = trimmed.replace(/[^\d]/g, '')
      if (digits) {
        return `https://wa.me/${digits}`
      }
      return `https://wa.me/${encodeURIComponent(trimmed.replace(/^\+/, ''))}`
    }
    case 'wechat': {
      if (/wechat\.com\/|weixin\.qq\.com\//i.test(trimmed)) {
        return ensureHttps(trimmed)
      }
      return `weixin://dl/chat?${encodeURIComponent(trimmed)}`
    }
    case 'fbmessenger': {
      if (/m\.me\/|messenger\.com\/t\/|facebook\.com\/messages\/t\//i.test(trimmed)) {
        return ensureHttps(trimmed)
      }
      return `https://m.me/${normalizeHandle(trimmed, ['m.me/', 'messenger.com/t/', 'facebook.com/messages/t/'])}`
    }
    case 'snapchat': {
      if (/snapchat\.com\/add\//i.test(trimmed)) {
        return ensureHttps(trimmed)
      }
      return `https://www.snapchat.com/add/${normalizeHandle(trimmed, ['snapchat.com/add/'])}`
    }
    default:
      return ''
  }
}

type ContactItem = {
  id: ContactKind
  label: string
  shortLabel: string
  value: string
  href: string
}

const buildContactItems = (source: ContactSource): ContactItem[] => {
  const items: ContactItem[] = []
  for (const config of CONTACT_CONFIG) {
    const raw = source[config.field]
    if (!raw) continue
    const value = raw.trim()
    if (!value) continue
    items.push({
      id: config.id,
      label: config.label,
      shortLabel: config.shortLabel,
      value,
      href: buildContactHref(config.id, value),
    })
  }
  return items
}

type MediaImageProps = Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'src'> & {
  src?: string
  fallbackSrc?: string
}

const MediaImage = ({ src, fallbackSrc, alt, onError, loading, decoding, ...rest }: MediaImageProps) => {
  const [candidateSrc, setCandidateSrc] = useState<string>(src || fallbackSrc || '')
  const [resolvedSrc, setResolvedSrc] = useState<string>(src || fallbackSrc || '')
  const objectUrlRef = useRef<string | null>(null)
  const triedFallbackRef = useRef(false)

  useEffect(() => {
    triedFallbackRef.current = false
    setCandidateSrc(src || fallbackSrc || '')
  }, [src, fallbackSrc])

  useEffect(() => {
    let cancelled = false
    const controller = new AbortController()

    const clearObjectUrl = () => {
      if (objectUrlRef.current) {
        URL.revokeObjectURL(objectUrlRef.current)
        objectUrlRef.current = null
      }
    }

    const load = async (value?: string) => {
      if (!value) return ''
      if (!isNgrokUrl(value)) return value
      // Ngrok can serve a warning interstitial; fetching manually avoids the HTML response.
      const res = await fetch(value, {
        headers: { 'ngrok-skip-browser-warning': 'true' },
        signal: controller.signal,
      })
      if (!res.ok) {
        throw new Error(`media fetch failed (${res.status})`)
      }
      const blob = await res.blob()
      const blobUrl = URL.createObjectURL(blob)
      objectUrlRef.current = blobUrl
      return blobUrl
    }

    const run = async () => {
      clearObjectUrl()
      try {
        const next = await load(candidateSrc)
        if (cancelled) return
        if (next) {
          setResolvedSrc(next)
          return
        }
      } catch {
        // try fallback
      }
      if (!fallbackSrc || triedFallbackRef.current || fallbackSrc === candidateSrc) {
        if (!cancelled) setResolvedSrc('')
        return
      }
      triedFallbackRef.current = true
      setCandidateSrc(fallbackSrc)
    }

    run()
    return () => {
      cancelled = true
      controller.abort()
      clearObjectUrl()
    }
  }, [candidateSrc, fallbackSrc])

  if (!resolvedSrc) return null
  return (
    <img
      src={resolvedSrc}
      alt={alt}
      loading={loading ?? 'lazy'}
      decoding={decoding ?? 'async'}
      onError={(event) => {
        if (fallbackSrc && !triedFallbackRef.current && fallbackSrc !== candidateSrc) {
          triedFallbackRef.current = true
          setCandidateSrc(fallbackSrc)
        } else {
          setResolvedSrc('')
        }
        onError?.(event)
      }}
      {...rest}
    />
  )
}

type ContactIconsProps = {
  source: ContactSource
  unlocked?: boolean
  className?: string
}

const ContactIcons = ({ source, unlocked = false, className }: ContactIconsProps) => {
  const items = buildContactItems(source)
  if (items.length === 0) return null
  const label = unlocked ? 'Contact creator' : 'Join event to contact'
  return (
    <div className={`card__contacts${className ? ` ${className}` : ''}`} data-locked={!unlocked}>
      {items.map((item) => {
        const title = unlocked ? `${item.label}: ${item.value}` : label
        const classes = `contact-icon contact-icon--${item.id}${unlocked ? '' : ' contact-icon--locked'}`
        const iconSrc = CONTACT_ICON_SRC[item.id]
        if (unlocked && item.href) {
          return (
            <a
              key={item.id}
              className={classes}
              href={item.href}
              target="_blank"
              rel="noreferrer"
              title={title}
              aria-label={title}
              onClick={(event) => event.stopPropagation()}
            >
              {iconSrc ? (
                <img className="contact-icon__img" src={iconSrc} alt="" loading="lazy" decoding="async" />
              ) : (
                <span className="contact-icon__fallback" aria-hidden="true">
                  {item.shortLabel}
                </span>
              )}
            </a>
          )
        }
        return (
          <span
            key={item.id}
            className={classes}
            title={title}
            aria-label={title}
            aria-disabled
            onClick={(event) => event.stopPropagation()}
          >
            {iconSrc ? (
              <img className="contact-icon__img" src={iconSrc} alt="" loading="lazy" decoding="async" />
            ) : (
              <span className="contact-icon__fallback" aria-hidden="true">
                {item.shortLabel}
              </span>
            )}
          </span>
        )
      })}
    </div>
  )
}

type ProfileAvatarProps = {
  user: User | null
  size?: 'sm' | 'md' | 'lg'
  className?: string
  label?: string
}

const ProfileAvatar = ({ user, size = 'md', className, label = 'Profile' }: ProfileAvatarProps) => {
  const seed = user?.firstName || user?.username || user?.lastName || 'U'
  const initial = seed ? seed.trim().charAt(0).toUpperCase() : 'U'
  return (
    <div className={`avatar avatar--${size}${className ? ` ${className}` : ''}`}>
      {user?.photoUrl ? <img src={user.photoUrl} alt={label} loading="lazy" decoding="async" /> : <span>{initial}</span>}
    </div>
  )
}

const pulseIcon = L.divIcon({
  className: 'pulse-marker',
  html: '<span class="pulse-marker__ring"></span><span class="pulse-marker__core"></span>',
  iconSize: [26, 26],
  iconAnchor: [13, 13],
})

const getInitDataFromLocation = () => {
  const searchParams = new URLSearchParams(window.location.search)
  const fromSearch = searchParams.get('initData') || searchParams.get('tgWebAppData')
  if (fromSearch) return fromSearch
  const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash
  if (!hash) return ''
  const hashParams = new URLSearchParams(hash)
  return hashParams.get('tgWebAppData') || hashParams.get('initData') || ''
}

type EventLink = { eventId: number | null; eventKey: string; refCode: string }
type PendingReferral = { eventId: number; refCode: string }

const parseEventId = (value: string | null) => {
  if (!value) return null
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || parsed <= 0) return null
  return parsed
}

const parseEventKey = (value: string | null) => {
  if (!value) return ''
  const trimmed = value.trim()
  if (!trimmed || trimmed.length > MAX_EVENT_KEY_LENGTH) return ''
  return trimmed
}

const parseRefCode = (value: string | null) => {
  if (!value) return ''
  const cleaned = value.trim().replace(/[^a-zA-Z0-9_-]/g, '')
  if (!cleaned || cleaned.length > MAX_REF_CODE_LENGTH) return ''
  return cleaned
}

const extractEventLinkFromParams = (params: URLSearchParams): EventLink => {
  const eventId = parseEventId(params.get('eventId') || params.get('event'))
  if (!eventId) return { eventId: null, eventKey: '', refCode: '' }
  const eventKey = parseEventKey(params.get('eventKey') || params.get('key') || params.get('accessKey'))
  const refCode = parseRefCode(params.get('refCode') || params.get('ref'))
  return { eventId, eventKey, refCode }
}

const getEventLinkFromLocation = (): EventLink => {
  if (typeof window === 'undefined') return { eventId: null, eventKey: '', refCode: '' }
  const searchParams = new URLSearchParams(window.location.search)
  const fromSearch = extractEventLinkFromParams(searchParams)
  if (fromSearch.eventId) return fromSearch
  const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash
  if (!hash) return { eventId: null, eventKey: '', refCode: '' }
  const hashParams = new URLSearchParams(hash)
  return extractEventLinkFromParams(hashParams)
}

const parseStartParam = (raw: string): EventLink => {
  if (!raw) return { eventId: null, eventKey: '', refCode: '' }
  const trimmed = raw.trim()
  const referralMatch = trimmed.match(/^e_(\d+)(?:_([a-zA-Z0-9_-]+))?(?:__r_([a-zA-Z0-9_-]+))?$/i)
  if (referralMatch) {
    const eventId = parseEventId(referralMatch[1])
    if (!eventId) return { eventId: null, eventKey: '', refCode: '' }
    return {
      eventId,
      eventKey: parseEventKey(referralMatch[2] || ''),
      refCode: parseRefCode(referralMatch[3] || ''),
    }
  }
  const legacyMatch = trimmed.match(/^event_(\d+)(?:_([a-zA-Z0-9_-]+))?/i)
  if (legacyMatch) {
    const eventId = parseEventId(legacyMatch[1])
    if (!eventId) return { eventId: null, eventKey: '', refCode: '' }
    return { eventId, eventKey: parseEventKey(legacyMatch[2] || ''), refCode: '' }
  }
  const fallbackMatch = trimmed.match(/\d+/)
  const eventId = fallbackMatch ? parseEventId(fallbackMatch[0]) : null
  return { eventId, eventKey: '', refCode: '' }
}

const getEventLinkFromTelegram = (): EventLink => {
  if (typeof window === 'undefined') return { eventId: null, eventKey: '', refCode: '' }
  const tg = (window as any).Telegram?.WebApp
  const startParam = tg?.initDataUnsafe?.start_param || tg?.initDataUnsafe?.startParam
  if (!startParam) return { eventId: null, eventKey: '', refCode: '' }
  return parseStartParam(String(startParam))
}

const getPageFromLocation = (): AppPage => {
  if (typeof window === 'undefined') return 'home'
  const path = window.location.pathname || '/'
  if (path.startsWith('/admin')) return 'admin'
  return path.startsWith(PROFILE_PATH) ? 'profile' : 'home'
}

const getAdminRouteFromLocation = (): { section: AdminSection; userId: number | null } => {
  if (typeof window === 'undefined') return { section: 'users', userId: null }
  const path = window.location.pathname || '/'
  if (!path.startsWith('/admin')) return { section: 'users', userId: null }
  const trimmed = path.replace(/^\/admin\/?/, '')
  if (!trimmed) return { section: 'users', userId: null }
  const parts = trimmed.split('/').filter(Boolean)
  if (parts[0] === 'users') {
    if (parts[1]) {
      const parsed = Number(parts[1])
      if (Number.isFinite(parsed) && parsed > 0) {
        return { section: 'user', userId: parsed }
      }
    }
    return { section: 'users', userId: null }
  }
  if (parts[0] === 'broadcasts') {
    return { section: 'broadcasts', userId: null }
  }
  if (parts[0] === 'parser') {
    return { section: 'parser', userId: null }
  }
  return { section: 'users', userId: null }
}

const updateEventLinkInLocation = (eventId: number | null, eventKey?: string) => {
  if (typeof window === 'undefined') return
  try {
    const url = new URL(window.location.href)
    if (eventId && eventId > 0) {
      url.searchParams.set('eventId', String(eventId))
    } else {
      url.searchParams.delete('eventId')
    }
    if (eventKey) {
      url.searchParams.set('eventKey', eventKey)
    } else {
      url.searchParams.delete('eventKey')
    }
    url.searchParams.delete('refCode')
    window.history.replaceState({}, '', url.toString())
  } catch {
    // ignore invalid URL updates
  }
}

const upsertCoordsInDescription = (value: string, lat: number, lng: number) => {
  const coordsLine = `${COORDS_LABEL} ${formatCoords(lat, lng)} (${buildCoordsUrl(lat, lng)})`
  const cleaned = value
    .split('\n')
    .filter((line) => !line.trim().startsWith(COORDS_LABEL))
    .join('\n')
    .trimEnd()
  if (!cleaned) return coordsLine.slice(0, MAX_DESCRIPTION)
  const separator = '\n\n'
  const maxBaseLen = MAX_DESCRIPTION - separator.length - coordsLine.length
  const trimmedBase = maxBaseLen > 0 && cleaned.length > maxBaseLen ? cleaned.slice(0, maxBaseLen) : cleaned
  return `${trimmedBase}${separator}${coordsLine}`.trimEnd()
}

const loadStoredCenter = (): LatLng | null => {
  if (typeof window === 'undefined') return null
  try {
    const raw = window.localStorage.getItem(VIEW_STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as { lat?: number; lng?: number }
    if (typeof parsed.lat !== 'number' || typeof parsed.lng !== 'number') return null
    return { lat: parsed.lat, lng: parsed.lng }
  } catch {
    return null
  }
}

const loadStoredEventKeys = () => {
  if (typeof window === 'undefined') return {} as Record<number, string>
  try {
    const raw = window.localStorage.getItem(EVENT_KEY_STORAGE)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, string>
    const out: Record<number, string> = {}
    Object.entries(parsed || {}).forEach(([key, value]) => {
      const id = Number(key)
      if (!Number.isFinite(id) || id <= 0) return
      const cleaned = parseEventKey(value)
      if (!cleaned) return
      out[id] = cleaned
    })
    return out
  } catch {
    return {}
  }
}

const saveStoredEventKeys = (value: Record<number, string>) => {
  if (typeof window === 'undefined') return
  try {
    const sanitized: Record<number, string> = {}
    Object.entries(value).forEach(([key, val]) => {
      const id = Number(key)
      if (!Number.isFinite(id) || id <= 0) return
      const cleaned = parseEventKey(val)
      if (!cleaned) return
      sanitized[id] = cleaned
    })
    window.localStorage.setItem(EVENT_KEY_STORAGE, JSON.stringify(sanitized))
  } catch {
    // ignore storage errors
  }
}

const loadPendingReferral = (): PendingReferral | null => {
  if (typeof window === 'undefined') return null
  try {
    const raw = window.localStorage.getItem(PENDING_REFERRAL_STORAGE)
    if (!raw) return null
    const parsed = JSON.parse(raw) as { eventId?: number; refCode?: string }
    const eventId = typeof parsed.eventId === 'number' ? parsed.eventId : null
    const refCode = typeof parsed.refCode === 'string' ? parseRefCode(parsed.refCode) : ''
    if (!eventId || !refCode) return null
    return { eventId, refCode }
  } catch {
    return null
  }
}

const savePendingReferral = (value: PendingReferral) => {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(PENDING_REFERRAL_STORAGE, JSON.stringify(value))
  } catch {
    // ignore storage errors
  }
}

const clearPendingReferral = () => {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.removeItem(PENDING_REFERRAL_STORAGE)
  } catch {
    // ignore storage errors
  }
}

const saveStoredCenter = (center: LatLng) => {
  if (typeof window === 'undefined') return
  window.localStorage.setItem(VIEW_STORAGE_KEY, JSON.stringify(center))
}

function App() {
  const [token, setToken] = useState<string | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [activePage, setActivePage] = useState<AppPage>(() => getPageFromLocation())
  const [adminSection, setAdminSection] = useState<AdminSection>(() => getAdminRouteFromLocation().section)
  const [adminUserId, setAdminUserId] = useState<number | null>(
    () => getAdminRouteFromLocation().userId
  )
  const [profileLoading, setProfileLoading] = useState(false)
  const [profileError, setProfileError] = useState<string | null>(null)
  const [profileNotice, setProfileNotice] = useState<string | null>(null)
  const [referralCode, setReferralCode] = useState<string | null>(null)
  const [toast, setToast] = useState<string | null>(null)
  const [myEvents, setMyEvents] = useState<UserEvent[]>([])
  const [myEventsTotal, setMyEventsTotal] = useState(0)
  const [myEventsLoading, setMyEventsLoading] = useState(false)
  const [topupOpen, setTopupOpen] = useState(false)
  const [topupAmount, setTopupAmount] = useState('')
  const [topupBusy, setTopupBusy] = useState(false)
  const [cardBusy, setCardBusy] = useState(false)
  const [userName, setUserName] = useState<string>('')
  const [userLocation, setUserLocation] = useState<LatLng | null>(null)
  const [viewLocation, setViewLocation] = useState<LatLng | null>(() => loadStoredCenter())
  const [markers, setMarkers] = useState<EventMarker[]>([])
  const [feed, setFeed] = useState<EventCard[]>([])
  const [activeFilters, setActiveFilters] = useState<EventFilter[]>([])
  const [nearbyOnly, setNearbyOnly] = useState(false)
  const [createFilters, setCreateFilters] = useState<EventFilter[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(() => getEventLinkFromLocation().eventId)
  const [selectedEvent, setSelectedEvent] = useState<EventDetail | null>(null)
  const [eventAccessKeys, setEventAccessKeys] = useState<Record<number, string>>(() => {
    const stored = loadStoredEventKeys()
    const link = getEventLinkFromLocation()
    if (link.eventId && link.eventKey) {
      stored[link.eventId] = link.eventKey
    }
    return stored
  })
  const [sharedEvents, setSharedEvents] = useState<Record<number, EventCard>>({})
  const [comments, setComments] = useState<EventComment[]>([])
  const [commentsLoading, setCommentsLoading] = useState(false)
  const [commentBody, setCommentBody] = useState('')
  const [commentSending, setCommentSending] = useState(false)
  const [likeBusy, setLikeBusy] = useState(false)
  const scrollAttemptsRef = useRef(0)
  const scrolledEventRef = useRef<number | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [creating, setCreating] = useState(false)
  const [editingEventId, setEditingEventId] = useState<number | null>(null)
  const [formDefaults, setFormDefaults] = useState<FormDefaults>(EMPTY_FORM_DEFAULTS)
  const [formKey, setFormKey] = useState(0)
  const [adminBusy, setAdminBusy] = useState(false)
  const [adminAccessDenied, setAdminAccessDenied] = useState(false)
  const [adminUsers, setAdminUsers] = useState<AdminUser[]>([])
  const [adminUsersTotal, setAdminUsersTotal] = useState(0)
  const [adminUsersLoading, setAdminUsersLoading] = useState(false)
  const [adminUsersError, setAdminUsersError] = useState<string | null>(null)
  const [adminSearch, setAdminSearch] = useState('')
  const [adminBlockedFilter, setAdminBlockedFilter] = useState<'all' | 'active' | 'blocked'>('all')
  const [adminUserDetail, setAdminUserDetail] = useState<AdminUser | null>(null)
  const [adminUserEvents, setAdminUserEvents] = useState<UserEvent[]>([])
  const [adminUserLoading, setAdminUserLoading] = useState(false)
  const [adminUserError, setAdminUserError] = useState<string | null>(null)
  const [adminBlockReason, setAdminBlockReason] = useState('')
  const [adminBlockBusy, setAdminBlockBusy] = useState(false)
  const [broadcasts, setBroadcasts] = useState<AdminBroadcast[]>([])
  const [broadcastsTotal, setBroadcastsTotal] = useState(0)
  const [broadcastsLoading, setBroadcastsLoading] = useState(false)
  const [broadcastsError, setBroadcastsError] = useState<string | null>(null)
  const [broadcastAudience, setBroadcastAudience] = useState<'all' | 'selected' | 'filter'>('all')
  const [broadcastMessage, setBroadcastMessage] = useState('')
  const [broadcastUserIds, setBroadcastUserIds] = useState('')
  const [broadcastMinBalance, setBroadcastMinBalance] = useState('')
  const [broadcastLastSeenAfter, setBroadcastLastSeenAfter] = useState('')
  const [broadcastButtons, setBroadcastButtons] = useState<BroadcastButton[]>([{ text: '', url: '' }])
  const [broadcastBusy, setBroadcastBusy] = useState(false)
  const [broadcastStartBusyId, setBroadcastStartBusyId] = useState<number | null>(null)
  const [parserSources, setParserSources] = useState<AdminParserSource[]>([])
  const [parserSourcesTotal, setParserSourcesTotal] = useState(0)
  const [parserSourcesLoading, setParserSourcesLoading] = useState(false)
  const [parserEvents, setParserEvents] = useState<AdminParsedEvent[]>([])
  const [parserEventsTotal, setParserEventsTotal] = useState(0)
  const [parserEventsLoading, setParserEventsLoading] = useState(false)
  const [parserStatusFilter, setParserStatusFilter] = useState<'all' | 'pending' | 'imported' | 'error' | 'rejected'>(
    'all'
  )
  const [parserError, setParserError] = useState<string | null>(null)
  const [parserSourceInput, setParserSourceInput] = useState('')
  const [parserSourceTitle, setParserSourceTitle] = useState('')
  const [parserSourceType, setParserSourceType] = useState<'auto' | 'telegram' | 'web' | 'instagram' | 'vk'>('auto')
  const [parserSourceBusy, setParserSourceBusy] = useState(false)
  const [parserParseInput, setParserParseInput] = useState('')
  const [parserParseType, setParserParseType] = useState<'auto' | 'telegram' | 'web' | 'instagram' | 'vk'>('auto')
  const [parserParseBusy, setParserParseBusy] = useState(false)
  const [parserSourceParseBusyId, setParserSourceParseBusyId] = useState<number | null>(null)
  const [parserImportBusyId, setParserImportBusyId] = useState<number | null>(null)
  const [parserRejectBusyId, setParserRejectBusyId] = useState<number | null>(null)
  const [parserGeocodeBusyId, setParserGeocodeBusyId] = useState<number | null>(null)
  const [parserImportDrafts, setParserImportDrafts] = useState<Record<number, ParserImportDraft>>({})
  const [adminLoginUsername, setAdminLoginUsername] = useState('')
  const [adminLoginPassword, setAdminLoginPassword] = useState('')
  const [adminLoginTelegramId, setAdminLoginTelegramId] = useState('')
  const [adminLoginError, setAdminLoginError] = useState<string | null>(null)
  const [adminLoginBusy, setAdminLoginBusy] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)
  const [description, setDescription] = useState('')
  const [createLatLng, setCreateLatLng] = useState<LatLng | null>(null)
  const [uploadedMedia, setUploadedMedia] = useState<UploadedMedia[]>([])
  const [createErrors, setCreateErrors] = useState<CreateErrors>({})
  const mapRef = useRef<HTMLDivElement | null>(null)
  const mapInstance = useRef<L.Map | null>(null)
  const markerLayer = useRef<L.LayerGroup | null>(null)
  const draftMarker = useRef<L.Marker | null>(null)
  const createPanelRef = useRef<HTMLElement | null>(null)
  const mapCardRef = useRef<HTMLElement | null>(null)
  const titleFieldRef = useRef<HTMLElement | null>(null)
  const descriptionFieldRef = useRef<HTMLElement | null>(null)
  const startsAtFieldRef = useRef<HTMLElement | null>(null)
  const contactsFieldRef = useRef<HTMLElement | null>(null)
  const hasLocation = useRef(false)
  const hasUserMovedMap = useRef(false)
  const hasStoredCenter = useRef(viewLocation != null)
  const hasLoadedFeed = useRef(false)
  const isEditing = editingEventId != null
  const isAdmin = Boolean(user && ADMIN_TELEGRAM_IDS.has(user.telegramId))
  const accessKeysList = useMemo(() => {
    const values = Object.values(eventAccessKeys).filter(Boolean)
    return Array.from(new Set(values))
  }, [eventAccessKeys])
  const selectedAccessKey =
    selectedId != null
      ? eventAccessKeys[selectedId] ||
        (selectedEvent && selectedEvent.event.id === selectedId ? selectedEvent.event.accessKey || '' : '')
      : ''
  const feedLocation = useMemo(() => {
    const preferView = hasStoredCenter.current || hasUserMovedMap.current
    if (preferView) return viewLocation ?? userLocation
    return userLocation ?? viewLocation
  }, [userLocation, viewLocation])
  const feedRadiusM = nearbyOnly ? NEARBY_RADIUS_M : 0
  const feedCenter = useMemo(() => {
    if (!feedLocation) return null
    if (!nearbyOnly) return feedLocation
    return userLocation ?? feedLocation
  }, [feedLocation, nearbyOnly, userLocation])
  const canCreate = useMemo(() => !!token && !!(viewLocation || userLocation), [token, viewLocation, userLocation])
  const greeting = userName ? `Hi, ${userName}` : 'Events nearby'
  const { profileDisplayName, profileHandle } = useMemo(() => {
    if (!user) return { profileDisplayName: 'Профиль', profileHandle: '' }
    const full = [user.firstName, user.lastName].filter(Boolean).join(' ').trim()
    if (full) {
      return { profileDisplayName: full, profileHandle: user.username ? `@${user.username}` : '' }
    }
    if (user.username) {
      return { profileDisplayName: `@${user.username}`, profileHandle: '' }
    }
    return { profileDisplayName: 'Пользователь', profileHandle: '' }
  }, [user])
  const ratingValue = typeof user?.rating === 'number' ? user.rating : 0
  const ratingCount = typeof user?.ratingCount === 'number' ? user.ratingCount : 0
  const balanceTokens = typeof user?.balanceTokens === 'number' ? user.balanceTokens : 0
  const mapCenter = viewLocation ?? userLocation
  const mapCenterLabel = mapCenter ? formatCoords(mapCenter.lat, mapCenter.lng) : 'Locating...'
  const pinLabel = createLatLng ? formatCoords(createLatLng.lat, createLatLng.lng) : null
  const createCoordsLabel = createLatLng ? `${createLatLng.lat.toFixed(4)}, ${createLatLng.lng.toFixed(4)}` : null
  const detailEvent = selectedEvent && selectedEvent.event.id === selectedId ? selectedEvent : null
  const uploadedMediaRef = useRef<UploadedMedia[]>([])
  const createFiltersLimitReached = createFilters.length >= MAX_EVENT_FILTERS
  const activeFilterCount = activeFilters.length + (nearbyOnly ? 1 : 0)
  const activeFiltersLabel =
    activeFilterCount > 0 ? `${activeFilterCount} active` : `Up to ${MAX_EVENT_FILTERS}`
  const createErrorOrder: (keyof CreateErrors)[] = ['title', 'description', 'startsAt', 'contacts', 'location']
  const createErrorRefs: Record<keyof CreateErrors, React.RefObject<HTMLElement>> = {
    title: titleFieldRef,
    description: descriptionFieldRef,
    startsAt: startsAtFieldRef,
    contacts: contactsFieldRef,
    location: mapCardRef,
  }

  const clearCreateError = (key: keyof CreateErrors) => {
    setCreateErrors((prev) => {
      if (!prev[key]) return prev
      const next = { ...prev }
      delete next[key]
      return next
    })
  }

  const scrollToCreateError = (errors: CreateErrors) => {
    const first = createErrorOrder.find((key) => errors[key])
    if (!first) return
    const target = createErrorRefs[first]?.current
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: first === 'location' ? 'center' : 'start' })
    }
  }

  const toggleActiveFilter = (id: EventFilter) => {
    setActiveFilters((prev) => (prev.includes(id) ? prev.filter((f) => f !== id) : [...prev, id]))
  }

  const toggleCreateFilter = (id: EventFilter) => {
    setCreateFilters((prev) => {
      if (prev.includes(id)) {
        return prev.filter((f) => f !== id)
      }
      if (prev.length >= MAX_EVENT_FILTERS) {
        return prev
      }
      return [...prev, id]
    })
  }

  const revokePreviews = (items: UploadedMedia[]) => {
    items.forEach((item) => {
      if (item.previewUrl.startsWith('blob:')) {
        URL.revokeObjectURL(item.previewUrl)
      }
    })
  }

  const clearUploadedMedia = () => {
    setUploadedMedia((prev) => {
      revokePreviews(prev)
      return []
    })
  }

  const replaceUploadedMedia = (next: UploadedMedia[]) => {
    setUploadedMedia((prev) => {
      revokePreviews(prev)
      return next
    })
  }

  const resetFormState = (close: boolean) => {
    setEditingEventId(null)
    setCreateErrors({})
    setCreateFilters([])
    setCreateLatLng(null)
    setDescription('')
    setFormDefaults(EMPTY_FORM_DEFAULTS)
    setFormKey((prev) => prev + 1)
    setFormError(null)
    clearUploadedMedia()
    if (close) {
      setCreating(false)
    }
  }

  const buildFormDefaults = (event: EventDetail['event']): FormDefaults => ({
    title: event.title || '',
    startsAt: formatDateTimeLocal(event.startsAt),
    endsAt: formatDateTimeLocal(event.endsAt),
    capacity: event.capacity != null ? String(event.capacity) : '',
    contactTelegram: event.contactTelegram || '',
    contactWhatsapp: event.contactWhatsapp || '',
    contactWechat: event.contactWechat || '',
    contactFbMessenger: event.contactFbMessenger || '',
    contactSnapchat: event.contactSnapchat || '',
    isPrivate: Boolean(event.isPrivate),
  })

  const focusMapAt = (lat: number, lng: number) => {
    hasUserMovedMap.current = true
    if (mapCardRef.current) {
      mapCardRef.current.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
    const map = mapInstance.current
    if (map) {
      logDebug('map_focus_point', { lat, lng })
      const nextZoom = Math.max(map.getZoom(), FOCUS_ZOOM)
      map.setView([lat, lng], nextZoom, { animate: true })
    } else {
      setViewLocation({ lat, lng })
    }
  }

  const focusCreatePin = () => {
    if (!createLatLng) return
    focusMapAt(createLatLng.lat, createLatLng.lng)
  }

  const openCreateForm = (source: string) => {
    if (creating) return
    logInfo('toggle_create_form', { open: true, source })
    resetFormState(false)
    setCreating(true)
  }

  const closeCreateForm = (source: string) => {
    logInfo('toggle_create_form', { open: false, source })
    resetFormState(true)
  }

  const toggleCreateForm = () => {
    if (creating) {
      closeCreateForm('hero')
    } else {
      openCreateForm('hero')
    }
  }

  const navigateToPage = (page: AppPage) => {
    setActivePage(page)
    if (page !== 'profile') {
      setTopupOpen(false)
    }
    if (typeof window === 'undefined') return
    try {
      const url = new URL(window.location.href)
      if (page === 'profile') {
        url.pathname = PROFILE_PATH
      } else if (page === 'admin') {
        url.pathname = '/admin/users'
      } else {
        url.pathname = '/'
      }
      if (page === 'profile') {
        url.searchParams.delete('eventId')
        url.searchParams.delete('eventKey')
      }
      window.history.pushState({}, '', url.toString())
    } catch {
      // ignore invalid URL updates
    }
  }

  const navigateToAdmin = (section: AdminSection, userId?: number | null) => {
    setActivePage('admin')
    setAdminSection(section)
    setAdminUserId(userId ?? null)
    if (typeof window === 'undefined') return
    try {
      const url = new URL(window.location.href)
      if (section === 'broadcasts') {
        url.pathname = '/admin/broadcasts'
      } else if (section === 'parser') {
        url.pathname = '/admin/parser'
      } else if (section === 'user' && userId) {
        url.pathname = `/admin/users/${userId}`
      } else {
        url.pathname = '/admin/users'
      }
      url.searchParams.delete('eventId')
      url.searchParams.delete('eventKey')
      window.history.pushState({}, '', url.toString())
    } catch {
      // ignore invalid URL updates
    }
  }

  const openProfile = () => {
    if (!user) return
    navigateToPage('profile')
  }

  const goHome = () => {
    navigateToPage('home')
  }

  const showToast = (message: string) => {
    setToast(message)
    window.setTimeout(() => setToast(null), 2500)
  }

  const clearActiveFilters = () => {
    if (activeFilters.length === 0 && !nearbyOnly) return
    logInfo('feed_filters_clear', { count: activeFilters.length, nearbyOnly })
    setActiveFilters([])
    setNearbyOnly(false)
  }

  const getDistanceLabel = (lat: number, lng: number) => {
    if (!userLocation) return null
    const label = formatDistanceLabel(getDistanceKm(userLocation, { lat, lng }))
    return label || null
  }

  const startEditFromDetail = (source?: EventDetail | null) => {
    const target = source ?? detailEvent ?? selectedEvent
    if (!target) return
    const event = target.event
    setEditingEventId(event.id)
    setError(null)
    setFormError(null)
    setCreateErrors({})
    setDescription(event.description || '')
    setCreateFilters(event.filters || [])
    setCreateLatLng({ lat: event.lat, lng: event.lng })
    setFormDefaults(buildFormDefaults(event))
    setFormKey((prev) => prev + 1)
    replaceUploadedMedia(target.media.map((url) => ({ fileUrl: url, previewUrl: url })))
    setCreating(true)
    focusMapAt(event.lat, event.lng)
    requestAnimationFrame(() => {
      createPanelRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
  }

  const renderDescription = (value: string) => {
    const lines = value.split('\n')
    return lines.map((line, index) => {
      const coords = parseCoordsFromLine(line)
      const content = coords ? (
        <span className="detail-coords">
          {COORDS_LABEL}{' '}
          <a
            href={buildCoordsUrl(coords.lat, coords.lng)}
            className="link-button"
            onClick={(event) => {
              event.preventDefault()
              focusMapAt(coords.lat, coords.lng)
            }}
            aria-label={`Center map on ${formatCoords(coords.lat, coords.lng)}`}
          >
            {formatCoords(coords.lat, coords.lng)}
          </a>
        </span>
      ) : (
        line
      )
      return (
        <React.Fragment key={`desc-${index}`}>
          {index > 0 && <br />}
          {content}
        </React.Fragment>
      )
    })
  }

  const closeTopupModal = () => {
    setTopupOpen(false)
    setTopupAmount('')
  }

  const handleProfileEventClick = (eventId: number) => {
    goHome()
    setSelectedId(eventId)
  }

  const handleTokenTopup = async () => {
    if (!token) return
    setProfileError(null)
    setProfileNotice(null)
    const parsed = Number(topupAmount)
    if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
      setProfileError('Введите целое число токенов.')
      return
    }
    if (parsed < 1 || parsed > MAX_TOPUP_TOKENS) {
      setProfileError(`Сумма должна быть от 1 до ${MAX_TOPUP_TOKENS}.`)
      return
    }
    setTopupBusy(true)
    try {
      const res = await topupToken(token, parsed)
      setUser((prev) => (prev ? { ...prev, balanceTokens: res.balanceTokens } : prev))
      setProfileNotice('Баланс обновлён.')
      closeTopupModal()
    } catch (err: any) {
      setProfileError(err.message)
    } finally {
      setTopupBusy(false)
    }
  }

  const handleCardTopup = async () => {
    if (!token || !CARD_TOPUP_ENABLED) return
    setProfileError(null)
    setProfileNotice(null)
    setCardBusy(true)
    try {
      const res = await topupCard(token)
      const tg = (window as any).Telegram?.WebApp
      if (res.invoiceId && tg?.openInvoice) {
        tg.openInvoice(res.invoiceId)
        return
      }
      if (res.paymentUrl) {
        window.open(res.paymentUrl, '_blank', 'noopener,noreferrer')
        return
      }
      setProfileNotice('Ссылка на оплату будет доступна позже.')
    } catch (err: any) {
      setProfileError(err.message)
    } finally {
      setCardBusy(false)
    }
  }

  useEffect(() => {
    if (API_URL_ERROR) {
      const suffix = API_URL ? ` (current: ${API_URL})` : ''
      logError('app_init_error', { error: API_URL_ERROR, apiUrl: API_URL })
      setError(`${API_URL_ERROR}${suffix}`)
      return
    }
    logInfo('app_init', { apiUrl: API_URL, logLevel: getActiveLogLevel() })
    const tg = (window as any).Telegram?.WebApp
    const locationLink = getEventLinkFromLocation()
    if (locationLink.eventId && locationLink.refCode) {
      savePendingReferral({ eventId: locationLink.eventId, refCode: locationLink.refCode })
    }
    if (tg) {
      tg.ready()
      tg.expand()
      logDebug('telegram_webapp_ready')
      const startLink = getEventLinkFromTelegram()
      if (startLink.eventId) {
        setSelectedId((prev) => prev ?? startLink.eventId)
        if (startLink.eventKey) {
          setEventAccessKeys((prev) => ({ ...prev, [startLink.eventId]: startLink.eventKey }))
        }
      }
      if (startLink.eventId && startLink.refCode) {
        savePendingReferral({ eventId: startLink.eventId, refCode: startLink.refCode })
      }
    }
    const initData = tg?.initData || getInitDataFromLocation()
    if (!initData) {
      if (getPageFromLocation() === 'admin') {
        logWarn('auth_missing_init_data_admin')
        return
      }
      logWarn('auth_missing_init_data')
      setError('Open this app inside Telegram WebApp (or add ?initData=... for browser testing).')
      return
    }

    logDebug('auth_start', { initDataLength: initData.length })
    authTelegram(initData)
      .then((res) => {
        setToken(res.accessToken)
        setUser(res.user)
        const name = [res.user.firstName, res.user.lastName].filter(Boolean).join(' ').trim()
        setUserName(name || (res.user.username ? `@${res.user.username}` : ''))
        setError(null)
        setLogToken(res.accessToken)
        const pending = loadPendingReferral()
        if (pending) {
          claimReferral(res.accessToken, pending)
            .then((claim) => {
              if (claim.awarded) {
                if (typeof claim.inviteeBalanceTokens === 'number') {
                  setUser((prev) =>
                    prev ? { ...prev, balanceTokens: claim.inviteeBalanceTokens } : prev
                  )
                }
                showToast('+100 токенов вам и другу')
              }
              clearPendingReferral()
            })
            .catch((err) => {
              logWarn('referral_claim_error', { message: err.message })
            })
        }
        logInfo('auth_success', { userId: res.user.id, telegramId: res.user.telegramId })
      })
      .catch((err) => {
        setLogToken(null)
        setUser(null)
        logError('auth_error', { message: err.message })
        setError(`Auth error: ${err.message}`)
      })
  }, [])

  useEffect(() => {
    if (typeof window === 'undefined') return
    const handler = () => {
      setActivePage(getPageFromLocation())
      const route = getAdminRouteFromLocation()
      setAdminSection(route.section)
      setAdminUserId(route.userId)
    }
    window.addEventListener('popstate', handler)
    return () => window.removeEventListener('popstate', handler)
  }, [])

  useEffect(() => {
    if (activePage !== 'profile') {
      setTopupOpen(false)
    }
  }, [activePage])

  useEffect(() => {
    if (!token || activePage !== 'profile') return
    let cancelled = false
    setProfileLoading(true)
    setProfileError(null)
    setProfileNotice(null)
    getMe(token)
      .then((res) => {
        if (cancelled) return
        setUser(res)
        const name = [res.firstName, res.lastName].filter(Boolean).join(' ').trim()
        setUserName(name || (res.username ? `@${res.username}` : ''))
      })
      .catch((err) => {
        if (!cancelled) setProfileError(err.message)
      })
      .finally(() => {
        if (!cancelled) setProfileLoading(false)
      })

    setMyEventsLoading(true)
    getMyEvents(token, 20, 0)
      .then((res) => {
        if (cancelled) return
        setMyEvents(res.items)
        setMyEventsTotal(res.total)
      })
      .catch((err) => {
        if (!cancelled) setProfileError(err.message)
      })
      .finally(() => {
        if (!cancelled) setMyEventsLoading(false)
      })

    return () => {
      cancelled = true
    }
  }, [token, activePage])

  useEffect(() => {
    if (activePage !== 'admin') return
    setAdminAccessDenied(false)
    if (!token) return
    if (adminSection === 'users') {
      loadAdminUsers()
      return
    }
    if (adminSection === 'user' && adminUserId) {
      loadAdminUserDetail(adminUserId)
      return
    }
    if (adminSection === 'broadcasts') {
      loadBroadcasts()
      return
    }
    if (adminSection === 'parser') {
      loadParserSources()
      loadParsedEvents()
    }
  }, [activePage, adminSection, adminUserId, token])

  useEffect(() => {
    if (activePage !== 'admin' || adminSection !== 'parser' || !token) return
    loadParsedEvents()
  }, [activePage, adminSection, parserStatusFilter, token])

  useEffect(() => {
    const setViewportHeight = () => {
      const vh = window.innerHeight * 0.01
      document.documentElement.style.setProperty('--vh', `${vh}px`)
    }
    setViewportHeight()
    window.addEventListener('resize', setViewportHeight)
    return () => window.removeEventListener('resize', setViewportHeight)
  }, [])

  useEffect(() => {
    if (typeof document === 'undefined') return
    if (!isAndroidDevice()) return
    const root = document.documentElement
    root.classList.add('android')
    return () => root.classList.remove('android')
  }, [])

  useEffect(() => {
    if (selectedId == null) {
      scrollAttemptsRef.current = 0
      scrolledEventRef.current = null
      return
    }
    if (scrolledEventRef.current === selectedId) return
    const tryScroll = () => {
      if (scrolledEventRef.current === selectedId) return
      const target = document.querySelector(`[data-event-id="${selectedId}"]`)
      if (target instanceof HTMLElement) {
        target.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' })
        scrolledEventRef.current = selectedId
        return
      }
      const fallback = document.querySelector('.detail-panel')
      if (fallback instanceof HTMLElement) {
        fallback.scrollIntoView({ behavior: 'smooth', block: 'start', inline: 'nearest' })
        scrolledEventRef.current = selectedId
        return
      }
      if (scrollAttemptsRef.current < 6) {
        scrollAttemptsRef.current += 1
        window.setTimeout(tryScroll, 300)
      }
    }
    scrollAttemptsRef.current = 0
    tryScroll()
  }, [selectedId, feed.length, selectedEvent])

  useEffect(() => {
    if (!creating) return
    const target = createPanelRef.current
    if (!target) return
    const raf = requestAnimationFrame(() => {
      target.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
    return () => cancelAnimationFrame(raf)
  }, [creating])

  useEffect(() => {
    if (!creating) {
      setCreateErrors({})
    }
  }, [creating])

  useEffect(() => {
    if (!isEditing) return
    if (!creating) {
      setCreating(true)
    }
    const raf = requestAnimationFrame(() => {
      createPanelRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
    return () => cancelAnimationFrame(raf)
  }, [isEditing, creating])

  useEffect(() => {
    if (activePage !== 'home') return
    updateEventLinkInLocation(selectedId, selectedAccessKey)
  }, [selectedId, selectedAccessKey, activePage])

  useEffect(() => {
    saveStoredEventKeys(eventAccessKeys)
  }, [eventAccessKeys])

  useEffect(() => {
    setLogToken(token)
  }, [token])

  useEffect(() => {
    if (!token) return
    if (!navigator.geolocation) {
      logWarn('geolocation_unavailable')
      setViewLocation((prev) => prev ?? DEFAULT_CENTER)
      return
    }
    let cancelled = false

    const handleSuccess = (pos: GeolocationPosition) => {
      if (cancelled) return
      hasLocation.current = true
      const next = { lat: pos.coords.latitude, lng: pos.coords.longitude }
      logDebug('geolocation_success', { lat: next.lat, lng: next.lng, accuracy: pos.coords.accuracy })
      setUserLocation((prev) => {
        if (prev && prev.lat === next.lat && prev.lng === next.lng) {
          return prev
        }
        return next
      })
      setViewLocation(next)
    }

    const handleError = () => {
      if (cancelled) return
      logWarn('geolocation_error')
      if (!hasLocation.current) {
        setViewLocation((prev) => prev ?? DEFAULT_CENTER)
      }
    }

    const requestLocation = () => {
      navigator.geolocation.getCurrentPosition(handleSuccess, handleError, {
        enableHighAccuracy: true,
        timeout: 5000,
        maximumAge: 30000,
      })
    }

    requestLocation()
    const intervalId = window.setInterval(requestLocation, LOCATION_POLL_MS)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [token])

  useEffect(() => {
    if (!token || !userLocation || !hasLocation.current) return
    let cancelled = false

    const send = () => {
      if (cancelled) return
      logDebug('location_update_send', { lat: userLocation.lat, lng: userLocation.lng })
      updateLocation(token, userLocation.lat, userLocation.lng).catch(() => {})
    }

    send()
    const intervalId = window.setInterval(send, LOCATION_POLL_MS)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [token, userLocation])

  useEffect(() => {
    if (!viewLocation) return
    saveStoredCenter(viewLocation)
  }, [viewLocation])

  useEffect(() => {
    uploadedMediaRef.current = uploadedMedia
  }, [uploadedMedia])

  useEffect(() => {
    return () => {
      revokePreviews(uploadedMediaRef.current)
    }
  }, [])

  useEffect(() => {
    if (!mapRef.current || !viewLocation) return
    if (!mapInstance.current) {
      mapInstance.current = L.map(mapRef.current, { attributionControl: false, zoomControl: false }).setView(
        [viewLocation.lat, viewLocation.lng],
        13
      )
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '',
      }).addTo(mapInstance.current)
      markerLayer.current = L.layerGroup().addTo(mapInstance.current)

      mapInstance.current.on('dragstart zoomstart', () => {
        hasUserMovedMap.current = true
        logDebug('map_interaction_start')
      })
      mapInstance.current.on('click', (e: L.LeafletMouseEvent) => {
        const next = { lat: e.latlng.lat, lng: e.latlng.lng }
        logDebug('map_click', { lat: next.lat, lng: next.lng })
        setCreateLatLng(next)
        setDescription((prev) => upsertCoordsInDescription(prev, next.lat, next.lng))
        setCreateErrors((prev) => {
          if (!prev.location) return prev
          const nextErrors = { ...prev }
          delete nextErrors.location
          return nextErrors
        })
      })
      mapInstance.current.on('moveend', () => {
        const center = mapInstance.current?.getCenter()
        if (!center) return
        const next = { lat: center.lat, lng: center.lng }
        logDebug('map_move_end', { lat: next.lat, lng: next.lng })
        setViewLocation((prev) => {
          if (!prev) return next
          const sameLat = Math.abs(prev.lat - next.lat) < 0.00001
          const sameLng = Math.abs(prev.lng - next.lng) < 0.00001
          return sameLat && sameLng ? prev : next
        })
      })
      requestAnimationFrame(() => {
        mapInstance.current?.invalidateSize()
      })
    }
  }, [viewLocation])

  useEffect(() => {
    return () => {
      if (mapInstance.current) {
        mapInstance.current.off()
        mapInstance.current.remove()
        mapInstance.current = null
      }
      markerLayer.current = null
      draftMarker.current = null
    }
  }, [])

  useEffect(() => {
    const map = mapInstance.current
    const node = mapRef.current
    if (!map || !node) return

    let frame: number | null = null
    const refresh = () => {
      if (frame) cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        map.invalidateSize()
        const center = viewLocation ?? map.getCenter()
        map.setView([center.lat, center.lng], map.getZoom(), { animate: false })
      })
    }

    refresh()

    const observer = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(refresh) : null
    observer?.observe(node)
    window.addEventListener('resize', refresh)
    window.addEventListener('orientationchange', refresh)

    return () => {
      if (frame) cancelAnimationFrame(frame)
      observer?.disconnect()
      window.removeEventListener('resize', refresh)
      window.removeEventListener('orientationchange', refresh)
    }
  }, [viewLocation])

  useEffect(() => {
    if (!mapInstance.current || !viewLocation) return
    const center = mapInstance.current.getCenter()
    if (center.lat === viewLocation.lat && center.lng === viewLocation.lng) return
    mapInstance.current.setView([viewLocation.lat, viewLocation.lng], mapInstance.current.getZoom(), { animate: false })
  }, [viewLocation])

  useEffect(() => {
    if (!token || !feedCenter) return
    let cancelled = false

    const load = () => {
      if (cancelled) return
      const showLoading = !hasLoadedFeed.current
      if (showLoading) {
        setLoading(true)
      }
      logDebug('feed_load_start', { lat: feedCenter.lat, lng: feedCenter.lng, radiusM: feedRadiusM })
      Promise.all([
        getNearby(token, feedCenter.lat, feedCenter.lng, feedRadiusM, activeFilters, accessKeysList),
        getFeed(token, feedCenter.lat, feedCenter.lng, feedRadiusM, activeFilters, accessKeysList),
      ])
        .then(([nearby, feedItems]) => {
          if (cancelled) return
          setMarkers(mergeMarkersWithShared(nearby, sharedEvents))
          setFeed(mergeFeedWithShared(feedItems, sharedEvents))
          setError(null)
          logInfo('feed_load_success', { markers: nearby.length, feed: feedItems.length })
        })
        .catch((err) => {
          if (!cancelled) setError(err.message)
          logError('feed_load_error', { message: err.message })
        })
        .finally(() => {
          if (cancelled) return
          if (showLoading) {
            setLoading(false)
            hasLoadedFeed.current = true
          }
        })
    }

    load()
    const intervalId = window.setInterval(load, LOCATION_POLL_MS)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [token, feedCenter, feedRadiusM, activeFilters, accessKeysList, sharedEvents])

  useEffect(() => {
    if (!markerLayer.current) return
    markerLayer.current.clearLayers()
    markers.forEach((m) => {
      const marker = L.marker([m.lat, m.lng], { icon: pulseIcon })
      marker.on('click', () => setSelectedId(m.id))
      markerLayer.current?.addLayer(marker)
    })
  }, [markers])

  useEffect(() => {
    if (!mapInstance.current) return
    if (!createLatLng) {
      if (draftMarker.current) {
        mapInstance.current.removeLayer(draftMarker.current)
        draftMarker.current = null
      }
      return
    }
    const latlng = L.latLng(createLatLng.lat, createLatLng.lng)
    if (!draftMarker.current) {
      draftMarker.current = L.marker(latlng, { icon: pulseIcon })
      draftMarker.current.addTo(mapInstance.current)
    } else {
      draftMarker.current.setLatLng(latlng)
    }
  }, [createLatLng])

  useEffect(() => {
    if (!token || selectedId == null) return
    logDebug('event_select', { eventId: selectedId })
    getEvent(token, selectedId, selectedAccessKey)
      .then((detail) => {
        const detailAccessKey = detail.event.accessKey || selectedAccessKey
        if (detailAccessKey) {
          setEventAccessKeys((prev) => {
            if (prev[detail.event.id] === detailAccessKey) return prev
            return { ...prev, [detail.event.id]: detailAccessKey }
          })
        }
        if (detail.event.isPrivate) {
          const card = buildEventCardFromDetail(detail, detailAccessKey)
          setSharedEvents((prev) => ({ ...prev, [detail.event.id]: card }))
          setFeed((prev) => mergeFeedWithShared(prev, { [detail.event.id]: card }))
          setMarkers((prev) => mergeMarkersWithShared(prev, { [detail.event.id]: card }))
        }
        setSelectedEvent(detail)
      })
      .catch((err) => {
        logError('event_load_error', { message: err.message, eventId: selectedId })
        setError(err.message)
      })
  }, [token, selectedId, selectedAccessKey])

  useEffect(() => {
    if (!token || selectedId == null) {
      setComments([])
      setCommentBody('')
      return
    }
    let cancelled = false
    setCommentsLoading(true)
    setCommentBody('')
    getEventComments(token, selectedId, 100, 0, selectedAccessKey)
      .then((items) => {
        if (!cancelled) setComments(items)
      })
      .catch((err) => {
        if (!cancelled) logError('comments_load_error', { message: err.message, eventId: selectedId })
      })
      .finally(() => {
        if (!cancelled) setCommentsLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [token, selectedId, selectedAccessKey])


  const handleJoin = async () => {
    if (!token || !selectedEvent) return
    setError(null)
    setLoading(true)
    logInfo('join_event_start', { eventId: selectedEvent.event.id })
    try {
      await joinEvent(token, selectedEvent.event.id, selectedAccessKey)
      const updated = await getEvent(token, selectedEvent.event.id, selectedAccessKey)
      setSelectedEvent(updated)
      setFeed((prev) =>
        prev.map((item) =>
          item.id === updated.event.id
            ? {
                ...item,
                participantsCount: updated.event.participantsCount,
                isJoined: updated.isJoined,
                contactTelegram: updated.event.contactTelegram,
                contactWhatsapp: updated.event.contactWhatsapp,
                contactWechat: updated.event.contactWechat,
                contactFbMessenger: updated.event.contactFbMessenger,
                contactSnapchat: updated.event.contactSnapchat,
              }
            : item
        )
      )
      logInfo('join_event_success', { eventId: selectedEvent.event.id })
    } catch (err: any) {
      logError('join_event_error', { message: err.message, eventId: selectedEvent.event.id })
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleLeave = async () => {
    if (!token || !selectedEvent) return
    setError(null)
    setLoading(true)
    logInfo('leave_event_start', { eventId: selectedEvent.event.id })
    try {
      await leaveEvent(token, selectedEvent.event.id, selectedAccessKey)
      const updated = await getEvent(token, selectedEvent.event.id, selectedAccessKey)
      setSelectedEvent(updated)
      setFeed((prev) =>
        prev.map((item) =>
          item.id === updated.event.id
            ? {
                ...item,
                participantsCount: updated.event.participantsCount,
                isJoined: updated.isJoined,
                contactTelegram: updated.event.contactTelegram,
                contactWhatsapp: updated.event.contactWhatsapp,
                contactWechat: updated.event.contactWechat,
                contactFbMessenger: updated.event.contactFbMessenger,
                contactSnapchat: updated.event.contactSnapchat,
              }
            : item
        )
      )
      logInfo('leave_event_success', { eventId: selectedEvent.event.id })
    } catch (err: any) {
      logError('leave_event_error', { message: err.message, eventId: selectedEvent.event.id })
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleLikeToggle = async () => {
    if (!token || !selectedEvent || likeBusy) return
    setError(null)
    setLikeBusy(true)
    const eventId = selectedEvent.event.id
    try {
      const res = selectedEvent.event.isLiked
        ? await unlikeEvent(token, eventId, selectedAccessKey)
        : await likeEvent(token, eventId, selectedAccessKey)
      setSelectedEvent((prev) =>
        prev
          ? {
              ...prev,
              event: { ...prev.event, likesCount: res.likesCount, isLiked: res.isLiked },
            }
          : prev
      )
      setFeed((prev) =>
        prev.map((item) =>
          item.id === eventId ? { ...item, likesCount: res.likesCount, isLiked: res.isLiked } : item
        )
      )
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLikeBusy(false)
    }
  }

  const handleAddComment = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!token || !selectedEvent || commentSending) return
    const trimmed = commentBody.trim()
    if (!trimmed) {
      setError('Comment cannot be empty')
      return
    }
    if (trimmed.length > MAX_COMMENT_LENGTH) {
      setError(`Комментарий слишком длинный (макс ${MAX_COMMENT_LENGTH})`)
      return
    }
    setError(null)
    setCommentSending(true)
    const eventId = selectedEvent.event.id
    try {
      const res = await addEventComment(token, eventId, trimmed, selectedAccessKey)
      setComments((prev) => [...prev, res.comment])
      setCommentBody('')
      setSelectedEvent((prev) =>
        prev
          ? {
              ...prev,
              event: { ...prev.event, commentsCount: res.commentsCount },
            }
          : prev
      )
      setFeed((prev) =>
        prev.map((item) =>
          item.id === eventId ? { ...item, commentsCount: res.commentsCount } : item
        )
      )
    } catch (err: any) {
      setError(err.message)
    } finally {
      setCommentSending(false)
    }
  }

  const handleShareEvent = async () => {
    if (!selectedEvent) return
    if (!token) {
      setError('Сначала войдите в приложение')
      return
    }
    const eventId = selectedEvent.event.id
    const accessKey = selectedEvent.event.accessKey || eventAccessKeys[eventId]
    let code = referralCode
    if (!code) {
      try {
        const res = await getReferralCode(token)
        code = res.code
        setReferralCode(res.code)
      } catch (err: any) {
        setError(err.message || 'Не удалось получить реф-код')
        return
      }
    }
    const url = buildShareUrl(eventId, accessKey, code || undefined)
    if (!url) {
      setError('Не удалось создать ссылку для шаринга')
      return
    }
    const title = selectedEvent.event.title || 'Gigme event'
    const text = `Event: ${title}`
    const tg = (window as any).Telegram?.WebApp
    const tgShareUrl = `https://t.me/share/url?url=${encodeURIComponent(url)}&text=${encodeURIComponent(text)}`
    try {
      if (tg?.openTelegramLink) {
        tg.openTelegramLink(tgShareUrl)
        return
      }
      if (navigator.share) {
        await navigator.share({ title, text, url })
        return
      }
      if (navigator.clipboard) {
        await navigator.clipboard.writeText(url)
        showToast('Ссылка скопирована')
        return
      }
    } catch (err: any) {
      logError('share_error', { message: err.message })
    }
    window.prompt('Ссылка на событие', url)
  }

  const handleCreate = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (!token) return
    if (uploading) {
      setFormError('Please wait for photos to finish uploading')
      setError(null)
      return
    }
    const form = new FormData(e.currentTarget)
    const title = String(form.get('title') || '')
    const startsAtLocal = String(form.get('startsAt') || '')
    const endsAtLocal = String(form.get('endsAt') || '')
    const capacityRaw = String(form.get('capacity') || '')
    const isPrivate = form.get('isPrivate') === 'on'
    const contactTelegram = String(form.get('contactTelegram') || '').trim()
    const contactWhatsapp = String(form.get('contactWhatsapp') || '').trim()
    const contactWechat = String(form.get('contactWechat') || '').trim()
    const contactFbMessenger = String(form.get('contactFbMessenger') || '').trim()
    const contactSnapchat = String(form.get('contactSnapchat') || '').trim()
    const descriptionValue = description.trim()
    const contactEntries = [
      contactTelegram,
      contactWhatsapp,
      contactWechat,
      contactFbMessenger,
      contactSnapchat,
    ]
    const nextErrors: CreateErrors = {}
    if (!title) nextErrors.title = 'Enter an event title'
    if (!descriptionValue) nextErrors.description = 'Add a description'
    if (!startsAtLocal) nextErrors.startsAt = 'Select date and time'
    if (!createLatLng) nextErrors.location = 'Pick a point on the map'
    const filledContacts = contactEntries.filter(Boolean).length
    if (filledContacts === 0) {
      nextErrors.contacts = 'Provide at least one contact'
    }
    if (contactEntries.some((value) => value.length > MAX_CONTACT_LENGTH)) {
      nextErrors.contacts = `Contact is too long (max ${MAX_CONTACT_LENGTH} characters)`
    }
    if (description.length > MAX_DESCRIPTION) {
      nextErrors.description = `Description is too long (max ${MAX_DESCRIPTION} characters)`
    }
    if (Object.keys(nextErrors).length > 0) {
      logWarn('create_event_invalid_form', { titleLength: title.length, descriptionLength: descriptionValue.length })
      setCreateErrors(nextErrors)
      setFormError('Please fill in required fields')
      setError(null)
      scrollToCreateError(nextErrors)
      return
    }

    const startsAtISO = new Date(startsAtLocal).toISOString()
    const endsAtISO = endsAtLocal ? new Date(endsAtLocal).toISOString() : undefined
    const endsAtPayload = endsAtLocal ? endsAtISO : ''
    const capacity = capacityRaw ? Number(capacityRaw) : undefined
    const point = createLatLng
    if (!point) return
    const filters = createFilters
    const media = uploadedMedia.map((item) => item.fileUrl)
    const createPayload = {
      title,
      description: descriptionValue,
      startsAt: startsAtISO,
      endsAt: endsAtISO,
      lat: point.lat,
      lng: point.lng,
      capacity,
      media,
      filters,
      isPrivate,
      contactTelegram: contactTelegram || undefined,
      contactWhatsapp: contactWhatsapp || undefined,
      contactWechat: contactWechat || undefined,
      contactFbMessenger: contactFbMessenger || undefined,
      contactSnapchat: contactSnapchat || undefined,
    }
    const updatePayload = {
      title,
      description: descriptionValue,
      startsAt: startsAtISO,
      endsAt: endsAtPayload,
      lat: point.lat,
      lng: point.lng,
      capacity,
      media,
      filters,
      contactTelegram,
      contactWhatsapp,
      contactWechat,
      contactFbMessenger,
      contactSnapchat,
    }

    setError(null)
    setFormError(null)
    setCreateErrors({})
    setLoading(true)
    try {
      if (isEditing && editingEventId != null) {
        logInfo('admin_update_event_start', {
          eventId: editingEventId,
          titleLength: title.length,
          descriptionLength: descriptionValue.length,
          startsAt: startsAtISO,
          endsAt: endsAtISO,
          lat: point.lat,
          lng: point.lng,
          capacity,
          filters,
          mediaCount: media.length,
          contacts: contactEntries.filter(Boolean).length,
        })
        await updateEventAdmin(token, editingEventId, updatePayload)
        const updated = await getEvent(token, editingEventId, eventAccessKeys[editingEventId])
        setSelectedEvent(updated)
        const refreshCenter = nearbyOnly && userLocation ? userLocation : feedLocation
        if (refreshCenter) {
          const [nearby, feedItems] = await Promise.all([
            getNearby(token, refreshCenter.lat, refreshCenter.lng, feedRadiusM, activeFilters, accessKeysList),
            getFeed(token, refreshCenter.lat, refreshCenter.lng, feedRadiusM, activeFilters, accessKeysList),
          ])
          setMarkers(mergeMarkersWithShared(nearby, sharedEvents))
          setFeed(mergeFeedWithShared(feedItems, sharedEvents))
        } else {
          setMarkers((prev) =>
            prev.map((marker) =>
              marker.id === updated.event.id
                ? {
                    ...marker,
                    title: updated.event.title,
                    startsAt: updated.event.startsAt,
                    lat: updated.event.lat,
                    lng: updated.event.lng,
                    filters: updated.event.filters || [],
                  }
                : marker
            )
          )
          setFeed((prev) =>
            sortFeedItems(
              prev.map((item) =>
                item.id === updated.event.id
                  ? {
                      ...item,
                      title: updated.event.title,
                      description: updated.event.description,
                      startsAt: updated.event.startsAt,
                      endsAt: updated.event.endsAt,
                      lat: updated.event.lat,
                      lng: updated.event.lng,
                      capacity: updated.event.capacity,
                      promotedUntil: updated.event.promotedUntil,
                      filters: updated.event.filters || [],
                      contactTelegram: updated.event.contactTelegram,
                      contactWhatsapp: updated.event.contactWhatsapp,
                      contactWechat: updated.event.contactWechat,
                      contactFbMessenger: updated.event.contactFbMessenger,
                      contactSnapchat: updated.event.contactSnapchat,
                      isPrivate: updated.event.isPrivate,
                      accessKey: updated.event.accessKey,
                      thumbnailUrl: updated.media[0],
                    }
                  : item
              )
            )
          )
        }
        resetFormState(true)
        logInfo('admin_update_event_success', { eventId: editingEventId })
        return
      }

      logInfo('create_event_start', {
        titleLength: title.length,
        descriptionLength: descriptionValue.length,
        startsAt: startsAtISO,
        endsAt: endsAtISO,
        lat: point.lat,
        lng: point.lng,
        capacity,
        filters,
        mediaCount: uploadedMedia.length,
        contacts: contactEntries.filter(Boolean).length,
      })
      const created = await createEvent(token, createPayload)
      if (created.accessKey) {
        setEventAccessKeys((prev) => {
          if (prev[created.eventId] === created.accessKey) return prev
          return { ...prev, [created.eventId]: created.accessKey }
        })
      }
      const newMarker: EventMarker = {
        id: created.eventId,
        title,
        startsAt: startsAtISO,
        lat: point.lat,
        lng: point.lng,
        isPromoted: false,
        filters,
      }
      const newFeedItem: EventCard = {
        id: created.eventId,
        title,
        description: descriptionValue,
        startsAt: startsAtISO,
        endsAt: endsAtISO,
        lat: point.lat,
        lng: point.lng,
        capacity,
        promotedUntil: undefined,
        creatorName: userName || 'You',
        thumbnailUrl: media[0],
        participantsCount: 1,
        likesCount: 0,
        commentsCount: 0,
        filters,
        contactTelegram: contactTelegram || undefined,
        contactWhatsapp: contactWhatsapp || undefined,
        contactWechat: contactWechat || undefined,
        contactFbMessenger: contactFbMessenger || undefined,
        contactSnapchat: contactSnapchat || undefined,
        isJoined: true,
        isLiked: false,
        isPrivate,
        accessKey: created.accessKey,
      }
      if (isPrivate) {
        setSharedEvents((prev) => ({ ...prev, [created.eventId]: newFeedItem }))
      }
      const matchesActiveFilters =
        activeFilters.length === 0 || filters.some((filter) => activeFilters.includes(filter))
      if (matchesActiveFilters) {
        setMarkers((prev) => {
          const exists = prev.some((m) => m.id === newMarker.id)
          if (exists) return prev
          return [newMarker, ...prev]
        })
        setFeed((prev) => {
          const exists = prev.some((e) => e.id === newFeedItem.id)
          if (exists) return prev
          return [newFeedItem, ...prev]
        })
      }
      mapInstance.current?.setView([point.lat, point.lng], mapInstance.current?.getZoom() ?? 13)
      resetFormState(true)
      const refreshCenter = nearbyOnly && userLocation ? userLocation : feedLocation
      if (refreshCenter) {
        const [nearby, feedItems] = await Promise.all([
          getNearby(token, refreshCenter.lat, refreshCenter.lng, feedRadiusM, activeFilters, accessKeysList),
          getFeed(token, refreshCenter.lat, refreshCenter.lng, feedRadiusM, activeFilters, accessKeysList),
        ])
        setMarkers(() => {
          const hasCreated = nearby.some((m) => m.id === newMarker.id)
          const base = hasCreated ? nearby : [newMarker, ...nearby]
          return mergeMarkersWithShared(base, sharedEvents)
        })
        setFeed(() => {
          const hasCreated = feedItems.some((e) => e.id === newFeedItem.id)
          const base = hasCreated ? feedItems : [newFeedItem, ...feedItems]
          return mergeFeedWithShared(base, sharedEvents)
        })
      }
      logInfo('create_event_success', { eventId: created.eventId })
    } catch (err: any) {
      logError('create_event_error', { message: err.message })
      setFormError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const removeUploadedMediaAt = (index: number) => {
    setUploadedMedia((prev) => {
      if (index < 0 || index >= prev.length) return prev
      const next = [...prev]
      const [removed] = next.splice(index, 1)
      if (removed?.previewUrl.startsWith('blob:')) {
        URL.revokeObjectURL(removed.previewUrl)
      }
      return next
    })
  }

  const handleFileUpload = async (files: FileList | null) => {
    if (!token || !files) return
    const fileArray = Array.from(files).slice(0, 5 - uploadedMedia.length)
    if (fileArray.length === 0) return
    setUploading(true)
    const presignEnabled = isPresignEnabled()
    try {
      logInfo('media_upload_start', { count: fileArray.length })
      for (const originalFile of fileArray) {
        const file = await optimizeImageForUpload(originalFile)
        if (file !== originalFile) {
          logDebug('media_upload_optimized', {
            fileName: originalFile.name,
            originalBytes: originalFile.size,
            optimizedBytes: file.size,
          })
        }
        const previewUrl = URL.createObjectURL(file)
        try {
          let fileUrl = ''
          if (presignEnabled) {
            try {
              // Prefer presigned uploads to keep large files off the API server.
              logDebug('media_presign_request', { fileName: file.name, sizeBytes: file.size, contentType: file.type })
              const presign = await presignMedia(token, {
                fileName: file.name,
                contentType: file.type,
                sizeBytes: file.size,
              })
              try {
                new URL(presign.uploadUrl)
              } catch {
                throw new Error(
                  `Upload URL is invalid. Check S3_PUBLIC_ENDPOINT (got ${presign.uploadUrl}).`
                )
              }
              const uploadRes = await fetch(presign.uploadUrl, {
                method: 'PUT',
                headers: { 'Content-Type': file.type },
                body: file,
              })
              if (!uploadRes.ok) {
                throw new Error(`Upload failed (${uploadRes.status})`)
              }
              fileUrl = presign.fileUrl
              logInfo('media_upload_presigned_success', { fileName: file.name })
            } catch (presignErr: any) {
              const uploaded = await uploadMedia(token, file)
              fileUrl = uploaded.fileUrl
              if (!fileUrl) {
                throw presignErr
              }
              logInfo('media_upload_fallback_success', { fileName: file.name })
            }
          } else {
            const uploaded = await uploadMedia(token, file)
            fileUrl = uploaded.fileUrl
            logInfo('media_upload_direct_success', { fileName: file.name })
          }
          setUploadedMedia((prev) => [...prev, { fileUrl, previewUrl }])
        } catch (err) {
          URL.revokeObjectURL(previewUrl)
          throw err
        }
      }
    } catch (err: any) {
      logError('media_upload_error', { message: err.message })
      setFormError(err.message)
      setError(null)
    } finally {
      setUploading(false)
    }
  }

  const handleAdminDelete = async () => {
    if (!token) return
    const target = detailEvent ?? selectedEvent
    if (!target) return
    const confirmed = window.confirm('Delete this event? This cannot be undone.')
    if (!confirmed) return
    setAdminBusy(true)
    setError(null)
    const eventId = target.event.id
    try {
      await deleteEventAdmin(token, eventId)
      setFeed((prev) => prev.filter((item) => item.id !== eventId))
      setMarkers((prev) => prev.filter((marker) => marker.id !== eventId))
      setSharedEvents((prev) => {
        if (!prev[eventId]) return prev
        const next = { ...prev }
        delete next[eventId]
        return next
      })
      setEventAccessKeys((prev) => {
        if (!prev[eventId]) return prev
        const next = { ...prev }
        delete next[eventId]
        return next
      })
      setSelectedEvent(null)
      setSelectedId(null)
      if (isEditing && editingEventId === eventId) {
        resetFormState(true)
      }
      logInfo('admin_delete_event_success', { eventId })
    } catch (err: any) {
      logError('admin_delete_event_error', { message: err.message, eventId })
      setError(err.message)
    } finally {
      setAdminBusy(false)
    }
  }

  const handleAdminPromote = async (mode: '24h' | '7d' | 'clear') => {
    if (!token) return
    const target = detailEvent ?? selectedEvent
    if (!target) return
    setAdminBusy(true)
    setError(null)
    const eventId = target.event.id
    const payload =
      mode === 'clear'
        ? { clear: true }
        : { durationMinutes: mode === '24h' ? 24 * 60 : 7 * 24 * 60 }
    try {
      await promoteEvent(token, eventId, payload)
      const updated = await getEvent(token, eventId, eventAccessKeys[eventId])
      const isPromoted = updated.event.promotedUntil
        ? new Date(updated.event.promotedUntil).getTime() > Date.now()
        : false
      setSelectedEvent(updated)
      setMarkers((prev) =>
        prev.map((marker) => (marker.id === eventId ? { ...marker, isPromoted } : marker))
      )
      setFeed((prev) =>
        sortFeedItems(
          prev.map((item) =>
            item.id === eventId ? { ...item, promotedUntil: updated.event.promotedUntil } : item
          )
        )
      )
      logInfo('admin_promote_event_success', { eventId, mode })
    } catch (err: any) {
      logError('admin_promote_event_error', { message: err.message, eventId, mode })
      setError(err.message)
    } finally {
      setAdminBusy(false)
    }
  }

  const handleAdminApiError = (err: any, setter?: (value: string | null) => void) => {
    const status = err?.status
    if (status === 401 || status === 403) {
      setAdminAccessDenied(true)
      return
    }
    if (setter) setter(err?.message || 'Ошибка')
  }

  const loadAdminUsers = async () => {
    if (!token) return
    setAdminUsersLoading(true)
    setAdminUsersError(null)
    setAdminAccessDenied(false)
    try {
      const blocked =
        adminBlockedFilter === 'all' ? undefined : adminBlockedFilter === 'blocked' ? 'true' : 'false'
      const res = await adminListUsers(token, {
        search: adminSearch.trim() || undefined,
        blocked,
        limit: 50,
        offset: 0,
      })
      setAdminUsers(res.items)
      setAdminUsersTotal(res.total)
    } catch (err: any) {
      handleAdminApiError(err, setAdminUsersError)
    } finally {
      setAdminUsersLoading(false)
    }
  }

  const loadAdminUserDetail = async (id: number) => {
    if (!token) return
    setAdminUserLoading(true)
    setAdminUserError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminGetUser(token, id)
      setAdminUserDetail(res.user)
      setAdminUserEvents(res.createdEvents)
      setAdminBlockReason('')
    } catch (err: any) {
      handleAdminApiError(err, setAdminUserError)
    } finally {
      setAdminUserLoading(false)
    }
  }

  const handleAdminSearch = (event: React.FormEvent) => {
    event.preventDefault()
    if (activePage !== 'admin') return
    navigateToAdmin('users')
    loadAdminUsers()
  }

  const handleAdminBlockToggle = async () => {
    if (!token || !adminUserDetail) return
    setAdminBlockBusy(true)
    setAdminUserError(null)
    setAdminAccessDenied(false)
    try {
      if (adminUserDetail.isBlocked) {
        await adminUnblockUser(token, adminUserDetail.id)
      } else {
        await adminBlockUser(token, adminUserDetail.id, adminBlockReason.trim())
      }
      await loadAdminUserDetail(adminUserDetail.id)
    } catch (err: any) {
      handleAdminApiError(err, setAdminUserError)
    } finally {
      setAdminBlockBusy(false)
    }
  }

  const loadBroadcasts = async () => {
    if (!token) return
    setBroadcastsLoading(true)
    setBroadcastsError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminListBroadcasts(token, 50, 0)
      setBroadcasts(res.items)
      setBroadcastsTotal(res.total)
    } catch (err: any) {
      handleAdminApiError(err, setBroadcastsError)
    } finally {
      setBroadcastsLoading(false)
    }
  }

  const buildParserImportDraft = (item: AdminParsedEvent): ParserImportDraft => {
    const fallbackLat = mapCenter?.lat ?? DEFAULT_CENTER.lat
    const fallbackLng = mapCenter?.lng ?? DEFAULT_CENTER.lng
    return {
      startsAt: item.dateTime ? formatDateTimeLocal(item.dateTime) : '',
      lat: String(fallbackLat),
      lng: String(fallbackLng),
      addressLabel: item.location || '',
    }
  }

  const loadParserSources = async () => {
    if (!token) return
    setParserSourcesLoading(true)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminListParserSources(token, 100, 0)
      setParserSources(res.items)
      setParserSourcesTotal(res.total)
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserSourcesLoading(false)
    }
  }

  const loadParsedEvents = async () => {
    if (!token) return
    setParserEventsLoading(true)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      const status = parserStatusFilter === 'all' ? undefined : parserStatusFilter
      const res = await adminListParsedEvents(token, { status, limit: 100, offset: 0 })
      setParserEvents(res.items)
      setParserEventsTotal(res.total)
      setParserImportDrafts((prev) => {
        const next = { ...prev }
        res.items.forEach((item) => {
          if (!next[item.id]) {
            next[item.id] = buildParserImportDraft(item)
          }
        })
        return next
      })
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserEventsLoading(false)
    }
  }

  const handleCreateParserSource = async () => {
    if (!token) return
    const input = parserSourceInput.trim()
    if (!input) {
      setParserError('Укажите URL или канал для источника')
      return
    }
    setParserSourceBusy(true)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      await adminCreateParserSource(token, {
        sourceType: parserSourceType,
        input,
        title: parserSourceTitle.trim() || undefined,
        isActive: true,
      })
      setParserSourceInput('')
      setParserSourceTitle('')
      await loadParserSources()
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserSourceBusy(false)
    }
  }

  const handleToggleParserSource = async (source: AdminParserSource) => {
    if (!token) return
    setParserSourceParseBusyId(source.id)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      await adminUpdateParserSource(token, source.id, { isActive: !source.isActive })
      await loadParserSources()
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserSourceParseBusyId(null)
    }
  }

  const handleParseSource = async (sourceId: number) => {
    if (!token) return
    setParserSourceParseBusyId(sourceId)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminParseSource(token, sourceId)
      if (res.error) {
        setParserError(res.error)
      }
      await loadParserSources()
      await loadParsedEvents()
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
      await loadParserSources()
      await loadParsedEvents()
    } finally {
      setParserSourceParseBusyId(null)
    }
  }

  const handleParseInputQuick = async () => {
    if (!token) return
    const input = parserParseInput.trim()
    if (!input) {
      setParserError('Введите URL или Telegram канал')
      return
    }
    setParserParseBusy(true)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminParseInput(token, { sourceType: parserParseType, input })
      if (res.error) {
        setParserError(res.error)
      } else {
        setParserParseInput('')
      }
      await loadParsedEvents()
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
      await loadParsedEvents()
    } finally {
      setParserParseBusy(false)
    }
  }

  const updateParserDraft = (id: number, patch: Partial<ParserImportDraft>) => {
    setParserImportDrafts((prev) => ({ ...prev, [id]: { ...prev[id], ...patch } }))
  }

  const handleParserGeocode = async (item: AdminParsedEvent) => {
    if (!token) return
    const draft = parserImportDrafts[item.id] || buildParserImportDraft(item)
    const query = (draft.addressLabel || item.location || item.name || '').trim()
    if (!query) {
      setParserError('Для геокодинга нужен адрес или название')
      return
    }
    setParserGeocodeBusyId(item.id)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminGeocodeLocation(token, { query, limit: 1 })
      const first = res.items[0]
      if (!first) {
        setParserError('Координаты не найдены')
        return
      }
      updateParserDraft(item.id, {
        lat: String(first.lat),
        lng: String(first.lng),
        addressLabel: first.displayName || draft.addressLabel,
      })
      showToast('Координаты заполнены')
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserGeocodeBusyId(null)
    }
  }

  const handleImportParsedEvent = async (item: AdminParsedEvent) => {
    if (!token) return
    const draft = parserImportDrafts[item.id] || buildParserImportDraft(item)
    const lat = Number(draft.lat)
    const lng = Number(draft.lng)
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      setParserError('Проверьте координаты (lat/lng)')
      return
    }
    let startsAt: string | undefined
    if (draft.startsAt.trim()) {
      const parsed = new Date(draft.startsAt)
      if (Number.isNaN(parsed.getTime())) {
        setParserError('Некорректный startsAt')
        return
      }
      startsAt = parsed.toISOString()
    }
    setParserImportBusyId(item.id)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      const res = await adminImportParsedEvent(token, item.id, {
        startsAt,
        lat,
        lng,
        addressLabel: draft.addressLabel.trim() || undefined,
      })
      showToast('Событие добавлено')
      await loadParsedEvents()
      setSelectedId(res.eventId)
      navigateToPage('home')
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserImportBusyId(null)
    }
  }

  const handleRejectParsed = async (id: number) => {
    if (!token) return
    setParserRejectBusyId(id)
    setParserError(null)
    setAdminAccessDenied(false)
    try {
      await adminRejectParsedEvent(token, id)
      await loadParsedEvents()
    } catch (err: any) {
      handleAdminApiError(err, setParserError)
    } finally {
      setParserRejectBusyId(null)
    }
  }

  const updateBroadcastButton = (index: number, field: 'text' | 'url', value: string) => {
    setBroadcastButtons((prev) =>
      prev.map((item, i) => (i === index ? { ...item, [field]: value } : item))
    )
  }

  const addBroadcastButton = () => {
    setBroadcastButtons((prev) => [...prev, { text: '', url: '' }])
  }

  const removeBroadcastButton = (index: number) => {
    setBroadcastButtons((prev) => prev.filter((_, i) => i !== index))
  }

  const handleCreateBroadcast = async () => {
    if (!token) return
    const message = broadcastMessage.trim()
    if (!message) {
      setBroadcastsError('Введите сообщение')
      return
    }
    if (message.length > 4096) {
      setBroadcastsError('Сообщение слишком длинное')
      return
    }
    setBroadcastBusy(true)
    setBroadcastsError(null)
    setAdminAccessDenied(false)
    try {
      const cleanedButtons = broadcastButtons
        .map((btn) => ({ text: btn.text.trim(), url: btn.url.trim() }))
        .filter((btn) => btn.text && btn.url)
      const payload: {
        audience: 'all' | 'selected' | 'filter'
        userIds?: number[]
        filters?: { blocked?: boolean; minBalance?: number; lastSeenAfter?: string }
        message: string
        buttons?: BroadcastButton[]
      } = {
        audience: broadcastAudience,
        message,
      }
      if (cleanedButtons.length > 0) {
        payload.buttons = cleanedButtons
      }
      if (broadcastAudience === 'selected') {
        const ids = broadcastUserIds
          .split(',')
          .map((item) => Number(item.trim()))
          .filter((val) => Number.isFinite(val) && val > 0)
        if (ids.length === 0) {
          setBroadcastsError('Укажите userIds через запятую')
          setBroadcastBusy(false)
          return
        }
        payload.userIds = ids
      }
      if (broadcastAudience === 'filter') {
        const filters: { blocked?: boolean; minBalance?: number; lastSeenAfter?: string } = {
          blocked: false,
        }
        if (broadcastMinBalance.trim()) {
          const parsed = Number(broadcastMinBalance)
          if (!Number.isFinite(parsed) || parsed < 0) {
            setBroadcastsError('Некорректный минимальный баланс')
            setBroadcastBusy(false)
            return
          }
          filters.minBalance = parsed
        }
        if (broadcastLastSeenAfter.trim()) {
          const date = new Date(broadcastLastSeenAfter)
          if (Number.isNaN(date.getTime())) {
            setBroadcastsError('Некорректная дата lastSeenAfter')
            setBroadcastBusy(false)
            return
          }
          filters.lastSeenAfter = date.toISOString()
        }
        payload.filters = filters
      }
      await adminCreateBroadcast(token, payload)
      setBroadcastMessage('')
      setBroadcastUserIds('')
      setBroadcastMinBalance('')
      setBroadcastLastSeenAfter('')
      setBroadcastButtons([{ text: '', url: '' }])
      await loadBroadcasts()
    } catch (err: any) {
      handleAdminApiError(err, setBroadcastsError)
    } finally {
      setBroadcastBusy(false)
    }
  }

  const handleStartBroadcast = async (id: number) => {
    if (!token) return
    setBroadcastStartBusyId(id)
    setBroadcastsError(null)
    setAdminAccessDenied(false)
    try {
      await adminStartBroadcast(token, id)
      await loadBroadcasts()
    } catch (err: any) {
      handleAdminApiError(err, setBroadcastsError)
    } finally {
      setBroadcastStartBusyId(null)
    }
  }

  const openEventFromAdmin = (eventId: number) => {
    setSelectedId(eventId)
    navigateToPage('home')
  }

  const handleAdminLogin = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!adminLoginUsername.trim() || !adminLoginPassword) {
      setAdminLoginError('Введите логин и пароль')
      return
    }
    setAdminLoginBusy(true)
    setAdminLoginError(null)
    try {
      const telegramId = Number(adminLoginTelegramId.trim())
      const payload: { username: string; password: string; telegramId?: number } = {
        username: adminLoginUsername.trim(),
        password: adminLoginPassword,
      }
      if (Number.isFinite(telegramId) && telegramId > 0) {
        payload.telegramId = telegramId
      }
      const res = await adminLogin(payload)
      setToken(res.accessToken)
      setUser(res.user)
      setLogToken(res.accessToken)
      setAdminAccessDenied(false)
      loadAdminUsers()
    } catch (err: any) {
      setAdminLoginError(err?.message || 'Ошибка входа')
    } finally {
      setAdminLoginBusy(false)
    }
  }

  const renderAdminUsers = () => (
    <section className="panel admin-panel">
      <div className="panel__header">
        <h2>Пользователи</h2>
        <span className="chip chip--ghost">Всего: {adminUsersTotal}</span>
      </div>
      <form className="admin-filters" onSubmit={handleAdminSearch}>
        <input
          type="text"
          placeholder="Поиск по username, имени или Telegram ID"
          value={adminSearch}
          onChange={(event) => setAdminSearch(event.target.value)}
        />
        <select
          value={adminBlockedFilter}
          onChange={(event) => setAdminBlockedFilter(event.target.value as 'all' | 'active' | 'blocked')}
        >
          <option value="all">Все</option>
          <option value="active">Активные</option>
          <option value="blocked">Заблокированные</option>
        </select>
        <button type="submit" className="button button--accent" disabled={adminUsersLoading}>
          {adminUsersLoading ? 'Поиск…' : 'Найти'}
        </button>
      </form>
      {adminUsersError && <div className="status status--error">{adminUsersError}</div>}
      {adminUsersLoading ? (
        <div className="status status--loading">Загрузка…</div>
      ) : (
        <div className="admin-table">
          <div className="admin-table__row admin-table__head">
            <div>Пользователь</div>
            <div>Баланс</div>
            <div>Создан</div>
            <div>Last seen</div>
            <div>Статус</div>
            <div />
          </div>
          {adminUsers.length === 0 ? (
            <div className="admin-table__row admin-table__empty">Нет пользователей</div>
          ) : (
            adminUsers.map((item) => {
              const name = [item.firstName, item.lastName].filter(Boolean).join(' ').trim()
              return (
                <div className="admin-table__row" key={item.id}>
                  <div className="admin-user">
                    {item.photoUrl ? (
                      <img src={item.photoUrl} alt={name || item.username || 'User'} loading="lazy" decoding="async" />
                    ) : (
                      <div className="admin-user__placeholder" />
                    )}
                    <div>
                      <div className="admin-user__name">{name || item.username || `ID ${item.id}`}</div>
                      <div className="admin-user__meta">
                        {item.username ? `@${item.username}` : '—'} · TG {item.telegramId}
                      </div>
                    </div>
                  </div>
                  <div>{(item.balanceTokens || 0).toLocaleString()} GT</div>
                  <div>{formatTimestamp(item.createdAt)}</div>
                  <div>{formatTimestamp(item.lastSeenAt)}</div>
                  <div>
                    <span className={`badge ${item.isBlocked ? 'badge--danger' : 'badge--ok'}`}>
                      {item.isBlocked ? 'Blocked' : 'Active'}
                    </span>
                  </div>
                  <div>
                    <button
                      type="button"
                      className="button button--ghost button--compact"
                      onClick={() => navigateToAdmin('user', item.id)}
                    >
                      Открыть
                    </button>
                  </div>
                </div>
              )
            })
          )}
        </div>
      )}
    </section>
  )

  const renderAdminUserDetail = () => {
    if (adminUserLoading) {
      return <div className="status status--loading">Загрузка…</div>
    }
    if (adminUserError) {
      return <div className="status status--error">{adminUserError}</div>
    }
    if (!adminUserDetail) {
      return <div className="status status--error">Пользователь не найден</div>
    }
    const name = [adminUserDetail.firstName, adminUserDetail.lastName].filter(Boolean).join(' ').trim()
    return (
      <div className="admin-detail">
        <button
          type="button"
          className="button button--ghost button--compact"
          onClick={() => navigateToAdmin('users')}
        >
          ← Назад к списку
        </button>
        <section className="panel admin-panel">
          <div className="panel__header">
            <h2>Пользователь</h2>
            <span className="chip chip--ghost">ID {adminUserDetail.id}</span>
          </div>
          <div className="admin-user-card">
            <div className="admin-user">
              {adminUserDetail.photoUrl ? (
                <img
                  src={adminUserDetail.photoUrl}
                  alt={name || adminUserDetail.username || 'User'}
                  loading="lazy"
                  decoding="async"
                />
              ) : (
                <div className="admin-user__placeholder" />
              )}
              <div>
                <div className="admin-user__name">{name || adminUserDetail.username || `ID ${adminUserDetail.id}`}</div>
                <div className="admin-user__meta">
                  {adminUserDetail.username ? `@${adminUserDetail.username}` : '—'} · TG {adminUserDetail.telegramId}
                </div>
              </div>
            </div>
            <div className="admin-user-card__stats">
              <div>Баланс: {(adminUserDetail.balanceTokens || 0).toLocaleString()} GT</div>
              <div>Создан: {formatTimestamp(adminUserDetail.createdAt)}</div>
              <div>Last seen: {formatTimestamp(adminUserDetail.lastSeenAt)}</div>
              <div>
                Статус:{' '}
                <span className={`badge ${adminUserDetail.isBlocked ? 'badge--danger' : 'badge--ok'}`}>
                  {adminUserDetail.isBlocked ? 'Blocked' : 'Active'}
                </span>
              </div>
            </div>
            <div className="admin-block">
              {!adminUserDetail.isBlocked && (
                <input
                  type="text"
                  placeholder="Причина блокировки"
                  value={adminBlockReason}
                  onChange={(event) => setAdminBlockReason(event.target.value)}
                />
              )}
              <button
                type="button"
                className={`button ${adminUserDetail.isBlocked ? 'button--ghost' : 'button--danger'}`}
                onClick={handleAdminBlockToggle}
                disabled={adminBlockBusy}
              >
                {adminBlockBusy ? 'Сохранение…' : adminUserDetail.isBlocked ? 'Разблокировать' : 'Заблокировать'}
              </button>
            </div>
          </div>
        </section>
        <section className="panel admin-panel">
          <div className="panel__header">
            <h2>Созданные события</h2>
            <span className="chip chip--ghost">{adminUserEvents.length}</span>
          </div>
          {adminUserEvents.length === 0 ? (
            <div className="status status--neutral">Нет событий</div>
          ) : (
            <div className="admin-events">
              {adminUserEvents.map((event) => (
                <button
                  type="button"
                  className="admin-event"
                  key={event.id}
                  onClick={() => openEventFromAdmin(event.id)}
                >
                  <div className="admin-event__title">{event.title}</div>
                  <div className="admin-event__meta">
                    {formatTimestamp(event.startsAt)} · {event.participantsCount} участников
                  </div>
                </button>
              ))}
            </div>
          )}
        </section>
      </div>
    )
  }

  const renderAdminBroadcasts = () => (
    <div className="admin-broadcasts">
      <section className="panel admin-panel">
        <div className="panel__header">
          <h2>Новая рассылка</h2>
        </div>
        <div className="admin-form">
          <label>
            Аудитория
            <select
              value={broadcastAudience}
              onChange={(event) => setBroadcastAudience(event.target.value as 'all' | 'selected' | 'filter')}
            >
              <option value="all">Все активные</option>
              <option value="selected">Выбранные</option>
              <option value="filter">Фильтр</option>
            </select>
          </label>
          {broadcastAudience === 'selected' && (
            <label>
              User IDs
              <input
                type="text"
                placeholder="1,2,3"
                value={broadcastUserIds}
                onChange={(event) => setBroadcastUserIds(event.target.value)}
              />
            </label>
          )}
          {broadcastAudience === 'filter' && (
            <div className="admin-filter-grid">
              <label>
                Мин. баланс
                <input
                  type="number"
                  min="0"
                  value={broadcastMinBalance}
                  onChange={(event) => setBroadcastMinBalance(event.target.value)}
                />
              </label>
              <label>
                Last seen после
                <input
                  type="datetime-local"
                  value={broadcastLastSeenAfter}
                  onChange={(event) => setBroadcastLastSeenAfter(event.target.value)}
                />
              </label>
            </div>
          )}
          <label>
            Сообщение
            <textarea
              maxLength={4096}
              value={broadcastMessage}
              onChange={(event) => setBroadcastMessage(event.target.value)}
            />
          </label>
          <div className="admin-buttons">
            <div className="admin-buttons__header">
              Кнопки
              <button type="button" className="button button--ghost button--compact" onClick={addBroadcastButton}>
                + Добавить
              </button>
            </div>
            {broadcastButtons.map((btn, index) => (
              <div className="admin-buttons__row" key={`btn-${index}`}>
                <input
                  type="text"
                  placeholder="Текст"
                  value={btn.text}
                  onChange={(event) => updateBroadcastButton(index, 'text', event.target.value)}
                />
                <input
                  type="text"
                  placeholder="URL"
                  value={btn.url}
                  onChange={(event) => updateBroadcastButton(index, 'url', event.target.value)}
                />
                <button
                  type="button"
                  className="button button--ghost button--compact"
                  onClick={() => removeBroadcastButton(index)}
                  disabled={broadcastButtons.length === 1}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
          <button type="button" className="button button--accent" onClick={handleCreateBroadcast} disabled={broadcastBusy}>
            {broadcastBusy ? 'Создание…' : 'Создать'}
          </button>
          {broadcastsError && <div className="status status--error">{broadcastsError}</div>}
        </div>
      </section>
      <section className="panel admin-panel">
        <div className="panel__header">
          <h2>История</h2>
          <div className="admin-history-actions">
            <span className="chip chip--ghost">Всего: {broadcastsTotal}</span>
            <button type="button" className="button button--ghost button--compact" onClick={loadBroadcasts}>
              Обновить
            </button>
          </div>
        </div>
        {broadcastsLoading ? (
          <div className="status status--loading">Загрузка…</div>
        ) : (
          <div className="admin-table">
            <div className="admin-table__row admin-table__head">
              <div>ID</div>
              <div>Создано</div>
              <div>Аудитория</div>
              <div>Статус</div>
              <div>Прогресс</div>
              <div />
            </div>
            {broadcasts.length === 0 ? (
              <div className="admin-table__row admin-table__empty">Нет рассылок</div>
            ) : (
              broadcasts.map((item) => (
                <div className="admin-table__row" key={item.id}>
                  <div>#{item.id}</div>
                  <div>{formatTimestamp(item.createdAt)}</div>
                  <div>{item.audience}</div>
                  <div>
                    <span className="badge badge--ghost">{item.status}</span>
                  </div>
                  <div>
                    {item.sent}/{item.failed}/{item.targeted}
                  </div>
                  <div>
                    <button
                      type="button"
                      className="button button--ghost button--compact"
                      disabled={item.status !== 'pending' || broadcastStartBusyId === item.id}
                      onClick={() => handleStartBroadcast(item.id)}
                    >
                      {broadcastStartBusyId === item.id ? 'Старт…' : 'Запустить'}
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </section>
    </div>
  )

  const renderAdminParser = () => (
    <div className="admin-parser">
      <section className="panel admin-panel">
        <div className="panel__header">
          <h2>Источники парсинга</h2>
          <div className="admin-history-actions">
            <span className="chip chip--ghost">Всего: {parserSourcesTotal}</span>
            <button type="button" className="button button--ghost button--compact" onClick={loadParserSources}>
              Обновить
            </button>
          </div>
        </div>
        <div className="admin-form">
          <label>
            Название
            <input
              type="text"
              value={parserSourceTitle}
              onChange={(event) => setParserSourceTitle(event.target.value)}
              placeholder="Например: Amsterdam Telegram"
            />
          </label>
          <label>
            Источник (URL или канал)
            <input
              type="text"
              value={parserSourceInput}
              onChange={(event) => setParserSourceInput(event.target.value)}
              placeholder="https://t.me/s/channel или channelName"
            />
          </label>
          <label>
            Тип
            <select
              value={parserSourceType}
              onChange={(event) =>
                setParserSourceType(event.target.value as 'auto' | 'telegram' | 'web' | 'instagram' | 'vk')
              }
            >
              <option value="auto">auto</option>
              <option value="telegram">telegram</option>
              <option value="web">web</option>
              <option value="instagram">instagram</option>
              <option value="vk">vk</option>
            </select>
          </label>
          <button
            type="button"
            className="button button--accent"
            onClick={handleCreateParserSource}
            disabled={parserSourceBusy}
          >
            {parserSourceBusy ? 'Сохранение…' : 'Добавить источник'}
          </button>
        </div>
        {parserSourcesLoading ? (
          <div className="status status--loading">Загрузка…</div>
        ) : (
          <div className="admin-table">
            <div className="admin-table__row admin-table__head">
              <div>Название</div>
              <div>Input</div>
              <div>Тип</div>
              <div>Статус</div>
              <div>Last parsed</div>
              <div />
            </div>
            {parserSources.length === 0 ? (
              <div className="admin-table__row admin-table__empty">Нет источников</div>
            ) : (
              parserSources.map((source) => (
                <div className="admin-table__row" key={source.id}>
                  <div>{source.title || `#${source.id}`}</div>
                  <div className="admin-parser__input">{source.input}</div>
                  <div>{source.sourceType}</div>
                  <div>
                    <span className={`badge ${source.isActive ? 'badge--ok' : 'badge--danger'}`}>
                      {source.isActive ? 'active' : 'disabled'}
                    </span>
                  </div>
                  <div>{formatTimestamp(source.lastParsedAt)}</div>
                  <div className="admin-parser-actions">
                    <button
                      type="button"
                      className="button button--ghost button--compact"
                      onClick={() => handleParseSource(source.id)}
                      disabled={parserSourceParseBusyId === source.id}
                    >
                      {parserSourceParseBusyId === source.id ? 'Парсинг…' : 'Парсить'}
                    </button>
                    <button
                      type="button"
                      className="button button--ghost button--compact"
                      onClick={() => handleToggleParserSource(source)}
                      disabled={parserSourceParseBusyId === source.id}
                    >
                      {source.isActive ? 'Выключить' : 'Включить'}
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </section>

      <section className="panel admin-panel">
        <div className="panel__header">
          <h2>Быстрый парсинг</h2>
        </div>
        <div className="admin-form admin-form--inline">
          <input
            type="text"
            value={parserParseInput}
            onChange={(event) => setParserParseInput(event.target.value)}
            placeholder="URL или Telegram канал"
          />
          <select
            value={parserParseType}
            onChange={(event) => setParserParseType(event.target.value as 'auto' | 'telegram' | 'web' | 'instagram' | 'vk')}
          >
            <option value="auto">auto</option>
            <option value="telegram">telegram</option>
            <option value="web">web</option>
            <option value="instagram">instagram</option>
            <option value="vk">vk</option>
          </select>
          <button type="button" className="button button--accent" onClick={handleParseInputQuick} disabled={parserParseBusy}>
            {parserParseBusy ? 'Парсинг…' : 'Запустить'}
          </button>
        </div>
        {parserError && <div className="status status--error">{parserError}</div>}
      </section>

      <section className="panel admin-panel">
        <div className="panel__header">
          <h2>Спарсенные события</h2>
          <div className="admin-history-actions">
            <span className="chip chip--ghost">Всего: {parserEventsTotal}</span>
            <select
              value={parserStatusFilter}
              onChange={(event) =>
                setParserStatusFilter(event.target.value as 'all' | 'pending' | 'imported' | 'error' | 'rejected')
              }
            >
              <option value="all">Все</option>
              <option value="pending">pending</option>
              <option value="imported">imported</option>
              <option value="error">error</option>
              <option value="rejected">rejected</option>
            </select>
            <button type="button" className="button button--ghost button--compact" onClick={loadParsedEvents}>
              Обновить
            </button>
          </div>
        </div>
        {parserEventsLoading ? (
          <div className="status status--loading">Загрузка…</div>
        ) : parserEvents.length === 0 ? (
          <div className="status status--neutral">Нет спарсенных событий</div>
        ) : (
          <div className="admin-parser-events">
            {parserEvents.map((item) => {
              const draft = parserImportDrafts[item.id] || buildParserImportDraft(item)
              return (
                <div className="admin-parser-event" key={item.id}>
                  <div className="admin-parser-event__header">
                    <div>
                      <div className="admin-event__title">{item.name || 'Без названия'}</div>
                      <div className="admin-event__meta">
                        {item.sourceType} · {formatTimestamp(item.dateTime)} · {formatTimestamp(item.parsedAt)}
                      </div>
                    </div>
                    <span className="badge badge--ghost">{item.status}</span>
                  </div>
                  {item.location && <div className="admin-parser-event__location">{item.location}</div>}
                  {item.description && <div className="admin-parser-event__description">{item.description}</div>}
                  {item.links?.length > 0 && (
                    <div className="admin-parser-event__links">
                      {item.links.map((link) => (
                        <a key={`${item.id}-${link}`} href={link} target="_blank" rel="noreferrer">
                          {link}
                        </a>
                      ))}
                    </div>
                  )}
                  {item.parserError && <div className="status status--error">{item.parserError}</div>}
                  {item.status === 'pending' && (
                    <div className="admin-parser-import">
                      <label>
                        StartsAt
                        <input
                          type="datetime-local"
                          value={draft.startsAt}
                          onChange={(event) => updateParserDraft(item.id, { startsAt: event.target.value })}
                        />
                      </label>
                      <label>
                        Lat
                        <input
                          type="number"
                          step="any"
                          value={draft.lat}
                          onChange={(event) => updateParserDraft(item.id, { lat: event.target.value })}
                        />
                      </label>
                      <label>
                        Lng
                        <input
                          type="number"
                          step="any"
                          value={draft.lng}
                          onChange={(event) => updateParserDraft(item.id, { lng: event.target.value })}
                        />
                      </label>
                      <label>
                        Address
                        <input
                          type="text"
                          value={draft.addressLabel}
                          onChange={(event) => updateParserDraft(item.id, { addressLabel: event.target.value })}
                        />
                        <button
                          type="button"
                          className="button button--ghost button--compact"
                          onClick={() => handleParserGeocode(item)}
                          disabled={parserGeocodeBusyId === item.id}
                        >
                          {parserGeocodeBusyId === item.id ? 'Поиск…' : 'Автокоординаты'}
                        </button>
                      </label>
                      <div className="admin-parser-actions">
                        <button
                          type="button"
                          className="button button--accent button--compact"
                          onClick={() => handleImportParsedEvent(item)}
                          disabled={parserImportBusyId === item.id}
                        >
                          {parserImportBusyId === item.id ? 'Импорт…' : 'Добавить в приложение'}
                        </button>
                        <button
                          type="button"
                          className="button button--ghost button--compact"
                          onClick={() => handleRejectParsed(item.id)}
                          disabled={parserRejectBusyId === item.id}
                        >
                          {parserRejectBusyId === item.id ? '...' : 'Отклонить'}
                        </button>
                      </div>
                    </div>
                  )}
                  {item.status === 'imported' && item.importedEventId && (
                    <button
                      type="button"
                      className="button button--ghost button--compact"
                      onClick={() => openEventFromAdmin(item.importedEventId!)}
                    >
                      Открыть событие #{item.importedEventId}
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </section>
    </div>
  )

  const renderAdminPanel = () => {
    if (!token) {
      return (
        <section className="panel admin-panel">
          <div className="panel__header">
            <h2>Админ вход</h2>
          </div>
          <form className="admin-form" onSubmit={handleAdminLogin}>
            <label>
              Логин
              <input
                type="text"
                value={adminLoginUsername}
                onChange={(event) => setAdminLoginUsername(event.target.value)}
              />
            </label>
            <label>
              Пароль
              <input
                type="password"
                value={adminLoginPassword}
                onChange={(event) => setAdminLoginPassword(event.target.value)}
              />
            </label>
            <label>
              Telegram ID (если несколько админов)
              <input
                type="number"
                value={adminLoginTelegramId}
                onChange={(event) => setAdminLoginTelegramId(event.target.value)}
              />
            </label>
            <button type="submit" className="button button--accent" disabled={adminLoginBusy}>
              {adminLoginBusy ? 'Вход…' : 'Войти'}
            </button>
            {adminLoginError && <div className="status status--error">{adminLoginError}</div>}
          </form>
        </section>
      )
    }
    if (adminAccessDenied) {
      return <div className="status status--error">Нет доступа</div>
    }
    return (
      <div className="admin">
        <div className="admin__nav">
          <button type="button" className="button button--ghost button--compact" onClick={goHome}>
            ← Назад
          </button>
          <div className="admin__title">Админ-панель</div>
          <div className="admin__tabs">
            <button
              type="button"
              className={`button button--compact ${adminSection === 'users' ? 'button--accent' : 'button--ghost'}`}
              onClick={() => navigateToAdmin('users')}
            >
              Users
            </button>
            <button
              type="button"
              className={`button button--compact ${
                adminSection === 'broadcasts' ? 'button--accent' : 'button--ghost'
              }`}
              onClick={() => navigateToAdmin('broadcasts')}
            >
              Broadcasts
            </button>
            <button
              type="button"
              className={`button button--compact ${adminSection === 'parser' ? 'button--accent' : 'button--ghost'}`}
              onClick={() => navigateToAdmin('parser')}
            >
              Parser
            </button>
          </div>
        </div>
        {adminSection === 'users' && renderAdminUsers()}
        {adminSection === 'user' && renderAdminUserDetail()}
        {adminSection === 'broadcasts' && renderAdminBroadcasts()}
        {adminSection === 'parser' && renderAdminParser()}
      </div>
    )
  }

  return (
    <div className="app">
      {activePage === 'admin' ? (
        renderAdminPanel()
      ) : activePage === 'profile' ? (
        <div className="profile">
          <div className="profile__nav">
            <button
              type="button"
              className="button button--ghost button--compact"
              onClick={goHome}
            >
              ← Назад
            </button>
            <div className="profile__title">Профиль</div>
            {isAdmin && (
              <button
                type="button"
                className="button button--ghost button--compact"
                onClick={() => navigateToAdmin('users')}
              >
                Админ
              </button>
            )}
          </div>

          <div className="status-stack">
            {profileError && <div className="status status--error">{profileError}</div>}
            {profileNotice && <div className="status status--success">{profileNotice}</div>}
            {toast && <div className="status status--success">{toast}</div>}
            {profileLoading && <div className="status status--loading">Загрузка…</div>}
          </div>

          <section className="panel profile-card">
            {profileLoading ? (
              <div className="profile-header profile-header--skeleton">
                <div className="avatar avatar--lg skeleton" />
                <div className="profile-header__info">
                  <div className="skeleton-line skeleton-line--title" />
                  <div className="skeleton-line" />
                  <div className="skeleton-line skeleton-line--short" />
                </div>
              </div>
            ) : (
              <div className="profile-header">
                <ProfileAvatar user={user} size="lg" label="Profile" />
                <div className="profile-header__info">
                  <div className="profile-header__name">{profileDisplayName}</div>
                  {profileHandle && <div className="profile-header__handle">{profileHandle}</div>}
                  {user?.telegramId && (
                    <div className="profile-header__meta">Telegram ID: {user.telegramId}</div>
                  )}
                </div>
                <div className="profile-header__stats">
                  <span className="chip chip--ghost">
                    ★ {ratingValue.toFixed(1)} · {ratingCount} оценок
                  </span>
                  <span className="chip chip--accent">{balanceTokens.toLocaleString()} GT</span>
                </div>
              </div>
            )}
          </section>

          <section className="panel profile-card">
            <div className="panel__header">
              <h2>Баланс</h2>
              <span className="chip chip--accent">{balanceTokens.toLocaleString()} GT</span>
            </div>
            <p className="profile-balance__hint">GigTokens можно тратить на продвижение событий и бонусы.</p>
            <div className="profile-actions">
              <button
                type="button"
                className="button button--accent"
                onClick={() => {
                  setProfileError(null)
                  setProfileNotice(null)
                  setTopupOpen(true)
                }}
                disabled={!token || profileLoading}
              >
                Пополнить токенами
              </button>
              <button
                type="button"
                className="button button--ghost"
                onClick={handleCardTopup}
                disabled={!token || !CARD_TOPUP_ENABLED || cardBusy}
              >
                {CARD_TOPUP_ENABLED ? (cardBusy ? 'Обработка…' : 'Пополнить картой') : 'Скоро'}
              </button>
            </div>
          </section>

          {topupOpen && (
            <div className="modal-backdrop" role="dialog" aria-modal="true" onClick={closeTopupModal}>
              <div className="modal" onClick={(event) => event.stopPropagation()}>
                <div className="modal__header">
                  <h3>Пополнить токенами</h3>
                  <button
                    type="button"
                    className="button button--ghost button--compact"
                    onClick={closeTopupModal}
                    aria-label="Close"
                  >
                    ×
                  </button>
                </div>
                <form
                  onSubmit={(event) => {
                    event.preventDefault()
                    handleTokenTopup()
                  }}
                >
                  <label className="field">
                    Сумма
                    <input
                      type="number"
                      min={1}
                      max={MAX_TOPUP_TOKENS}
                      step={1}
                      inputMode="numeric"
                      placeholder="500"
                      value={topupAmount}
                      onChange={(event) => setTopupAmount(event.target.value)}
                    />
                  </label>
                  <p className="hint">Минимум 1, максимум {MAX_TOPUP_TOKENS}.</p>
                  <div className="modal__actions">
                    <button type="submit" className="button button--accent" disabled={topupBusy}>
                      {topupBusy ? 'Создаём…' : 'Создать заявку'}
                    </button>
                    <button type="button" className="button button--ghost" onClick={closeTopupModal}>
                      Отмена
                    </button>
                  </div>
                </form>
              </div>
            </div>
          )}

          <section className="panel profile-card">
            <div className="panel__header">
              <h2>Мои события</h2>
              <span className="chip chip--ghost">{myEventsTotal} всего</span>
            </div>
            <div className="profile-tabs">
              <button type="button" className="tab tab--active">
                Созданные
              </button>
            </div>
            {myEventsLoading ? (
              <div className="profile-events">
                {Array.from({ length: 3 }).map((_, index) => (
                  <div className="profile-event profile-event--skeleton" key={`skeleton-${index}`}>
                    <div className="profile-event__thumb skeleton" />
                    <div className="profile-event__body">
                      <div className="skeleton-line skeleton-line--title" />
                      <div className="skeleton-line skeleton-line--short" />
                    </div>
                  </div>
                ))}
              </div>
            ) : myEvents.length === 0 ? (
              <div className="empty-state">
                <div>
                  <h3>Вы ещё не создали ни одного события</h3>
                  <p>Создайте первое событие и пригласите людей рядом.</p>
                </div>
                <button
                  type="button"
                  className="button button--primary"
                  disabled={!canCreate}
                  onClick={() => {
                    goHome()
                    openCreateForm('profile_empty')
                  }}
                >
                  Создать событие
                </button>
              </div>
            ) : (
              <div className="profile-events">
                {myEvents.map((event) => {
                  const startsAt = new Date(event.startsAt)
                  const isPast = startsAt.getTime() < Date.now()
                  return (
                    <button
                      key={event.id}
                      type="button"
                      className="profile-event"
                      onClick={() => handleProfileEventClick(event.id)}
                    >
                      <div className="profile-event__thumb">
                        {event.thumbnailUrl ? (
                          <img src={event.thumbnailUrl} alt={event.title} loading="lazy" decoding="async" />
                        ) : (
                          <div className="profile-event__placeholder">No photo</div>
                        )}
                      </div>
                      <div className="profile-event__body">
                        <div className="profile-event__title">{event.title}</div>
                        <div className="profile-event__meta">
                          <span>{startsAt.toLocaleString()}</span>
                          <span className={`tag ${isPast ? 'tag--muted' : 'tag--accent'}`}>
                            {isPast ? 'Прошло' : 'Скоро'}
                          </span>
                          <span>{event.participantsCount} участников</span>
                        </div>
                      </div>
                    </button>
                  )
                })}
              </div>
            )}
          </section>
        </div>
      ) : (
        <>
          <header className="hero">
            <div className="hero__main">
              <div className="hero__copy">
                <p className="eyebrow">Local energy</p>
                <h1>Gigme</h1>
                <p className="hero__subtitle">{greeting}</p>
              </div>
              <div className="hero__actions">
                <button
                  className="button button--primary"
                  disabled={!canCreate}
                  onClick={toggleCreateForm}
                >
                  {creating ? (isEditing ? 'Close edit' : 'Close') : 'Create event'}
                </button>
                <span className="chip chip--ghost">{mapCenterLabel}</span>
              </div>
            </div>
            <section
              className={`map-card hero__map-card${createErrors.location ? ' map-card--error' : ''}`}
              ref={mapCardRef}
            >
              <div className="map" ref={mapRef} />
              <div className="map-overlay">
                {pinLabel && <span className="chip chip--accent">Pin: {pinLabel}</span>}
                <span className="chip chip--ghost">Tap map to pin</span>
                {createErrors.location && creating && (
                  <span className="chip chip--danger">{createErrors.location}</span>
                )}
              </div>
            </section>
            <button
              type="button"
              className="hero__profile"
              onClick={openProfile}
              disabled={!user}
              aria-label="Open profile"
            >
              <ProfileAvatar user={user} size="sm" label="Profile" />
            </button>
            <div className="hero__filters">
              <div className="hero__filters-head">
                <div className="hero__filters-title">
                  <span className="hero__filters-label">Filters</span>
                  <span className="hero__filters-count">{activeFiltersLabel}</span>
                </div>
                {activeFilterCount > 0 && (
                  <button
                    type="button"
                    className="button button--ghost button--compact"
                    onClick={clearActiveFilters}
                  >
                    Clear
                  </button>
                )}
              </div>
              <div className="filter-row">
                <button
                  type="button"
                  className={`filter-pill${nearbyOnly ? ' filter-pill--active' : ''}`}
                  aria-pressed={nearbyOnly}
                  onClick={() => setNearbyOnly((prev) => !prev)}
                >
                  <span className="filter-pill__icon" aria-hidden="true">
                    📍
                  </span>
                  <span className="filter-pill__label">Nearby 100 km</span>
                </button>
              </div>
              <div className="filter-row">
                {EVENT_FILTERS.map((filter) => {
                  const active = activeFilters.includes(filter.id)
                  return (
                    <button
                      key={filter.id}
                      type="button"
                      className={`filter-pill filter-pill--icon${active ? ' filter-pill--active' : ''}`}
                      aria-pressed={active}
                      aria-label={filter.label}
                      title={filter.label}
                      onClick={() => toggleActiveFilter(filter.id)}
                    >
                      <span aria-hidden="true">{filter.icon}</span>
                    </button>
                  )
                })}
              </div>
            </div>
          </header>

          <div className="status-stack">
            {error && !formError && <div className="status status--error">{error}</div>}
            {toast && <div className="status status--success">{toast}</div>}
            {loading && <div className="status status--loading">Loading...</div>}
          </div>

          <div className={`layout${creating ? ' layout--with-create' : ''}`}>
        {creating && (
          <section className="panel form-panel" ref={createPanelRef}>
            <div className="panel__header">
              <h2>{isEditing ? 'Edit event' : 'New event'}</h2>
              <span className="chip chip--ghost">{isEditing ? 'Editing' : 'Draft'}</span>
            </div>
            {formError && <div className="form-banner status status--error">{formError}</div>}
            <form className="form" onSubmit={handleCreate} key={formKey}>
              <label
                className={`field${createErrors.title ? ' field--error' : ''}`}
                ref={titleFieldRef}
              >
                Title
                <input
                  name="title"
                  maxLength={80}
                  required
                  defaultValue={formDefaults.title}
                  aria-invalid={Boolean(createErrors.title)}
                  aria-describedby={createErrors.title ? 'create-title-error' : undefined}
                  onChange={() => clearCreateError('title')}
                />
                {createErrors.title && (
                  <span className="field__error" id="create-title-error" role="alert">
                    {createErrors.title}
                  </span>
                )}
              </label>
              <label
                className={`field${createErrors.description ? ' field--error' : ''}`}
                ref={descriptionFieldRef}
              >
                Description
                <textarea
                  name="description"
                  maxLength={MAX_DESCRIPTION}
                  required
                  value={description}
                  aria-invalid={Boolean(createErrors.description)}
                  aria-describedby={createErrors.description ? 'create-description-error' : undefined}
                  onChange={(e) => {
                    setDescription(e.target.value)
                    clearCreateError('description')
                  }}
                />
                {createErrors.description && (
                  <span className="field__error" id="create-description-error" role="alert">
                    {createErrors.description}
                  </span>
                )}
              </label>
              <div className="field">
                <div className="field__label">
                  <span>Filters</span>
                  <span className="field__hint">
                    {createFilters.length}/{MAX_EVENT_FILTERS}
                  </span>
                </div>
                <div className="filter-row">
                  {EVENT_FILTERS.map((filter) => {
                    const active = createFilters.includes(filter.id)
                    const disabled = !active && createFiltersLimitReached
                    return (
                      <button
                        key={filter.id}
                        type="button"
                        className={`filter-pill${active ? ' filter-pill--active' : ''}`}
                        aria-pressed={active}
                        disabled={disabled}
                        onClick={() => toggleCreateFilter(filter.id)}
                      >
                        <span className="filter-pill__icon" aria-hidden="true">
                          {filter.icon}
                        </span>
                        <span className="filter-pill__label">{filter.label}</span>
                      </button>
                    )
                  })}
                </div>
                <p className="hint">
                  Select up to {MAX_EVENT_FILTERS} filters. {createFilters.length}/{MAX_EVENT_FILTERS} selected.
                </p>
              </div>
              <div className="form-grid">
                <label
                  className={`field${createErrors.startsAt ? ' field--error' : ''}`}
                  ref={startsAtFieldRef}
                >
                  Starts at
                  <input
                    name="startsAt"
                    type="datetime-local"
                    required
                    defaultValue={formDefaults.startsAt}
                    aria-invalid={Boolean(createErrors.startsAt)}
                    aria-describedby={createErrors.startsAt ? 'create-starts-error' : undefined}
                    onChange={() => clearCreateError('startsAt')}
                  />
                  {createErrors.startsAt && (
                    <span className="field__error" id="create-starts-error" role="alert">
                      {createErrors.startsAt}
                    </span>
                  )}
                </label>
                <label className="field">
                  Ends at
                  <input name="endsAt" type="datetime-local" defaultValue={formDefaults.endsAt} />
                </label>
                <label className="field">
                  Participant limit
                  <input name="capacity" type="number" min={1} defaultValue={formDefaults.capacity} />
                </label>
              </div>
              <div
                className={`field${createErrors.contacts ? ' field--error' : ''}`}
                ref={contactsFieldRef}
              >
                <div className="field__label">
                  <span>Contacts</span>
                  <span className="field__hint">Visible after joining</span>
                </div>
                <div className="form-grid">
                  <label className="field">
                    Telegram
                    <input
                      name="contactTelegram"
                      maxLength={MAX_CONTACT_LENGTH}
                      placeholder="@username"
                      defaultValue={formDefaults.contactTelegram}
                      onChange={() => clearCreateError('contacts')}
                    />
                  </label>
                  <label className="field">
                    WhatsApp
                    <input
                      name="contactWhatsapp"
                      maxLength={MAX_CONTACT_LENGTH}
                      placeholder="+1 555 000 0000"
                      defaultValue={formDefaults.contactWhatsapp}
                      onChange={() => clearCreateError('contacts')}
                    />
                  </label>
                  <label className="field">
                    WeChat
                    <input
                      name="contactWechat"
                      maxLength={MAX_CONTACT_LENGTH}
                      placeholder="WeChat ID"
                      defaultValue={formDefaults.contactWechat}
                      onChange={() => clearCreateError('contacts')}
                    />
                  </label>
                  <label className="field">
                    Messenger
                    <input
                      name="contactFbMessenger"
                      maxLength={MAX_CONTACT_LENGTH}
                      placeholder="m.me/username"
                      defaultValue={formDefaults.contactFbMessenger}
                      onChange={() => clearCreateError('contacts')}
                    />
                  </label>
                  <label className="field">
                    Snapchat
                    <input
                      name="contactSnapchat"
                      maxLength={MAX_CONTACT_LENGTH}
                      placeholder="snap username"
                      defaultValue={formDefaults.contactSnapchat}
                      onChange={() => clearCreateError('contacts')}
                    />
                  </label>
                </div>
                {createErrors.contacts && (
                  <span className="field__error" role="alert">
                    {createErrors.contacts}
                  </span>
                )}
                <p className="hint">Add handles or links to reach the host after joining.</p>
              </div>
              <div className="field">
                <div className="field__label">
                  <span>Privacy</span>
                  <span className="field__hint">Link only</span>
                </div>
                <label className="checkbox-row">
                  <input type="checkbox" name="isPrivate" defaultChecked={formDefaults.isPrivate} />
                  <span>Private event (visible only via link)</span>
                </label>
                <p className="hint">Private events stay off the public map and feed.</p>
              </div>
              <label className="field">
                Photos (up to 5)
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  disabled={uploading}
                  onChange={(e) => handleFileUpload(e.target.files)}
                />
              </label>
              <div className="media-list">
                {uploadedMedia.map((item, index) => (
                  <div className="media-item" key={`${item.fileUrl}-${index}`}>
                    <MediaImage src={item.previewUrl || item.fileUrl} alt="media" />
                    <button
                      type="button"
                      className="media-remove"
                      onClick={() => removeUploadedMediaAt(index)}
                      aria-label="Remove photo"
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>
              {uploading && <p className="hint">Uploading photos…</p>}
              <p className="hint">
                Tap on the map to choose event location (required). Current:{' '}
                {createCoordsLabel ? (
                  <button
                    type="button"
                    className="link-button"
                    onClick={focusCreatePin}
                    aria-label={`Center map on ${createCoordsLabel}`}
                  >
                    {createCoordsLabel}
                  </button>
                ) : (
                  'not selected'
                )}
                .
                Coordinates are added to the description.
              </p>
              <div className="form-actions">
                <button className="button button--primary" type="submit" disabled={loading || uploading}>
                  {uploading ? 'Uploading…' : isEditing ? 'Save changes' : 'Create'}
                </button>
                {isEditing && (
                  <button
                    type="button"
                    className="button button--ghost"
                    disabled={loading || uploading}
                    onClick={() => resetFormState(true)}
                  >
                    Cancel edit
                  </button>
                )}
              </div>
            </form>
          </section>
        )}

        <section className="panel feed-panel">
          <div className="panel__header">
            <h2>Nearby feed</h2>
            <span className="chip chip--ghost">{feed.length} events</span>
          </div>
          {feed.length === 0 && (
            <div className="empty-state">
              <div>
                <h3>No events yet</h3>
                <p>Be the first to drop a pin and invite people around you.</p>
              </div>
              <button
                type="button"
                className="button button--primary"
                disabled={!canCreate}
                onClick={() => openCreateForm('empty_state')}
              >
                Create the first event
              </button>
            </div>
          )}
          <div className="feed-grid">
            {feed.map((event) => {
              const distanceLabel = getDistanceLabel(event.lat, event.lng)
              const accessKey = event.accessKey || eventAccessKeys[event.id]
              const proxyThumb = buildMediaProxyUrl(event.id, 0, accessKey)
              const allowFallback = !event.isPrivate || Boolean(accessKey)
              const thumbnailSrc = proxyThumb || (allowFallback ? event.thumbnailUrl : undefined)
              const thumbnailFallback = proxyThumb && allowFallback && event.thumbnailUrl ? event.thumbnailUrl : undefined
              if (event.id === selectedId) {
                if (!detailEvent) {
                  return (
                    <article
                      key={event.id}
                      className="panel detail-panel detail-panel--inline detail-panel--loading"
                      data-event-id={event.id}
                    >
                      <div className="card__media">
                        {distanceLabel && <span className="card__distance">{distanceLabel}</span>}
                        {thumbnailSrc ? (
                          <MediaImage
                            src={thumbnailSrc}
                            alt="thumb"
                            fallbackSrc={thumbnailFallback}
                          />
                        ) : (
                          <div className="card__placeholder">No photo</div>
                        )}
                      </div>
                      <div className="card__body">
                        <div className="card__top">
                          <h3>{event.title}</h3>
                          <span className="tag">Loading</span>
                        </div>
                        <p className="card__time">{new Date(event.startsAt).toLocaleString()}</p>
                        <p className="card__host">{event.creatorName || 'Community'}</p>
                      </div>
                    </article>
                  )
                }

                const detailAccessKey = detailEvent.event.accessKey || eventAccessKeys[detailEvent.event.id]
                const allowMediaFallback = !detailEvent.event.isPrivate || Boolean(detailAccessKey)
                return (
                  <article key={event.id} className="panel detail-panel detail-panel--inline" data-event-id={event.id}>
                    <div className="detail-header">
                      <div>
                        <h2>{detailEvent.event.title}</h2>
                        <p className="detail-meta">{new Date(detailEvent.event.startsAt).toLocaleString()}</p>
                        {detailEvent.event.endsAt && (
                          <p className="detail-meta">Ends: {new Date(detailEvent.event.endsAt).toLocaleString()}</p>
                        )}
                      </div>
                      <span className="chip chip--accent">{detailEvent.event.participantsCount} going</span>
                    </div>
                    {detailEvent.media[0] && (
                      <div className="detail-hero">
                        <MediaImage
                          src={resolveMediaSrc(detailEvent.event.id, 0, allowMediaFallback ? detailEvent.media[0] : undefined, detailAccessKey)}
                          alt="event hero"
                          fallbackSrc={allowMediaFallback ? detailEvent.media[0] : undefined}
                        />
                      </div>
                    )}
                    <p className="detail-description">{renderDescription(detailEvent.event.description)}</p>
                    <div className="media-list">
                      {detailEvent.media.slice(1).map((url, index) => (
                        <MediaImage
                          key={url}
                          src={resolveMediaSrc(detailEvent.event.id, index + 1, allowMediaFallback ? url : undefined, detailAccessKey)}
                          alt="media"
                          fallbackSrc={allowMediaFallback ? url : undefined}
                        />
                      ))}
                    </div>
                    <div className="actions">
                      {detailEvent.isJoined ? (
                        <button className="button button--ghost" onClick={handleLeave}>
                          Leave event
                        </button>
                      ) : (
                        <button className="button button--accent" onClick={handleJoin}>
                          Join event
                        </button>
                      )}
                      <button className="button button--ghost" type="button" onClick={handleShareEvent}>
                        Поделиться
                      </button>
                    </div>
                    <div className="engagement">
                      <button
                        type="button"
                        className={`button button--ghost button--compact${detailEvent.event.isLiked ? ' button--liked' : ''}`}
                        onClick={handleLikeToggle}
                        disabled={likeBusy}
                      >
                        {detailEvent.event.isLiked ? '♥ Liked' : '♡ Like'}
                      </button>
                      <div className="engagement__meta">
                        <span>{detailEvent.event.likesCount} likes</span>
                        <span>{detailEvent.event.commentsCount} comments</span>
                      </div>
                    </div>
                    <section className="comments">
                      <div className="comments__header">
                        <h3>Comments</h3>
                        <span className="chip chip--ghost">
                          {commentsLoading ? 'Loading…' : comments.length}
                        </span>
                      </div>
                      <div className="comments__list">
                        {commentsLoading ? (
                          <p className="hint">Loading comments…</p>
                        ) : comments.length === 0 ? (
                          <p className="empty">No comments yet</p>
                        ) : (
                          comments.map((comment) => (
                            <div key={comment.id} className="comment">
                              <div className="comment__meta">
                                <span className="comment__author">{comment.userName}</span>
                                <span className="comment__time">
                                  {new Date(comment.createdAt).toLocaleString()}
                                </span>
                              </div>
                              <p className="comment__body">{comment.body}</p>
                            </div>
                          ))
                        )}
                      </div>
                      <form className="comment-form" onSubmit={handleAddComment}>
                        <textarea
                          value={commentBody}
                          onChange={(event) => setCommentBody(event.target.value)}
                          placeholder="Write a comment…"
                          maxLength={MAX_COMMENT_LENGTH}
                          rows={3}
                        />
                        <div className="comment-form__actions">
                          <span className="hint">
                            {commentBody.length}/{MAX_COMMENT_LENGTH}
                          </span>
                          <button
                            className="button button--accent button--compact"
                            type="submit"
                            disabled={commentSending || !commentBody.trim()}
                          >
                            {commentSending ? 'Sending…' : 'Send'}
                          </button>
                        </div>
                      </form>
                    </section>
                    {isAdmin && (
                      <div className="admin-actions">
                        <span className="chip chip--ghost">
                          {isEditing && editingEventId === detailEvent.event.id ? 'Editing' : 'Admin'}
                        </span>
                        <button
                          type="button"
                          className="button button--ghost button--compact"
                          onClick={(event) => {
                            event.stopPropagation()
                            startEditFromDetail(detailEvent)
                          }}
                          disabled={adminBusy || (isEditing && editingEventId === detailEvent.event.id)}
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          className="button button--danger button--compact"
                          onClick={(event) => {
                            event.stopPropagation()
                            handleAdminDelete()
                          }}
                          disabled={adminBusy}
                        >
                          Delete
                        </button>
                        <div className="admin-actions__group">
                          <button
                            type="button"
                            className="button button--accent button--compact"
                            onClick={(event) => {
                              event.stopPropagation()
                              handleAdminPromote('24h')
                            }}
                            disabled={adminBusy}
                          >
                            Promote 24h
                          </button>
                          <button
                            type="button"
                            className="button button--accent button--compact"
                            onClick={(event) => {
                              event.stopPropagation()
                              handleAdminPromote('7d')
                            }}
                            disabled={adminBusy}
                          >
                            Promote 7d
                          </button>
                          <button
                            type="button"
                            className="button button--ghost button--compact"
                            onClick={(event) => {
                              event.stopPropagation()
                              handleAdminPromote('clear')
                            }}
                            disabled={adminBusy}
                          >
                            Clear
                          </button>
                        </div>
                      </div>
                    )}
                    <ContactIcons source={detailEvent.event} unlocked={detailEvent.isJoined} className="detail-contacts" />
                    <h3>Participants</h3>
                    <ul className="participants">
                      {detailEvent.participants.map((p) => (
                        <li key={p.userId}>{p.name}</li>
                      ))}
                    </ul>
                  </article>
                )
              }

              const remaining = event.capacity
                ? Math.max(event.capacity - event.participantsCount, 0)
                : null
              const isFeatured = Boolean(event.promotedUntil)
              return (
                <article
                  key={event.id}
                  className="card"
                  data-event-id={event.id}
                  onClick={() => {
                    logInfo('feed_card_click', { eventId: event.id })
                    setSelectedId(event.id)
                  }}
                >
                  <div className="card__media">
                    {distanceLabel && <span className="card__distance">{distanceLabel}</span>}
                    {thumbnailSrc ? (
                      <MediaImage
                        src={thumbnailSrc}
                        alt="thumb"
                        fallbackSrc={thumbnailFallback}
                      />
                    ) : (
                      <div className="card__placeholder">No photo</div>
                    )}
                  </div>
                  <div className="card__body">
                    <div className="card__top">
                      <h3>{event.title}</h3>
                      {isFeatured && <span className="tag">Featured</span>}
                    </div>
                    <p className="card__time">{new Date(event.startsAt).toLocaleString()}</p>
                    <p className="card__host">{event.creatorName || 'Community'}</p>
                    <div className="card__meta">
                      <span>{event.participantsCount} going</span>
                      {remaining != null && <span>{remaining} spots</span>}
                    </div>
                    <ContactIcons source={event} unlocked={Boolean(event.isJoined)} />
                  </div>
                </article>
              )
            })}
          </div>
        </section>
      </div>
    </>
  )}
    </div>
  )
}

export default App
