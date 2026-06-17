<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
import { mapConfig } from '@/config/map'
import { listOwnerParkings, upsertOwnerParkingLayout } from '@/services/owner/parkingSettingsApi'
import { useAuthStore } from '@/stores/auth'

L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
})

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const ownerParkings = ref([])
const selectedParkingId = ref('')
const selectedSpotId = ref('')

const loading = ref(false)
const loadError = ref('')
const mapNotice = ref('')
const mapFatalError = ref('')
const gridError = ref('')
const gridSuccess = ref('')
const savingLayout = ref(false)

const mapContainer = ref(null)
const mapInstance = ref(null)
const markersLayer = ref(null)
const markerByParkingId = new Map()
const relocatingLocation = ref(false)

const gridConfigForm = reactive({
  rows: 0,
  cols: 0,
  floor: 'B1',
  zone: 'Zone A',
  laneRows: '',
  laneCols: '',
})

const spotForm = reactive({
  label: '',
  type: 'STANDARD',
  state: 'AVAILABLE',
  arduinoId: '',
  channel: '',
  topic: 'parking/spots',
})

const selectedSpotForm = reactive({
  label: '',
  type: 'STANDARD',
  state: 'AVAILABLE',
  arduinoId: '',
  channel: '',
  topic: '',
})

const dayLabelMap = {
  MONDAY: 'Lundi',
  TUESDAY: 'Mardi',
  WEDNESDAY: 'Mercredi',
  THURSDAY: 'Jeudi',
  FRIDAY: 'Vendredi',
  SATURDAY: 'Samedi',
  SUNDAY: 'Dimanche',
}

const typeLabelMap = {
  STANDARD: 'Standard',
  PMR: 'PMR',
  VIP: 'VIP',
}

const spotTypeOptions = ['STANDARD', 'PMR', 'VIP']

const stateLabelMap = {
  AVAILABLE: 'Disponible',
  OCCUPIED: 'Occupee',
  RESERVED: 'Reservee',
  OFFLINE: 'Hors service',
}

const spotStateOptions = ['AVAILABLE', 'OCCUPIED', 'RESERVED', 'OFFLINE']

const toNumber = (value, fallback) => {
  const parsed = Number(value)

  if (Number.isFinite(parsed)) {
    return parsed
  }

  return fallback
}

const parseLaneInput = (value, maxCount) => {
  const tokens = String(value ?? '')
    .split(/[\s,;]+/)
    .map((item) => item.trim())
    .filter(Boolean)

  const uniq = new Set()

  tokens.forEach((token) => {
    const parsed = Math.round(toNumber(token, -1))
    if (parsed >= 0 && parsed < maxCount) {
      uniq.add(parsed)
    }
  })

  return Array.from(uniq).sort((a, b) => a - b)
}

const isValidCoordinatePair = (lat, lng) => {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
}

const updateParkingRecord = (updatedParking) => {
  ownerParkings.value = ownerParkings.value.map((parking) => {
    return parking.id === updatedParking.id ? updatedParking : parking
  })
}

const generateSpotLabel = () => {
  const existing = new Set(selectedSpots.value.map((spot) => spot.label.toUpperCase()))
  let index = selectedSpots.value.length + 1

  while (index < 10000) {
    const label = `P${String(index).padStart(2, '0')}`
    if (!existing.has(label.toUpperCase())) {
      return label
    }
    index += 1
  }

  return `P${Date.now()}`
}

const buildOwnerPayload = (parking) => {
  if (!parking?.location?.valid) {
    return null
  }

  const grid = parking.indoorMap?.grid ?? { rows: 0, cols: 0, laneRows: [], laneCols: [] }
  const spots = Array.isArray(parking.indoorMap?.spots) ? parking.indoorMap.spots : []

  return {
    parkingId: String(parking.id ?? '').trim(),
    name: String(parking.name ?? '').trim(),
    address: String(parking.address ?? '').trim(),
    location: {
      lat: Number(parking.location.lat) || 0,
      lng: Number(parking.location.lng) || 0,
    },
    capacity: Math.max(1, Math.round(toNumber(parking.capacity, 1))),
    indoorMap: {
      floor: String(parking.indoorMap?.floor ?? 'B1').trim() || 'B1',
      zone: String(parking.indoorMap?.zone ?? 'Zone A').trim() || 'Zone A',
      grid: {
        rows: Math.max(1, Math.round(toNumber(grid.rows, 1))),
        cols: Math.max(1, Math.round(toNumber(grid.cols, 1))),
        laneRows: Array.isArray(grid.laneRows) ? grid.laneRows : [],
        laneCols: Array.isArray(grid.laneCols) ? grid.laneCols : [],
      },
      spots: spots.map((spot) => {
        return {
          spotId: String(spot.id ?? '').trim(),
          label: String(spot.label ?? '').trim(),
          row: Math.max(0, Math.round(toNumber(spot.row, 0))),
          col: Math.max(0, Math.round(toNumber(spot.col, 0))),
          type: String(spot.type ?? 'STANDARD').trim().toUpperCase(),
          state: String(spot.state ?? 'AVAILABLE').trim().toUpperCase(),
          sensor: {
            arduinoId: String(spot.sensor?.arduinoId ?? '').trim(),
            channel: String(spot.sensor?.channel ?? '').trim(),
            topic: String(spot.sensor?.topic ?? '').trim(),
          },
          updatedAt: String(spot.updatedAt ?? new Date().toISOString()),
        }
      }),
    },
  }
}

