<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
import { mapConfig } from '@/config/map'
import { deleteAdminParking, listAdminParkings, upsertAdminParkingLayout } from '@/services/admin/parkingApi'
import { useAuthStore } from '@/stores/auth'
import { useParkingsStore } from '@/stores/parkings'
import { useUsersStore } from '@/stores/users'

L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
})

const apiEndpoint = import.meta.env.VITE_PARKING_LAYOUT_API_URL ?? '/api/admin/parkings/layout'

const mapContainer = ref(null)
const mapInstance = ref(null)
const markersLayer = ref(null)
const pendingSelectionMarker = ref(null)
const parkingImageInputRef = ref(null)

const mapError = ref('')
const addError = ref('')
const addSuccess = ref('')
const gridError = ref('')
const gridSuccess = ref('')
const apiError = ref('')
const apiSuccess = ref('')
const selectedPosition = ref(null)

const selectedParkingId = ref('')
const selectedSpotId = ref('')
const creatingParking = ref(false)
const deletingParking = ref(false)
const sendingToApi = ref(false)
const persistingLayout = ref(false)
const showApiPanel = ref(false)
const isCreatingNewParking = ref(false)

const route = useRoute()

const parkingsStore = useParkingsStore()
const usersStore = useUsersStore()
const authStore = useAuthStore()
const { parkings, isAddPanelOpen } = storeToRefs(parkingsStore)

const spotTypeOptions = parkingsStore.validSpotTypes
const spotStateOptions = parkingsStore.validSpotStates

const typeLabelMap = {
  STANDARD: 'Standard',
  PMR: 'PMR',
  VIP: 'VIP',
}

const stateLabelMap = {
  AVAILABLE: 'Disponible',
  OCCUPIED: 'Occupee',
  RESERVED: 'Reservee',
  OFFLINE: 'Hors service',
}

const equipmentOptions = [
  'GPL Autorise',
  'Securite 24/7',
  'Videosurveillance',
  'Accessible Handi',
  'Borne Elec',
]

const tagOptions = [
  'Proche Tram',
  'Proche Metro',
  'Proche Bus',
  'Centre Ville',
  'Couvert',
]

const vehicleTypeOptions = ['car', 'moto', 'truck']

const maxParkingImageSizeBytes = 5 * 1024 * 1024

const parkingForm = reactive({
  name: '',
  address: '',
  ownerName: '',
  ownerEmail: '',
  ownerPhone: '',
  ownerPassword: '',
  capacity: 120,
  rows: 6,
  cols: 8,
  floor: 'B1',
  zone: 'Zone A',
  laneRows: '2',
  walkingTime: '5 mins de marche',
  rating: 4.2,
  pricePerHour: 100,
  availableSpots: 120,
  lastUpdate: '',
  isOpen24h: true,
  equipments: ['Securite 24/7', 'Videosurveillance'],
  tags: ['Proche Tram'],
  imageUrl: '',
  imageFileName: '',
  maxVehicleHeightMeters: 2,
  supportedVehicleTypes: ['car', 'moto'],
  nearTelepherique: false,
})

const gridConfigForm = reactive({
  rows: 6,
  cols: 8,
  floor: 'B1',
  zone: 'Zone A',
  laneRows: '2',
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

const toNumber = (value, fallback) => {
  const parsed = Number(value)

  if (Number.isFinite(parsed)) {
    return parsed
  }

  return fallback
}

const isValidEmail = (value) => {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value ?? '').trim())
}

const clamp = (value, min, max) => {
  if (value < min) {
    return min
  }

  if (value > max) {
    return max
  }

  return value
}

const parseLaneRowsInput = (value, rowsCount) => {
  const tokens = String(value ?? '')
    .split(/[\s,;]+/)
    .map((item) => item.trim())
    .filter(Boolean)

  const uniq = new Set()

  tokens.forEach((token) => {
    const parsed = Math.round(toNumber(token, -1))
    if (parsed >= 0 && parsed < rowsCount) {
      uniq.add(parsed)
    }
  })

  return Array.from(uniq).sort((a, b) => a - b)
}

const normalizeStringArray = (value, { lowercase = false } = {}) => {
  if (!Array.isArray(value)) {
    return []
  }

  const normalized = value
    .map((item) => String(item ?? '').trim())
    .filter(Boolean)
    .map((item) => (lowercase ? item.toLowerCase() : item))

  return Array.from(new Set(normalized))
}

const getImageFileNameFromUrl = (value) => {
  const raw = String(value ?? '').trim()
  if (!raw) {
    return ''
  }

  if (raw.startsWith('data:image/')) {
    return 'image-importee'
  }

  try {
    const url = new URL(raw)
    const pieces = url.pathname.split('/').filter(Boolean)
    const filename = pieces.length ? decodeURIComponent(pieces[pieces.length - 1]) : ''
    return filename || 'image-distance'
  } catch {
    const pieces = raw.split('/').filter(Boolean)
    return pieces.length ? pieces[pieces.length - 1] : 'image-distance'
  }
}

const onParkingImageSelected = (event) => {
  addError.value = ''

  const input = event?.target
  const file = input?.files?.[0]

  if (!file) {
    return
  }

  if (!String(file.type ?? '').startsWith('image/')) {
    addError.value = 'Selectionnez un fichier image valide (png, jpg, webp...).'
    if (input) {
      input.value = ''
    }
    return
  }

  if (file.size > maxParkingImageSizeBytes) {
    addError.value = 'Image trop grande. Taille maximale: 5 MB.'
    if (input) {
      input.value = ''
    }
    return
  }

  const reader = new FileReader()

  reader.onload = () => {
    parkingForm.imageUrl = String(reader.result ?? '')
    parkingForm.imageFileName = file.name
  }

  reader.onerror = () => {
    addError.value = 'Impossible de lire l image selectionnee.'
  }

  reader.readAsDataURL(file)
}

const clearParkingImageSelection = () => {
  parkingForm.imageUrl = ''
  parkingForm.imageFileName = ''

  if (parkingImageInputRef.value) {
    parkingImageInputRef.value.value = ''
  }
}

const clearParkingForm = () => {
  parkingForm.name = ''
  parkingForm.address = ''
  parkingForm.ownerName = ''
  parkingForm.ownerEmail = ''
  parkingForm.ownerPhone = ''
  parkingForm.ownerPassword = ''
  parkingForm.capacity = 120
  parkingForm.rows = 6
  parkingForm.cols = 8
  parkingForm.floor = 'B1'
  parkingForm.zone = 'Zone A'
  parkingForm.laneRows = '2'
  parkingForm.walkingTime = '5 mins de marche'
  parkingForm.rating = 4.2
  parkingForm.pricePerHour = 100
  parkingForm.availableSpots = 120
  parkingForm.lastUpdate = ''
  parkingForm.isOpen24h = true
  parkingForm.equipments = ['Securite 24/7', 'Videosurveillance']
  parkingForm.tags = ['Proche Tram']
  parkingForm.imageUrl = ''
  parkingForm.imageFileName = ''
  parkingForm.maxVehicleHeightMeters = 2
  parkingForm.supportedVehicleTypes = ['car', 'moto']
  parkingForm.nearTelepherique = false
}

