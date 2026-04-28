<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { listOwnerParkings, updateOwnerBusinessSettings } from '@/services/owner/parkingSettingsApi'

const router = useRouter()
const authStore = useAuthStore()

const ownerParkings = ref([])
const selectedParkingId = ref('')

const loading = ref(false)
const saving = ref(false)
const loadError = ref('')
const saveError = ref('')
const saveSuccess = ref('')
const lastComponentCheckAt = ref('')

const dayOptions = [
  { key: 'MONDAY', label: 'Lundi' },
  { key: 'TUESDAY', label: 'Mardi' },
  { key: 'WEDNESDAY', label: 'Mercredi' },
  { key: 'THURSDAY', label: 'Jeudi' },
  { key: 'FRIDAY', label: 'Vendredi' },
  { key: 'SATURDAY', label: 'Samedi' },
  { key: 'SUNDAY', label: 'Dimanche' },
]

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

const componentToneClassMap = {
  success: 'border-emerald-200 bg-emerald-50 text-emerald-700',
  warning: 'border-amber-200 bg-amber-50 text-amber-700',
  danger: 'border-red-200 bg-red-50 text-red-700',
  neutral: 'border-outline-variant bg-surface-container text-on-surface-variant',
}

const settingsForm = reactive({
  workingDays: [],
  openingTime: '08:00',
  closingTime: '20:00',
  hourlyRateDzd: 0,
  dailyRateDzd: 0,
  monthlyRateDzd: '',
})

const normalizeParking = (payload = {}) => {
  const indoorMap = payload?.indoorMap ?? {}
  const grid = indoorMap?.grid ?? {}
  const spots = Array.isArray(indoorMap?.spots) ? indoorMap.spots : []
  const businessSettings = payload?.businessSettings ?? {}
  const pricing = businessSettings?.pricing ?? {}

  return {
    id: String(payload?.parkingId ?? '').trim(),
    name: String(payload?.name ?? '').trim(),
    address: String(payload?.address ?? '').trim(),
    capacity: Number(payload?.capacity ?? 0),
    indoorMap: {
      floor: String(indoorMap?.floor ?? 'B1'),
      zone: String(indoorMap?.zone ?? 'Zone A'),
      grid: {
        rows: Number(grid?.rows ?? 0),
        cols: Number(grid?.cols ?? 0),
        laneRows: Array.isArray(grid?.laneRows) ? grid.laneRows.map((row) => Number(row)) : [],
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
        currency: 'DZD',
        hourlyRateDzd: Number(pricing?.hourlyRateDzd ?? 0),
        dailyRateDzd: Number(pricing?.dailyRateDzd ?? 0),
        monthlyRateDzd: pricing?.monthlyRateDzd == null ? null : Number(pricing.monthlyRateDzd),
      },
    },
  }
}

const selectedParking = computed(() => {
  return ownerParkings.value.find((parking) => parking.id === selectedParkingId.value) ?? null
})

const selectedSpots = computed(() => {
  const spots = selectedParking.value?.indoorMap?.spots ?? []

  return [...spots].sort((a, b) => {
    if (Number(a.row) !== Number(b.row)) {
      return Number(a.row) - Number(b.row)
    }

    return Number(a.col) - Number(b.col)
  })
})

const selectedStats = computed(() => {
  const spots = selectedSpots.value
  const occupied = spots.filter((spot) => String(spot.state).toUpperCase() === 'OCCUPIED').length
  const available = spots.filter((spot) => String(spot.state).toUpperCase() === 'AVAILABLE').length
  const reserved = spots.filter((spot) => String(spot.state).toUpperCase() === 'RESERVED').length
  const offline = spots.filter((spot) => String(spot.state).toUpperCase() === 'OFFLINE').length
  const total = spots.length

  return {
    total,
    occupied,
    available,
    reserved,
    offline,
    occupancyPercent: total ? Math.round((occupied / total) * 100) : 0,
  }
})

