<script setup>
import { computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useUsersStore } from '@/stores/users'
import { useAuthStore } from '@/stores/auth'
import StatCard from '@/components/ui/StatCard.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'

const usersStore = useUsersStore()
const authStore = useAuthStore()

const {
  stats,
  tabs,
  activeTab,
  filteredUsers,
  usersLoading,
  usersError,
  actionError,
  actionSuccess,
} = storeToRefs(usersStore)

const roleToneMap = {
  Administrateur: 'info',
  'Proprietaire de parking': 'warning',
  Client: 'neutral',
}

const usersView = computed(() => {
  return filteredUsers.value.map((user) => {
    const initials = user.name
      .split(' ')
      .slice(0, 2)
      .map((part) => part[0])
      .join('')
      .toUpperCase()

    const roleTone = roleToneMap[user.role] ?? 'neutral'

    return {
      ...user,
      initials,
      roleTone,
    }
  })
})

const tabClass = (tabKey) => {
  if (tabKey === activeTab.value) {
    return 'rounded-full bg-surface-container-lowest px-4 py-2 text-sm font-semibold text-primary shadow-sm'
  }

  return 'rounded-full px-4 py-2 text-sm font-semibold text-on-surface-variant hover:bg-surface-container'
}

const setTab = (tab) => {
  usersStore.setActiveTab(tab)
}

const refreshData = async () => {
  await usersStore.loadUsers({
    authHeaders: authStore.authHeaders,
  })
}

const canToggleOwnerStatus = (user) => user.roleKey === 'OWNER'

const ownerActionLabel = (user) => {
  return user.accountStatus === 'blocked' ? 'activer' : 'suspendre'
}

const ownerActionClass = (user) => {
  if (user.accountStatus === 'blocked') {
    return 'rounded-lg bg-emerald-100 px-2 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-200'
  }

  return 'rounded-lg bg-amber-100 px-2 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-200'
}

const onToggleOwnerStatus = async (user) => {
  await usersStore.toggleOwnerStatus({
    user,
    authHeaders: authStore.authHeaders,
  })
}

const isOwnerStatusUpdating = (user) => usersStore.isUpdatingOwnerStatus(user.id)

onMounted(async () => {
  await refreshData()
})
</script>

<template>
  <section class="space-y-8">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="font-headline text-2xl font-extrabold text-on-surface">Annuaire des utilisateurs</h2>
        <p class="mt-1 text-sm text-on-surface-variant">
        Suivez les identites, roles, activite et sante d acces de la plateforme.
        </p>
      </div>

      <button
        type="button"
        class="rounded-lg bg-surface-container px-3 py-2 text-xs font-semibold uppercase tracking-[0.08em] text-on-surface hover:bg-surface-container-high"
        @click="refreshData"
      >
        Actualiser
      </button>
    </div>

    <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <StatCard
        v-for="card in stats"
        :key="card.title"
        :title="card.title"
        :value="card.value"
        :subtitle="card.subtitle"
      />
    </div>

    <p v-if="actionSuccess" class="rounded-xl bg-emerald-100 px-4 py-3 text-sm font-medium text-emerald-700">
      {{ actionSuccess }}
    </p>
    <p v-if="actionError" class="rounded-xl bg-red-100 px-4 py-3 text-sm font-medium text-red-700">
      {{ actionError }}
    </p>
    <p v-if="usersError" class="rounded-xl bg-red-100 px-4 py-3 text-sm font-medium text-red-700">
      {{ usersError }}
    </p>

    <article class="surface-card p-6">
      <div class="flex flex-wrap items-center gap-2 rounded-full bg-surface-container-low p-2">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          type="button"
          :class="tabClass(tab.key)"
          @click="setTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </div>

      <p v-if="usersLoading" class="mt-4 rounded-xl bg-surface-container-low px-3 py-2 text-sm text-on-surface-variant">
        Chargement des utilisateurs...
      </p>

      <div class="mt-5 overflow-x-auto">
        <table class="min-w-full text-left text-sm">
          <thead>
            <tr class="text-xs uppercase tracking-[0.08em] text-outline">
              <th class="px-3 py-2">Utilisateur</th>
              <th class="px-3 py-2">Role</th>
              <th class="px-3 py-2">Derniere activite</th>
              <th class="px-3 py-2">Statut</th>
              <th class="px-3 py-2 text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="user in usersView"
              :key="user.id"
              class="group rounded-xl odd:bg-surface-container-low"
            >
              <td class="px-3 py-3">
                <div class="flex items-center gap-3">
                  <div
                    class="flex h-10 w-10 items-center justify-center rounded-full bg-primary-fixed text-xs font-bold text-primary"
                  >
                    {{ user.initials }}
                  </div>
                  <div>
                    <p class="font-semibold text-on-surface">{{ user.name }}</p>
                    <p class="text-xs text-on-surface-variant">{{ user.email }}</p>
                  </div>
                </div>
              </td>
              <td class="px-3 py-3">
                <StatusBadge :label="user.role" :tone="user.roleTone" />
              </td>
              <td class="px-3 py-3 text-on-surface-variant">
                <p>{{ user.lastActive }}</p>
                <p class="text-xs">IP : {{ user.ip }}</p>
              </td>
              <td class="px-3 py-3">
                <StatusBadge :label="user.status" :tone="user.statusTone" />
              </td>
              <td class="px-3 py-3">
                <div class="flex items-center justify-end gap-2 opacity-0 transition-opacity group-hover:opacity-100">
                  <button
                    v-if="canToggleOwnerStatus(user)"
                    type="button"
                    :class="ownerActionClass(user)"
                    :disabled="isOwnerStatusUpdating(user)"
                    @click="onToggleOwnerStatus(user)"
                  >
                    {{ isOwnerStatusUpdating(user) ? 'en cours...' : ownerActionLabel(user) }}
                  </button>
                  <button
                    v-else
                    type="button"
                    class="rounded-lg bg-surface-container px-2 py-1 text-xs font-semibold text-on-surface-variant"
                    disabled
                  >
                    -
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </section>
</template>