const fillParkingFormFromSelected = (parking) => {
  if (!parking) {
    return
  }

  parkingForm.name = parking.name ?? ''
  parkingForm.address = parking.address ?? ''
  parkingForm.ownerName = parking.owner?.name ?? ''
  parkingForm.ownerEmail = parking.owner?.email ?? ''
  parkingForm.ownerPhone = parking.owner?.phone ?? ''
  parkingForm.ownerPassword = ''
  parkingForm.capacity = Math.max(1, Number(parking.capacity ?? 1))
  parkingForm.rows = Math.max(2, Number(parking.indoorGrid?.rows ?? 6))
  parkingForm.cols = Math.max(2, Number(parking.indoorGrid?.cols ?? 8))
  parkingForm.floor = parking.indoorGrid?.floor ?? 'B1'
  parkingForm.zone = parking.indoorGrid?.zone ?? 'Zone A'
  parkingForm.laneRows = Array.isArray(parking.indoorGrid?.laneRows)
    ? parking.indoorGrid.laneRows.join(',')
    : '2'
  parkingForm.walkingTime = parking.walkingTime ?? ''
  parkingForm.rating = Number(parking.rating ?? 0)
  parkingForm.pricePerHour = Number(parking.pricePerHour ?? 0)
  parkingForm.availableSpots = Math.max(0, Number(parking.availableSpots ?? parking.capacity ?? 0))
  parkingForm.lastUpdate = parking.lastUpdate ?? ''
  parkingForm.isOpen24h = Boolean(parking.isOpen24h)
  parkingForm.equipments = normalizeStringArray(parking.equipments)
  parkingForm.tags = normalizeStringArray(parking.tags)
  parkingForm.imageUrl = parking.imageUrl ?? ''
  parkingForm.imageFileName = getImageFileNameFromUrl(parking.imageUrl)
  parkingForm.maxVehicleHeightMeters = parking.maxVehicleHeightMeters ?? ''
  parkingForm.supportedVehicleTypes = normalizeStringArray(parking.supportedVehicleTypes, { lowercase: true })
  parkingForm.nearTelepherique = Boolean(parking.nearTelepherique)
}

const activateNewParkingMode = () => {
  isCreatingNewParking.value = true
  selectedParkingId.value = ''
  selectedSpotId.value = ''
  clearParkingForm()
  selectedPosition.value = null
  clearSelectionMarker()
  addError.value = ''
  addSuccess.value = ''
}

const clearSelectionMarker = () => {
  if (pendingSelectionMarker.value && mapInstance.value) {
    mapInstance.value.removeLayer(pendingSelectionMarker.value)
    pendingSelectionMarker.value = null
  }
}

const updateSelectionMarker = () => {
  clearSelectionMarker()

  if (!mapInstance.value || !selectedPosition.value || !isAddPanelOpen.value) {
    return
  }

  pendingSelectionMarker.value = L.circleMarker(selectedPosition.value, {
    radius: 8,
    color: '#004ac6',
    fillColor: '#004ac6',
    fillOpacity: 0.85,
    weight: 2,
  })
    .addTo(mapInstance.value)
    .bindTooltip('Position selectionnee', { permanent: false })
}

