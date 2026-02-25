import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './styles.css'
import 'leaflet/dist/leaflet.css'

// applyBackgroundAssetPaths handles apply background asset paths.
const applyBackgroundAssetPaths = () => {
  if (typeof document === 'undefined') return
  const baseUrl = import.meta.env.BASE_URL || '/'
  const normalizedBase = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`
  document.documentElement.style.setProperty('--bg-image-wide', `url('${normalizedBase}bg/bg-wide.png')`)
  document.documentElement.style.setProperty('--bg-image-tall', `url('${normalizedBase}bg/bg-tall.png')`)
}

applyBackgroundAssetPaths()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
