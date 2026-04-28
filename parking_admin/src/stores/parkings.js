import { defineStore } from 'pinia'
import { ref } from 'vue'

const clamp = (value, min, max) => {
  if (value < min) {
    return min
  }

  if (value > max) {
    return max
  }

  return value
}

const parseNumber = (value, fallback) => {
  const parsed = Number(value)

  if (Number.isFinite(parsed)) {
    return parsed
  }

  return fallback
}

const parseOptionalNumber = (value, fallback = null) => {
  const parsed = Number(value)

  if (Number.isFinite(parsed)) {
    return parsed
  }

  return fallback
}

const toBoolean = (value, fallback = false) => {
  if (typeof value === 'boolean') {
    return value
  }

  if (typeof value === 'number') {
    return value === 1
  }

  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase()

    if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
      return true
    }

    if (normalized === 'false' || normalized === '0' || normalized === 'no') {
      return false
    }
  }

  return fallback
}

const toStringList = (value) => {
  if (Array.isArray(value)) {
    return value
      .map((item) => String(item ?? '').trim())
      .filter(Boolean)
  }

  if (typeof value === 'string') {
    return value
      .split(/[\r\n,;]+/)
      .map((item) => item.trim())
      .filter(Boolean)
  }

  return []
}

const normalizeVehicleTypes = (value) => {
  const unique = new Set(
    toStringList(value)
      .map((item) => item.toLowerCase())
      .filter(Boolean),
  )

  return Array.from(unique)
}

const normalizePosition = (position, fallback) => {
  if (!Array.isArray(position) || position.length !== 2) {
    return fallback
  }

  return [
    parseNumber(position[0], fallback[0]),
    parseNumber(position[1], fallback[1]),
  ]
}

const defaultCenter = [36.7538, 3.0588]
const validSpotTypes = ['STANDARD', 'PMR', 'VIP']
const validSpotStates = ['AVAILABLE', 'OCCUPIED', 'RESERVED', 'OFFLINE']

const normalizeSpotType = (value) => {
  const normalized = String(value ?? '').trim().toUpperCase()

  if (validSpotTypes.includes(normalized)) {
    return normalized
  }

  return 'STANDARD'
}

const normalizeSpotState = (value) => {
  const normalized = String(value ?? '').trim().toUpperCase()

  if (validSpotStates.includes(normalized)) {
    return normalized
  }

  return 'AVAILABLE'
}

const toSensorBinding = (input = {}) => {
  return {
    arduinoId: String(input.arduinoId ?? input.deviceId ?? '').trim(),
    channel: String(input.channel ?? '').trim(),
    topic: String(input.topic ?? '').trim(),
  }
}

const toOwnerRecord = (input = {}) => {
  return {
    name: String(input.name ?? '').trim(),
    email: String(input.email ?? '').trim().toLowerCase(),
    phone: String(input.phone ?? '').trim(),
  }
}

const toSpotRecord = (input, id) => {
  return {
    id,
    label: String(input.label ?? id).trim() || id,
    row: Math.max(0, Math.round(parseNumber(input.row, 0))),
    col: Math.max(0, Math.round(parseNumber(input.col, 0))),
    type: normalizeSpotType(input.type),
    state: normalizeSpotState(input.state),
    sensor: toSensorBinding(input.sensor ?? input),
    updatedAt: String(input.updatedAt ?? new Date().toISOString()),
  }
}

const toGridRecord = (input = {}) => {
  const source = input.indoorGrid ?? input
  const spotsInput = Array.isArray(source.spots) ? source.spots : []

  return {
    floor: String(source.floor ?? 'B1').trim() || 'B1',
    zone: String(source.zone ?? 'Zone A').trim() || 'Zone A',
    rows: Math.max(2, Math.round(parseNumber(source.rows, 6))),
    cols: Math.max(2, Math.round(parseNumber(source.cols, 8))),
    laneRows: Array.isArray(source.laneRows)
      ? source.laneRows
          .map((value) => Math.max(0, Math.round(parseNumber(value, -1))))
          .filter((value) => value >= 0)
      : [],
    spots: spotsInput.map((spot, index) => {
      const spotId = String(spot.id ?? `SP-${String(index + 1).padStart(3, '0')}`)
      return toSpotRecord(spot, spotId)
    }),
  }
}

const parseNumericId = (id, prefix) => {
  const value = String(id ?? '')
  const regex = new RegExp(`^${prefix}(\\d+)$`)
  const match = value.match(regex)

  if (!match) {
    return 0
  }

  return Number(match[1])
}