const laneRowsLabel = computed(() => {
  const laneRows = selectedParking.value?.indoorMap?.grid?.laneRows ?? []

  if (!laneRows.length) {
    return 'Aucune voie definie'
  }

  return laneRows.map((row) => `L${Number(row) + 1}`).join(', ')
})

const spotCountDelta = computed(() => {
  if (!selectedParking.value) {
    return 0
  }

  return Number(selectedParking.value.capacity) - selectedStats.value.total
})

const formattedWorkingDays = computed(() => {
  const days = selectedParking.value?.businessSettings?.workingDays ?? []
  if (!days.length) {
    return '-'
  }

  return days
    .map((day) => dayOptions.find((item) => item.key === day)?.label ?? day)
    .join(', ')
})

const sensorBindingCount = computed(() => {
  return selectedSpots.value.filter((spot) => {
    const sensor = spot.sensor ?? {}
    return Boolean(String(sensor?.arduinoId ?? '').trim() && String(sensor?.channel ?? '').trim())
  }).length
})

const componentDiagnostics = computed(() => {
  if (!selectedParking.value) {
    return [
      {
        key: 'entry',
        title: 'Capteur entree',
        status: 'Parking non selectionne',
        details: 'Selectionnez un parking pour lancer le controle.',
        tone: 'neutral',
      },
      {
        key: 'exit',
        title: 'Capteur sortie',
        status: 'Parking non selectionne',
        details: 'Selectionnez un parking pour lancer le controle.',
        tone: 'neutral',
      },
      {
        key: 'parked',
        title: 'Detecteur voiture garee',
        status: 'Parking non selectionne',
        details: 'Selectionnez un parking pour lancer le controle.',
        tone: 'neutral',
      },
    ]
  }

  const spots = selectedSpots.value
  const spotsWithSignal = spots.filter((spot) => {
    const sensor = spot.sensor ?? {}
    return Boolean(
      String(sensor?.arduinoId ?? '').trim() ||
        String(sensor?.channel ?? '').trim() ||
        String(sensor?.topic ?? '').trim(),
    )
  })

  const bindingCount = sensorBindingCount.value
  const sensorText = spotsWithSignal
    .map((spot) => {
      const sensor = spot.sensor ?? {}
      return `${String(sensor?.arduinoId ?? '')} ${String(sensor?.channel ?? '')} ${String(sensor?.topic ?? '')}`.toLowerCase()
    })
    .join(' ')

  const hasEntryTag = /(entry|entree|inbound|gate-in|gate_in|porte-entree)/.test(sensorText)
  const hasExitTag = /(exit|sortie|outbound|gate-out|gate_out|porte-sortie)/.test(sensorText)

  let entryStatus = 'Non configure'
  let entryDetails = 'Aucun capteur detecte dans la carte interieure.'
  let entryTone = 'danger'

  if (spotsWithSignal.length) {
    if (hasEntryTag || bindingCount >= 2) {
      entryStatus = 'Connecte'
      entryDetails = `${bindingCount} liaison(s) Arduino detectee(s).`
      entryTone = 'success'
    } else {
      entryStatus = 'A verifier'
      entryDetails = 'Signal capteur present, mais etiquette entree absente.'
      entryTone = 'warning'
    }
  }

  let exitStatus = 'Non configure'
  let exitDetails = 'Aucun capteur detecte dans la carte interieure.'
  let exitTone = 'danger'

  if (spotsWithSignal.length) {
    if (hasExitTag || bindingCount >= 2) {
      exitStatus = 'Connecte'
      exitDetails = `${bindingCount} liaison(s) Arduino detectee(s).`
      exitTone = 'success'
    } else {
      exitStatus = 'A verifier'
      exitDetails = 'Signal capteur present, mais etiquette sortie absente.'
      exitTone = 'warning'
    }
  }

  let parkedStatus = 'Non configure'
  let parkedDetails = 'Aucune place instrumentee avec detecteur Arduino.'
  let parkedTone = 'danger'

  if (spots.length && !bindingCount) {
    parkedStatus = 'Partiel'
    parkedDetails = 'Des places existent, mais sans liaison capteur complete.'
    parkedTone = 'warning'
  }

  if (bindingCount) {
    if (selectedStats.value.offline > 0) {
      parkedStatus = 'A surveiller'
      parkedDetails = `${selectedStats.value.offline} detecteur(s) hors service.`
      parkedTone = 'warning'
    } else {
      parkedStatus = 'Operationnel'
      parkedDetails = `${selectedStats.value.occupied} voiture(s) detectee(s) comme garees.`
      parkedTone = 'success'
    }
  }

  return [
    {
      key: 'entry',
      title: 'Capteur entree',
      status: entryStatus,
      details: entryDetails,
      tone: entryTone,
    },
    {
      key: 'exit',
      title: 'Capteur sortie',
      status: exitStatus,
      details: exitDetails,
      tone: exitTone,
    },
    {
      key: 'parked',
      title: 'Detecteur voiture garee',
      status: parkedStatus,
      details: parkedDetails,
      tone: parkedTone,
    },
  ]
})