const parkingStats = (parking) => {
  const spots = parking.indoorGrid?.spots ?? []
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

const popupNode = (parking) => {
  const container = document.createElement('div')
  const stats = parkingStats(parking)

  const title = document.createElement('strong')
  title.textContent = parking.name
  container.appendChild(title)

  const address = document.createElement('div')
  address.textContent = parking.address
  address.style.fontSize = '12px'
  container.appendChild(address)

  const meta = document.createElement('div')
  meta.textContent = `Places: ${stats.total} | Occupation: ${stats.occupancyPercent}%`
  meta.style.fontSize = '12px'
  container.appendChild(meta)

  const ownerMeta = document.createElement('div')
  ownerMeta.textContent = `Owner: ${parking.owner?.name || '-'} | Tel: ${parking.owner?.phone || '-'}`
  ownerMeta.style.fontSize = '12px'
  container.appendChild(ownerMeta)

  const gridMeta = document.createElement('div')
  gridMeta.textContent = `Etage: ${parking.indoorGrid?.floor || '-'} | Zone: ${parking.indoorGrid?.zone || '-'}`
  gridMeta.style.fontSize = '12px'
  container.appendChild(gridMeta)

  return container
}

const renderParkingMarkers = () => {
  if (!markersLayer.value) {
    return
  }

  markersLayer.value.clearLayers()

  parkings.value.forEach((parking) => {
    const marker = L.marker(parking.position, {
      icon: parkingMarkerIcon(parking),
    })

    marker.on('click', () => {
      selectedParkingId.value = parking.id
    })

    marker.bindTooltip(parking.name, {
      permanent: true,
      direction: 'top',
      offset: [0, -20],
      opacity: 0.9,
    })

    marker.bindPopup(popupNode(parking))
    markersLayer.value.addLayer(marker)
  })
}

const initializeMap = () => {
  if (!mapContainer.value) {
    return null
  }

  const map = L.map(mapContainer.value, {
    minZoom: mapConfig.minZoom,
    zoomControl: true,
  }).setView(mapConfig.center, mapConfig.zoom)

  L.tileLayer(mapConfig.tileUrl, {
    attribution: mapConfig.attribution,
    maxZoom: mapConfig.maxZoom,
  }).addTo(map)

  markersLayer.value = L.layerGroup().addTo(map)
  renderParkingMarkers()

  map.on('click', (event) => {
    if (!isAddPanelOpen.value) {
      return
    }

    selectedPosition.value = [
      Number(event.latlng.lat.toFixed(6)),
      Number(event.latlng.lng.toFixed(6)),
    ]
    addError.value = ''
    addSuccess.value = ''
    updateSelectionMarker()
  })

  return map
}

const selectedParking = computed(() => {
  return parkings.value.find((parking) => parking.id === selectedParkingId.value) ?? null
})

const selectedGrid = computed(() => {
  return selectedParking.value?.indoorGrid ?? null
})

const selectedSpots = computed(() => {
  return selectedGrid.value?.spots ?? []
})

const selectedSpot = computed(() => {
  return selectedSpots.value.find((spot) => spot.id === selectedSpotId.value) ?? null
})

const selectedPositionLabel = computed(() => {
  if (!selectedPosition.value) {
    return 'Aucune position selectionnee'
  }

  const [lat, lng] = selectedPosition.value
  return `${lat.toFixed(6)}, ${lng.toFixed(6)}`
})

const selectedParkingPositionLabel = computed(() => {
  if (!selectedParking.value?.position || selectedParking.value.position.length !== 2) {
    return '-'
  }

  const [lat, lng] = selectedParking.value.position
  return `${Number(lat).toFixed(6)}, ${Number(lng).toFixed(6)}`
})

const selectedParkingOwnerLabel = computed(() => {
  const ownerName = String(selectedParking.value?.owner?.name ?? '').trim()
  const ownerEmail = String(selectedParking.value?.owner?.email ?? '').trim()

  if (ownerName && ownerEmail) {
    return `${ownerName} (${ownerEmail})`
  }

  return ownerName || ownerEmail || 'Non renseigne'
})

const selectedParkingEquipmentsLabel = computed(() => {
  const values = Array.isArray(selectedParking.value?.equipments)
    ? selectedParking.value.equipments
    : []

  return values.length ? values.join(', ') : '-'
})

const selectedParkingTagsLabel = computed(() => {
  const values = Array.isArray(selectedParking.value?.tags)
    ? selectedParking.value.tags
    : []

  return values.length ? values.join(', ') : '-'
})

const selectedParkingVehicleTypesLabel = computed(() => {
  const values = Array.isArray(selectedParking.value?.supportedVehicleTypes)
    ? selectedParking.value.supportedVehicleTypes
    : []

  return values.length ? values.join(', ') : '-'
})

const gridRows = computed(() => {
  const rows = selectedGrid.value?.rows ?? 0
  return Array.from({ length: rows }, (_, index) => index)
})

const gridCols = computed(() => {
  const cols = selectedGrid.value?.cols ?? 0
  return Array.from({ length: cols }, (_, index) => index)
})

const laneRowSet = computed(() => {
  return new Set(selectedGrid.value?.laneRows ?? [])
})

const spotMapByCell = computed(() => {
  const map = new Map()
  selectedSpots.value.forEach((spot) => {
    map.set(`${spot.row}-${spot.col}`, spot)
  })
  return map
})

const selectedParkingStats = computed(() => {
  if (!selectedParking.value) {
    return {
      total: 0,
      occupied: 0,
      available: 0,
      reserved: 0,
      offline: 0,
      occupancyPercent: 0,
    }
  }

  return parkingStats(selectedParking.value)
})

const payloadForApi = computed(() => {
  if (!selectedParkingId.value) {
    return null
  }

  return parkingsStore.parkingPayload(selectedParkingId.value)
})

const payloadPreview = computed(() => {
  if (!payloadForApi.value) {
    return '{}'
  }

  return JSON.stringify(payloadForApi.value, null, 2)
})

const syncGridConfigFromParking = () => {
  if (!selectedGrid.value) {
    gridConfigForm.rows = 6
    gridConfigForm.cols = 8
    gridConfigForm.floor = 'B1'
    gridConfigForm.zone = 'Zone A'
    gridConfigForm.laneRows = '2'
    return
  }

  gridConfigForm.rows = selectedGrid.value.rows
  gridConfigForm.cols = selectedGrid.value.cols
  gridConfigForm.floor = selectedGrid.value.floor
  gridConfigForm.zone = selectedGrid.value.zone
  gridConfigForm.laneRows = (selectedGrid.value.laneRows ?? []).join(',')
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

const startAddMode = () => {
  parkingsStore.openAddPanel()
  activateNewParkingMode()
}

const cancelAddMode = () => {
  isCreatingNewParking.value = false
  parkingsStore.closeAddPanel()
  selectedPosition.value = null
  addError.value = ''
  addSuccess.value = ''
  clearSelectionMarker()

  if (selectedParking.value) {
    fillParkingFormFromSelected(selectedParking.value)
  }
}

const sendParkingPayloadToApi = async (payload) => {
  return upsertAdminParkingLayout({
    payload,
    authHeaders: authStore.authHeaders,
  })
}

const deleteParkingFromApi = async (parkingId) => {
  return deleteAdminParking({
    parkingId,
    authHeaders: authStore.authHeaders,
  })
}

const loadParkingsFromApi = async () => {
  if (!authStore.isAuthenticated || authStore.role !== 'admin') {
    return
  }

  const result = await listAdminParkings({
    authHeaders: authStore.authHeaders,
  })

  if (!result.ok) {
    mapError.value = result.message
    return
  }

  mapError.value = ''
  parkingsStore.replaceParkingsFromApi(result.data)
}

const persistSelectedParkingLayout = async ({
  successMessage = '',
  errorPrefix = 'Sauvegarde carte interieure echouee',
  rollbackOnError = true,
} = {}) => {
  if (persistingLayout.value) {
    return false
  }

  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return false
  }

  const payload = parkingsStore.parkingPayload(selectedParking.value.id)
  if (!payload) {
    gridError.value = 'Payload parking invalide.'
    return false
  }

  persistingLayout.value = true

  try {
    const result = await sendParkingPayloadToApi(payload)

    if (!result.ok) {
      gridError.value = `${errorPrefix}: ${result.message}`

      if (rollbackOnError) {
        await loadParkingsFromApi()
      }

      return false
    }

    const persistedParking = parkingsStore.upsertParkingFromApiPayload(result.data)
    if (persistedParking) {
      selectedParkingId.value = persistedParking.id
    }

    if (selectedSpotId.value) {
      const currentSpots = persistedParking?.indoorGrid?.spots ?? selectedSpots.value
      const stillExists = currentSpots.some((spot) => spot.id === selectedSpotId.value)

      if (!stillExists) {
        selectedSpotId.value = ''
      }
    }

    if (successMessage) {
      gridSuccess.value = successMessage
    }

    return true
  } finally {
    persistingLayout.value = false
  }
}

const saveParking = async () => {
  addError.value = ''
  addSuccess.value = ''

  if (creatingParking.value) {
    return
  }

  if (!isAddPanelOpen.value) {
    addError.value = 'Activez le mode ajout avant de sauvegarder.'
    return
  }

  if (!selectedPosition.value) {
    addError.value = 'Selectionnez un emplacement sur la map.'
    return
  }

  const name = parkingForm.name.trim()
  const address = parkingForm.address.trim()
  const ownerName = parkingForm.ownerName.trim()
  const ownerEmail = parkingForm.ownerEmail.trim().toLowerCase()
  const ownerPhone = parkingForm.ownerPhone.trim()
  const ownerPassword = String(parkingForm.ownerPassword ?? '').trim()

  if (!name || !address) {
    addError.value = 'Le nom et l adresse sont obligatoires.'
    return
  }

  if (!ownerName || !ownerEmail || !ownerPhone || !ownerPassword) {
    addError.value = 'Le compte owner est obligatoire (nom, email, telephone, mot de passe).'
    return
  }

  if (!isValidEmail(ownerEmail)) {
    addError.value = 'Email owner invalide.'
    return
  }

  if (ownerPassword.length < 8) {
    addError.value = 'Mot de passe owner trop court (min 8 caracteres).'
    return
  }

  if (usersStore.hasUserEmail(ownerEmail) || authStore.hasAccount(ownerEmail, 'owner')) {
    addError.value = 'Un compte owner existe deja avec cet email.'
    return
  }

  creatingParking.value = true

  try {
    const ownerAuthResult = await authStore.registerOwnerAccount({
      name: ownerName,
      email: ownerEmail,
      phone: ownerPhone,
      password: ownerPassword,
    })

    if (!ownerAuthResult.ok) {
      addError.value = ownerAuthResult.message
      return
    }

    const capacity = Math.max(1, Math.round(toNumber(parkingForm.capacity, 1)))
    const rows = Math.max(2, Math.round(toNumber(parkingForm.rows, 6)))
    const cols = Math.max(2, Math.round(toNumber(parkingForm.cols, 8)))
    const laneRows = parseLaneRowsInput(parkingForm.laneRows, rows)
    const availableSpots = clamp(Math.round(toNumber(parkingForm.availableSpots, capacity)), 0, capacity)
    const rating = clamp(toNumber(parkingForm.rating, 0), 0, 5)
    const pricePerHour = Math.max(0, toNumber(parkingForm.pricePerHour, 0))
    const walkingTime = parkingForm.walkingTime.trim()
    const lastUpdate = String(parkingForm.lastUpdate ?? '').trim() || new Date().toISOString()
    const equipments = normalizeStringArray(parkingForm.equipments)
    const tags = normalizeStringArray(parkingForm.tags)
    const imageUrl = String(parkingForm.imageUrl ?? '').trim()
    const maxVehicleHeightRaw = toNumber(parkingForm.maxVehicleHeightMeters, NaN)
    const maxVehicleHeightMeters = Number.isFinite(maxVehicleHeightRaw)
      ? Math.max(0, maxVehicleHeightRaw)
      : null
    const supportedVehicleTypes = normalizeStringArray(parkingForm.supportedVehicleTypes, { lowercase: true })
    const isOpen24h = Boolean(parkingForm.isOpen24h)
    const nearTelepherique = Boolean(parkingForm.nearTelepherique)

    const created = parkingsStore.addParking({
      name,
      address,
      owner: {
        name: ownerName,
        email: ownerEmail,
        phone: ownerPhone,
      },
      position: selectedPosition.value,
      capacity,
      rows,
      cols,
      floor: parkingForm.floor,
      zone: parkingForm.zone,
      laneRows,
      walkingTime,
      rating,
      pricePerHour,
      availableSpots,
      lastUpdate,
      isOpen24h,
      equipments,
      tags,
      imageUrl,
      maxVehicleHeightMeters,
      supportedVehicleTypes,
      nearTelepherique,
    })

    const createdOwnerAccount = ownerAuthResult.owner && typeof ownerAuthResult.owner === 'object'
      ? ownerAuthResult.owner
      : null

    const ownerUserResult = usersStore.addOwnerAccount({
      name: ownerName,
      email: ownerEmail,
      phone: ownerPhone,
      parkingName: created.name,
      parkingId: created.id,
      ownerId: createdOwnerAccount?._id ?? createdOwnerAccount?.id,
      accountStatus: createdOwnerAccount?.account_status,
      subscriptionStatus: createdOwnerAccount?.subscription_status,
    })

    if (!ownerUserResult.ok) {
      addError.value = `${created.name} enregistre, mais la fiche utilisateur owner n a pas ete ajoutee: ${ownerUserResult.message}`
      selectedParkingId.value = created.id
      return
    }

    const payload = parkingsStore.parkingPayload(created.id)
    if (!payload) {
      parkingsStore.removeParking(created.id)
      usersStore.removeUserByEmail(ownerEmail)
      addError.value = 'Parking local invalide, enregistrement backend annule.'
      return
    }

    const persisted = await sendParkingPayloadToApi(payload)
    if (!persisted.ok) {
      parkingsStore.removeParking(created.id)
      usersStore.removeUserByEmail(ownerEmail)
      addError.value = `Compte owner cree, mais enregistrement parking backend echoue: ${persisted.message}`
      return
    }

    const persistedParking = parkingsStore.upsertParkingFromApiPayload(persisted.data)
    if (persistedParking) {
      selectedParkingId.value = persistedParking.id
    }

    addSuccess.value = `${created.name} enregistre en base avec le compte owner ${ownerEmail}.`
    selectedParkingId.value = persistedParking?.id ?? created.id
    isCreatingNewParking.value = false
    clearParkingForm()
    selectedPosition.value = null
    clearSelectionMarker()
    parkingsStore.closeAddPanel()

    if (mapInstance.value) {
      mapInstance.value.flyTo(created.position, Math.max(mapConfig.zoom, 15))
    }
  } finally {
    creatingParking.value = false
  }
}

const deleteSelectedParking = async () => {
  gridError.value = ''
  gridSuccess.value = ''
  addError.value = ''
  addSuccess.value = ''

  if (deletingParking.value) {
    return
  }

  const parking = selectedParking.value

  if (!parking) {
    gridError.value = 'Selectionnez un parking a supprimer.'
    return
  }

  const confirmed = window.confirm(`Supprimer le parking ${parking.name} (${parking.id}) ?`)
  if (!confirmed) {
    return
  }

  deletingParking.value = true

  try {
    const result = await deleteParkingFromApi(parking.id)

    if (!result.ok) {
      gridError.value = result.message
      return
    }

    parkingsStore.removeParking(parking.id)
    selectedSpotId.value = ''
    isCreatingNewParking.value = false

    if (selectedParkingId.value === parking.id) {
      selectedParkingId.value = ''
    }

    gridSuccess.value = `Parking ${parking.name} supprime avec succes.`
  } finally {
    deletingParking.value = false
  }
}

const applyGridConfig = async () => {
  gridError.value = ''
  gridSuccess.value = ''

  if (persistingLayout.value) {
    gridError.value = 'Sauvegarde en cours, veuillez patienter.'
    return
  }

  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return
  }

  const rows = Math.max(2, Math.round(toNumber(gridConfigForm.rows, 6)))
  const cols = Math.max(2, Math.round(toNumber(gridConfigForm.cols, 8)))
  const laneRows = parseLaneRowsInput(gridConfigForm.laneRows, rows)

  const updated = parkingsStore.setIndoorGridConfig(selectedParking.value.id, {
    floor: gridConfigForm.floor,
    zone: gridConfigForm.zone,
    rows,
    cols,
    laneRows,
  })

  if (!updated) {
    gridError.value = 'Mise a jour de la grille impossible.'
    return
  }

  if (selectedSpot.value) {
    const exists = updated.indoorGrid.spots.some((spot) => spot.id === selectedSpot.value.id)
    if (!exists) {
      selectedSpotId.value = ''
    }
  }

  await persistSelectedParkingLayout({
    successMessage: 'Configuration de grille appliquee et enregistree.',
    errorPrefix: 'Enregistrement de la grille impossible',
  })
}

