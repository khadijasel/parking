<script setup>
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { Bar } from 'vue-chartjs'
import { useDashboardStore } from '@/stores/dashboard'
import { useAuthStore } from '@/stores/auth'
import StatCard from '@/components/ui/StatCard.vue'

const dashboardStore = useDashboardStore()
const authStore = useAuthStore()

const {
  statCards,
  aiSuggestions,
  recentActivity,
  selectedPeriod,
  statsLoading,
  statsError,
  periodOptions,
  revenueChartData,
  revenueChartOptions,
} = storeToRefs(dashboardStore)

const onPeriodChange = (event) => {
  dashboardStore.setPeriod(event.target.value)
}

const refreshTotals = async () => {
  if (!authStore.isAuthenticated || authStore.role !== 'admin') {
    return
  }

  await dashboardStore.loadRealtimeTotals({
    authHeaders: authStore.authHeaders,
  })
}

onMounted(async () => {
  await refreshTotals()
})
</script>

<template>
  <section class="space-y-8">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="font-headline text-2xl font-extrabold text-on-surface">Vue strategique</h2>
        <p class="mt-1 text-sm text-on-surface-variant">
          Centre de pilotage en temps reel pour les operations, la demande et les revenus.
        </p>
      </div>

      <button
        type="button"
        class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold uppercase tracking-[0.08em] text-on-surface hover:bg-surface-container-high disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="statsLoading"
        @click="refreshTotals"
      >
        {{ statsLoading ? 'Actualisation...' : 'Actualiser totaux' }}
      </button>
    </div>

    <p v-if="statsError" class="rounded-xl bg-red-100 px-4 py-3 text-sm font-medium text-red-700">
      {{ statsError }}
    </p>

    <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <StatCard
        v-for="card in statCards"
        :key="card.title"
        :title="card.title"
        :value="card.value"
        :subtitle="card.subtitle"
        :badge-label="card.badgeLabel"
        :badge-tone="card.badgeTone"
      />
    </div>

    <div class="grid gap-6">
      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Optimisation des espaces</h3>
        <p class="mt-1 text-sm text-on-surface-variant">Suggestions IA basees sur l occupation actuelle.</p>

        <ul class="mt-5 space-y-4">
          <li
            v-for="suggestion in aiSuggestions"
            :key="suggestion.title"
            class="rounded-xl bg-surface-container-low p-4"
          >
            <p class="font-semibold text-on-surface">{{ suggestion.title }}</p>
            <p class="mt-1 text-sm text-on-surface-variant">{{ suggestion.description }}</p>
          </li>
        </ul>
      </article>
    </div>

    <div class="grid gap-6 xl:grid-cols-[1.4fr,1fr]">
      <article class="surface-card p-6">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h3 class="font-headline text-lg font-bold text-on-surface">Revenus hebdomadaires</h3>

          <label class="text-xs font-semibold uppercase tracking-[0.1em] text-outline">
            Periode
            <select
              :value="selectedPeriod"
              class="mt-1 block rounded-lg bg-surface-container px-3 py-2 text-sm font-medium text-on-surface focus:outline-none focus:ring-2 focus:ring-primary/30"
              @change="onPeriodChange"
            >
              <option v-for="option in periodOptions" :key="option" :value="option">{{ option }}</option>
            </select>
          </label>
        </div>

        <div class="mt-5 h-72">
          <Bar :data="revenueChartData" :options="revenueChartOptions" />
        </div>
      </article>

      <article class="surface-card p-6">
        <h3 class="font-headline text-lg font-bold text-on-surface">Activite recente</h3>

        <ul class="mt-4 space-y-4">
          <li
            v-for="event in recentActivity"
            :key="event.id"
            class="rounded-xl bg-surface-container-low p-4"
          >
            <div class="flex items-center justify-between gap-2">
              <p class="text-sm font-semibold text-on-surface">{{ event.title }}</p>
              <p class="text-[11px] font-semibold uppercase tracking-[0.1em] text-outline">
                {{ event.timestamp }}
              </p>
            </div>
            <p class="mt-1 text-xs text-on-surface-variant">{{ event.detail }}</p>
          </li>
        </ul>
      </article>
    </div>
  </section>
</template>