const getMaxParkingNumericId = (items) => {
  return items.reduce((maxId, item) => {
    const current = parseNumericId(item.id, 'PK-')
    return current > maxId ? current : maxId
  }, 0)
}

const getMaxSpotNumericId = (items) => {
  return items.reduce((maxId, parking) => {
    const spots = parking.indoorGrid?.spots ?? []

    const maxSpot = spots.reduce((maxSpotId, spot) => {
      const current = parseNumericId(spot.id, 'SP-')
      return current > maxSpotId ? current : maxSpotId
    }, 0)

    return maxSpot > maxId ? maxSpot : maxId
  }, 0)
}

const updateParkingRecord = (parking, nextGrid) => {
  return {
    ...parking,
    indoorGrid: nextGrid,
  }
}

const demoSpots = [
  { label: 'P01', row: 0, col: 0, type: 'STANDARD', state: 'OCCUPIED', arduinoId: 'ESP32-A1', channel: 'D1', topic: 'parking/pk01/p01' },
  { label: 'P02', row: 0, col: 2, type: 'STANDARD', state: 'AVAILABLE', arduinoId: 'ESP32-A1', channel: 'D2', topic: 'parking/pk01/p02' },
  { label: 'P03', row: 0, col: 4, type: 'VIP', state: 'OCCUPIED', arduinoId: 'ESP32-A1', channel: 'D3', topic: 'parking/pk01/p03' },
  { label: 'P04', row: 0, col: 6, type: 'STANDARD', state: 'AVAILABLE', arduinoId: 'ESP32-A1', channel: 'D4', topic: 'parking/pk01/p04' },
  { label: 'P05', row: 4, col: 0, type: 'PMR', state: 'RESERVED', arduinoId: 'ESP32-A2', channel: 'D1', topic: 'parking/pk01/p05' },
  { label: 'P06', row: 4, col: 2, type: 'STANDARD', state: 'AVAILABLE', arduinoId: 'ESP32-A2', channel: 'D2', topic: 'parking/pk01/p06' },
  { label: 'P07', row: 4, col: 4, type: 'STANDARD', state: 'OCCUPIED', arduinoId: 'ESP32-A2', channel: 'D3', topic: 'parking/pk01/p07' },
  { label: 'P08', row: 4, col: 6, type: 'STANDARD', state: 'AVAILABLE', arduinoId: 'ESP32-A2', channel: 'D4', topic: 'parking/pk01/p08' },
]

const initialParkings = [
  {
    id: 'PK-01',
    name: 'Centre-ville Central',
    address: 'Boulevard Amirouche, Alger',
    owner: {
      name: 'Youssef Benali',
      email: 'youssef@urbanlots.ma',
      phone: '+213551000001',
    },
    position: [36.7538, 3.0588],
    capacity: 220,
    indoorGrid: {
      floor: 'B1',
      zone: 'Zone A',
      rows: 6,
      cols: 8,
      laneRows: [2],
      spots: demoSpots,
    },
  },
  {
    id: 'PK-02',
    name: 'Harbor Pier 4',
    address: 'Zone portuaire Est, Alger',
    owner: {
      name: 'Rachid Omar',
      email: 'rachid@westgatepark.com',
      phone: '+213551000002',
    },
    position: [36.7682, 3.0841],
    capacity: 160,
    indoorGrid: {
      floor: 'B1',
      zone: 'Zone B',
      rows: 6,
      cols: 8,
      laneRows: [2],
      spots: [],
    },
  },
  {
    id: 'PK-03',
    name: 'Quartier Tech',
    address: 'Tech Valley Bloc B, Alger',
    owner: {
      name: 'Samir Kouider',
      email: 'samir@quartier-tech.dz',
      phone: '+213551000003',
    },
    position: [36.7416, 3.0212],
    capacity: 140,
    indoorGrid: {
      floor: 'RDC',
      zone: 'Zone C',
      rows: 6,
      cols: 8,
      laneRows: [2],
      spots: [],
    },
  },
]

