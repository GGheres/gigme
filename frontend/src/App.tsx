import React, { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import {
  API_URL,
  API_URL_ERROR,
  addEventComment,
  authTelegram,
  createEvent,
  deleteEventAdmin,
  EventCard,
  EventComment,
  EventDetail,
  EventMarker,
  getEventComments,
  getEvent,
  getFeed,
  getNearby,
  joinEvent,
  likeEvent,
  leaveEvent,
  promoteEvent,
  presignMedia,
  unlikeEvent,
  updateEventAdmin,
  uploadMedia,
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

const formatDateTimeLocal = (value?: string | null) => {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const pad = (num: number) => String(num).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours()
  )}:${pad(date.getMinutes())}`
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

const DEFAULT_CENTER: LatLng = { lat: 52.37, lng: 4.9 }
const COORDS_LABEL = 'Coordinates:'
const MAX_DESCRIPTION = 1000
const MAX_CONTACT_LENGTH = 120
const MAX_COMMENT_LENGTH = 400
const LOCATION_POLL_MS = 60000
const VIEW_STORAGE_KEY = 'gigme:lastCenter'
const MAX_EVENT_FILTERS = 3
const FOCUS_ZOOM = 16
const LOGO_FRAME_COUNT = 134
const LOGO_FPS = 24
const LOGO_FRAME_PREFIX = '/gigmov-frames/frame_'

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
const buildShareUrl = (eventId: number) => {
  if (typeof window === 'undefined') return ''
  const botUsername = TELEGRAM_BOT_USERNAME.replace(/^@+/, '').trim()
  if (botUsername) {
    try {
      const tgUrl = new URL(`https://t.me/${botUsername}`)
      tgUrl.searchParams.set('start', `event_${eventId}`)
      return tgUrl.toString()
    } catch {
      // fall through to web share URL
    }
  }
  try {
    const url = new URL(window.location.origin + window.location.pathname)
    url.searchParams.set('eventId', String(eventId))
    return url.toString()
  } catch {
    return ''
  }
}
const COORDS_REGEX = /Coordinates:\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)/i
const buildMediaProxyUrl = (eventId: number, index: number) => {
  if (API_URL_ERROR) return ''
  return `${API_URL}/media/events/${eventId}/${index}`
}
const resolveMediaSrc = (eventId: number, index: number, fallback?: string) => {
  const proxy = buildMediaProxyUrl(eventId, index)
  return proxy || fallback || ''
}
const NGROK_HOST_RE = /ngrok-free\.app|ngrok\.io/i

const isNgrokUrl = (value?: string) => {
  if (!value) return false
  return NGROK_HOST_RE.test(value)
}

const isIOSDevice = () => {
  if (typeof navigator === 'undefined') return false
  const ua = navigator.userAgent || ''
  const iOS = /iPad|iPhone|iPod/.test(ua)
  const iPadOS = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1
  return iOS || iPadOS
}

