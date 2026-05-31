<script setup>
import { computed, onMounted, ref } from 'vue'
import { listOwnerParkings } from '@/services/owner/parkingSettingsApi'
import { useAuthStore } from '@/stores/auth'

const authStore = useAuthStore()

const loading = ref(false)
const loadError = ref('')
const ownerParkings = ref([])

const toNumber = (value, fallback = 0) => {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

const normalizeParking = (payload = {}) => {
  const indoorMap = payload?.indoorMap ?? {}
  const spots = Array.isArray(indoorMap?.spots) ? indoorMap.spots : []

  return {
    id: String(payload?.parkingId ?? '').trim(),
    name: String(payload?.name ?? '').trim(),
    capacity: Math.max(0, toNumber(payload?.capacity, 0)),
    spots: spots.map((spot) => ({
      state: String(spot?.state ?? 'AVAILABLE').trim().toUpperCase(),
    })),
  }
}

const totals = computed(() => {
  const stats = {
    parkings: ownerParkings.value.length,
    capacity: 0,
    total: 0,
    available: 0,
    occupied: 0,
    reserved: 0,
    offline: 0,
  }

  ownerParkings.value.forEach((parking) => {
    stats.capacity += parking.capacity
    stats.total += parking.spots.length

    parking.spots.forEach((spot) => {
      if (spot.state === 'OCCUPIED') stats.occupied += 1
      else if (spot.state === 'RESERVED') stats.reserved += 1
      else if (spot.state === 'OFFLINE') stats.offline += 1
      else stats.available += 1
    })
  })

  return stats
})

const occupancyPercent = computed(() => {
  if (!totals.value.total) {
    return 0
  }

  return Math.round((totals.value.occupied / totals.value.total) * 100)
})

const utilizationPercent = computed(() => {
  if (!totals.value.total) {
    return 0
  }

  return Math.round(((totals.value.occupied + totals.value.reserved) / totals.value.total) * 100)
})

const drawGap = computed(() => totals.value.capacity - totals.value.total)

const offlinePercent = computed(() => {
  if (!totals.value.total) {
    return 0
  }

  return Math.round((totals.value.offline / totals.value.total) * 100)
})

const averageOccupancyPerParking = computed(() => {
  if (!ownerParkings.value.length) {
    return 0
  }

  const sum = ownerParkings.value.reduce((acc, parking) => {
    const total = parking.spots.length
    if (!total) {
      return acc
    }

    const occupied = parking.spots.filter((spot) => spot.state === 'OCCUPIED').length
    return acc + Math.round((occupied / total) * 100)
  }, 0)

  return Math.round(sum / ownerParkings.value.length)
})

const spotStateDistribution = computed(() => {
  const total = Math.max(1, totals.value.total)
  const items = [
    { key: 'available', label: 'Disponibles', value: totals.value.available, color: '#16a34a' },
    { key: 'occupied', label: 'Occupees', value: totals.value.occupied, color: '#dc2626' },
    { key: 'reserved', label: 'Reservees', value: totals.value.reserved, color: '#d97706' },
    { key: 'offline', label: 'Offline', value: totals.value.offline, color: '#64748b' },
  ]

  return items.map((item) => ({
    ...item,
    percent: Math.round((item.value / total) * 100),
  }))
})

const pieStyle = computed(() => {
  const parts = []
  let cursor = 0

  spotStateDistribution.value.forEach((item) => {
    const next = cursor + item.percent
    parts.push(`${item.color} ${cursor}% ${next}%`)
    cursor = next
  })

  if (cursor < 100) {
    parts.push(`#e2e8f0 ${cursor}% 100%`)
  }

  return {
    background: `conic-gradient(${parts.join(', ')})`,
  }
})

const parkingBars = computed(() => {
  const maxSpots = Math.max(
    1,
    ...ownerParkings.value.map((parking) => parking.spots.length),
  )

  return ownerParkings.value.map((parking) => {
    const occupied = parking.spots.filter((spot) => spot.state === 'OCCUPIED').length
    const total = parking.spots.length
    const ratio = Math.round((total / maxSpots) * 100)

    return {
      id: parking.id,
      name: parking.name || parking.id,
      total,
      occupied,
      ratio,
      occupancy: total ? Math.round((occupied / total) * 100) : 0,
    }
  })
})

const topOccupiedParking = computed(() => {
  if (!parkingBars.value.length) {
    return null
  }

  return parkingBars.value.reduce((best, current) => {
    if (!best) return current
    if (current.occupancy > best.occupancy) return current
    if (current.occupancy === best.occupancy && current.total > best.total) return current
    return best
  }, null)
})

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
      return
    }

    ownerParkings.value = result.data.map((payload) => normalizeParking(payload))
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await loadOwnerParkings()
})
</script>