const normalizeSpot = (spot = {}) => {
  const type = String(spot?.type ?? 'STANDARD').trim().toUpperCase()
  const state = String(spot?.state ?? 'AVAILABLE').trim().toUpperCase()

  return {
    id: String(spot?.spotId ?? '').trim(),
    label: String(spot?.label ?? '').trim(),
    row: Math.max(0, Math.round(toNumber(spot?.row, 0))),
    col: Math.max(0, Math.round(toNumber(spot?.col, 0))),
    type,
    state,
    sensor: {
      arduinoId: String(spot?.sensor?.arduinoId ?? '').trim(),
      channel: String(spot?.sensor?.channel ?? '').trim(),
      topic: String(spot?.sensor?.topic ?? '').trim(),
    },
    updatedAt: String(spot?.updatedAt ?? ''),
  }
}

const normalizeParking = (payload = {}) => {
  const location = payload?.location ?? {}
  const ownerAccount = payload?.ownerAccount ?? {}
  const indoorMap = payload?.indoorMap ?? {}
  const grid = indoorMap?.grid ?? {}
  const businessSettings = payload?.businessSettings ?? {}
  const pricing = businessSettings?.pricing ?? {}
  const spots = Array.isArray(indoorMap?.spots)
    ? indoorMap.spots.map((spot) => normalizeSpot(spot)).filter((spot) => spot.id)
    : []

  const lat = toNumber(location?.lat, Number.NaN)
  const lng = toNumber(location?.lng, Number.NaN)

  return {
    id: String(payload?.parkingId ?? '').trim(),
    name: String(payload?.name ?? '').trim(),
    address: String(payload?.address ?? '').trim(),
    capacity: toNumber(payload?.capacity, 0),
    ownerAccount: {
      name: String(ownerAccount?.name ?? '').trim(),
      email: String(ownerAccount?.email ?? '').trim(),
      phone: String(ownerAccount?.phone ?? '').trim(),
    },
    location: {
      lat,
      lng,
      valid: isValidCoordinatePair(lat, lng),
    },
    indoorMap: {
      floor: String(indoorMap?.floor ?? 'B1').trim() || 'B1',
      zone: String(indoorMap?.zone ?? 'Zone A').trim() || 'Zone A',
      grid: {
        rows: Math.max(0, Math.round(toNumber(grid?.rows, 0))),
        cols: Math.max(0, Math.round(toNumber(grid?.cols, 0))),
        laneRows: Array.isArray(grid?.laneRows)
          ? grid.laneRows
              .map((row) => Math.max(0, Math.round(toNumber(row, -1))))
              .filter((row) => row >= 0)
          : [],
        laneCols: Array.isArray(grid?.laneCols)
          ? grid.laneCols
              .map((col) => Math.max(0, Math.round(toNumber(col, -1))))
              .filter((col) => col >= 0)
          : [],
      },
      spots,
    },
    businessSettings: {
      workingDays: Array.isArray(businessSettings?.workingDays)
        ? businessSettings.workingDays.map((day) => String(day).toUpperCase())
        : ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'],
      openingTime: String(businessSettings?.openingTime ?? '08:00'),
      closingTime: String(businessSettings?.closingTime ?? '20:00'),
      pricing: {
        hourlyRateDzd: toNumber(pricing?.hourlyRateDzd, 0),
        dailyRateDzd: toNumber(pricing?.dailyRateDzd, 0),
        monthlyRateDzd: pricing?.monthlyRateDzd == null ? null : toNumber(pricing.monthlyRateDzd, 0),
      },
    },
  }
}

const parkingStats = (parking) => {
  const spots = parking?.indoorMap?.spots ?? []
  const occupied = spots.filter((spot) => spot.state === 'OCCUPIED').length
  const available = spots.filter((spot) => spot.state === 'AVAILABLE').length
  const reserved = spots.filter((spot) => spot.state === 'RESERVED').length
  const offline = spots.filter((spot) => spot.state === 'OFFLINE').length

  return {
    total: spots.length,
    occupied,
    available,
    reserved,
    offline,
    occupancyPercent: spots.length ? Math.round((occupied / spots.length) * 100) : 0,
  }
}

const markerVisual = (parking) => {
  const stats = parkingStats(parking)

  if (stats.occupancyPercent >= 85) {
    return {
      color: '#dc2626',
      label: 'P',
    }
  }

  if (stats.occupancyPercent >= 60) {
    return {
      color: '#d97706',
      label: 'P',
    }
  }

  return {
    color: '#16a34a',
    label: 'P',
  }
}