const cellKey = (row, col) => `${row}-${col}`

const spotAt = (row, col) => {
  return spotMapByCell.value.get(cellKey(row, col)) ?? null
}

const isLaneCell = (row) => {
  return laneRowSet.value.has(row)
}

const cellClass = (row, col) => {
  if (isLaneCell(row)) {
    return 'cursor-not-allowed border-dashed border-outline-variant bg-surface-container text-outline'
  }

  const spot = spotAt(row, col)
  if (!spot) {
    return 'border-outline-variant bg-surface-container-low text-outline hover:border-primary/50 hover:bg-primary/5'
  }

  if (spot.state === 'OCCUPIED') {
    return 'border-red-300 bg-red-50 text-red-700'
  }

  if (spot.state === 'RESERVED') {
    return 'border-amber-300 bg-amber-50 text-amber-700'
  }

  if (spot.state === 'OFFLINE') {
    return 'border-slate-300 bg-slate-100 text-slate-500'
  }

  return 'border-emerald-300 bg-emerald-50 text-emerald-700'
}

const removeSpotById = (spotId) => {
  gridError.value = ''
  gridSuccess.value = ''

  if (!selectedParking.value || !spotId) {
    gridError.value = 'Selectionnez une place a supprimer.'
    return false
  }

  const removed = parkingsStore.removeGridSpot(selectedParking.value.id, spotId)

  if (!removed) {
    gridError.value = 'Suppression impossible.'
    return false
  }

  if (selectedSpotId.value === spotId) {
    selectedSpotId.value = ''
  }

  return true
}

