<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
import { mapConfig } from '@/config/map'
import { listOwnerParkings } from '@/services/owner/parkingSettingsApi'
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

const mapContainer = ref(null)
const mapInstance = ref(null)
const markersLayer = ref(null)
const markerByParkingId = new Map()

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

const stateLabelMap = {
  AVAILABLE: 'Disponible',
  OCCUPIED: 'Occupee',
  RESERVED: 'Reservee',
  OFFLINE: 'Hors service',
}

const toNumber = (value, fallback) => {
  const parsed = Number(value)

  if (Number.isFinite(parsed)) {
    return parsed
  }

  return fallback
}

const isValidCoordinatePair = (lat, lng) => {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
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
  return selectedParking.value?.indoorMap?.grid ?? { rows: 0, cols: 0, laneRows: [] }
})

const selectedSpots = computed(() => {
  return selectedParking.value?.indoorMap?.spots ?? []
})

const selectedSpot = computed(() => {
  return selectedSpots.value.find((spot) => spot.id === selectedSpotId.value) ?? null
})

const selectedParkingStats = computed(() => {
  return parkingStats(selectedParking.value)
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

const spotMapByCell = computed(() => {
  const map = new Map()
  selectedSpots.value.forEach((spot) => {
    map.set(`${spot.row}-${spot.col}`, spot)
  })
  return map
})

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
  ownerRow.textContent = `Owner: ${parking.ownerAccount?.name || '-'} | Tel: ${parking.ownerAccount?.phone || '-'}`
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
    renderParkingMarkers()
  } finally {
    loading.value = false
  }
}

const spotAt = (row, col) => {
  return spotMapByCell.value.get(`${row}-${col}`) ?? null
}

const isLaneCell = (row) => {
  return laneRowSet.value.has(row)
}

const cellClass = (row, col) => {
  if (isLaneCell(row)) {
    return 'cursor-default border-dashed border-outline-variant bg-surface-container text-outline'
  }

  const spot = spotAt(row, col)
  if (!spot) {
    return 'cursor-default border-outline-variant bg-surface-container-low text-outline'
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
  if (isLaneCell(row)) {
    return
  }

  const spot = spotAt(row, col)
  selectedSpotId.value = spot?.id ?? ''
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
        Meme experience visuelle que l admin, en mode lecture seule pour owner.
      </p>
      <p class="mt-2 inline-flex rounded-lg bg-primary/10 px-3 py-2 text-xs font-semibold text-primary">
        Mode lecture seule: le compte owner ne peut pas ajouter ou modifier des parkings.
      </p>
    </div>

    <div class="grid gap-6 xl:grid-cols-[1.35fr,1fr]">
      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Emplacement global du parking</h3>
        <p class="mt-1 text-sm text-on-surface-variant">Selectionnez un parking owner pour le centrer sur la carte.</p>

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
            <p><span class="font-semibold text-on-surface">Adresse:</span> {{ selectedParking.address || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Owner:</span> {{ selectedParkingOwnerLabel }}</p>
            <p><span class="font-semibold text-on-surface">Telephone:</span> {{ selectedParking.ownerAccount?.phone || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Position:</span> {{ selectedLocationLabel }}</p>
            <p><span class="font-semibold text-on-surface">Capacite:</span> {{ selectedParking.capacity }}</p>
            <p><span class="font-semibold text-on-surface">Places dessinees:</span> {{ selectedParkingStats.total }}</p>
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
            Parking owner
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
            <p><span class="font-semibold text-on-surface">Owner:</span> {{ selectedParking.ownerAccount?.name || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Email:</span> {{ selectedParking.ownerAccount?.email || '-' }}</p>
            <p><span class="font-semibold text-on-surface">Jours:</span> {{ selectedWorkingDaysLabel }}</p>
            <p><span class="font-semibold text-on-surface">Heures:</span> {{ selectedParking.businessSettings.openingTime }} - {{ selectedParking.businessSettings.closingTime }}</p>
            <p><span class="font-semibold text-on-surface">Tarif horaire:</span> {{ selectedParking.businessSettings.pricing.hourlyRateDzd }} DZD</p>
            <p><span class="font-semibold text-on-surface">Tarif journalier:</span> {{ selectedParking.businessSettings.pricing.dailyRateDzd }} DZD</p>
            <p class="sm:col-span-2"><span class="font-semibold text-on-surface">Tarif mensuel:</span> {{ selectedMonthlyRateLabel }}</p>
          </div>
        </article>

        <article class="surface-card p-6">
          <h3 class="font-headline text-lg font-bold text-on-surface">Carte interieure (lecture seule)</h3>
          <p class="mt-1 text-sm text-on-surface-variant">
            Visualisation des voies et places. Cliquez une place pour afficher ses details.
          </p>

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
                >
                  <template v-if="isLaneCell(row)">
                    VOIE
                  </template>
                  <template v-else-if="spotAt(row, col)">
                    <span>{{ spotAt(row, col).label }}</span>
                    <span class="text-[10px]">{{ typeLabelMap[spotAt(row, col).type] }}</span>
                  </template>
                  <template v-else>
                    -
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
      Aucun parking disponible pour ce compte owner.
    </p>
  </section>
</template>