const syncFormFromSelectedParking = () => {
  const parking = selectedParking.value

  if (!parking) {
    settingsForm.workingDays = []
    settingsForm.openingTime = '08:00'
    settingsForm.closingTime = '20:00'
    settingsForm.hourlyRateDzd = 0
    settingsForm.dailyRateDzd = 0
    settingsForm.monthlyRateDzd = ''
    return
  }

  const settings = parking.businessSettings
  settingsForm.workingDays = Array.isArray(settings.workingDays) ? [...settings.workingDays] : []
  settingsForm.openingTime = String(settings.openingTime ?? '08:00')
  settingsForm.closingTime = String(settings.closingTime ?? '20:00')
  settingsForm.hourlyRateDzd = Number(settings.pricing?.hourlyRateDzd ?? 0)
  settingsForm.dailyRateDzd = Number(settings.pricing?.dailyRateDzd ?? 0)
  settingsForm.monthlyRateDzd = settings.pricing?.monthlyRateDzd == null ? '' : Number(settings.pricing.monthlyRateDzd)
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
      return
    }

    ownerParkings.value = result.data.map((payload) => normalizeParking(payload))

    if (!ownerParkings.value.length) {
      selectedParkingId.value = ''
      return
    }

    const exists = ownerParkings.value.some((parking) => parking.id === selectedParkingId.value)
    if (!exists) {
      selectedParkingId.value = ownerParkings.value[0].id
    }
  } finally {
    loading.value = false
  }
}

const validateSettings = () => {
  if (!settingsForm.workingDays.length) {
    return 'Selectionnez au moins un jour de travail.'
  }

  if (!settingsForm.openingTime || !settingsForm.closingTime) {
    return 'Renseignez les heures d ouverture et de fermeture.'
  }

  if (settingsForm.openingTime === settingsForm.closingTime) {
    return 'L heure d ouverture doit etre differente de l heure de fermeture.'
  }

  const hourly = Number(settingsForm.hourlyRateDzd)
  const daily = Number(settingsForm.dailyRateDzd)
  const monthly = settingsForm.monthlyRateDzd === '' ? null : Number(settingsForm.monthlyRateDzd)

  if (Number.isNaN(hourly) || hourly < 0) {
    return 'Tarif horaire DZD invalide.'
  }

  if (Number.isNaN(daily) || daily < 0) {
    return 'Tarif journalier DZD invalide.'
  }

  if (monthly != null && (Number.isNaN(monthly) || monthly < 0)) {
    return 'Tarif mensuel DZD invalide.'
  }

  return ''
}