const isAndroidDevice = () => {
  if (typeof navigator === 'undefined') return false
  return /Android/i.test(navigator.userAgent || '')
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

const MediaImage = ({ src, fallbackSrc, alt, onError, ...rest }: MediaImageProps) => {
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
                <img className="contact-icon__img" src={iconSrc} alt="" loading="lazy" />
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
              <img className="contact-icon__img" src={iconSrc} alt="" loading="lazy" />
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

const LogoAnimation = () => {
  const [useCanvas] = useState(() => isIOSDevice())
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const containerRef = useRef<HTMLDivElement | null>(null)
  const frameRef = useRef(1)
  const sizeRef = useRef({ width: 0, height: 0 })
  const imagesRef = useRef<(HTMLImageElement | null)[]>([])

  useEffect(() => {
    if (!useCanvas) return
    const canvas = canvasRef.current
    const container = containerRef.current
    if (!canvas || !container) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const images = new Array(LOGO_FRAME_COUNT).fill(null) as (HTMLImageElement | null)[]
    imagesRef.current = images

    for (let i = 1; i <= LOGO_FRAME_COUNT; i += 1) {
      const img = new Image()
      img.src = `${LOGO_FRAME_PREFIX}${String(i).padStart(4, '0')}.png`
      img.onload = () => {
        images[i - 1] = img
      }
    }

    const resize = () => {
      const rect = container.getBoundingClientRect()
      if (!rect.width || !rect.height) return
      const ratio = window.devicePixelRatio || 1
      canvas.width = Math.max(1, Math.round(rect.width * ratio))
      canvas.height = Math.max(1, Math.round(rect.height * ratio))
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
      ctx.imageSmoothingEnabled = true
      sizeRef.current = { width: rect.width, height: rect.height }
    }

    resize()

    const observer = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(resize) : null
    observer?.observe(container)
    window.addEventListener('orientationchange', resize)
    window.addEventListener('resize', resize)

    let raf = 0
    let lastTime = performance.now()
    const frameDuration = 1000 / LOGO_FPS

    const render = (time: number) => {
      const elapsed = time - lastTime
      if (elapsed >= frameDuration) {
        const advance = Math.floor(elapsed / frameDuration)
        frameRef.current = ((frameRef.current - 1 + advance) % LOGO_FRAME_COUNT) + 1
        lastTime = time - (elapsed % frameDuration)
      }

      const img = imagesRef.current[frameRef.current - 1]
      const { width, height } = sizeRef.current
      if (img && width && height) {
        ctx.clearRect(0, 0, width, height)
        const scale = Math.min(width / img.width, height / img.height)
        const drawW = img.width * scale
        const drawH = img.height * scale
        const dx = (width - drawW) / 2
        const dy = (height - drawH) / 2
        ctx.drawImage(img, dx, dy, drawW, drawH)
      }

      raf = requestAnimationFrame(render)
    }

    raf = requestAnimationFrame(render)

    return () => {
      cancelAnimationFrame(raf)
      observer?.disconnect()
      window.removeEventListener('orientationchange', resize)
      window.removeEventListener('resize', resize)
    }
  }, [useCanvas])

  return (
    <div className="logo-video-wrap" ref={containerRef}>
      {useCanvas ? (
        <canvas className="logo-canvas" ref={canvasRef} />
      ) : (
        <video className="logo-video" autoPlay loop muted playsInline preload="auto">
          <source src="/gigmov.webm" type="video/webm" />
          <source src="/gigmov.mp4" type="video/mp4" />
        </video>
      )}
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

const getEventIdFromLocation = () => {
  if (typeof window === 'undefined') return null
  const searchParams = new URLSearchParams(window.location.search)
  const fromSearch = searchParams.get('eventId') || searchParams.get('event')
  if (fromSearch) {
    const parsed = Number(fromSearch)
    if (Number.isFinite(parsed) && parsed > 0) return parsed
  }
  const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash
  if (!hash) return null
  const hashParams = new URLSearchParams(hash)
  const fromHash = hashParams.get('eventId') || hashParams.get('event')
  if (!fromHash) return null
  const parsed = Number(fromHash)
  if (Number.isFinite(parsed) && parsed > 0) return parsed
  return null
}

const getEventIdFromTelegram = () => {
  if (typeof window === 'undefined') return null
  const tg = (window as any).Telegram?.WebApp
  const startParam = tg?.initDataUnsafe?.start_param || tg?.initDataUnsafe?.startParam
  if (!startParam) return null
  const match = String(startParam).match(/\d+/)
  if (!match) return null
  const parsed = Number(match[0])
  if (!Number.isFinite(parsed) || parsed <= 0) return null
  return parsed
}

const updateEventIdInLocation = (eventId: number | null) => {
  if (typeof window === 'undefined') return
  try {
    const url = new URL(window.location.href)
    if (eventId && eventId > 0) {
      url.searchParams.set('eventId', String(eventId))
    } else {
      url.searchParams.delete('eventId')
    }
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

const saveStoredCenter = (center: LatLng) => {
  if (typeof window === 'undefined') return
  window.localStorage.setItem(VIEW_STORAGE_KEY, JSON.stringify(center))
}

function App() {
  const [token, setToken] = useState<string | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [userName, setUserName] = useState<string>('')
  const [userLocation, setUserLocation] = useState<LatLng | null>(null)
  const [viewLocation, setViewLocation] = useState<LatLng | null>(() => loadStoredCenter())
  const [markers, setMarkers] = useState<EventMarker[]>([])
  const [feed, setFeed] = useState<EventCard[]>([])
  const [activeFilters, setActiveFilters] = useState<EventFilter[]>([])
  const [createFilters, setCreateFilters] = useState<EventFilter[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(() => getEventIdFromLocation())
  const [selectedEvent, setSelectedEvent] = useState<EventDetail | null>(null)
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
  const feedLocation = useMemo(() => {
    const preferView = hasStoredCenter.current || hasUserMovedMap.current
    if (preferView) return viewLocation ?? userLocation
    return userLocation ?? viewLocation
  }, [userLocation, viewLocation])
  const canCreate = useMemo(() => !!token && !!(viewLocation || userLocation), [token, viewLocation, userLocation])
  const greeting = userName ? `Hi, ${userName}` : 'Events nearby'
  const mapCenter = viewLocation ?? userLocation
  const mapCenterLabel = mapCenter ? formatCoords(mapCenter.lat, mapCenter.lng) : 'Locating...'
  const pinLabel = createLatLng ? formatCoords(createLatLng.lat, createLatLng.lng) : null
  const createCoordsLabel = createLatLng ? `${createLatLng.lat.toFixed(4)}, ${createLatLng.lng.toFixed(4)}` : null
  const detailEvent = selectedEvent && selectedEvent.event.id === selectedId ? selectedEvent : null
  const uploadedMediaRef = useRef<UploadedMedia[]>([])
  const createFiltersLimitReached = createFilters.length >= MAX_EVENT_FILTERS
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

  useEffect(() => {
    if (API_URL_ERROR) {
      const suffix = API_URL ? ` (current: ${API_URL})` : ''
      logError('app_init_error', { error: API_URL_ERROR, apiUrl: API_URL })
      setError(`${API_URL_ERROR}${suffix}`)
      return
    }
    logInfo('app_init', { apiUrl: API_URL, logLevel: getActiveLogLevel() })
    const tg = (window as any).Telegram?.WebApp
    if (tg) {
      tg.ready()
      tg.expand()
      logDebug('telegram_webapp_ready')
      const startEventId = getEventIdFromTelegram()
      if (startEventId) {
        setSelectedId((prev) => prev ?? startEventId)
      }
    }
    const initData = tg?.initData || getInitDataFromLocation()
    if (!initData) {
      logWarn('auth_missing_init_data')
      setError('Open this app inside Telegram WebApp (or add ?initData=... for browser testing).')
      return
    }

    logDebug('auth_start', { initDataLength: initData.length })
    authTelegram(initData)
      .then((res) => {
        setToken(res.accessToken)
        setUser(res.user)
        const name = [res.user.firstName, res.user.lastName].filter(Boolean).join(' ')
        setUserName(name)
        setError(null)
        setLogToken(res.accessToken)
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
    updateEventIdInLocation(selectedId)
  }, [selectedId])

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
    if (!token || !feedLocation) return
    let cancelled = false

    const load = () => {
      if (cancelled) return
      const showLoading = !hasLoadedFeed.current
      if (showLoading) {
        setLoading(true)
      }
      logDebug('feed_load_start', { lat: feedLocation.lat, lng: feedLocation.lng })
      Promise.all([
        getNearby(token, feedLocation.lat, feedLocation.lng, 0, activeFilters),
        getFeed(token, feedLocation.lat, feedLocation.lng, 0, activeFilters),
      ])
        .then(([nearby, feedItems]) => {
          if (cancelled) return
          setMarkers(nearby)
          setFeed(feedItems)
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
  }, [token, feedLocation, activeFilters])

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
    getEvent(token, selectedId)
      .then((detail) => setSelectedEvent(detail))
      .catch((err) => {
        logError('event_load_error', { message: err.message, eventId: selectedId })
        setError(err.message)
      })
  }, [token, selectedId])

  useEffect(() => {
    if (!token || selectedId == null) {
      setComments([])
      setCommentBody('')
      return
    }
    let cancelled = false
    setCommentsLoading(true)
    setCommentBody('')
    getEventComments(token, selectedId, 100, 0)
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
  }, [token, selectedId])


  const handleJoin = async () => {
    if (!token || !selectedEvent) return
    setError(null)
    setLoading(true)
    logInfo('join_event_start', { eventId: selectedEvent.event.id })
    try {
      await joinEvent(token, selectedEvent.event.id)
      const updated = await getEvent(token, selectedEvent.event.id)
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
      await leaveEvent(token, selectedEvent.event.id)
      const updated = await getEvent(token, selectedEvent.event.id)
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
        ? await unlikeEvent(token, eventId)
        : await likeEvent(token, eventId)
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
      const res = await addEventComment(token, eventId, trimmed)
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
    const eventId = selectedEvent.event.id
    const url = buildShareUrl(eventId)
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
        setError('Ссылка скопирована')
        window.setTimeout(() => setError(null), 2000)
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
        const updated = await getEvent(token, editingEventId)
        setSelectedEvent(updated)
        if (feedLocation) {
          const [nearby, feedItems] = await Promise.all([
            getNearby(token, feedLocation.lat, feedLocation.lng, 0, activeFilters),
            getFeed(token, feedLocation.lat, feedLocation.lng, 0, activeFilters),
          ])
          setMarkers(nearby)
          setFeed(feedItems)
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
      if (feedLocation) {
        const [nearby, feedItems] = await Promise.all([
          getNearby(token, feedLocation.lat, feedLocation.lng, 0, activeFilters),
          getFeed(token, feedLocation.lat, feedLocation.lng, 0, activeFilters),
        ])
        setMarkers(() => {
          const hasCreated = nearby.some((m) => m.id === newMarker.id)
          return hasCreated ? nearby : [newMarker, ...nearby]
        })
        setFeed(() => {
          const hasCreated = feedItems.some((e) => e.id === newFeedItem.id)
          return hasCreated ? feedItems : [newFeedItem, ...feedItems]
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
      for (const file of fileArray) {
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
      const updated = await getEvent(token, eventId)
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

  return (
    <div className="app">
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
              onClick={() => {
                if (creating) {
                  logInfo('toggle_create_form', { open: false })
                  resetFormState(true)
                  return
                }
                logInfo('toggle_create_form', { open: true })
                resetFormState(false)
                setCreating(true)
              }}
            >
              {creating ? (isEditing ? 'Close edit' : 'Close') : 'Create event'}
            </button>
            <span className="chip chip--ghost">{mapCenterLabel}</span>
          </div>
        </div>
        <div className="hero__brand" aria-hidden="true">
          <LogoAnimation />
        </div>
        <div className="hero__filters">
          <span className="hero__filters-label">Filters</span>
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
        {loading && <div className="status status--loading">Loading...</div>}
      </div>

      <div className="layout">
        <section
          className={`map-card${createErrors.location ? ' map-card--error' : ''}`}
          ref={mapCardRef}
        >
          <div className="map" ref={mapRef} />
          <div className="map-overlay">
            {pinLabel && <span className="chip chip--accent">Pin: {pinLabel}</span>}
            <span className="chip chip--ghost">Tap map to pin</span>
            {createErrors.location && creating && <span className="chip chip--danger">{createErrors.location}</span>}
          </div>
        </section>

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
                <p className="hint">Select up to {MAX_EVENT_FILTERS} filters.</p>
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
          {feed.length === 0 && <p className="empty">No events yet</p>}
          <div className="feed-grid">
            {feed.map((event) => {
              const proxyThumb = buildMediaProxyUrl(event.id, 0)
              const thumbnailSrc = proxyThumb || event.thumbnailUrl
              const thumbnailFallback = proxyThumb && event.thumbnailUrl ? event.thumbnailUrl : undefined
              if (event.id === selectedId) {
                if (!detailEvent) {
                  return (
                    <article
                      key={event.id}
                      className="panel detail-panel detail-panel--inline detail-panel--loading"
                      data-event-id={event.id}
                    >
                      <div className="card__media">
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
                          src={resolveMediaSrc(detailEvent.event.id, 0, detailEvent.media[0])}
                          alt="event hero"
                          fallbackSrc={detailEvent.media[0]}
                        />
                      </div>
                    )}
                    <p className="detail-description">{renderDescription(detailEvent.event.description)}</p>
                    <div className="media-list">
                      {detailEvent.media.slice(1).map((url, index) => (
                        <MediaImage
                          key={url}
                          src={resolveMediaSrc(detailEvent.event.id, index + 1, url)}
                          alt="media"
                          fallbackSrc={url}
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
                        Share
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
    </div>
  )
}

export default App