<template>
  <section class="space-y-6">
    <div class="flex items-center justify-between gap-3">
      <div>
        <h2 class="font-headline text-2xl font-extrabold text-on-surface">Statistiques proprietaire</h2>
        <p class="mt-1 text-sm text-on-surface-variant">Vue separee des indicateurs et graphiques de vos parkings.</p>
      </div>
      <button
        type="button"
        class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold text-on-surface hover:bg-surface-container-high"
        :disabled="loading"
        @click="loadOwnerParkings"
      >
        {{ loading ? 'Actualisation...' : 'Actualiser' }}
      </button>
    </div>

    <p v-if="loadError" class="rounded-lg bg-red-100 px-3 py-2 text-sm font-semibold text-red-700">
      {{ loadError }}
    </p>

    <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Parkings</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ totals.parkings }}</p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Capacite totale</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ totals.capacity }}</p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Places dessinees</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ totals.total }}</p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Occupation</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ occupancyPercent }}%</p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Utilisation</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ utilizationPercent }}%</p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Ecart capacite</p>
        <p class="mt-2 text-2xl font-extrabold" :class="drawGap === 0 ? 'text-emerald-600' : 'text-amber-600'">{{ drawGap }}</p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Offline</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ totals.offline }} <span class="text-base font-semibold text-on-surface-variant">({{ offlinePercent }}%)</span></p>
      </article>
      <article class="surface-card p-4">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Moyenne occupation</p>
        <p class="mt-2 text-2xl font-extrabold text-on-surface">{{ averageOccupancyPerParking }}%</p>
      </article>
      <article class="surface-card p-4 xl:col-span-2">
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Parking le plus charge</p>
        <p class="mt-2 text-xl font-extrabold text-on-surface">
          {{ topOccupiedParking?.name || 'N/A' }}
        </p>
        <p class="mt-1 text-sm text-on-surface-variant">
          {{ topOccupiedParking ? `${topOccupiedParking.occupied}/${topOccupiedParking.total} (${topOccupiedParking.occupancy}%)` : 'Aucune donnee.' }}
        </p>
      </article>
    </div>

    <div class="grid gap-6 xl:grid-cols-2">
      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Repartition des etats</h3>
        <div class="mt-4 flex items-center gap-6">
          <div class="h-36 w-36 rounded-full border border-outline-variant/50" :style="pieStyle" />
          <div class="flex-1 space-y-2">
            <div v-for="item in spotStateDistribution" :key="item.key" class="space-y-1">
              <div class="flex items-center justify-between text-xs font-semibold">
                <span class="text-on-surface">{{ item.label }}</span>
                <span class="text-on-surface-variant">{{ item.value }} ({{ item.percent }}%)</span>
              </div>
              <div class="h-2 rounded bg-surface-container-low">
                <div class="h-2 rounded" :style="{ width: `${item.percent}%`, backgroundColor: item.color }" />
              </div>
            </div>
          </div>
        </div>
      </article>

      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Comparaison par parking</h3>
        <div v-if="parkingBars.length" class="mt-4 space-y-3">
          <div v-for="item in parkingBars" :key="item.id" class="space-y-1">
            <div class="flex items-center justify-between text-xs font-semibold">
              <span class="text-on-surface">{{ item.name }}</span>
              <span class="text-on-surface-variant">{{ item.occupied }}/{{ item.total }} ({{ item.occupancy }}%)</span>
            </div>
            <div class="h-3 rounded bg-surface-container-low">
              <div class="h-3 rounded bg-primary" :style="{ width: `${item.ratio}%` }" />
            </div>
          </div>
        </div>
        <p v-else class="mt-4 text-sm text-on-surface-variant">Aucune donnee a afficher.</p>
      </article>
    </div>
  </section>
</template>