const onGridCellClick = async (row, col) => {
  gridError.value = ''
  gridSuccess.value = ''

  if (persistingLayout.value) {
    gridError.value = 'Sauvegarde en cours, veuillez patienter.'
    return
  }

  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return
  }

  if (isLaneCell(row)) {
    gridError.value = 'Cette ligne est definie comme voie de circulation.'
    return
  }

  const existing = spotAt(row, col)
  if (existing) {
    selectedSpotId.value = existing.id
    return
  }

  const label = spotForm.label.trim() || generateSpotLabel()
  const duplicate = selectedSpots.value.some((spot) => spot.label.toUpperCase() === label.toUpperCase())

  if (duplicate) {
    gridError.value = 'ID de place deja utilise. Changez le code.'
    return
  }

  const createdSpot = parkingsStore.addGridSpot(selectedParking.value.id, {
    label,
    row,
    col,
    type: spotForm.type,
    state: spotForm.state,
    arduinoId: spotForm.arduinoId.trim(),
    channel: spotForm.channel.trim(),
    topic: spotForm.topic.trim(),
  })

  if (!createdSpot) {
    gridError.value = 'Impossible de creer la place sur cette case.'
    return
  }

  selectedSpotId.value = createdSpot.id

  const saved = await persistSelectedParkingLayout({
    successMessage: `Place ${createdSpot.label} ajoutee et enregistree.`,
    errorPrefix: 'Enregistrement de la nouvelle place impossible',
  })

  if (!saved) {
    return
  }

  spotForm.label = ''
}

const onGridCellRightClick = async (row, col) => {
  gridError.value = ''
  gridSuccess.value = ''

  if (persistingLayout.value) {
    gridError.value = 'Sauvegarde en cours, veuillez patienter.'
    return
  }

  if (!selectedParking.value) {
    gridError.value = 'Selectionnez un parking.'
    return
  }

  if (isLaneCell(row)) {
    return
  }

  const existing = spotAt(row, col)
  if (!existing) {
    return
  }

  const confirmed = window.confirm(`Supprimer la place ${existing.label} ?`)
  if (!confirmed) {
    return
  }

  const removed = removeSpotById(existing.id)
  if (!removed) {
    return
  }

  await persistSelectedParkingLayout({
    successMessage: `Place ${existing.label} supprimee et enregistree.`,
    errorPrefix: 'Enregistrement de la suppression impossible',
  })
}

const saveSelectedSpot = async () => {
  gridError.value = ''
  gridSuccess.value = ''

  if (persistingLayout.value) {
    gridError.value = 'Sauvegarde en cours, veuillez patienter.'
    return
  }

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

  const updated = parkingsStore.updateGridSpot(selectedParking.value.id, selectedSpot.value.id, {
    label,
    type: selectedSpotForm.type,
    state: selectedSpotForm.state,
    sensor: {
      arduinoId: selectedSpotForm.arduinoId.trim(),
      channel: selectedSpotForm.channel.trim(),
      topic: selectedSpotForm.topic.trim(),
    },
    updatedAt: new Date().toISOString(),
  })

  if (!updated) {
    gridError.value = 'Mise a jour de la place impossible.'
    return
  }

  await persistSelectedParkingLayout({
    successMessage: `Place ${updated.label} mise a jour et enregistree.`,
    errorPrefix: 'Enregistrement de la place modifiee impossible',
  })
}

const removeSelectedSpot = async () => {
  if (persistingLayout.value) {
    gridError.value = 'Sauvegarde en cours, veuillez patienter.'
    return
  }

  const spot = selectedSpot.value

  if (!spot) {
    gridError.value = 'Selectionnez une place a supprimer.'
    return
  }

  const removed = removeSpotById(spot.id)
  if (!removed) {
    return
  }

  await persistSelectedParkingLayout({
    successMessage: `Place ${spot.label} supprimee de la grille et enregistree.`,
    errorPrefix: 'Enregistrement de la suppression impossible',
  })
}

const sendLayoutToApi = async () => {
  apiError.value = ''
  apiSuccess.value = ''

  if (!payloadForApi.value) {
    apiError.value = 'Aucun parking selectionne.'
    return
  }

  sendingToApi.value = true

  const result = await sendParkingPayloadToApi(payloadForApi.value)

  if (!result.ok) {
    apiError.value = `Envoi API echoue: ${result.message}`
    sendingToApi.value = false
    return
  }

  const persistedParking = parkingsStore.upsertParkingFromApiPayload(result.data)
  if (persistedParking) {
    selectedParkingId.value = persistedParking.id
  }

  apiSuccess.value = 'JSON envoye a l API avec succes.'
  sendingToApi.value = false
}

