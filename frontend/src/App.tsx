import React, { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import {
  API_URL,
  API_URL_ERROR,
  authTelegram,
  createEvent,
  EventCard,
  EventDetail,
  EventMarker,
  getEvent,
  getFeed,
  getNearby,
  joinEvent,
  leaveEvent,
  presignMedia,
  uploadMedia,
  updateLocation,
} from './api'
import { getActiveLogLevel, logDebug, logError, logInfo, logWarn, setLogToken } from './logger'

type LatLng = { lat: number; lng: number }
type UploadedMedia = { fileUrl: string; previewUrl: string }
type EventFilter = 'dating' | 'party' | 'travel' | 'fun' | 'bar' | 'feedme'

const DEFAULT_CENTER: LatLng = { lat: 52.37, lng: 4.9 }
const COORDS_LABEL = 'Coordinates:'
const MAX_DESCRIPTION = 1000
const LOCATION_POLL_MS = 60000
const VIEW_STORAGE_KEY = 'gigme:lastCenter'
const MAX_EVENT_FILTERS = 3

const EVENT_FILTERS: { id: EventFilter; label: string; icon: string }[] = [
  { id: 'dating', label: 'Dating', icon: '💘' },
  { id: 'party', label: 'Party', icon: '🎉' },
  { id: 'travel', label: 'Travel', icon: '✈️' },
  { id: 'fun', label: 'Fun', icon: '🎈' },
  { id: 'bar', label: 'Bar', icon: '🍸' },
  { id: 'feedme', label: 'Feedme', icon: '🍕' },
]

const formatCoords = (lat: number, lng: number) => `${lat.toFixed(5)}, ${lng.toFixed(5)}`
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

type MediaImageProps = Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'src'> & {
  src?: string
  fallbackSrc?: string
}

const MediaImage = ({ src, fallbackSrc, alt, ...rest }: MediaImageProps) => {
  const [resolvedSrc, setResolvedSrc] = useState<string>(src || '')
  const objectUrlRef = useRef<string | null>(null)

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
        const next = await load(src)
        if (cancelled) return
        if (next) {
          setResolvedSrc(next)
          return
        }
      } catch {
        // try fallback
      }
      try {
        const nextFallback = await load(fallbackSrc)
        if (cancelled) return
        setResolvedSrc(nextFallback)
      } catch {
        if (!cancelled) setResolvedSrc('')
      }
    }

    run()
    return () => {
      cancelled = true
      controller.abort()
      clearObjectUrl()
    }
  }, [src, fallbackSrc])

  if (!resolvedSrc) return null
  return <img src={resolvedSrc} alt={alt} {...rest} />
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
  const coordsLine = `${COORDS_LABEL} ${formatCoords(lat, lng)}`
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
  const [userName, setUserName] = useState<string>('')
  const [userLocation, setUserLocation] = useState<LatLng | null>(null)
  const [viewLocation, setViewLocation] = useState<LatLng | null>(() => loadStoredCenter())
  const [markers, setMarkers] = useState<EventMarker[]>([])
  const [feed, setFeed] = useState<EventCard[]>([])
  const [activeFilters, setActiveFilters] = useState<EventFilter[]>([])
  const [createFilters, setCreateFilters] = useState<EventFilter[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(() => getEventIdFromLocation())
  const [selectedEvent, setSelectedEvent] = useState<EventDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [creating, setCreating] = useState(false)
  const [description, setDescription] = useState('')
  const [createLatLng, setCreateLatLng] = useState<LatLng | null>(null)
  const [uploadedMedia, setUploadedMedia] = useState<UploadedMedia[]>([])
  const mapRef = useRef<HTMLDivElement | null>(null)
  const mapInstance = useRef<L.Map | null>(null)
  const markerLayer = useRef<L.LayerGroup | null>(null)
  const draftMarker = useRef<L.Marker | null>(null)
  const hasLocation = useRef(false)
  const hasUserMovedMap = useRef(false)
  const hasStoredCenter = useRef(viewLocation != null)
  const hasLoadedFeed = useRef(false)
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
  const selectedInFeed = selectedId != null && feed.some((item) => item.id === selectedId)
  const detailEvent = selectedEvent && selectedEvent.event.id === selectedId ? selectedEvent : null
  const uploadedMediaRef = useRef<UploadedMedia[]>([])
  const createFiltersLimitReached = createFilters.length >= MAX_EVENT_FILTERS

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
        const name = [res.user.firstName, res.user.lastName].filter(Boolean).join(' ')
        setUserName(name)
        setError(null)
        setLogToken(res.accessToken)
        logInfo('auth_success', { userId: res.user.id, telegramId: res.user.telegramId })
      })
      .catch((err) => {
        setLogToken(null)
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
    if (selectedId == null) return
    const target = document.querySelector(`[data-event-id="${selectedId}"]`)
    if (target instanceof HTMLElement) {
      target.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' })
    }
  }, [selectedId])

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


  const handleJoin = async () => {
    if (!token || !selectedEvent) return
    logInfo('join_event_start', { eventId: selectedEvent.event.id })
    await joinEvent(token, selectedEvent.event.id)
    const updated = await getEvent(token, selectedEvent.event.id)
    setSelectedEvent(updated)
    logInfo('join_event_success', { eventId: selectedEvent.event.id })
  }

  const handleLeave = async () => {
    if (!token || !selectedEvent) return
    logInfo('leave_event_start', { eventId: selectedEvent.event.id })
    await leaveEvent(token, selectedEvent.event.id)
    const updated = await getEvent(token, selectedEvent.event.id)
    setSelectedEvent(updated)
    logInfo('leave_event_success', { eventId: selectedEvent.event.id })
  }

  const handleCreate = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (!token) return
    if (uploading) {
      setError('Please wait for photos to finish uploading')
      return
    }
    const form = new FormData(e.currentTarget)
    const title = String(form.get('title') || '')
    const startsAtLocal = String(form.get('startsAt') || '')
    const endsAtLocal = String(form.get('endsAt') || '')
    const capacityRaw = String(form.get('capacity') || '')
    const descriptionValue = description.trim()

    if (!title || !descriptionValue || !startsAtLocal) {
      logWarn('create_event_invalid_form', { titleLength: title.length, descriptionLength: descriptionValue.length })
      setError('Please fill all required fields')
      return
    }
    if (description.length > MAX_DESCRIPTION) {
      logWarn('create_event_description_too_long', { descriptionLength: description.length })
      setError(`Description too long (max ${MAX_DESCRIPTION} characters)`)
      return
    }

    const startsAtISO = new Date(startsAtLocal).toISOString()
    const endsAtISO = endsAtLocal ? new Date(endsAtLocal).toISOString() : undefined
    const capacity = capacityRaw ? Number(capacityRaw) : undefined
    const point = createLatLng || viewLocation || userLocation || DEFAULT_CENTER
    const filters = createFilters

    setLoading(true)
    try {
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
      })
      const created = await createEvent(token, {
        title,
        description: descriptionValue,
        startsAt: startsAtISO,
        endsAt: endsAtISO,
        lat: point.lat,
        lng: point.lng,
        capacity,
        media: uploadedMedia.map((item) => item.fileUrl),
        filters,
      })
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
        thumbnailUrl: uploadedMedia[0]?.fileUrl,
        participantsCount: 1,
        filters,
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
      setCreating(false)
      clearUploadedMedia()
      setCreateLatLng(null)
      setDescription('')
      setCreateFilters([])
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
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleFileUpload = async (files: FileList | null) => {
    if (!token || !files) return
    const fileArray = Array.from(files).slice(0, 5 - uploadedMedia.length)
    if (fileArray.length === 0) return
    setUploading(true)
    try {
      logInfo('media_upload_start', { count: fileArray.length })
      for (const file of fileArray) {
        const previewUrl = URL.createObjectURL(file)
        try {
          let fileUrl = ''
          try {
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
          setUploadedMedia((prev) => [...prev, { fileUrl, previewUrl }])
        } catch (err) {
          URL.revokeObjectURL(previewUrl)
          throw err
        }
      }
    } catch (err: any) {
      logError('media_upload_error', { message: err.message })
      setError(err.message)
    } finally {
      setUploading(false)
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
                setCreating((v) => {
                  const next = !v
                  logInfo('toggle_create_form', { open: next })
                  return next
                })
              }}
            >
              {creating ? 'Close' : 'Create event'}
            </button>
            <span className="chip chip--ghost">{mapCenterLabel}</span>
          </div>
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
        {error && <div className="status status--error">{error}</div>}
        {loading && <div className="status status--loading">Loading...</div>}
      </div>

      <div className="layout">
        <section className="map-card">
          <div className="map" ref={mapRef} />
          <div className="map-overlay">
            {pinLabel && <span className="chip chip--accent">Pin: {pinLabel}</span>}
            <span className="chip chip--ghost">Tap map to pin</span>
          </div>
        </section>

        {creating && (
          <section className="panel form-panel">
            <div className="panel__header">
              <h2>New event</h2>
              <span className="chip chip--ghost">Draft</span>
            </div>
            <form className="form" onSubmit={handleCreate}>
              <label className="field">
                Title
                <input name="title" maxLength={80} required />
              </label>
              <label className="field">
                Description
                <textarea
                  name="description"
                  maxLength={MAX_DESCRIPTION}
                  required
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
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
                <label className="field">
                  Starts at
                  <input name="startsAt" type="datetime-local" required />
                </label>
                <label className="field">
                  Ends at
                  <input name="endsAt" type="datetime-local" />
                </label>
                <label className="field">
                  Participant limit
                  <input name="capacity" type="number" min={1} />
                </label>
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
              {uploadedMedia.map((item) => (
                <MediaImage
                  key={item.fileUrl}
                  src={item.previewUrl || item.fileUrl}
                  alt="media"
                />
              ))}
            </div>
            {uploading && <p className="hint">Uploading photos…</p>}
            <p className="hint">
              Tap on the map to choose event location. Current:{' '}
              {createLatLng ? `${createLatLng.lat.toFixed(4)}, ${createLatLng.lng.toFixed(4)}` : 'not selected'}.
              Coordinates are added to the description.
            </p>
            <button className="button button--primary" type="submit" disabled={loading || uploading}>
              {uploading ? 'Uploading…' : 'Create'}
            </button>
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
              const thumbnailSrc = event.thumbnailUrl || proxyThumb
              const thumbnailFallback = event.thumbnailUrl ? proxyThumb : undefined
              if (event.id === selectedId) {
                if (!detailEvent) {
                  return (
                    <article
                      key={event.id}
                      className="card card--selected detail-inline detail-inline--loading"
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
                  <article key={event.id} className="card card--selected detail-inline" data-event-id={event.id}>
                    <div className="detail-header">
                      <div>
                        <h2>{detailEvent.event.title}</h2>
                        <p className="detail-meta">{new Date(detailEvent.event.startsAt).toLocaleString()}</p>
                        {detailEvent.event.endsAt && (
                          <p className="detail-meta">Ends: {new Date(detailEvent.event.endsAt).toLocaleString()}</p>
                        )}
                      </div>
                      <div className="detail-header__actions">
                        <span className="chip chip--accent">{detailEvent.event.participantsCount} going</span>
                        <button
                          className="button button--ghost button--compact"
                          onClick={() => setSelectedId(null)}
                        >
                          Close
                        </button>
                      </div>
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
                    <p className="detail-description">{detailEvent.event.description}</p>
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
                    </div>
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
                  </div>
                </article>
              )
            })}
          </div>
        </section>

        {selectedEvent && !selectedInFeed && (
          <section className="panel detail-panel">
            <div className="detail-header">
              <div>
                <h2>{selectedEvent.event.title}</h2>
                <p className="detail-meta">{new Date(selectedEvent.event.startsAt).toLocaleString()}</p>
                {selectedEvent.event.endsAt && (
                  <p className="detail-meta">Ends: {new Date(selectedEvent.event.endsAt).toLocaleString()}</p>
                )}
              </div>
              <span className="chip chip--accent">{selectedEvent.event.participantsCount} going</span>
            </div>
            {selectedEvent.media[0] && (
              <div className="detail-hero">
                <MediaImage
                  src={resolveMediaSrc(selectedEvent.event.id, 0, selectedEvent.media[0])}
                  alt="event hero"
                  fallbackSrc={selectedEvent.media[0]}
                />
              </div>
            )}
            <p className="detail-description">{selectedEvent.event.description}</p>
            <div className="media-list">
              {selectedEvent.media.slice(1).map((url, index) => (
                <MediaImage
                  key={url}
                  src={resolveMediaSrc(selectedEvent.event.id, index + 1, url)}
                  alt="media"
                  fallbackSrc={url}
                />
              ))}
            </div>
            <div className="actions">
              {selectedEvent.isJoined ? (
                <button className="button button--ghost" onClick={handleLeave}>
                  Leave event
                </button>
              ) : (
                <button className="button button--accent" onClick={handleJoin}>
                  Join event
                </button>
              )}
            </div>
            <h3>Participants</h3>
            <ul className="participants">
              {selectedEvent.participants.map((p) => (
                <li key={p.userId}>{p.name}</li>
              ))}
            </ul>
          </section>
        )}
      </div>
    </div>
  )
}

export default App
