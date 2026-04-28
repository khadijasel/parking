const parseNumber = (value, fallback) => {
  const parsed = Number(value)

  if (Number.isFinite(parsed)) {
    return parsed
  }

  return fallback
}

const parseCenter = (latValue, lngValue, fallback) => {
  return [
    parseNumber(latValue, fallback[0]),
    parseNumber(lngValue, fallback[1]),
  ]
}

const defaultCenter = [36.7538, 3.0588]

export const mapConfig = {
  tileUrl:
    import.meta.env.VITE_MAP_TILE_URL ??
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution:
    import.meta.env.VITE_MAP_ATTRIBUTION ?? '&copy; OpenStreetMap contributors',
  center: parseCenter(
    import.meta.env.VITE_MAP_CENTER_LAT,
    import.meta.env.VITE_MAP_CENTER_LNG,
    defaultCenter,
  ),
  zoom: parseNumber(import.meta.env.VITE_MAP_ZOOM, 13),
  minZoom: parseNumber(import.meta.env.VITE_MAP_MIN_ZOOM, 3),
  maxZoom: parseNumber(import.meta.env.VITE_MAP_MAX_ZOOM, 19),
}