const saveBusinessSettings = async () => {
  saveError.value = ''
  saveSuccess.value = ''

  if (!selectedParking.value) {
    saveError.value = 'Selectionnez un parking owner.'
    return
  }

  const validationMessage = validateSettings()
  if (validationMessage) {
    saveError.value = validationMessage
    return
  }

  saving.value = true

  try {
    const payload = {
      workingDays: [...settingsForm.workingDays],
      openingTime: settingsForm.openingTime,
      closingTime: settingsForm.closingTime,
      pricing: {
        hourlyRateDzd: Number(settingsForm.hourlyRateDzd),
        dailyRateDzd: Number(settingsForm.dailyRateDzd),
        monthlyRateDzd: settingsForm.monthlyRateDzd === '' ? null : Number(settingsForm.monthlyRateDzd),
      },
    }

    const result = await updateOwnerBusinessSettings({
      parkingId: selectedParking.value.id,
      payload,
      authHeaders: authStore.authHeaders,
    })

    if (!result.ok) {
      saveError.value = result.message
      return
    }

    const updatedParking = normalizeParking(result.data)

    ownerParkings.value = ownerParkings.value.map((parking) => {
      if (parking.id !== updatedParking.id) {
        return parking
      }

      return updatedParking
    })

    saveSuccess.value = 'Horaires, jours de travail et tarifs en DZD enregistres.'
  } finally {
    saving.value = false
  }
}

const goToLiveMap = async () => {
  if (!selectedParkingId.value) {
    await router.push('/owner/live-map')
    return
  }

  await router.push({
    path: '/owner/live-map',
    query: { parkingId: selectedParkingId.value },
  })
}

const runComponentVerification = () => {
  lastComponentCheckAt.value = new Date().toLocaleString('fr-FR')
}

watch(selectedParkingId, () => {
  saveError.value = ''
  saveSuccess.value = ''
  syncFormFromSelectedParking()
  runComponentVerification()
})

onMounted(async () => {
  await loadOwnerParkings()
  syncFormFromSelectedParking()
  runComponentVerification()
})
</script>