const toParkingRecord = (input, id) => {
  const fallbackPosition = defaultCenter
  const capacity = Math.max(1, Math.round(parseNumber(input.capacity, 1)))

  const indoorGrid = toGridRecord({
    floor: input.floor,
    zone: input.zone,
    rows: input.rows,
    cols: input.cols,
    laneRows: input.laneRows,
    spots: input.indoorGrid?.spots ?? [],
    indoorGrid: input.indoorGrid,
  })

  return {
    id,
    name: String(input.name ?? '').trim(),
    address: String(input.address ?? '').trim(),
    owner: toOwnerRecord(input.owner),
    position: normalizePosition(input.position, fallbackPosition),
    capacity,
    walkingTime: String(input.walkingTime ?? '').trim(),
    rating: clamp(parseNumber(input.rating, 0), 0, 5),
    pricePerHour: Math.max(0, parseNumber(input.pricePerHour, 0)),
    availableSpots: clamp(
      Math.round(parseNumber(input.availableSpots, capacity)),
      0,
      capacity,
    ),
    lastUpdate: String(input.lastUpdate ?? '').trim(),
    isOpen24h: toBoolean(input.isOpen24h, false),
    equipments: toStringList(input.equipments),
    tags: toStringList(input.tags),
    imageUrl: String(input.imageUrl ?? '').trim(),
    maxVehicleHeightMeters: parseOptionalNumber(input.maxVehicleHeightMeters, null),
    supportedVehicleTypes: normalizeVehicleTypes(input.supportedVehicleTypes),
    nearTelepherique: toBoolean(input.nearTelepherique, false),
    indoorGrid,
  }
}

const toApiPayload = (parking) => {
  return {
    parkingId: parking.id,
    name: parking.name,
    address: parking.address,
    ownerAccount: {
      name: parking.owner?.name ?? '',
      email: parking.owner?.email ?? '',
      phone: parking.owner?.phone ?? '',
    },
    location: {
      lat: parking.position[0],
      lng: parking.position[1],
    },
    capacity: parking.capacity,
    walkingTime: parking.walkingTime,
    rating: parking.rating,
    pricePerHour: parking.pricePerHour,
    availableSpots: parking.availableSpots,
    lastUpdate: parking.lastUpdate,
    isOpen24h: parking.isOpen24h,
    equipments: parking.equipments,
    tags: parking.tags,
    imageUrl: parking.imageUrl,
    maxVehicleHeightMeters: parking.maxVehicleHeightMeters,
    supportedVehicleTypes: parking.supportedVehicleTypes,
    nearTelepherique: parking.nearTelepherique,
    indoorMap: {
      floor: parking.indoorGrid.floor,
      zone: parking.indoorGrid.zone,
      grid: {
        rows: parking.indoorGrid.rows,
        cols: parking.indoorGrid.cols,
        laneRows: parking.indoorGrid.laneRows,
      },
      spots: parking.indoorGrid.spots.map((spot) => {
        return {
          spotId: spot.id,
          label: spot.label,
          row: spot.row,
          col: spot.col,
          type: spot.type,
          state: spot.state,
          sensor: {
            arduinoId: spot.sensor.arduinoId,
            channel: spot.sensor.channel,
            topic: spot.sensor.topic,
          },
          updatedAt: spot.updatedAt,
        }
      }),
    },
  }
}

const toParkingInputFromApiPayload = (payload = {}) => {
  const spots = Array.isArray(payload?.indoorMap?.spots)
    ? payload.indoorMap.spots.map((spot) => {
        return {
          id: String(spot.spotId ?? '').trim(),
          label: String(spot.label ?? '').trim(),
          row: parseNumber(spot.row, 0),
          col: parseNumber(spot.col, 0),
          type: spot.type,
          state: spot.state,
          sensor: {
            arduinoId: spot?.sensor?.arduinoId ?? '',
            channel: spot?.sensor?.channel ?? '',
            topic: spot?.sensor?.topic ?? '',
          },
          updatedAt: spot.updatedAt,
        }
      })
    : []

  return {
    name: String(payload.name ?? '').trim(),
    address: String(payload.address ?? '').trim(),
    owner: {
      name: payload?.ownerAccount?.name ?? '',
      email: payload?.ownerAccount?.email ?? '',
      phone: payload?.ownerAccount?.phone ?? '',
    },
    position: [
      parseNumber(payload?.location?.lat, defaultCenter[0]),
      parseNumber(payload?.location?.lng, defaultCenter[1]),
    ],
    capacity: parseNumber(payload.capacity, 1),
    walkingTime: String(payload.walkingTime ?? '').trim(),
    rating: parseNumber(payload.rating, 0),
    pricePerHour: parseNumber(payload.pricePerHour, 0),
    availableSpots: parseNumber(payload.availableSpots, parseNumber(payload.capacity, 1)),
    lastUpdate: String(payload.lastUpdate ?? '').trim(),
    isOpen24h: toBoolean(payload.isOpen24h, false),
    equipments: toStringList(payload.equipments),
    tags: toStringList(payload.tags),
    imageUrl: String(payload.imageUrl ?? '').trim(),
    maxVehicleHeightMeters: parseOptionalNumber(payload.maxVehicleHeightMeters, null),
    supportedVehicleTypes: normalizeVehicleTypes(payload.supportedVehicleTypes),
    nearTelepherique: toBoolean(payload.nearTelepherique, false),
    indoorGrid: {
      floor: payload?.indoorMap?.floor,
      zone: payload?.indoorMap?.zone,
      rows: parseNumber(payload?.indoorMap?.grid?.rows, 6),
      cols: parseNumber(payload?.indoorMap?.grid?.cols, 8),
      laneRows: Array.isArray(payload?.indoorMap?.grid?.laneRows)
        ? payload.indoorMap.grid.laneRows
        : [],
      spots,
    },
  }
}