const parkingMarkerIcon = (parking) => {
  const visual = markerVisual(parking)

  return L.divIcon({
    className: 'parking-map-pin',
    html: `<div style="height:36px;width:36px;border-radius:9999px;background:${visual.color};border:2px solid #ffffff;box-shadow:0 4px 10px rgba(15,23,42,0.28);display:flex;align-items:center;justify-content:center;color:#ffffff;font-size:14px;font-weight:800;">${visual.label}</div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 18],
    popupAnchor: [0, -16],
    tooltipAnchor: [0, -22],
  })
}

const selectedParking = computed(() => {
  return ownerParkings.value.find((parking) => parking.id === selectedParkingId.value) ?? null
})

const selectedGrid = computed(() => {
  return selectedParking.value?.indoorMap?.grid ?? { rows: 0, cols: 0, laneRows: [], laneCols: [] }
})

const selectedSpots = computed(() => {
  return selectedParking.value?.indoorMap?.spots ?? []
})

const selectedSpot = computed(() => {
  return selectedSpots.value.find((spot) => spot.id === selectedSpotId.value) ?? null
})

const selectedLocationLabel = computed(() => {
  if (!selectedParking.value?.location?.valid) {
    return '-'
  }

  return `${selectedParking.value.location.lat.toFixed(6)}, ${selectedParking.value.location.lng.toFixed(6)}`
})

const selectedParkingOwnerLabel = computed(() => {
  const ownerName = String(selectedParking.value?.ownerAccount?.name ?? '').trim()
  const ownerEmail = String(selectedParking.value?.ownerAccount?.email ?? '').trim()

  if (ownerName && ownerEmail) {
    return `${ownerName} (${ownerEmail})`
  }

  return ownerName || ownerEmail || 'Non renseigne'
})

const selectedMonthlyRateLabel = computed(() => {
  const monthlyRate = selectedParking.value?.businessSettings?.pricing?.monthlyRateDzd

  if (monthlyRate == null) {
    return '-'
  }

  return `${Number(monthlyRate)} DZD`
})

const selectedWorkingDaysLabel = computed(() => {
  const workingDays = selectedParking.value?.businessSettings?.workingDays ?? []

  if (!workingDays.length) {
    return '-'
  }

  return workingDays
    .map((day) => dayLabelMap[day] ?? day)
    .join(', ')
})

const gridRows = computed(() => {
  return Array.from({ length: Math.max(0, selectedGrid.value.rows) }, (_, index) => index)
})

const gridCols = computed(() => {
  return Array.from({ length: Math.max(0, selectedGrid.value.cols) }, (_, index) => index)
})

const laneRowSet = computed(() => {
  return new Set(selectedGrid.value.laneRows ?? [])
})

const laneColSet = computed(() => {
  return new Set(selectedGrid.value.laneCols ?? [])
})

const spotMapByCell = computed(() => {
  const map = new Map()
  selectedSpots.value.forEach((spot) => {
    map.set(`${spot.row}-${spot.col}`, spot)
  })
  return map
})

const syncGridConfigFromParking = () => {
  const grid = selectedParking.value?.indoorMap?.grid

  if (!grid) {
    gridConfigForm.rows = 0
    gridConfigForm.cols = 0
    gridConfigForm.floor = 'B1'
    gridConfigForm.zone = 'Zone A'
    gridConfigForm.laneRows = ''
    gridConfigForm.laneCols = ''
    return
  }

  gridConfigForm.rows = grid.rows
  gridConfigForm.cols = grid.cols
  gridConfigForm.floor = selectedParking.value?.indoorMap?.floor ?? 'B1'
  gridConfigForm.zone = selectedParking.value?.indoorMap?.zone ?? 'Zone A'
  gridConfigForm.laneRows = Array.isArray(grid.laneRows) ? grid.laneRows.join(',') : ''
  gridConfigForm.laneCols = Array.isArray(grid.laneCols) ? grid.laneCols.join(',') : ''
}

const persistSelectedParkingLayout = async ({ successMessage = '', errorPrefix = 'Sauvegarde echouee' } = {}) => {
  if (savingLayout.value) {
    return false
  }

  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return false
  }

  const payload = buildOwnerPayload(selectedParking.value)
  if (!payload) {
    gridError.value = 'Coordonnees parking invalides.'
    return false
  }

  savingLayout.value = true
  gridError.value = ''
  gridSuccess.value = ''

  try {
    const result = await upsertOwnerParkingLayout({
      payload,
      authHeaders: authStore.authHeaders,
    })

    if (!result.ok) {
      gridError.value = `${errorPrefix}: ${result.message}`
      return false
    }

    const updatedParking = normalizeParking(result.data)
    updateParkingRecord(updatedParking)
    selectedParkingId.value = updatedParking.id
    gridSuccess.value = successMessage
    return true
  } finally {
    savingLayout.value = false
  }
}

const toggleLocationRelocation = () => {
  if (!selectedParking.value || savingLayout.value) {
    return
  }

  relocatingLocation.value = !relocatingLocation.value

  if (relocatingLocation.value) {
    gridError.value = ''
    gridSuccess.value = 'Mode deplacement actif: cliquez sur la carte pour definir le nouvel emplacement.'
    return
  }

  gridSuccess.value = 'Mode deplacement desactive.'
}

const relocateSelectedParking = async (lat, lng) => {
  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return
  }

  const nextParking = {
    ...selectedParking.value,
    location: {
      lat,
      lng,
      valid: true,
    },
  }

  updateParkingRecord(nextParking)
  renderParkingMarkers()
  focusOnSelectedParking()

  const success = await persistSelectedParkingLayout({
    successMessage: 'Emplacement parking mis a jour et enregistre.',
    errorPrefix: 'Enregistrement de l emplacement impossible',
  })

  if (success) {
    relocatingLocation.value = false
  }
}

const applyGridConfig = async () => {
  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return
  }

  const rows = Math.max(1, Math.round(toNumber(gridConfigForm.rows, 1)))
  const cols = Math.max(1, Math.round(toNumber(gridConfigForm.cols, 1)))
  const laneRows = parseLaneInput(gridConfigForm.laneRows, rows)
  const laneCols = parseLaneInput(gridConfigForm.laneCols, cols)

  const nextGrid = {
    rows,
    cols,
    laneRows,
    laneCols,
  }

  const nextParking = {
    ...selectedParking.value,
    indoorMap: {
      ...selectedParking.value.indoorMap,
      floor: String(gridConfigForm.floor ?? 'B1').trim() || 'B1',
      zone: String(gridConfigForm.zone ?? 'Zone A').trim() || 'Zone A',
      grid: nextGrid,
    },
  }

  updateParkingRecord(nextParking)

  await persistSelectedParkingLayout({
    successMessage: 'Grille mise a jour et enregistree.',
    errorPrefix: 'Enregistrement de la grille impossible',
  })
}

const addSpotAt = async (row, col) => {
  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return
  }

  const spotId = `R${row + 1}C${col + 1}`
  const label = spotForm.label.trim() || generateSpotLabel()

  const duplicate = selectedSpots.value.some((spot) => spot.label.toUpperCase() === label.toUpperCase())
  if (duplicate) {
    gridError.value = 'ID de place deja utilise.'
    return
  }

  const nextSpot = {
    id: spotId,
    label,
    row,
    col,
    type: spotForm.type,
    state: spotForm.state,
    sensor: {
      arduinoId: spotForm.arduinoId.trim(),
      channel: spotForm.channel.trim(),
      topic: spotForm.topic.trim(),
    },
    updatedAt: new Date().toISOString(),
  }

  const nextSpots = [...selectedSpots.value, nextSpot]
  const nextParking = {
    ...selectedParking.value,
    indoorMap: {
      ...selectedParking.value.indoorMap,
      spots: nextSpots,
    },
  }

  updateParkingRecord(nextParking)
  selectedSpotId.value = nextSpot.id
  spotForm.label = ''

  await persistSelectedParkingLayout({
    successMessage: `Place ${nextSpot.label} ajoutee et enregistree.`,
    errorPrefix: 'Enregistrement de la place impossible',
  })
}

const saveSelectedSpot = async () => {
  if (!selectedParking.value || !selectedSpot.value) {
    gridError.value = 'Selectionnez une place a modifier.'
    return
  }

  const label = selectedSpotForm.label.trim()
  if (!label) {
    gridError.value = 'Le code de place est obligatoire.'
    return
  }

  const duplicate = selectedSpots.value.some((spot) => {
    return spot.id !== selectedSpot.value.id && spot.label.toUpperCase() === label.toUpperCase()
  })

  if (duplicate) {
    gridError.value = 'Un autre spot utilise deja ce code.'
    return
  }

  const nextSpots = selectedSpots.value.map((spot) => {
    if (spot.id !== selectedSpot.value.id) {
      return spot
    }

    return {
      ...spot,
      label,
      type: selectedSpotForm.type,
      state: selectedSpotForm.state,
      sensor: {
        arduinoId: selectedSpotForm.arduinoId.trim(),
        channel: selectedSpotForm.channel.trim(),
        topic: selectedSpotForm.topic.trim(),
      },
      updatedAt: new Date().toISOString(),
    }
  })

  const nextParking = {
    ...selectedParking.value,
    indoorMap: {
      ...selectedParking.value.indoorMap,
      spots: nextSpots,
    },
  }

  updateParkingRecord(nextParking)

  await persistSelectedParkingLayout({
    successMessage: 'Place mise a jour et enregistree.',
    errorPrefix: 'Enregistrement de la place impossible',
  })
}

const removeSelectedSpot = async () => {
  if (!selectedParking.value || !selectedSpot.value) {
    gridError.value = 'Selectionnez une place a supprimer.'
    return
  }

  const nextSpots = selectedSpots.value.filter((spot) => spot.id !== selectedSpot.value.id)
  const nextParking = {
    ...selectedParking.value,
    indoorMap: {
      ...selectedParking.value.indoorMap,
      spots: nextSpots,
    },
  }

  updateParkingRecord(nextParking)
  selectedSpotId.value = ''

  await persistSelectedParkingLayout({
    successMessage: 'Place supprimee et enregistree.',
    errorPrefix: 'Suppression de la place impossible',
  })
}

const syncSelectionFromRoute = () => {
  if (!ownerParkings.value.length) {
    selectedParkingId.value = ''
    return
  }

  const routeParkingId = String(route.query.parkingId ?? '').trim()

  if (routeParkingId && ownerParkings.value.some((parking) => parking.id === routeParkingId)) {
    selectedParkingId.value = routeParkingId
    return
  }

  const currentIsValid = ownerParkings.value.some((parking) => parking.id === selectedParkingId.value)

  if (!currentIsValid) {
    selectedParkingId.value = ownerParkings.value[0].id
  }
}

const popupNode = (parking) => {
  const container = document.createElement('div')
  const stats = parkingStats(parking)

  const title = document.createElement('strong')
  title.textContent = parking.name || parking.id
  container.appendChild(title)

  const idRow = document.createElement('div')
  idRow.textContent = `ID: ${parking.id || '-'}`
  idRow.style.fontSize = '12px'
  container.appendChild(idRow)

  const ownerRow = document.createElement('div')
  ownerRow.textContent = `Proprietaire: ${parking.ownerAccount?.name || '-'} | Tel: ${parking.ownerAccount?.phone || '-'}`
  ownerRow.style.fontSize = '12px'
  container.appendChild(ownerRow)

  const statsRow = document.createElement('div')
  statsRow.textContent = `Places: ${stats.total} | Occupation: ${stats.occupancyPercent}%`
  statsRow.style.fontSize = '12px'
  container.appendChild(statsRow)

  const gridRow = document.createElement('div')
  gridRow.textContent = `Etage: ${parking.indoorMap?.floor || '-'} | Zone: ${parking.indoorMap?.zone || '-'}`
  gridRow.style.fontSize = '12px'
  container.appendChild(gridRow)

  const addressRow = document.createElement('div')
  addressRow.textContent = parking.address || '-'
  addressRow.style.fontSize = '12px'
  container.appendChild(addressRow)

  return container
}

const focusOnSelectedParking = () => {
  if (!mapInstance.value || !selectedParking.value?.location?.valid) {
    return
  }

  const marker = markerByParkingId.get(selectedParking.value.id)

  mapInstance.value.flyTo(
    [selectedParking.value.location.lat, selectedParking.value.location.lng],
    Math.max(mapConfig.zoom, 15),
  )

  if (marker) {
    marker.openPopup()
  }
}

const renderParkingMarkers = () => {
  if (!mapInstance.value || !markersLayer.value) {
    return
  }

  markersLayer.value.clearLayers()
  markerByParkingId.clear()

  const parkingsWithLocation = ownerParkings.value.filter((parking) => parking.location.valid)

  if (!parkingsWithLocation.length) {
    mapNotice.value = ownerParkings.value.length
      ? 'Aucune coordonnee map valide pour vos parkings.'
      : ''
    return
  }

  mapNotice.value = ''

  parkingsWithLocation.forEach((parking) => {
    const marker = L.marker([parking.location.lat, parking.location.lng], {
      title: parking.name || parking.id,
      keyboard: false,
      icon: parkingMarkerIcon(parking),
    })

    marker.bindPopup(popupNode(parking))
    marker.bindTooltip(parking.name || parking.id, {
      permanent: true,
      direction: 'top',
      offset: [0, -20],
      opacity: 0.9,
    })
    marker.on('click', () => {
      selectedParkingId.value = parking.id
    })

    markersLayer.value.addLayer(marker)
    markerByParkingId.set(parking.id, marker)
  })

  if (selectedParking.value?.location?.valid) {
    focusOnSelectedParking()
    return
  }

  const bounds = L.latLngBounds(
    parkingsWithLocation.map((parking) => [parking.location.lat, parking.location.lng]),
  )

  mapInstance.value.fitBounds(bounds, {
    padding: [30, 30],
    maxZoom: Math.max(mapConfig.zoom, 15),
  })
}

const initializeMap = () => {
  if (!mapContainer.value) {
    mapFatalError.value = 'Impossible de charger la map.'
    return
  }

  const map = L.map(mapContainer.value, {
    minZoom: mapConfig.minZoom,
    zoomControl: true,
  }).setView(mapConfig.center, mapConfig.zoom)

  L.tileLayer(mapConfig.tileUrl, {
    attribution: mapConfig.attribution,
    maxZoom: mapConfig.maxZoom,
  }).addTo(map)

  map.on('click', (event) => {
    if (!relocatingLocation.value || savingLayout.value || !selectedParking.value) {
      return
    }

    const lat = Number(event.latlng.lat.toFixed(6))
    const lng = Number(event.latlng.lng.toFixed(6))
    relocateSelectedParking(lat, lng)
  })

  markersLayer.value = L.layerGroup().addTo(map)
  mapFatalError.value = ''
  mapInstance.value = map
}

const loadOwnerParkings = async () => {
  loading.value = true
  loadError.value = ''

  try {
    const result = await listOwnerParkings({
      authHeaders: authStore.authHeaders,
    })

    if (!result.ok) {
      loadError.value = result.message
      ownerParkings.value = []
      selectedParkingId.value = ''
      selectedSpotId.value = ''
      renderParkingMarkers()
      return
    }

    ownerParkings.value = result.data.map((payload) => normalizeParking(payload))
    syncSelectionFromRoute()
    syncGridConfigFromParking()
    renderParkingMarkers()
  } finally {
    loading.value = false
  }
}

const spotAt = (row, col) => {
  return spotMapByCell.value.get(`${row}-${col}`) ?? null
}

const isHorizontalLane = (row) => {
  return laneRowSet.value.has(row)
}

const isVerticalLane = (col) => {
  return laneColSet.value.has(col)
}

const isLaneCell = (row, col) => {
  return isHorizontalLane(row) || isVerticalLane(col)
}

const getLaneType = (row, col) => {
  const hasHorizontal = isHorizontalLane(row)
  const hasVertical = isVerticalLane(col)
  if (hasHorizontal && hasVertical) {
    return 'intersection'
  }
  if (hasHorizontal) {
    return 'horizontal'
  }
  if (hasVertical) {
    return 'vertical'
  }
  return null
}

const cellClass = (row, col) => {
  if (isLaneCell(row, col)) {
    const laneType = getLaneType(row, col)
    if (laneType === 'intersection') {
      return 'cursor-not-allowed border-solid border-primary bg-primary/10 text-primary font-bold'
    }
    return 'cursor-not-allowed border-dashed border-outline-variant bg-surface-container text-outline'
  }

  const spot = spotAt(row, col)
  if (!spot) {
    return 'cursor-pointer border-outline-variant bg-surface-container-low text-outline hover:border-primary/50 hover:bg-primary/5'
  }

  if (spot.state === 'OCCUPIED') {
    return 'cursor-pointer border-red-300 bg-red-50 text-red-700'
  }

  if (spot.state === 'RESERVED') {
    return 'cursor-pointer border-amber-300 bg-amber-50 text-amber-700'
  }

  if (spot.state === 'OFFLINE') {
    return 'cursor-pointer border-slate-300 bg-slate-100 text-slate-500'
  }

  return 'cursor-pointer border-emerald-300 bg-emerald-50 text-emerald-700'
}

const onGridCellClick = (row, col) => {
  if (isLaneCell(row, col)) {
    return
  }

  const spot = spotAt(row, col)
  if (!spot) {
    addSpotAt(row, col)
    return
  }

  selectedSpotId.value = spot.id
}

const onGridCellRightClick = (row, col) => {
  if (isLaneCell(row, col)) {
    return
  }

  const spot = spotAt(row, col)
  if (!spot) {
    return
  }

  const confirmed = window.confirm(`Supprimer la place ${spot.label} ?`)
  if (!confirmed) {
    return
  }

  selectedSpotId.value = spot.id
  removeSelectedSpot()
}

watch(selectedParkingId, (nextValue) => {
  const nextParkingId = String(nextValue ?? '').trim()
  const currentParkingId = String(route.query.parkingId ?? '').trim()

  if (nextParkingId !== currentParkingId) {
    const nextQuery = { ...route.query }

    if (nextParkingId) {
      nextQuery.parkingId = nextParkingId
    } else {
      delete nextQuery.parkingId
    }

    router.replace({ path: route.path, query: nextQuery }).catch(() => {
      // Ignore duplicate navigation errors.
    })
  }

  selectedSpotId.value = ''
  relocatingLocation.value = false
  gridError.value = ''
  gridSuccess.value = ''
  syncGridConfigFromParking()
  focusOnSelectedParking()
})

watch(
  () => route.query.parkingId,
  () => {
    syncSelectionFromRoute()
    focusOnSelectedParking()
  },
)

watch(
  selectedSpots,
  (spots) => {
    if (!selectedSpotId.value) {
      return
    }

    const exists = spots.some((spot) => spot.id === selectedSpotId.value)
    if (!exists) {
      selectedSpotId.value = ''
    }
  },
)

watch(
  selectedSpot,
  (spot) => {
    if (!spot) {
      selectedSpotForm.label = ''
      selectedSpotForm.type = 'STANDARD'
      selectedSpotForm.state = 'AVAILABLE'
      selectedSpotForm.arduinoId = ''
      selectedSpotForm.channel = ''
      selectedSpotForm.topic = ''
      return
    }

    selectedSpotForm.label = spot.label
    selectedSpotForm.type = spot.type
    selectedSpotForm.state = spot.state
    selectedSpotForm.arduinoId = spot.sensor?.arduinoId ?? ''
    selectedSpotForm.channel = spot.sensor?.channel ?? ''
    selectedSpotForm.topic = spot.sensor?.topic ?? ''
  },
)

onMounted(async () => {
  await nextTick()
  initializeMap()
  await loadOwnerParkings()
})

onBeforeUnmount(() => {
  markerByParkingId.clear()

  if (mapInstance.value) {
    mapInstance.value.remove()
    mapInstance.value = null
  }
})
</script>

<template>
  <section class="space-y-8">
    <div>
      <h2 class="font-headline text-2xl font-extrabold text-on-surface">Carte en direct</h2>
      <p class="mt-1 text-sm text-on-surface-variant">
        Modifiez la carte de votre parking, ajustez la grille et sauvegardez vos changements.
      </p>
      <p class="mt-2 inline-flex rounded-lg bg-primary/10 px-3 py-2 text-xs font-semibold text-primary">
        Mode edition active: cliquez une case vide pour ajouter une place, puis sauvegardez.
      </p>
    </div>

    <div class="grid gap-6 xl:grid-cols-[1.35fr,1fr]">
      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Emplacement global du parking</h3>
        <p class="mt-1 text-sm text-on-surface-variant">
          Selectionnez un parking proprietaire pour le centrer. Activez le mode deplacement puis cliquez sur la carte pour modifier son emplacement.
        </p>

        <div class="mt-4 flex flex-wrap items-center gap-2">
          <button
            type="button"
            class="rounded-lg px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-60"
            :class="relocatingLocation ? 'bg-primary text-white' : 'bg-surface-container text-on-surface hover:bg-surface-container-high'"
            :disabled="savingLayout || !selectedParking"
            @click="toggleLocationRelocation"
          >
            {{ relocatingLocation ? 'Mode deplacement actif' : 'Modifier emplacement' }}
          </button>
          <p v-if="selectedParking" class="text-xs text-on-surface-variant">
            Position actuelle: {{ selectedLocationLabel }}
          </p>
        </div>

        <p v-if="mapNotice" class="mt-3 rounded-lg bg-amber-100 px-3 py-2 text-sm font-semibold text-amber-700">
          {{ mapNotice }}
        </p>

        <div class="mt-5 overflow-hidden rounded-2xl border border-outline-variant/40">
          <div
            v-if="mapFatalError"
            class="flex h-[420px] items-center justify-center bg-surface-container-low px-4 text-center text-sm font-semibold text-error"
          >
            {{ mapFatalError }}
          </div>
          <div v-else ref="mapContainer" class="h-[420px] w-full" />
        </div>

        <article v-if="selectedParking" class="mt-4 rounded-2xl bg-surface-container-low p-4">
          <div class="flex items-start gap-3">
            <div>
              <h4 class="font-headline text-base font-bold text-on-surface">{{ selectedParking.name }}</h4>
              <p class="text-xs text-on-surface-variant">{{ selectedParking.id }}</p>
            </div>
          </div>

          <div class="mt-3 grid gap-2 text-xs text-on-surface-variant sm:grid-cols-2">
            <p><span class="font-semibold text-on-surface">Adresse:</span> {{ selectedParking.address || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Proprietaire:</span> {{ selectedParkingOwnerLabel }}</p>
            <p><span class="font-semibold text-on-surface">Telephone:</span> {{ selectedParking.ownerAccount?.phone || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Position:</span> {{ selectedLocationLabel }}</p>
            <p><span class="font-semibold text-on-surface">Capacite:</span> {{ selectedParking.capacity }}</p>
            <p><span class="font-semibold text-on-surface">Etage:</span> {{ selectedParking.indoorMap?.floor || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Zone:</span> {{ selectedParking.indoorMap?.zone || '-' }}</p>
          </div>
        </article>
      </article>

      <div class="space-y-6">
        <article class="surface-card p-6">
          <div class="flex items-center justify-between gap-3">
            <h3 class="font-headline text-lg font-bold text-on-surface">Informations pre-remplies</h3>
            <button
              type="button"
              class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold text-on-surface hover:bg-surface-container-high"
              @click="loadOwnerParkings"
            >
              Actualiser
            </button>
          </div>

          <label class="mt-4 block text-xs font-semibold uppercase tracking-[0.08em] text-outline">
            Parking proprietaire
            <select
              v-model="selectedParkingId"
              class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
            >
              <option value="">Selectionner un parking</option>
              <option v-for="parking in ownerParkings" :key="parking.id" :value="parking.id">
                {{ parking.name }} ({{ parking.id }})
              </option>
            </select>
          </label>

          <p v-if="loading" class="mt-3 rounded-lg bg-surface-container-low px-3 py-2 text-sm font-semibold text-on-surface-variant">
            Chargement de vos parkings...
          </p>
          <p v-if="loadError" class="mt-3 rounded-lg bg-red-100 px-3 py-2 text-sm font-semibold text-red-700">
            {{ loadError }}
          </p>

          <div v-if="selectedParking" class="mt-4 grid gap-2 text-xs text-on-surface-variant sm:grid-cols-2">
            <p><span class="font-semibold text-on-surface">Proprietaire:</span> {{ selectedParking.ownerAccount?.name || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Email:</span> {{ selectedParking.ownerAccount?.email || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Jours:</span> {{ selectedWorkingDaysLabel }}</p>
            <p><span class="font-semibold text-on-surface">Heures:</span> {{ selectedParking.businessSettings.openingTime }} - {{ selectedParking.businessSettings.closingTime }}</p>
            <p><span class="font-semibold text-on-surface">Tarif horaire:</span> {{ selectedParking.businessSettings.pricing.hourlyRateDzd }} DZD</p>
            <p><span class="font-semibold text-on-surface">Tarif journalier:</span> {{ selectedParking.businessSettings.pricing.dailyRateDzd }} DZD</p>
            <p class="sm:col-span-2"><span class="font-semibold text-on-surface">Tarif mensuel:</span> {{ selectedMonthlyRateLabel }}</p>
          </div>
        </article>

        <article class="surface-card p-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 class="font-headline text-lg font-bold text-on-surface">Carte interieure (edition)</h3>
              <p class="mt-1 text-sm text-on-surface-variant">
                Modifiez la grille, ajoutez des places, puis sauvegardez votre carte.
              </p>
            </div>
            <button
              type="button"
              class="rounded-lg bg-primary px-3 py-2 text-xs font-semibold text-white hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="savingLayout || !selectedParking"
              @click="persistSelectedParkingLayout({ successMessage: 'Carte enregistree.', errorPrefix: 'Enregistrement impossible' })"
            >
              {{ savingLayout ? 'Sauvegarde...' : 'Sauvegarder la carte' }}
            </button>
          </div>

          <p v-if="gridError" class="mt-3 rounded-lg bg-red-100 px-3 py-2 text-sm font-semibold text-red-700">
            {{ gridError }}
          </p>
          <p v-if="gridSuccess" class="mt-3 rounded-lg bg-emerald-100 px-3 py-2 text-sm font-semibold text-emerald-700">
            {{ gridSuccess }}
          </p>

          <div class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-6">
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Lignes
              <input
                v-model.number="gridConfigForm.rows"
                type="number"
                min="1"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Colonnes
              <input
                v-model.number="gridConfigForm.cols"
                type="number"
                min="1"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Etage
              <input
                v-model.trim="gridConfigForm.floor"
                type="text"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Zone
              <input
                v-model.trim="gridConfigForm.zone"
                type="text"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Voies lignes
              <input
                v-model.trim="gridConfigForm.laneRows"
                type="text"
                placeholder="2, 4"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Voies colonnes
              <input
                v-model.trim="gridConfigForm.laneCols"
                type="text"
                placeholder="3"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
          </div>

          <div class="mt-3 flex flex-wrap items-center gap-2">
            <button
              type="button"
              class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold text-on-surface hover:bg-surface-container-high"
              :disabled="savingLayout || !selectedParking"
              @click="applyGridConfig"
            >
              Appliquer la grille
            </button>
            <p class="text-xs text-on-surface-variant">Cliquez une case vide pour ajouter une place.</p>
          </div>

          <div class="mt-4 grid gap-3 md:grid-cols-2">
            <div class="rounded-xl bg-surface-container-low p-3">
              <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Nouvelle place</p>
              <div class="mt-2 grid gap-2 sm:grid-cols-2">
                <input
                  v-model.trim="spotForm.label"
                  type="text"
                  placeholder="Code (auto si vide)"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <select
                  v-model="spotForm.type"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  <option v-for="option in spotTypeOptions" :key="option" :value="option">
                    {{ typeLabelMap[option] || option }}
                  </option>
                </select>
                <select
                  v-model="spotForm.state"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  <option v-for="option in spotStateOptions" :key="option" :value="option">
                    {{ stateLabelMap[option] || option }}
                  </option>
                </select>
                <input
                  v-model.trim="spotForm.arduinoId"
                  type="text"
                  placeholder="Arduino ID"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model.trim="spotForm.channel"
                  type="text"
                  placeholder="Canal"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model.trim="spotForm.topic"
                  type="text"
                  placeholder="Topic"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
              </div>
            </div>

            <div class="rounded-xl bg-surface-container-low p-3">
              <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Place selectionnee</p>
              <div v-if="selectedSpot" class="mt-2 grid gap-2 sm:grid-cols-2">
                <input
                  v-model.trim="selectedSpotForm.label"
                  type="text"
                  placeholder="Code"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <select
                  v-model="selectedSpotForm.type"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  <option v-for="option in spotTypeOptions" :key="option" :value="option">
                    {{ typeLabelMap[option] || option }}
                  </option>
                </select>
                <select
                  v-model="selectedSpotForm.state"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  <option v-for="option in spotStateOptions" :key="option" :value="option">
                    {{ stateLabelMap[option] || option }}
                  </option>
                </select>
                <input
                  v-model.trim="selectedSpotForm.arduinoId"
                  type="text"
                  placeholder="Arduino ID"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model.trim="selectedSpotForm.channel"
                  type="text"
                  placeholder="Canal"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model.trim="selectedSpotForm.topic"
                  type="text"
                  placeholder="Topic"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <div class="flex flex-wrap items-center gap-2 sm:col-span-2">
                  <button
                    type="button"
                    class="rounded-lg bg-primary px-3 py-2 text-xs font-semibold text-white hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-60"
                    :disabled="savingLayout"
                    @click="saveSelectedSpot"
                  >
                    Enregistrer la place
                  </button>
                  <button
                    type="button"
                    class="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-100 disabled:cursor-not-allowed disabled:opacity-60"
                    :disabled="savingLayout"
                    @click="removeSelectedSpot"
                  >
                    Supprimer
                  </button>
                </div>
              </div>
              <p v-else class="mt-2 text-xs text-on-surface-variant">Selectionnez une place pour la modifier.</p>
            </div>
          </div>

          <div class="mt-4 grid grid-cols-2 gap-2 text-xs font-semibold">
            <span class="rounded-lg bg-surface-container px-2 py-1 text-outline">— Voie horiz</span>
            <span class="rounded-lg bg-primary/10 px-2 py-1 text-primary font-bold">✕ Croisement</span>
          </div>

          <div class="mt-4 overflow-x-auto">
            <div
              class="grid min-w-[460px] gap-1"
              :style="{ gridTemplateColumns: `repeat(${selectedGrid?.cols ?? 1}, minmax(0, 1fr))` }"
            >
              <template v-for="row in gridRows" :key="`row-${row}`">
                <button
                  v-for="col in gridCols"
                  :key="`cell-${row}-${col}`"
                  type="button"
                  class="flex h-16 flex-col items-center justify-center rounded-lg border text-xs font-bold transition"
                  :class="[cellClass(row, col), selectedSpot?.row === row && selectedSpot?.col === col ? 'ring-2 ring-primary/60' : '']"
                  @click="onGridCellClick(row, col)"
                  @contextmenu.prevent="onGridCellRightClick(row, col)"
                >
                  <template v-if="isLaneCell(row, col)">
                    <template v-if="getLaneType(row, col) === 'intersection'">
                      ✕
                    </template>
                    <template v-else-if="getLaneType(row, col) === 'horizontal'">
                      —
                    </template>
                    <template v-else-if="getLaneType(row, col) === 'vertical'">
                      &#124;
                    </template>
                  </template>
                  <template v-else-if="spotAt(row, col)">
                    <span>{{ spotAt(row, col).label }}</span>
                    <span class="text-[10px]">{{ typeLabelMap[spotAt(row, col).type] }}</span>
                  </template>
                  <template v-else>
                    +
                  </template>
                </button>
              </template>
            </div>
          </div>

          <div v-if="selectedSpot" class="mt-4 rounded-xl bg-surface-container-low p-4">
            <p class="text-sm font-bold text-on-surface">Details place selectionnee</p>
            <div class="mt-2 grid gap-2 text-xs text-on-surface-variant sm:grid-cols-2">
              <p><span class="font-semibold text-on-surface">Code:</span> {{ selectedSpot.label }}</p>
              <p><span class="font-semibold text-on-surface">Cellule:</span> L{{ selectedSpot.row + 1 }} / C{{ selectedSpot.col + 1 }}</p>
              <p><span class="font-semibold text-on-surface">Type:</span> {{ typeLabelMap[selectedSpot.type] || selectedSpot.type }}</p>
              <p><span class="font-semibold text-on-surface">Etat:</span> {{ stateLabelMap[selectedSpot.state] || selectedSpot.state }}</p>
              <p><span class="font-semibold text-on-surface">Arduino:</span> {{ selectedSpot.sensor?.arduinoId || '-' }}</p>
              <p><span class="font-semibold text-on-surface">Canal:</span> {{ selectedSpot.sensor?.channel || '-' }}</p>
              <p class="sm:col-span-2"><span class="font-semibold text-on-surface">Topic:</span> {{ selectedSpot.sensor?.topic || '-' }}</p>
            </div>
          </div>
        </article>
      </div>
    </div>

    <p v-if="!loading && !ownerParkings.length" class="rounded-lg bg-surface-container-low px-3 py-2 text-sm font-semibold text-on-surface-variant">
      Aucun parking disponible pour ce compte proprietaire.
    </p>
  </section>
</template>