const applyParkingSelectionFromRoute = (list) => {
  if (isAddPanelOpen.value || isCreatingNewParking.value) {
    return false
  }

  const routeParkingId = String(route.query.parkingId ?? '').trim()

  if (!routeParkingId) {
    return false
  }

  const exists = list.some((parking) => parking.id === routeParkingId)
  if (!exists) {
    return false
  }

  if (selectedParkingId.value !== routeParkingId) {
    selectedParkingId.value = routeParkingId
  }

  return true
}

watch(
  () => parkings.value,
  (list) => {
    renderParkingMarkers()

    if (!list.length) {
      selectedParkingId.value = ''
      return
    }

    const appliedFromRoute = applyParkingSelectionFromRoute(list)
    if (appliedFromRoute) {
      return
    }

    const exists = list.some((parking) => parking.id === selectedParkingId.value)
    if (!exists) {
      selectedParkingId.value = ''
    }
  },
  { deep: true, immediate: true },
)

watch(
  selectedParkingId,
  () => {
    if (selectedParkingId.value) {
      isCreatingNewParking.value = false
    }

    selectedSpotId.value = ''
    syncGridConfigFromParking()
    gridError.value = ''
    gridSuccess.value = ''
    apiError.value = ''
    apiSuccess.value = ''
  },
  { immediate: true },
)

watch(
  () => route.query.parkingId,
  () => {
    applyParkingSelectionFromRoute(parkings.value)
  },
)

watch(
  selectedParking,
  (parking) => {
    if (!parking || isCreatingNewParking.value) {
      return
    }

    fillParkingFormFromSelected(parking)
  },
  { immediate: true },
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
  { immediate: true },
)

watch(
  isAddPanelOpen,
  (isOpen) => {
    if (isOpen) {
      activateNewParkingMode()
      updateSelectionMarker()
      return
    }

    selectedPosition.value = null
    updateSelectionMarker()
  },
  { immediate: true },
)

onMounted(() => {
  try {
    mapInstance.value = initializeMap()
  } catch (error) {
    mapError.value = 'Impossible de charger la map.'
  }

  loadParkingsFromApi()
})

