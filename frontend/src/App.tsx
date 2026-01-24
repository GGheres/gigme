import React, { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
import {
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
} from './api'

type LatLng = { lat: number; lng: number }

const DEFAULT_CENTER: LatLng = { lat: 52.37, lng: 4.9 }

L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
})

function App() {
  const [token, setToken] = useState<string | null>(null)
  const [userName, setUserName] = useState<string>('')
  const [location, setLocation] = useState<LatLng | null>(null)
  const [markers, setMarkers] = useState<EventMarker[]>([])
  const [feed, setFeed] = useState<EventCard[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [selectedEvent, setSelectedEvent] = useState<EventDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [creating, setCreating] = useState(false)
  const [createLatLng, setCreateLatLng] = useState<LatLng | null>(null)
  const [uploadedMedia, setUploadedMedia] = useState<string[]>([])
  const mapRef = useRef<HTMLDivElement | null>(null)
  const mapInstance = useRef<L.Map | null>(null)
  const markerLayer = useRef<L.LayerGroup | null>(null)

  useEffect(() => {
    const tg = (window as any).Telegram?.WebApp
    if (!tg) {
      setError('Open this app inside Telegram WebApp')
      return
    }
    tg.ready()
    tg.expand()
    const initData = tg.initData
    if (!initData) {
      setError('initData is missing')
      return
    }

    authTelegram(initData)
      .then((res) => {
        setToken(res.accessToken)
        const name = [res.user.firstName, res.user.lastName].filter(Boolean).join(' ')
        setUserName(name)
        setError(null)
      })
      .catch((err) => {
        setError(`Auth error: ${err.message}`)
      })
  }, [])

  useEffect(() => {
    if (!token) return
    if (!navigator.geolocation) {
      setLocation(DEFAULT_CENTER)
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocation({ lat: pos.coords.latitude, lng: pos.coords.longitude })
      },
      () => {
        setLocation(DEFAULT_CENTER)
      },
      { enableHighAccuracy: true, timeout: 5000 }
    )
  }, [token])

  useEffect(() => {
    if (!mapRef.current || !location) return
    if (!mapInstance.current) {
      mapInstance.current = L.map(mapRef.current).setView([location.lat, location.lng], 13)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors',
      }).addTo(mapInstance.current)
      markerLayer.current = L.layerGroup().addTo(mapInstance.current)

      mapInstance.current.on('click', (e: L.LeafletMouseEvent) => {
        setCreateLatLng({ lat: e.latlng.lat, lng: e.latlng.lng })
      })
    } else {
      mapInstance.current.setView([location.lat, location.lng], 13)
    }
  }, [location])

  useEffect(() => {
    if (!token || !location) return
    setLoading(true)
    Promise.all([getNearby(token, location.lat, location.lng), getFeed(token, location.lat, location.lng)])
      .then(([nearby, feedItems]) => {
        setMarkers(nearby)
        setFeed(feedItems)
        setError(null)
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [token, location])

  useEffect(() => {
    if (!markerLayer.current) return
    markerLayer.current.clearLayers()
    markers.forEach((m) => {
      const marker = L.marker([m.lat, m.lng])
      marker.on('click', () => setSelectedId(m.id))
      markerLayer.current?.addLayer(marker)
    })
  }, [markers])

  useEffect(() => {
    if (!token || selectedId == null) return
    getEvent(token, selectedId)
      .then((detail) => setSelectedEvent(detail))
      .catch((err) => setError(err.message))
  }, [token, selectedId])

  const canCreate = useMemo(() => !!token && !!location, [token, location])

  const handleJoin = async () => {
    if (!token || !selectedEvent) return
    await joinEvent(token, selectedEvent.event.id)
    const updated = await getEvent(token, selectedEvent.event.id)
    setSelectedEvent(updated)
  }

  const handleLeave = async () => {
    if (!token || !selectedEvent) return
    await leaveEvent(token, selectedEvent.event.id)
    const updated = await getEvent(token, selectedEvent.event.id)
    setSelectedEvent(updated)
  }

  const handleCreate = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (!token) return
    const form = new FormData(e.currentTarget)
    const title = String(form.get('title') || '')
    const description = String(form.get('description') || '')
    const startsAtLocal = String(form.get('startsAt') || '')
    const endsAtLocal = String(form.get('endsAt') || '')
    const capacityRaw = String(form.get('capacity') || '')

    if (!title || !description || !startsAtLocal) {
      setError('Please fill all required fields')
      return
    }

    const startsAtISO = new Date(startsAtLocal).toISOString()
    const endsAtISO = endsAtLocal ? new Date(endsAtLocal).toISOString() : undefined
    const capacity = capacityRaw ? Number(capacityRaw) : undefined
    const point = createLatLng || location || DEFAULT_CENTER

    setLoading(true)
    try {
      await createEvent(token, {
        title,
        description,
        startsAt: startsAtISO,
        endsAt: endsAtISO,
        lat: point.lat,
        lng: point.lng,
        capacity,
        media: uploadedMedia,
      })
      setCreating(false)
      setUploadedMedia([])
      setCreateLatLng(null)
      if (location) {
        const [nearby, feedItems] = await Promise.all([
          getNearby(token, location.lat, location.lng),
          getFeed(token, location.lat, location.lng),
        ])
        setMarkers(nearby)
        setFeed(feedItems)
      }
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleFileUpload = async (files: FileList | null) => {
    if (!token || !files) return
    const fileArray = Array.from(files).slice(0, 5 - uploadedMedia.length)
    try {
      for (const file of fileArray) {
        const presign = await presignMedia(token, {
          fileName: file.name,
          contentType: file.type,
          sizeBytes: file.size,
        })
        await fetch(presign.uploadUrl, {
          method: 'PUT',
          headers: { 'Content-Type': file.type },
          body: file,
        })
        setUploadedMedia((prev) => [...prev, presign.fileUrl])
      }
    } catch (err: any) {
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
        <button disabled={!canCreate} onClick={() => setCreating((v) => !v)}>
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
              <textarea name="description" maxLength={1000} required />
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
            <p className="hint">Tap on the map to choose event location. Current: {createLatLng ? `${createLatLng.lat.toFixed(4)}, ${createLatLng.lng.toFixed(4)}` : 'not selected'}</p>
            <button type="submit">Create</button>
          </form>
        </section>
      )}

      <section className="panel">
        <h2>Nearby feed</h2>
        {feed.length === 0 && <p>No events yet</p>}
        <div className="feed">
          {feed.map((event) => (
            <div key={event.id} className="card" onClick={() => setSelectedId(event.id)}>
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