const toParkingRecordFromApiPayload = (payload = {}) => {
  const parkingId = String(payload.parkingId ?? '').trim()

  if (!parkingId) {
    return null
  }

  return toParkingRecord(toParkingInputFromApiPayload(payload), parkingId)
}

export const useParkingsStore = defineStore('parkings', () => {
  const parkings = ref(initialParkings.map((parking) => toParkingRecord(parking, parking.id)))
  const isAddPanelOpen = ref(false)
  const nextParkingNumericId = ref(getMaxParkingNumericId(parkings.value) + 1)
  const nextSpotNumericId = ref(getMaxSpotNumericId(parkings.value) + 1)

  const openAddPanel = () => {
    isAddPanelOpen.value = true
  }

  const closeAddPanel = () => {
    isAddPanelOpen.value = false
  }

  const addParking = (input) => {
    const id = `PK-${String(nextParkingNumericId.value).padStart(2, '0')}`
    nextParkingNumericId.value += 1

    const parking = toParkingRecord(input, id)
    parkings.value.unshift(parking)

    return parking
  }

  const removeParking = (parkingId) => {
    const before = parkings.value.length
    parkings.value = parkings.value.filter((item) => item.id !== parkingId)

    return parkings.value.length !== before
  }

  const setIndoorGridConfig = (parkingId, input) => {
    const index = parkings.value.findIndex((item) => item.id === parkingId)

    if (index === -1) {
      return null
    }

    const parking = parkings.value[index]
    const currentGrid = parking.indoorGrid ?? toGridRecord()

    const nextGrid = {
      ...currentGrid,
      floor: String(input.floor ?? currentGrid.floor).trim() || 'B1',
      zone: String(input.zone ?? currentGrid.zone).trim() || 'Zone A',
      rows: Math.max(2, Math.round(parseNumber(input.rows, currentGrid.rows))),
      cols: Math.max(2, Math.round(parseNumber(input.cols, currentGrid.cols))),
      laneRows: Array.isArray(input.laneRows)
        ? input.laneRows
            .map((value) => Math.max(0, Math.round(parseNumber(value, -1))))
            .filter((value) => value >= 0)
        : currentGrid.laneRows,
    }

    const filteredSpots = currentGrid.spots.filter((spot) => {
      return spot.row < nextGrid.rows && spot.col < nextGrid.cols
    })

    parkings.value[index] = updateParkingRecord(parking, {
      ...nextGrid,
      spots: filteredSpots,
    })

    return parkings.value[index]
  }

  const addGridSpot = (parkingId, input) => {
    const index = parkings.value.findIndex((item) => item.id === parkingId)

    if (index === -1) {
      return null
    }

    const parking = parkings.value[index]
    const currentGrid = parking.indoorGrid ?? toGridRecord()

    const row = Math.max(0, Math.round(parseNumber(input.row, 0)))
    const col = Math.max(0, Math.round(parseNumber(input.col, 0)))

    const exists = currentGrid.spots.some((spot) => spot.row === row && spot.col === col)
    if (exists) {
      return null
    }

    const spotId = `SP-${String(nextSpotNumericId.value).padStart(3, '0')}`
    nextSpotNumericId.value += 1

    const spot = toSpotRecord(
      {
        ...input,
        row,
        col,
      },
      spotId,
    )

    const nextGrid = {
      ...currentGrid,
      spots: [...currentGrid.spots, spot],
    }

    parkings.value[index] = updateParkingRecord(parking, nextGrid)
    return spot
  }

  const updateGridSpot = (parkingId, spotId, patch) => {
    const index = parkings.value.findIndex((item) => item.id === parkingId)

    if (index === -1) {
      return null
    }

    const parking = parkings.value[index]
    const currentGrid = parking.indoorGrid ?? toGridRecord()
    const spots = currentGrid.spots ?? []
    const spotIndex = spots.findIndex((spot) => spot.id === spotId)

    if (spotIndex === -1) {
      return null
    }

    const currentSpot = spots[spotIndex]
    const hasDirectSensorUpdate = ['arduinoId', 'channel', 'topic'].some((key) => {
      return Object.prototype.hasOwnProperty.call(patch, key)
    })

    let nextSensor = { ...currentSpot.sensor }

    if (Object.prototype.hasOwnProperty.call(patch, 'sensor')) {
      nextSensor = {
        ...nextSensor,
        ...toSensorBinding(patch.sensor ?? {}),
      }
    }

    if (hasDirectSensorUpdate) {
      nextSensor = {
        ...nextSensor,
        ...toSensorBinding({
          arduinoId: Object.prototype.hasOwnProperty.call(patch, 'arduinoId')
            ? patch.arduinoId
            : nextSensor.arduinoId,
          channel: Object.prototype.hasOwnProperty.call(patch, 'channel')
            ? patch.channel
            : nextSensor.channel,
          topic: Object.prototype.hasOwnProperty.call(patch, 'topic')
            ? patch.topic
            : nextSensor.topic,
        }),
      }
    }

    const mergedSpot = {
      ...currentSpot,
      ...patch,
      sensor: nextSensor,
    }

    const updatedSpot = toSpotRecord(mergedSpot, currentSpot.id)
    const nextSpots = [...spots]
    nextSpots.splice(spotIndex, 1, updatedSpot)

    const nextGrid = {
      ...currentGrid,
      spots: nextSpots,
    }

    parkings.value[index] = updateParkingRecord(parking, nextGrid)
    return updatedSpot
  }

  const removeGridSpot = (parkingId, spotId) => {
    const index = parkings.value.findIndex((item) => item.id === parkingId)

    if (index === -1) {
      return false
    }

    const parking = parkings.value[index]
    const currentGrid = parking.indoorGrid ?? toGridRecord()
    const nextSpots = currentGrid.spots.filter((spot) => spot.id !== spotId)

    if (nextSpots.length === currentGrid.spots.length) {
      return false
    }

    parkings.value[index] = updateParkingRecord(parking, {
      ...currentGrid,
      spots: nextSpots,
    })

    return true
  }

  const parkingPayload = (parkingId) => {
    const parking = parkings.value.find((item) => item.id === parkingId)

    if (!parking) {
      return null
    }

    return toApiPayload(parking)
  }

  const replaceParkingsFromApi = (payloads) => {
    if (!Array.isArray(payloads)) {
      return 0
    }

    const mapped = payloads
      .map((payload) => toParkingRecordFromApiPayload(payload))
      .filter(Boolean)

    parkings.value = mapped
    nextParkingNumericId.value = getMaxParkingNumericId(parkings.value) + 1
    nextSpotNumericId.value = getMaxSpotNumericId(parkings.value) + 1

    return mapped.length
  }

  const upsertParkingFromApiPayload = (payload) => {
    const record = toParkingRecordFromApiPayload(payload)

    if (!record) {
      return null
    }

    const index = parkings.value.findIndex((item) => item.id === record.id)

    if (index === -1) {
      parkings.value.unshift(record)
    } else {
      const next = [...parkings.value]
      next.splice(index, 1, record)
      parkings.value = next
    }

    nextParkingNumericId.value = getMaxParkingNumericId(parkings.value) + 1
    nextSpotNumericId.value = getMaxSpotNumericId(parkings.value) + 1

    return record
  }

  return {
    parkings,
    isAddPanelOpen,
    openAddPanel,
    closeAddPanel,
    addParking,
    removeParking,
    setIndoorGridConfig,
    addGridSpot,
    updateGridSpot,
    removeGridSpot,
    parkingPayload,
    replaceParkingsFromApi,
    upsertParkingFromApiPayload,
    validSpotTypes,
    validSpotStates,
  }
})