onBeforeUnmount(() => {
  clearSelectionMarker()

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
        Ajout parking + dessin interactif sur grille + liaison capteurs Arduino.
      </p>
    </div>

    <div class="grid gap-6 xl:grid-cols-[1.35fr,1fr]">
      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Emplacement global du parking</h3>
        <p class="mt-1 text-sm text-on-surface-variant">Cliquez sur la map pour choisir la position du parking.</p>

        <p
          v-if="isAddPanelOpen"
          class="mt-3 rounded-lg bg-primary/10 px-3 py-2 text-xs font-semibold text-primary"
        >
          Mode ajout actif: choisissez une position sur la map.
        </p>

        <div class="mt-5 overflow-hidden rounded-2xl border border-outline-variant/40">
          <div
            v-if="mapError"
            class="flex h-[420px] items-center justify-center bg-surface-container-low text-sm font-semibold text-error"
          >
            {{ mapError }}
          </div>
          <div v-else ref="mapContainer" class="h-[420px] w-full" />
        </div>

        <article v-if="selectedParking" class="mt-4 rounded-2xl bg-surface-container-low p-4">
          <div class="flex items-start justify-between gap-3">
            <div>
              <h4 class="font-headline text-base font-bold text-on-surface">{{ selectedParking.name }}</h4>
              <p class="text-xs text-on-surface-variant">{{ selectedParking.id }}</p>
            </div>
            <span class="rounded-full bg-primary/10 px-2 py-1 text-[11px] font-semibold text-primary">
              {{ selectedParkingStats.occupancyPercent }}% occupe
            </span>
          </div>

          <div class="mt-3 grid gap-2 text-xs text-on-surface-variant sm:grid-cols-2">
            <p><span class="font-semibold text-on-surface">Adresse:</span> {{ selectedParking.address }}</p>
            <p><span class="font-semibold text-on-surface">Owner:</span> {{ selectedParkingOwnerLabel }}</p>
            <p><span class="font-semibold text-on-surface">Telephone:</span> {{ selectedParking.owner?.phone || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Position:</span> {{ selectedParkingPositionLabel }}</p>
            <p><span class="font-semibold text-on-surface">Capacite:</span> {{ selectedParking.capacity }}</p>
            <p><span class="font-semibold text-on-surface">Disponibles:</span> {{ selectedParking.availableSpots ?? '-' }}</p>
            <p><span class="font-semibold text-on-surface">Places dessinees:</span> {{ selectedParkingStats.total }}</p>
            <p><span class="font-semibold text-on-surface">Prix / heure:</span> {{ selectedParking.pricePerHour ?? '-' }} DA</p>
            <p><span class="font-semibold text-on-surface">Note:</span> {{ selectedParking.rating ?? '-' }}</p>
            <p><span class="font-semibold text-on-surface">Etage:</span> {{ selectedParking.indoorGrid?.floor || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Zone:</span> {{ selectedParking.indoorGrid?.zone || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Ouvert 24h:</span> {{ selectedParking.isOpen24h ? 'Oui' : 'Non' }}</p>
            <p><span class="font-semibold text-on-surface">Temps marche:</span> {{ selectedParking.walkingTime || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Types vehicules:</span> {{ selectedParkingVehicleTypesLabel }}</p>
            <p><span class="font-semibold text-on-surface">Hauteur max:</span> {{ selectedParking.maxVehicleHeightMeters ?? '-' }} m</p>
            <p><span class="font-semibold text-on-surface">Telepherique:</span> {{ selectedParking.nearTelepherique ? 'Proche' : 'Non' }}</p>
            <p><span class="font-semibold text-on-surface">Mise a jour:</span> {{ selectedParking.lastUpdate || '-' }}</p>
            <p class="sm:col-span-2"><span class="font-semibold text-on-surface">Equipements:</span> {{ selectedParkingEquipmentsLabel }}</p>
            <p class="sm:col-span-2"><span class="font-semibold text-on-surface">Tags:</span> {{ selectedParkingTagsLabel }}</p>
            <div v-if="selectedParking.imageUrl" class="sm:col-span-2 space-y-2">
              <p><span class="font-semibold text-on-surface">Photo:</span></p>
              <img
                :src="selectedParking.imageUrl"
                :alt="`Photo ${selectedParking.name}`"
                class="h-40 w-full rounded-xl border border-outline-variant/40 object-cover"
              />
            </div>
          </div>
        </article>
      </article>

      <div class="space-y-6">
        <article class="surface-card p-6">
          <div class="flex items-center justify-between gap-3">
            <h3 class="font-headline text-lg font-bold text-on-surface">Ajouter un parking</h3>
            <button
              v-if="!isAddPanelOpen"
              type="button"
              class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold text-on-surface hover:bg-surface-container-high"
              @click="startAddMode"
            >
              Nouveau parking
            </button>
          </div>

          <form class="mt-4 space-y-3" @submit.prevent="saveParking">
            <p class="rounded-lg bg-surface-container-low px-3 py-2 text-xs font-semibold text-on-surface-variant">
              Emplacement selectionne: <span class="text-on-surface">{{ selectedPositionLabel }}</span>
            </p>

            <input
              v-model.trim="parkingForm.name"
              type="text"
              placeholder="Nom du parking"
              class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
            />

            <input
              v-model.trim="parkingForm.address"
              type="text"
              placeholder="Adresse"
              class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
            />

            <div class="space-y-3 rounded-xl bg-surface-container-low p-3">
              <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Compte owner du parking</p>

              <div class="grid grid-cols-1 gap-3 md:grid-cols-4">
                <input
                  v-model.trim="parkingForm.ownerName"
                  type="text"
                  placeholder="Nom owner"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model.trim="parkingForm.ownerEmail"
                  type="email"
                  placeholder="Email owner"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model.trim="parkingForm.ownerPhone"
                  type="text"
                  placeholder="Telephone owner"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <input
                  v-model="parkingForm.ownerPassword"
                  type="password"
                  placeholder="Mot de passe owner"
                  class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
              </div>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <input
                v-model.number="parkingForm.capacity"
                type="number"
                min="1"
                placeholder="Nb places"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.number="parkingForm.rows"
                type="number"
                min="2"
                placeholder="Lignes"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.number="parkingForm.cols"
                type="number"
                min="2"
                placeholder="Colonnes"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>

            <div class="grid grid-cols-3 gap-3">
              <input
                v-model.trim="parkingForm.floor"
                type="text"
                placeholder="Etage"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="parkingForm.zone"
                type="text"
                placeholder="Zone"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="parkingForm.laneRows"
                type="text"
                placeholder="Lignes voie ex: 2,5"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>

            <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
              <input
                v-model.number="parkingForm.pricePerHour"
                type="number"
                min="0"
                step="1"
                placeholder="Prix / heure (DA)"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.number="parkingForm.rating"
                type="number"
                min="0"
                max="5"
                step="0.1"
                placeholder="Note (0-5)"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.number="parkingForm.availableSpots"
                type="number"
                min="0"
                placeholder="Places disponibles"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <select
                v-model="parkingForm.walkingTime"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option value="2 min">Temps de marche: 2 min</option>
                <option value="5 min">Temps de marche: 5 min</option>
                <option value="8 min">Temps de marche: 8 min</option>
                <option value="10 min">Temps de marche: 10 min</option>
                <option value="15 min">Temps de marche: 15 min</option>
              </select>
            </div>

            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <div class="space-y-2 rounded-xl bg-surface-container-low p-3">
                <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Equipements</p>
                <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  <label
                    v-for="option in equipmentOptions"
                    :key="`equipment-${option}`"
                    class="inline-flex items-center gap-2 rounded-lg bg-surface-container px-3 py-2 text-xs text-on-surface"
                  >
                    <input v-model="parkingForm.equipments" type="checkbox" :value="option" class="h-4 w-4" />
                    {{ option }}
                  </label>
                </div>
              </div>

              <div class="space-y-2 rounded-xl bg-surface-container-low p-3">
                <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Tags</p>
                <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  <label
                    v-for="option in tagOptions"
                    :key="`tag-${option}`"
                    class="inline-flex items-center gap-2 rounded-lg bg-surface-container px-3 py-2 text-xs text-on-surface"
                  >
                    <input v-model="parkingForm.tags" type="checkbox" :value="option" class="h-4 w-4" />
                    {{ option }}
                  </label>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <div class="space-y-2 rounded-xl bg-surface-container-low p-3">
                <label class="block text-xs font-semibold uppercase tracking-[0.08em] text-outline">
                  Photo du parking
                  <input
                    ref="parkingImageInputRef"
                    type="file"
                    accept="image/png,image/jpeg,image/webp,image/jpg"
                    class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface file:mr-3 file:rounded-md file:border-0 file:bg-primary/15 file:px-3 file:py-1 file:text-xs file:font-semibold file:text-primary"
                    @change="onParkingImageSelected"
                  />
                </label>
                <p class="text-xs text-on-surface-variant">
                  {{ parkingForm.imageFileName || 'Aucun fichier selectionne' }}
                </p>
                <img
                  v-if="parkingForm.imageUrl"
                  :src="parkingForm.imageUrl"
                  alt="Apercu photo parking"
                  class="h-32 w-full rounded-xl border border-outline-variant/40 object-cover"
                />
                <button
                  v-if="parkingForm.imageUrl"
                  type="button"
                  class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold text-on-surface hover:bg-surface-container-high"
                  @click="clearParkingImageSelection"
                >
                  Supprimer la photo
                </button>
              </div>

              <div class="space-y-2 rounded-xl bg-surface-container-low p-3">
                <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Types vehicules</p>
                <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <label
                    v-for="option in vehicleTypeOptions"
                    :key="`vehicle-${option}`"
                    class="inline-flex items-center gap-2 rounded-lg bg-surface-container px-3 py-2 text-xs text-on-surface"
                  >
                    <input
                      v-model="parkingForm.supportedVehicleTypes"
                      type="checkbox"
                      :value="option"
                      class="h-4 w-4"
                    />
                    {{ option }}
                  </label>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
              <input
                v-model.number="parkingForm.maxVehicleHeightMeters"
                type="number"
                min="0"
                step="0.01"
                placeholder="Hauteur max (m)"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="parkingForm.lastUpdate"
                type="text"
                placeholder="Derniere mise a jour"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div class="flex items-center gap-3 rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface">
                <label class="inline-flex items-center gap-2">
                  <input v-model="parkingForm.isOpen24h" type="checkbox" class="h-4 w-4" />
                  Ouvert 24h
                </label>
                <label class="inline-flex items-center gap-2">
                  <input v-model="parkingForm.nearTelepherique" type="checkbox" class="h-4 w-4" />
                  Proche telepherique
                </label>
              </div>
            </div>

            <div class="flex items-center gap-2">
              <button type="submit" class="primary-cta px-4 py-2" :disabled="creatingParking">
                {{ creatingParking ? 'Creation...' : 'Enregistrer' }}
              </button>
              <button
                type="button"
                class="rounded-lg bg-surface-container px-4 py-2 text-sm font-semibold text-on-surface hover:bg-surface-container-high"
                @click="cancelAddMode"
              >
                Annuler
              </button>
            </div>

            <p v-if="addError" class="text-xs font-semibold text-error">{{ addError }}</p>
            <p v-if="addSuccess" class="text-xs font-semibold text-emerald-600">{{ addSuccess }}</p>
          </form>
        </article>

        <article class="surface-card p-6">
          <h3 class="font-headline text-lg font-bold text-on-surface">Dessiner la carte interactive</h3>
          <p class="mt-1 text-sm text-on-surface-variant">
            Cliquez une case vide pour creer une place. Cliquez une place existante pour la modifier.
            Clic droit sur une place pour la supprimer rapidement.
          </p>

          <div class="mt-4 space-y-3">
            <label class="block text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Parking cible
              <select
                v-model="selectedParkingId"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option value="">Selectionner un parking</option>
                <option v-for="parking in parkings" :key="parking.id" :value="parking.id">
                  {{ parking.name }} ({{ parking.id }})
                </option>
              </select>
            </label>

            <div class="flex items-center gap-2">
              <button
                type="button"
                class="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-100 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="deletingParking || persistingLayout || !selectedParking"
                @click="deleteSelectedParking"
              >
                {{ deletingParking ? 'Suppression...' : 'Supprimer parking' }}
              </button>
            </div>

            <div class="grid grid-cols-5 gap-3">
              <input
                v-model.number="gridConfigForm.rows"
                type="number"
                min="2"
                placeholder="Lignes"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.number="gridConfigForm.cols"
                type="number"
                min="2"
                placeholder="Colonnes"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="gridConfigForm.floor"
                type="text"
                placeholder="Etage"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="gridConfigForm.zone"
                type="text"
                placeholder="Zone"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="gridConfigForm.laneRows"
                type="text"
                placeholder="Lignes voie"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>

            <button
              type="button"
              class="primary-cta px-4 py-2 disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="persistingLayout"
              @click="applyGridConfig"
            >
              Appliquer grille
            </button>
          </div>

          <div class="mt-4 grid grid-cols-4 gap-2 text-xs font-semibold">
            <span class="rounded-lg bg-emerald-100 px-2 py-1 text-emerald-700">Libres: {{ selectedParkingStats.available }}</span>
            <span class="rounded-lg bg-red-100 px-2 py-1 text-red-700">Occupees: {{ selectedParkingStats.occupied }}</span>
            <span class="rounded-lg bg-amber-100 px-2 py-1 text-amber-700">Reservees: {{ selectedParkingStats.reserved }}</span>
            <span class="rounded-lg bg-slate-200 px-2 py-1 text-slate-700">Offline: {{ selectedParkingStats.offline }}</span>
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
                  <template v-if="isLaneCell(row)">
                    VOIE
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

          <div class="mt-4 space-y-3 rounded-xl bg-surface-container-low p-4">
            <p class="text-sm font-bold text-on-surface">Parametres nouvelle place (clic case vide)</p>
            <div class="grid grid-cols-3 gap-3">
              <input
                v-model.trim="spotForm.label"
                type="text"
                placeholder="ID place ex: P09"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <select
                v-model="spotForm.type"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option v-for="type in spotTypeOptions" :key="type" :value="type">{{ typeLabelMap[type] }}</option>
              </select>
              <select
                v-model="spotForm.state"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option v-for="state in spotStateOptions" :key="state" :value="state">{{ stateLabelMap[state] }}</option>
              </select>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <input
                v-model.trim="spotForm.arduinoId"
                type="text"
                placeholder="Arduino ID"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="spotForm.channel"
                type="text"
                placeholder="Canal / Pin"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="spotForm.topic"
                type="text"
                placeholder="MQTT topic"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>
          </div>

          <div v-if="selectedSpot" class="mt-4 space-y-3 rounded-xl bg-surface-container-low p-4">
            <p class="text-sm font-bold text-on-surface">Modifier la place selectionnee</p>
            <div class="grid grid-cols-3 gap-3">
              <input
                v-model.trim="selectedSpotForm.label"
                type="text"
                placeholder="ID place"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <select
                v-model="selectedSpotForm.type"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option v-for="type in spotTypeOptions" :key="type" :value="type">{{ typeLabelMap[type] }}</option>
              </select>
              <select
                v-model="selectedSpotForm.state"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option v-for="state in spotStateOptions" :key="state" :value="state">{{ stateLabelMap[state] }}</option>
              </select>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <input
                v-model.trim="selectedSpotForm.arduinoId"
                type="text"
                placeholder="Arduino ID"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="selectedSpotForm.channel"
                type="text"
                placeholder="Canal / Pin"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <input
                v-model.trim="selectedSpotForm.topic"
                type="text"
                placeholder="MQTT topic"
                class="w-full rounded-lg bg-surface-container px-3 py-2 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>

            <div class="flex items-center gap-2">
              <button
                type="button"
                class="primary-cta px-4 py-2 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="persistingLayout"
                @click="saveSelectedSpot"
              >
                Sauvegarder place
              </button>
              <button
                type="button"
                class="rounded-lg bg-surface-container px-4 py-2 text-sm font-semibold text-on-surface hover:bg-surface-container-high disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="persistingLayout"
                @click="removeSelectedSpot"
              >
                Supprimer
              </button>
            </div>
          </div>

          <p v-if="persistingLayout" class="mt-3 text-xs font-semibold text-primary">Sauvegarde de la carte interieure en cours...</p>
          <p v-if="gridError" class="mt-3 text-xs font-semibold text-error">{{ gridError }}</p>
          <p v-if="gridSuccess" class="mt-3 text-xs font-semibold text-emerald-600">{{ gridSuccess }}</p>
        </article>

        <article v-if="showApiPanel" class="surface-card p-6">
          <h3 class="font-headline text-lg font-bold text-on-surface">JSON et envoi API</h3>
          <p class="mt-1 text-sm text-on-surface-variant">Le JSON est serialise puis envoye a l API backend.</p>

          <p class="mt-3 text-xs font-semibold text-outline">Endpoint: {{ apiEndpoint }}</p>

          <pre class="mt-3 max-h-64 overflow-auto rounded-lg bg-surface-container-low p-3 text-xs text-on-surface-variant">{{ payloadPreview }}</pre>

          <button
            type="button"
            class="primary-cta mt-3 px-4 py-2"
            :disabled="sendingToApi"
            @click="sendLayoutToApi"
          >
            {{ sendingToApi ? 'Envoi...' : 'Envoyer JSON vers API' }}
          </button>

          <p v-if="apiError" class="mt-3 text-xs font-semibold text-error">{{ apiError }}</p>
          <p v-if="apiSuccess" class="mt-3 text-xs font-semibold text-emerald-600">{{ apiSuccess }}</p>
        </article>
      </div>
    </div>
  </section>
</template>
