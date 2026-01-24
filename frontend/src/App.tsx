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

const DEFAULT_CENTER: LatLng = { lat: 52.37, lng: 4.9 }
const COORDS_LABEL = 'Coordinates:'
const MAX_DESCRIPTION = 1000
const LOCATION_POLL_MS = 60000
const VIEW_STORAGE_KEY = 'gigme:lastCenter'

const formatCoords = (lat: number, lng: number) => `${lat.toFixed(5)}, ${lng.toFixed(5)}`

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
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [selectedEvent, setSelectedEvent] = useState<EventDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [creating, setCreating] = useState(false)
  const [description, setDescription] = useState('')
  const [createLatLng, setCreateLatLng] = useState<LatLng | null>(null)
  const [uploadedMedia, setUploadedMedia] = useState<string[]>([])
  const mapRef = useRef<HTMLDivElement | null>(null)
  const mapInstance = useRef<L.Map | null>(null)
  const markerLayer = useRef<L.LayerGroup | null>(null)
  const draftMarker = useRef<L.Marker | null>(null)
  const hasLocation = useRef(false)
  const hasUserMovedMap = useRef(false)
  const hasStoredCenter = useRef(viewLocation != null)
  const feedLocation = useMemo(() => {
    const preferView = hasStoredCenter.current || hasUserMovedMap.current
    if (preferView) return viewLocation ?? userLocation
    return userLocation ?? viewLocation
  }, [userLocation, viewLocation])
  const canCreate = useMemo(() => !!token && !!(viewLocation || userLocation), [token, viewLocation, userLocation])

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
      setViewLocation((prev) => {
        if (hasStoredCenter.current) return prev ?? next
        if (hasUserMovedMap.current) return prev ?? next
        return next
      })
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
    if (!mapRef.current || !viewLocation) return
    if (!mapInstance.current) {
      mapInstance.current = L.map(mapRef.current).setView([viewLocation.lat, viewLocation.lng], 13)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors',
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
        setViewLocation(next)
        saveStoredCenter(next)
      })
    }
  }, [viewLocation])

  useEffect(() => {
    if (!mapInstance.current || !viewLocation) return
    if (hasUserMovedMap.current) return
    const center = mapInstance.current.getCenter()
    if (center.lat === viewLocation.lat && center.lng === viewLocation.lng) return
    mapInstance.current.setView([viewLocation.lat, viewLocation.lng], mapInstance.current.getZoom(), { animate: false })
  }, [viewLocation])

  useEffect(() => {
    if (!token || !feedLocation) return
    let cancelled = false
    let first = true

    const load = () => {
      if (cancelled) return
      if (first) {
        setLoading(true)
      }
      logDebug('feed_load_start', { lat: feedLocation.lat, lng: feedLocation.lng })
      Promise.all([getNearby(token, feedLocation.lat, feedLocation.lng), getFeed(token, feedLocation.lat, feedLocation.lng)])
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
          if (first) {
            setLoading(false)
            first = false
          }
        })
    }

    load()
    const intervalId = window.setInterval(load, LOCATION_POLL_MS)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [token, feedLocation])

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
        media: uploadedMedia,
      })
      const newMarker: EventMarker = {
        id: created.eventId,
        title,
        startsAt: startsAtISO,
        lat: point.lat,
        lng: point.lng,
        isPromoted: false,
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
        thumbnailUrl: uploadedMedia[0],
        participantsCount: 1,
      }
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
      mapInstance.current?.setView([point.lat, point.lng], mapInstance.current?.getZoom() ?? 13)
      setCreating(false)
      setUploadedMedia([])
      setCreateLatLng(null)
      setDescription('')
      if (feedLocation) {
        const [nearby, feedItems] = await Promise.all([
          getNearby(token, feedLocation.lat, feedLocation.lng),
          getFeed(token, feedLocation.lat, feedLocation.lng),
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
    try {
      logInfo('media_upload_start', { count: fileArray.length })
      for (const file of fileArray) {
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
          await fetch(presign.uploadUrl, {
            method: 'PUT',
            headers: { 'Content-Type': file.type },
            body: file,
          })
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
        setUploadedMedia((prev) => [...prev, fileUrl])
      }
    } catch (err: any) {
      logError('media_upload_error', { message: err.message })
      setError(err.message)
    }
  }

  return (
    <div className="app">
      <header className="header">
        <div>
          <h1>Gigme</h1>
          <p>{userName ? `Hi, ${userName}` : 'Events nearby'}</p>
        </div>
        <button
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
      </header>

      {error && <div className="error">{error}</div>}
      {loading && <div className="loading">Loading...</div>}

      <div className="map" ref={mapRef} />

      {creating && (
        <section className="panel">
          <h2>New event</h2>
          <form onSubmit={handleCreate}>
            <label>
              Title
              <input name="title" maxLength={80} required />
            </label>
            <label>
              Description
              <textarea
                name="description"
                maxLength={MAX_DESCRIPTION}
                required
                value={description}
                onChange={(e) => setDescription(e.target.value)}
              />
            </label>
            <label>
              Starts at
              <input name="startsAt" type="datetime-local" required />
            </label>
            <label>
              Ends at
              <input name="endsAt" type="datetime-local" />
            </label>
            <label>
              Participant limit
              <input name="capacity" type="number" min={1} />
            </label>
            <label>
              Photos (up to 5)
              <input type="file" accept="image/*" multiple onChange={(e) => handleFileUpload(e.target.files)} />
            </label>
            <div className="media-list">
              {uploadedMedia.map((url) => (
                <img key={url} src={url} alt="media" />
              ))}
            </div>
            <p className="hint">
              Tap on the map to choose event location. Current:{' '}
              {createLatLng ? `${createLatLng.lat.toFixed(4)}, ${createLatLng.lng.toFixed(4)}` : 'not selected'}.
              Coordinates are added to the description.
            </p>
            <button type="submit">Create</button>
          </form>
        </section>
      )}

      <section className="panel">
        <h2>Nearby feed</h2>
        {feed.length === 0 && <p>No events yet</p>}
        <div className="feed">
          {feed.map((event) => (
            <div
              key={event.id}
              className="card"
              onClick={() => {
                logInfo('feed_card_click', { eventId: event.id })
                setSelectedId(event.id)
              }}
            >
              {event.thumbnailUrl && <img src={event.thumbnailUrl} alt="thumb" />}
              <div>
                <h3>{event.title}</h3>
                <p>{new Date(event.startsAt).toLocaleString()}</p>
                <p>{event.creatorName}</p>
                <p>Participants: {event.participantsCount}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {selectedEvent && (
        <section className="panel">
          <h2>{selectedEvent.event.title}</h2>
          <p>{selectedEvent.event.description}</p>
          <p>Starts: {new Date(selectedEvent.event.startsAt).toLocaleString()}</p>
          {selectedEvent.event.endsAt && <p>Ends: {new Date(selectedEvent.event.endsAt).toLocaleString()}</p>}
          <p>Participants: {selectedEvent.event.participantsCount}</p>
          <div className="media-list">
            {selectedEvent.media.map((url) => (
              <img key={url} src={url} alt="media" />
            ))}
          </div>
          <div className="actions">
            {selectedEvent.isJoined ? (
              <button onClick={handleLeave}>Leave event</button>
            ) : (
              <button onClick={handleJoin}>Join event</button>
            )}
          </div>
          <h3>Participants</h3>
          <ul>
            {selectedEvent.participants.map((p) => (
              <li key={p.userId}>{p.name}</li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

export default App
