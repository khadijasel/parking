<script setup>
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useUsersStore } from '@/stores/users'
import StatusBadge from '@/components/ui/StatusBadge.vue'

const usersStore = useUsersStore()
const authStore = useAuthStore()

const {
  historyEvents,
  historyLoading,
  historyError,
} = storeToRefs(usersStore)

const refreshHistory = async () => {
  await usersStore.loadGlobalHistory({
    authHeaders: authStore.authHeaders,
    limit: 200,
  })
}

onMounted(async () => {
  await refreshHistory()
})
</script>

<template>
  <section class="space-y-8">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="font-headline text-2xl font-extrabold text-on-surface">Historique global</h2>
        <p class="mt-1 text-sm text-on-surface-variant">
          Timeline complete des operations plateforme (comptes, parkings, reservations, paiements).
        </p>
      </div>

      <button
        type="button"
        class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold uppercase tracking-[0.08em] text-on-surface hover:bg-surface-container-high"
        @click="refreshHistory"
      >
        Actualiser
      </button>
    </div>

    <p v-if="historyError" class="rounded-xl bg-red-100 px-4 py-3 text-sm font-medium text-red-700">
      {{ historyError }}
    </p>

    <article class="surface-card p-6">
      <div class="flex items-center justify-between gap-3">
        <h3 class="text-lg font-bold text-on-surface">Evenements</h3>
        <p class="rounded-full bg-surface-container px-3 py-1 text-xs font-semibold text-on-surface-variant">
          {{ historyEvents.length }} evenements
        </p>
      </div>

      <p v-if="historyLoading" class="mt-4 rounded-xl bg-surface-container-low px-3 py-2 text-sm text-on-surface-variant">
        Chargement de l historique global...
      </p>

      <p
        v-if="!historyLoading && !historyEvents.length"
        class="mt-4 rounded-xl bg-surface-container-low px-3 py-2 text-sm text-on-surface-variant"
      >
        Aucun evenement disponible pour le moment.
      </p>

      <div v-if="historyEvents.length" class="mt-5 overflow-x-auto">
        <table class="min-w-full text-left text-sm">
          <thead>
            <tr class="text-xs uppercase tracking-[0.08em] text-outline">
              <th class="px-3 py-2">Date</th>
              <th class="px-3 py-2">Categorie</th>
              <th class="px-3 py-2">Action</th>
              <th class="px-3 py-2">Details</th>
              <th class="px-3 py-2">Acteur</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="event in historyEvents"
              :key="event.id"
              class="rounded-xl odd:bg-surface-container-low"
            >
              <td class="px-3 py-3 text-on-surface-variant">{{ event.occurredAtLabel }}</td>
              <td class="px-3 py-3">
                <StatusBadge :label="event.category" :tone="event.categoryTone" />
              </td>
              <td class="px-3 py-3 font-semibold text-on-surface">{{ event.action }}</td>
              <td class="px-3 py-3 text-on-surface-variant">{{ event.details }}</td>
              <td class="px-3 py-3 text-on-surface-variant">{{ event.actor }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </section>
</template>