<template>
  <section class="space-y-8">
    <div>
      <h2 class="font-headline text-2xl font-extrabold text-on-surface">Mon parking admin</h2>
      <p class="mt-1 text-sm text-on-surface-variant">
        Espace owner: modifiez vos jours/heures de travail et vos prix en dinar algerien (DZD).
      </p>
    </div>

    <article class="surface-card p-6">
      <div class="flex items-center justify-between gap-3">
        <label class="block w-full text-xs font-semibold uppercase tracking-[0.08em] text-outline">
          Parking administre
          <select
            v-model="selectedParkingId"
            class="mt-2 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
          >
            <option value="">Selectionner un parking</option>
            <option v-for="parking in ownerParkings" :key="parking.id" :value="parking.id">
              {{ parking.name }} ({{ parking.id }})
            </option>
          </select>
        </label>

        <button
          type="button"
          class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold uppercase tracking-[0.08em] text-on-surface hover:bg-surface-container-high"
          @click="loadOwnerParkings"
        >
          Actualiser
        </button>
      </div>

      <p v-if="loading" class="mt-4 rounded-lg bg-surface-container-low px-3 py-2 text-sm font-semibold text-on-surface-variant">
        Chargement de vos parkings...
      </p>
      <p v-if="loadError" class="mt-4 rounded-lg bg-red-100 px-3 py-2 text-sm font-semibold text-red-700">
        {{ loadError }}
      </p>

      <div v-if="selectedParking" class="mt-5 space-y-5">
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <div class="rounded-xl bg-surface-container-low p-4">
            <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Capacite cible</p>
            <p class="mt-1 text-2xl font-extrabold text-on-surface">{{ selectedParking.capacity }}</p>
          </div>
          <div class="rounded-xl bg-surface-container-low p-4">
            <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Places dessinees</p>
            <p class="mt-1 text-2xl font-extrabold text-on-surface">{{ selectedStats.total }}</p>
          </div>
          <div class="rounded-xl bg-surface-container-low p-4">
            <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Ecart places</p>
            <p class="mt-1 text-2xl font-extrabold" :class="spotCountDelta === 0 ? 'text-emerald-600' : 'text-amber-600'">
              {{ spotCountDelta }}
            </p>
          </div>
          <div class="rounded-xl bg-surface-container-low p-4">
            <p class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">Occupation</p>
            <p class="mt-1 text-2xl font-extrabold text-on-surface">{{ selectedStats.occupancyPercent }}%</p>
          </div>
        </div>

        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4 text-sm">
          <p class="rounded-lg bg-emerald-100 px-3 py-2 font-semibold text-emerald-700">Libres: {{ selectedStats.available }}</p>
          <p class="rounded-lg bg-red-100 px-3 py-2 font-semibold text-red-700">Occupees: {{ selectedStats.occupied }}</p>
          <p class="rounded-lg bg-amber-100 px-3 py-2 font-semibold text-amber-700">Reservees: {{ selectedStats.reserved }}</p>
          <p class="rounded-lg bg-slate-200 px-3 py-2 font-semibold text-slate-700">Offline: {{ selectedStats.offline }}</p>
        </div>

        <div class="rounded-xl bg-surface-container-low p-4 text-sm text-on-surface-variant">
          <p><span class="font-semibold text-on-surface">Adresse:</span> {{ selectedParking.address }}</p>
          <p class="mt-1"><span class="font-semibold text-on-surface">Etage:</span> {{ selectedParking.indoorMap.floor }}</p>
          <p class="mt-1"><span class="font-semibold text-on-surface">Zone:</span> {{ selectedParking.indoorMap.zone }}</p>
          <p class="mt-1"><span class="font-semibold text-on-surface">Grille:</span> {{ selectedParking.indoorMap.grid.rows }} lignes x {{ selectedParking.indoorMap.grid.cols }} colonnes</p>
          <p class="mt-1"><span class="font-semibold text-on-surface">Voies:</span> {{ laneRowsLabel }}</p>
        </div>

        <article class="rounded-xl bg-surface-container-low p-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 class="font-headline text-lg font-bold text-on-surface">Verification composants</h3>
              <p class="mt-1 text-xs text-on-surface-variant">
                Controle frontend des capteurs entree, sortie et detecteur de voiture garee.
              </p>
            </div>

            <button
              type="button"
              class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold uppercase tracking-[0.08em] text-on-surface hover:bg-surface-container-high"
              @click="runComponentVerification"
            >
              Verifier maintenant
            </button>
          </div>

          <p v-if="lastComponentCheckAt" class="mt-3 text-xs font-semibold text-on-surface-variant">
            Dernier controle: {{ lastComponentCheckAt }}
          </p>

          <div class="mt-4 grid gap-3 md:grid-cols-3">
            <article
              v-for="component in componentDiagnostics"
              :key="component.key"
              class="rounded-xl border px-3 py-3"
              :class="componentToneClassMap[component.tone]"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.08em]">{{ component.title }}</p>
              <p class="mt-2 text-lg font-extrabold">{{ component.status }}</p>
              <p class="mt-1 text-xs">{{ component.details }}</p>
            </article>
          </div>
        </article>

        <article class="rounded-xl bg-surface-container-low p-4">
          <h3 class="font-headline text-lg font-bold text-on-surface">Jours et heures de travail</h3>
          <p class="mt-1 text-xs text-on-surface-variant">
            Valeurs actuelles: {{ formattedWorkingDays }} | {{ selectedParking.businessSettings.openingTime }} - {{ selectedParking.businessSettings.closingTime }}
          </p>

          <div class="mt-4 grid grid-cols-2 gap-2 md:grid-cols-4 xl:grid-cols-7">
            <label
              v-for="day in dayOptions"
              :key="day.key"
              class="flex items-center gap-2 rounded-lg bg-surface-container px-2 py-2 text-sm text-on-surface"
            >
              <input
                v-model="settingsForm.workingDays"
                :value="day.key"
                type="checkbox"
                class="h-4 w-4"
              />
              <span>{{ day.label }}</span>
            </label>
          </div>

          <div class="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Ouverture
              <input
                v-model="settingsForm.openingTime"
                type="time"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Fermeture
              <input
                v-model="settingsForm.closingTime"
                type="time"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
          </div>
        </article>

        <article class="rounded-xl bg-surface-container-low p-4">
          <h3 class="font-headline text-lg font-bold text-on-surface">Prix en dinar algerien (DZD)</h3>
          <p class="mt-1 text-xs text-on-surface-variant">Modifiez vos tarifs et enregistrez-les pour votre parking.</p>

          <div class="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Tarif horaire (DZD)
              <input
                v-model.number="settingsForm.hourlyRateDzd"
                type="number"
                min="0"
                step="1"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Tarif journalier (DZD)
              <input
                v-model.number="settingsForm.dailyRateDzd"
                type="number"
                min="0"
                step="1"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
            <label class="text-xs font-semibold uppercase tracking-[0.08em] text-outline">
              Tarif mensuel (DZD)
              <input
                v-model.number="settingsForm.monthlyRateDzd"
                type="number"
                min="0"
                step="1"
                placeholder="Optionnel"
                class="mt-1 w-full rounded-lg bg-surface-container px-3 py-2 text-sm font-semibold text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </label>
          </div>

          <div class="mt-4 flex flex-wrap items-center gap-2">
            <button type="button" class="primary-cta px-4 py-2" :disabled="saving" @click="saveBusinessSettings">
              {{ saving ? 'Enregistrement...' : 'Sauvegarder les parametres' }}
            </button>
            <button type="button" class="rounded-lg bg-surface-container px-4 py-2 text-sm font-semibold text-on-surface hover:bg-surface-container-high" @click="goToLiveMap">
              Voir l emplacement sur la carte
            </button>
          </div>

          <p v-if="saveError" class="mt-3 rounded-lg bg-red-100 px-3 py-2 text-sm font-semibold text-red-700">{{ saveError }}</p>
          <p v-if="saveSuccess" class="mt-3 rounded-lg bg-emerald-100 px-3 py-2 text-sm font-semibold text-emerald-700">{{ saveSuccess }}</p>
        </article>

        <div class="flex items-center justify-between gap-3">
          <h3 class="font-headline text-lg font-bold text-on-surface">Liste des places</h3>
        </div>

        <div class="overflow-x-auto">
          <table class="min-w-full text-left text-sm">
            <thead>
              <tr class="text-xs uppercase tracking-[0.08em] text-outline">
                <th class="px-3 py-2">Place</th>
                <th class="px-3 py-2">Cellule</th>
                <th class="px-3 py-2">Type</th>
                <th class="px-3 py-2">Etat</th>
                <th class="px-3 py-2">Arduino</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="spot in selectedSpots" :key="spot.spotId" class="odd:bg-surface-container-low">
                <td class="px-3 py-2 font-semibold text-on-surface">{{ spot.label }}</td>
                <td class="px-3 py-2 text-on-surface-variant">L{{ Number(spot.row) + 1 }} / C{{ Number(spot.col) + 1 }}</td>
                <td class="px-3 py-2 text-on-surface-variant">{{ typeLabelMap[String(spot.type).toUpperCase()] || spot.type }}</td>
                <td class="px-3 py-2 text-on-surface-variant">{{ stateLabelMap[String(spot.state).toUpperCase()] || spot.state }}</td>
                <td class="px-3 py-2 text-on-surface-variant">
                  {{ spot.sensor?.arduinoId || '-' }} | {{ spot.sensor?.channel || '-' }}
                </td>
              </tr>
              <tr v-if="!selectedSpots.length">
                <td colspan="5" class="px-3 py-3 text-center text-sm font-semibold text-on-surface-variant">
                  Aucune place dessinee pour ce parking.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <p v-else-if="!loading" class="mt-4 rounded-lg bg-surface-container-low px-3 py-2 text-sm font-semibold text-on-surface-variant">
        Aucun parking disponible pour ce compte owner.
      </p>
    </article>
  </section>
</template>
